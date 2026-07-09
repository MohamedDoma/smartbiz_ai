<?php

namespace App\Services;

use App\Models\CommissionEntry;
use App\Models\FinanceAccount;
use App\Models\FinanceExpense;
use App\Models\FinanceSetting;
use App\Models\FinanceTransaction;
use App\Models\FinanceTransactionLine;
use App\Models\Invoice;
use App\Models\Payment;
use Illuminate\Support\Facades\DB;

/**
 * Creates balanced double-entry finance transactions.
 */
class FinancePostingService
{
    /**
     * Create a manual balanced transaction.
     */
    public function createTransaction(
        string $wsId,
        string $date,
        ?string $description,
        array $lines,
        string $currency = 'LYD',
        ?string $membershipId = null,
        ?string $sourceType = null,
        ?string $sourceId = null,
    ): FinanceTransaction {
        // Prevent duplicate source posting
        if ($sourceType && $sourceId) {
            $existing = FinanceTransaction::where('workspace_id', $wsId)
                ->where('source_type', $sourceType)
                ->where('source_id', $sourceId)
                ->where('status', '!=', 'void')
                ->first();
            if ($existing) {
                throw new \RuntimeException("Already posted: transaction {$existing->id}");
            }
        }

        // Validate balance
        $totalDebit = 0;
        $totalCredit = 0;
        foreach ($lines as $line) {
            $totalDebit  += (float) ($line['debit_amount'] ?? 0);
            $totalCredit += (float) ($line['credit_amount'] ?? 0);
        }
        if (abs($totalDebit - $totalCredit) > 0.01) {
            throw new \InvalidArgumentException(
                "Unbalanced: debit={$totalDebit}, credit={$totalCredit}"
            );
        }
        if ($totalDebit <= 0) {
            throw new \InvalidArgumentException("Transaction total must be > 0.");
        }

        return DB::transaction(function () use ($wsId, $date, $description, $lines, $currency, $membershipId, $sourceType, $sourceId, $totalDebit, $totalCredit) {
            $txn = FinanceTransaction::create([
                'workspace_id'          => $wsId,
                'transaction_date'      => $date,
                'description'           => $description,
                'source_type'           => $sourceType,
                'source_id'             => $sourceId,
                'status'                => 'posted',
                'currency'              => $currency,
                'total_debit'           => $totalDebit,
                'total_credit'          => $totalCredit,
                'posted_by_membership_id' => $membershipId,
                'posted_at'             => now(),
            ]);

            foreach ($lines as $i => $line) {
                // Verify account belongs to workspace
                $acct = FinanceAccount::where('workspace_id', $wsId)
                    ->where('id', $line['finance_account_id'])->first();
                if (!$acct) {
                    throw new \InvalidArgumentException("Account {$line['finance_account_id']} not found in workspace.");
                }

                FinanceTransactionLine::create([
                    'workspace_id'          => $wsId,
                    'finance_transaction_id' => $txn->id,
                    'finance_account_id'    => $acct->id,
                    'description'           => $line['description'] ?? null,
                    'debit_amount'          => $line['debit_amount'] ?? 0,
                    'credit_amount'         => $line['credit_amount'] ?? 0,
                    'currency'              => $currency,
                    'line_order'            => $i,
                ]);
            }

            return $txn->load('lines');
        });
    }

    /**
     * Post a manual expense as a balanced transaction.
     */
    public function postManualExpense(
        string $wsId,
        string $date,
        string $description,
        float $amount,
        string $currency = 'LYD',
        ?string $category = null,
        ?string $paymentMethod = null,
        ?string $membershipId = null,
    ): FinanceExpense {
        $settings = FinanceSetting::where('workspace_id', $wsId)->first();
        if (!$settings) {
            throw new \RuntimeException('Finance not bootstrapped. Call POST /api/finance/bootstrap first.');
        }

        $expenseAcct = $settings->default_general_expense_account_id;
        $cashAcct    = $paymentMethod === 'bank'
            ? $settings->default_bank_account_id
            : $settings->default_cash_account_id;

        if (!$expenseAcct || !$cashAcct) {
            throw new \RuntimeException('Default accounts not configured.');
        }

        return DB::transaction(function () use ($wsId, $date, $description, $amount, $currency, $category, $paymentMethod, $membershipId, $expenseAcct, $cashAcct) {
            $txn = $this->createTransaction(
                $wsId, $date,
                "مصروف: {$description}",
                [
                    ['finance_account_id' => $expenseAcct, 'debit_amount' => $amount, 'credit_amount' => 0, 'description' => $description],
                    ['finance_account_id' => $cashAcct,    'debit_amount' => 0,       'credit_amount' => $amount],
                ],
                $currency,
                $membershipId,
                'manual_expense',
            );

            return FinanceExpense::create([
                'workspace_id'          => $wsId,
                'expense_date'          => $date,
                'category'              => $category,
                'description'           => $description,
                'amount'                => $amount,
                'currency'              => $currency,
                'payment_method'        => $paymentMethod ?? 'cash',
                'paid_by_membership_id' => $membershipId,
                'finance_transaction_id' => $txn->id,
                'status'                => 'posted',
            ]);
        });
    }

