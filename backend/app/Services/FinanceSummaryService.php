<?php

namespace App\Services;

use App\Models\FinanceAccount;
use App\Models\FinanceTransactionLine;
use Illuminate\Support\Facades\DB;

/**
 * Returns financial summaries from transaction lines.
 */
class FinanceSummaryService
{
    /**
     * Dashboard summary totals.
     */
    public function getSummary(string $wsId): array
    {
        $balances = $this->accountBalances($wsId);

        $income   = 0;
        $expenses = 0;
        $cash     = 0;
        $receivable = 0;
        $commPayable = 0;

        foreach ($balances as $b) {
            match ($b['type']) {
                'income'    => $income += $b['balance'],
                'expense'   => $expenses += $b['balance'],
                'asset'     => match (true) {
                    in_array($b['code'], ['1000', '1010']) => $cash += $b['balance'],
                    $b['code'] === '1100' => $receivable += $b['balance'],
                    default => null,
                },
                'liability' => $b['code'] === '2000' ? $commPayable += $b['balance'] : null,
                default     => null,
            };
        }

        return [
            'income'              => number_format($income, 2, '.', ''),
            'expenses'            => number_format($expenses, 2, '.', ''),
            'net_profit'          => number_format($income - $expenses, 2, '.', ''),
            'cash_balance'        => number_format($cash, 2, '.', ''),
            'accounts_receivable' => number_format($receivable, 2, '.', ''),
            'commission_payable'  => number_format($commPayable, 2, '.', ''),
        ];
    }

    /**
     * Profit/loss by date range.
     */
    public function getProfitLoss(string $wsId, ?string $from = null, ?string $to = null): array
    {
        $query = FinanceTransactionLine::where('finance_transaction_lines.workspace_id', $wsId)
            ->join('finance_transactions', 'finance_transactions.id', '=', 'finance_transaction_lines.finance_transaction_id')
            ->join('finance_accounts', 'finance_accounts.id', '=', 'finance_transaction_lines.finance_account_id')
            ->where('finance_transactions.status', 'posted')
            ->whereIn('finance_accounts.type', ['income', 'expense']);

        if ($from) {
            $query->where('finance_transactions.transaction_date', '>=', $from);
        }
        if ($to) {
            $query->where('finance_transactions.transaction_date', '<=', $to);
        }

        $rows = $query->select(
            'finance_accounts.type',
            'finance_accounts.code',
            'finance_accounts.name',
            DB::raw('SUM(finance_transaction_lines.debit_amount) as total_debit'),
            DB::raw('SUM(finance_transaction_lines.credit_amount) as total_credit'),
        )->groupBy('finance_accounts.type', 'finance_accounts.code', 'finance_accounts.name')
            ->orderBy('finance_accounts.code')
            ->get();

        $income = 0;
        $expenses = 0;
        $details = [];

        foreach ($rows as $row) {
            // income: credit - debit (credit-normal)
            // expense: debit - credit (debit-normal)
            $balance = $row->type === 'income'
                ? (float) $row->total_credit - (float) $row->total_debit
                : (float) $row->total_debit - (float) $row->total_credit;

            if ($row->type === 'income') {
                $income += $balance;
            } else {
                $expenses += $balance;
            }

            $details[] = [
                'code'    => $row->code,
                'name'    => $row->name,
                'type'    => $row->type,
                'balance' => number_format($balance, 2, '.', ''),
            ];
        }

        return [
            'from'       => $from,
            'to'         => $to,
            'income'     => number_format($income, 2, '.', ''),
            'expenses'   => number_format($expenses, 2, '.', ''),
            'net_profit' => number_format($income - $expenses, 2, '.', ''),
            'details'    => $details,
        ];
    }

    /**
     * Balance for every account in the workspace.
     */
    public function accountBalances(string $wsId): array
    {
        $accounts = FinanceAccount::where('workspace_id', $wsId)
            ->where('is_active', true)->orderBy('sort_order')->get();


        // Get aggregated debit/credit per account
        $agg = FinanceTransactionLine::where('finance_transaction_lines.workspace_id', $wsId)
            ->join('finance_transactions', 'finance_transactions.id', '=', 'finance_transaction_lines.finance_transaction_id')
            ->where('finance_transactions.status', 'posted')
            ->select(
                'finance_transaction_lines.finance_account_id',
                DB::raw('SUM(finance_transaction_lines.debit_amount) as total_debit'),
                DB::raw('SUM(finance_transaction_lines.credit_amount) as total_credit'),
            )
            ->groupBy('finance_transaction_lines.finance_account_id')
            ->get()
            ->keyBy('finance_account_id');

        $result = [];
        foreach ($accounts as $acct) {
            $totals = $agg->get($acct->id);
            $debit  = (float) ($totals?->total_debit ?? 0);
            $credit = (float) ($totals?->total_credit ?? 0);

            // Balance based on normal balance side
            $balance = $acct->normal_balance === 'debit'
                ? $debit - $credit
                : $credit - $debit;

            $result[] = [
                'id'             => $acct->id,
                'code'           => $acct->code,
                'name'           => $acct->name,
                'type'           => $acct->type,
                'normal_balance' => $acct->normal_balance,
                'total_debit'    => number_format($debit, 2, '.', ''),
                'total_credit'   => number_format($credit, 2, '.', ''),
                'balance'        => (float) number_format($balance, 2, '.', ''),
            ];
        }

        return $result;
    }
}
