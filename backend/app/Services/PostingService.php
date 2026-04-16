<?php

namespace App\Services;

use App\Models\JournalEntry;
use Illuminate\Support\Facades\DB;

/**
 * Cross-module posting service.
 * Explicit, production-minded flows — no event system yet.
 */
class PostingService
{
    public function __construct(
        private readonly JournalEntryService $journalService,
        private readonly InventoryMovementService $movementService,
    ) {}

    /**
     * Post a payment as a journal entry (double-entry accounting effect).
     *
     * Creates a journal entry with:
     * - Debit to the payment's account (cash/bank)
     * - Credit to accounts receivable (if sale) or appropriate account
     *
     * Requires both account_id (payment account) and a receivable account.
     */
    public function postPaymentToJournal(
        string $workspaceId,
        string $userId,
        string $paymentId,
        string $receiveAccountId,
    ): JournalEntry {
        $payment = \App\Models\Payment::where('workspace_id', $workspaceId)
            ->findOrFail($paymentId);

        if (! $payment->account_id) {
            throw new \InvalidArgumentException('Payment must have an account_id to post to journal.');
        }

        return $this->journalService->create($workspaceId, $userId, [
            'description' => "Payment #{$payment->payment_number} — {$payment->payment_method}",
            'reference'   => "payment:{$payment->id}",
            'date'        => $payment->payment_date?->toDateString() ?? now()->toDateString(),
            'status'      => 'posted',
            'lines'       => [
                ['account_id' => $payment->account_id, 'debit' => (float) $payment->amount, 'credit' => 0],
                ['account_id' => $receiveAccountId,     'debit' => 0, 'credit' => (float) $payment->amount],
            ],
        ]);
    }

    /**
     * Post an inventory adjustment as a stock movement.
     */
    public function postStockAdjustment(
        string $workspaceId,
        string $userId,
        string $warehouseId,
        string $productId,
        string $type,     // 'adjustment_increase' | 'adjustment_decrease'
        float $quantity,
        ?string $reason = null,
    ): \App\Models\InventoryMovement {
        return $this->movementService->create($workspaceId, $userId, [
            'warehouse_id'   => $warehouseId,
            'product_id'     => $productId,
            'movement_type'  => $type,
            'quantity_change' => $quantity,
            'reference_type' => 'adjustment',
            'reason_code'    => $reason,
        ]);
    }
}