    /**
     * Post a commission entry to finance.
     */
    public function postCommissionEntry(string $wsId, string $commissionEntryId, ?string $membershipId = null): FinanceTransaction
    {
        $entry = CommissionEntry::where('workspace_id', $wsId)->findOrFail($commissionEntryId);

        $settings = FinanceSetting::where('workspace_id', $wsId)->first();
        if (!$settings) {
            throw new \RuntimeException('Finance not bootstrapped.');
        }

        $sourceType = 'commission_entry';
        $amount = (float) $entry->commission_amount;

        if (in_array($entry->status, ['pending', 'approved', 'calculated'])) {
            // Payable: DR Commission Expense, CR Commission Payable
            return $this->createTransaction(
                $wsId,
                now()->toDateString(),
                "عمولة مستحقة: #{$commissionEntryId}",
                [
                    ['finance_account_id' => $settings->default_commission_expense_account_id, 'debit_amount' => $amount, 'credit_amount' => 0],
                    ['finance_account_id' => $settings->default_commission_payable_account_id, 'debit_amount' => 0, 'credit_amount' => $amount],
                ],
                $entry->currency ?? 'LYD',
                $membershipId,
                $sourceType,
                $commissionEntryId,
            );
        }

        if ($entry->status === 'paid') {
            // Payment: DR Commission Payable, CR Cash
            return $this->createTransaction(
                $wsId,
                now()->toDateString(),
                "دفع عمولة: #{$commissionEntryId}",
                [
                    ['finance_account_id' => $settings->default_commission_payable_account_id, 'debit_amount' => $amount, 'credit_amount' => 0],
                    ['finance_account_id' => $settings->default_cash_account_id, 'debit_amount' => 0, 'credit_amount' => $amount],
                ],
                $entry->currency ?? 'LYD',
                $membershipId,
                $sourceType,
                $commissionEntryId,
            );
        }

        throw new \InvalidArgumentException("Commission entry status '{$entry->status}' cannot be posted.");
    }

    /**
     * Post a payment to finance.
     */
    public function postPayment(string $wsId, string $paymentId, ?string $membershipId = null): FinanceTransaction
    {
        $payment = Payment::where('workspace_id', $wsId)->findOrFail($paymentId);
        $settings = FinanceSetting::where('workspace_id', $wsId)->first();
        if (!$settings) {
            throw new \RuntimeException('Finance not bootstrapped.');
        }

        $amount = (float) $payment->amount;
        // DR Cash/Bank, CR Accounts Receivable
        return $this->createTransaction(
            $wsId,
            $payment->payment_date ?? now()->toDateString(),
            "دفعة: #{$payment->payment_number}",
            [
                ['finance_account_id' => $settings->default_cash_account_id, 'debit_amount' => $amount, 'credit_amount' => 0],
                ['finance_account_id' => $settings->default_accounts_receivable_account_id, 'debit_amount' => 0, 'credit_amount' => $amount],
            ],
            $payment->currency ?? 'LYD',
            $membershipId,
            'payment',
            $paymentId,
        );
    }

    /**
     * Post an invoice to finance.
     */
    public function postInvoice(string $wsId, string $invoiceId, ?string $membershipId = null): FinanceTransaction
    {
        $invoice = Invoice::where('workspace_id', $wsId)->findOrFail($invoiceId);
        $settings = FinanceSetting::where('workspace_id', $wsId)->first();
        if (!$settings) {
            throw new \RuntimeException('Finance not bootstrapped.');
        }

        $amount = (float) $invoice->net_amount;
        // DR Accounts Receivable, CR Sales Revenue
        return $this->createTransaction(
            $wsId,
            $invoice->issue_date ?? now()->toDateString(),
            "فاتورة: #{$invoice->invoice_number}",
            [
                ['finance_account_id' => $settings->default_accounts_receivable_account_id, 'debit_amount' => $amount, 'credit_amount' => 0],
                ['finance_account_id' => $settings->default_revenue_account_id, 'debit_amount' => 0, 'credit_amount' => $amount],
            ],
            $invoice->currency ?? 'LYD',
            $membershipId,
            'invoice',
            $invoiceId,
        );
    }

    /**
     * Void a posted transaction.
     */
    public function voidTransaction(string $wsId, string $txnId): FinanceTransaction
    {
        $txn = FinanceTransaction::where('workspace_id', $wsId)->findOrFail($txnId);
        if ($txn->status === 'void') {
            throw new \RuntimeException('Transaction already voided.');
        }
        $txn->update([
            'status'   => 'void',
            'voided_at' => now(),
        ]);
        return $txn;
    }
}
