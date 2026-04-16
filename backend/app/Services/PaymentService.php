<?php

namespace App\Services;

use App\Models\Invoice;
use App\Models\Payment;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Support\Facades\DB;

class PaymentService
{
    public function list(string $workspaceId, array $filters = []): LengthAwarePaginator
    {
        $query = Payment::where('workspace_id', $workspaceId);

        if (! empty($filters['invoice_id'])) {
            $query->where('invoice_id', $filters['invoice_id']);
        }
        if (! empty($filters['status'])) {
            $query->where('status', $filters['status']);
        }

        return $query->with('invoice')
            ->orderByDesc('created_at')
            ->paginate($filters['per_page'] ?? 25);
    }

    public function find(string $workspaceId, string $id): ?Payment
    {
        return Payment::where('workspace_id', $workspaceId)
            ->with('invoice')
            ->find($id);
    }

    /**
     * Create payment and sync the linked invoice's payment_status.
     */
    public function create(string $workspaceId, string $userId, array $data): Payment
    {
        return DB::transaction(function () use ($workspaceId, $userId, $data) {
            $payment = Payment::create(array_merge($data, [
                'workspace_id'  => $workspaceId,
                'created_by'    => $userId,
                'status'        => 'completed',
                'payment_date'  => $data['payment_date'] ?? now()->toDateString(),
            ]));

            // Sync invoice payment status if linked
            if ($payment->invoice_id) {
                $this->syncInvoicePaymentStatus($payment->invoice_id);
            }

            return $payment->load('invoice');
        });
    }

    /**
     * Reverse a payment. Creates a reversal record, marks original as reversed.
     */
    public function reverse(string $workspaceId, string $userId, Payment $payment, string $reason): Payment
    {
        if ($payment->status === 'reversed') {
            throw new \InvalidArgumentException('Payment is already reversed.');
        }
        if ($payment->is_reversal) {
            throw new \InvalidArgumentException('Cannot reverse a reversal payment.');
        }

        return DB::transaction(function () use ($workspaceId, $userId, $payment, $reason) {
            // Mark original as reversed
            $payment->update([
                'status'          => 'reversed',
                'reversed_at'     => now(),
                'reversed_by'     => $userId,
                'reversal_reason' => $reason,
            ]);

            // Create the reversal entry
            $reversal = Payment::create([
                'workspace_id'          => $workspaceId,
                'invoice_id'            => $payment->invoice_id,
                'account_id'            => $payment->account_id,
                'amount'                => $payment->amount,
                'payment_method'        => $payment->payment_method,
                'payment_date'          => now()->toDateString(),
                'created_by'            => $userId,
                'status'                => 'completed',
                'is_reversal'           => true,
                'reversal_of_payment_id'=> $payment->id,
                'reversal_reason'       => $reason,
            ]);

            // Re-sync invoice
            if ($payment->invoice_id) {
                $this->syncInvoicePaymentStatus($payment->invoice_id);
            }

            return $reversal->load('invoice');
        });
    }

    /**
     * Recalculate and update invoice.payment_status based on sum of completed payments.
     */
    public function syncInvoicePaymentStatus(string $invoiceId): void
    {
        $invoice = Invoice::find($invoiceId);
        if (! $invoice) return;

        // Sum completed non-reversal payments minus completed reversal payments
        $paidAmount = Payment::where('invoice_id', $invoiceId)
            ->where('status', 'completed')
            ->where('is_reversal', false)
            ->sum('amount');

        $reversedAmount = Payment::where('invoice_id', $invoiceId)
            ->where('status', 'completed')
            ->where('is_reversal', true)
            ->sum('amount');

        $netPaid = $paidAmount - $reversedAmount;

        if ($netPaid <= 0) {
            $newStatus = 'unpaid';
        } elseif ($netPaid >= (float) $invoice->net_amount) {
            $newStatus = 'paid';
        } else {
            $newStatus = 'partial';
        }

        $invoice->update(['payment_status' => $newStatus]);
    }
}
