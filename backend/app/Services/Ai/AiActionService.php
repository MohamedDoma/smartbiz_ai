<?php

namespace App\Services\Ai;

use App\Events\AiActionConfirmed;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Str;

/**
 * Handles confirm/reject lifecycle for AI-proposed actions.
 *
 * Supports:
 * - draft_contact, draft_product, draft_invoice (Phase 2)
 * - draft_order, draft_payment, draft_inventory_adjustment (Phase 3)
 * - update_invoice_status, update_order_status (Phase 3)
 */
class AiActionService
{
    /**
     * Confirm and execute a pending action.
     */
    public function confirm(string $actionId, string $workspaceId, string $userId): array
    {
        $action = DB::table('ai_change_requests')
            ->where('id', $actionId)
            ->where('workspace_id', $workspaceId)
            ->where('status', 'proposed')
            ->first();

        if (! $action) {
            throw new \InvalidArgumentException('Action not found or already processed.');
        }

        if ($action->expires_at && now()->isAfter($action->expires_at)) {
            DB::table('ai_change_requests')->where('id', $actionId)->update([
                'status'     => 'expired',
                'updated_at' => now(),
            ]);
            throw new \InvalidArgumentException('This action has expired.');
        }

        $diff   = json_decode($action->proposed_diff, true);
        $tool   = $diff['tool'] ?? null;
        $params = $diff['params'] ?? [];

        try {
            $result = match ($tool) {
                'draft_contact'              => $this->executeContact($workspaceId, $params),
                'draft_product'              => $this->executeProduct($workspaceId, $params),
                'draft_invoice'              => $this->executeInvoice($workspaceId, $params),
                'draft_order'                => $this->executeOrder($workspaceId, $params),
                'draft_payment'              => $this->executePayment($workspaceId, $params),
                'draft_inventory_adjustment' => $this->executeInventoryAdjustment($workspaceId, $params),
                'update_invoice_status'      => $this->executeInvoiceStatusUpdate($workspaceId, $params),
                'update_order_status'        => $this->executeOrderStatusUpdate($workspaceId, $params),
                'send_email'                 => $this->executeSendEmail($workspaceId, $params),
                default                      => throw new \InvalidArgumentException("Unknown tool: {$tool}"),
            };

            DB::table('ai_change_requests')->where('id', $actionId)->update([
                'status'       => 'applied',
                'reviewed_by'  => $userId,
                'reviewed_at'  => now(),
                'applied_at'   => now(),
                'applied_diff' => json_encode($result),
                'updated_at'   => now(),
            ]);

            // Dispatch event for email notification
            AiActionConfirmed::dispatch(
                $workspaceId,
                $userId,
                $actionId,
                $action->change_type,
                json_encode($result),
            );

            return ['status' => 'applied', 'result' => $result];
        } catch (\Throwable $e) {
            Log::error("AI action execution failed: {$e->getMessage()}", [
                'action_id' => $actionId,
                'tool'      => $tool,
            ]);
            throw $e;
        }
    }

    /**
     * Reject a pending action.
     */
    public function reject(string $actionId, string $workspaceId, string $userId, string $reason): array
    {
        $updated = DB::table('ai_change_requests')
            ->where('id', $actionId)
            ->where('workspace_id', $workspaceId)
            ->where('status', 'proposed')
            ->update([
                'status'       => 'rejected',
                'reviewed_by'  => $userId,
                'reviewed_at'  => now(),
                'review_notes' => $reason,
                'updated_at'   => now(),
            ]);

        if (! $updated) {
            throw new \InvalidArgumentException('Action not found or already processed.');
        }

        return ['status' => 'rejected'];
    }

    // ── Execution Methods ──────────────────────────

    private function executeContact(string $wsId, array $params): array
    {
        $contact = DB::table('contacts')->insertGetId([
            'id'           => Str::uuid()->toString(),
            'workspace_id' => $wsId,
            'name'         => $params['name'],
            'email'        => $params['email'] ?? null,
            'phone'        => $params['phone'] ?? null,
            'type'         => $params['type'] ?? 'customer',
            'address'      => $params['address'] ?? null,
            'created_at'   => now(),
            'updated_at'   => now(),
        ], 'id');

        return ['entity' => 'contact', 'id' => $contact, 'name' => $params['name']];
    }

    private function executeProduct(string $wsId, array $params): array
    {
        $product = DB::table('products')->insertGetId([
            'id'           => Str::uuid()->toString(),
            'workspace_id' => $wsId,
            'name'         => $params['name'],
            'sku'          => $params['sku'] ?? strtoupper(Str::random(8)),
            'base_price'   => $params['unit_price'] ?? 0,
            'type'         => $params['type'] ?? 'goods',
            'is_deleted'   => false,
            'created_at'   => now(),
            'updated_at'   => now(),
        ], 'id');

        return ['entity' => 'product', 'id' => $product, 'name' => $params['name']];
    }

    private function executeInvoice(string $wsId, array $params): array
    {
        $contactId = $params['resolved_contact_id'] ?? null;
        if (! $contactId) {
            throw new \InvalidArgumentException('Contact must be resolved before invoice creation.');
        }

        $items = [];
        $total = 0;
        foreach ($params['items'] ?? [] as $item) {
            $price = (float) ($item['unit_price'] ?? 0);
            $qty   = (float) ($item['quantity'] ?? 1);
            $total += $price * $qty;
            $items[] = [
                'product_id'   => $item['resolved_product_id'] ?? null,
                'product_name' => $item['resolved_product_name'] ?? $item['product_name'],
                'quantity'     => $qty,
                'unit_price'   => $price,
                'line_total'   => $price * $qty,
            ];
        }

        $invoiceId = Str::uuid()->toString();
        DB::table('invoices')->insert([
            'id'             => $invoiceId,
            'workspace_id'   => $wsId,
            'invoice_number' => 'AI-' . strtoupper(Str::random(6)),
            'invoice_type'   => $params['invoice_type'] ?? 'sale',
            'contact_id'     => $contactId,
            'net_amount'     => $total,
            'tax_amount'     => 0,
            'total_amount'   => $total,
            'payment_status' => 'unpaid',
            'due_date'       => now()->addDays(30)->toDateString(),
            'created_at'     => now(),
            'updated_at'     => now(),
        ]);

        return ['entity' => 'invoice', 'id' => $invoiceId, 'total' => $total, 'items_count' => count($items)];
    }

    private function executeOrder(string $wsId, array $params): array
    {
        $contactId = $params['resolved_contact_id'] ?? null;

        $total = 0;
        foreach ($params['items'] ?? [] as $item) {
            $total += (float) ($item['unit_price'] ?? 0) * (float) ($item['quantity'] ?? 1);
        }

        $orderId = Str::uuid()->toString();
        DB::table('orders')->insert([
            'id'           => $orderId,
            'workspace_id' => $wsId,
            'order_type'   => $params['order_type'] ?? 'sale_order',
            'contact_id'   => $contactId,
            'status'       => 'draft',
            'total_amount' => $total,
            'notes'        => $params['notes'] ?? 'Created via AI assistant',
            'created_at'   => now(),
            'updated_at'   => now(),
        ]);

        return ['entity' => 'order', 'id' => $orderId, 'total' => $total, 'order_type' => $params['order_type'] ?? 'sale_order'];
    }

    private function executePayment(string $wsId, array $params): array
    {
        $invoice = DB::table('invoices')
            ->where('workspace_id', $wsId)
            ->where('invoice_number', $params['invoice_number'] ?? '')
            ->first();

        if (! $invoice) {
            throw new \InvalidArgumentException("Invoice not found: {$params['invoice_number']}");
        }

        $paymentId = Str::uuid()->toString();
        DB::table('payments')->insert([
            'id'              => $paymentId,
            'workspace_id'    => $wsId,
            'invoice_id'      => $invoice->id,
            'amount'          => $params['amount'],
            'payment_method'  => $params['payment_method'] ?? 'cash',
            'payment_date'    => now()->toDateString(),
            'payment_number'  => 'AI-P-' . strtoupper(Str::random(6)),
            'status'          => 'completed',
            'created_at'      => now(),
            'updated_at'      => now(),
        ]);

        return ['entity' => 'payment', 'id' => $paymentId, 'invoice_id' => $invoice->id, 'amount' => $params['amount']];
    }

    private function executeInventoryAdjustment(string $wsId, array $params): array
    {
        $productId = $params['resolved_product_id'] ?? null;
        if (! $productId && ! empty($params['product_name'])) {
            $product = DB::table('products')
                ->where('workspace_id', $wsId)
                ->where('name', 'ILIKE', "%{$params['product_name']}%")
                ->first();
            $productId = $product?->id;
        }
        if (! $productId) {
            throw new \InvalidArgumentException('Product not found for inventory adjustment.');
        }

        $warehouse = DB::table('warehouses')->where('workspace_id', $wsId)->first();
        if (! $warehouse) {
            throw new \InvalidArgumentException('No warehouse found in this workspace.');
        }

        $currentQty = (float) (DB::table('inventory_levels')
            ->where('workspace_id', $wsId)
            ->where('product_id', $productId)
            ->where('warehouse_id', $warehouse->id)
            ->value('quantity') ?? 0);

        $change = (float) $params['quantity_change'];
        $newQty = max(0, $currentQty + $change);

        $movementId = Str::uuid()->toString();
        DB::table('inventory_movements')->insert([
            'id'              => $movementId,
            'workspace_id'    => $wsId,
            'warehouse_id'    => $warehouse->id,
            'product_id'      => $productId,
            'movement_type'   => $change >= 0 ? 'adjustment_in' : 'adjustment_out',
            'quantity_change'  => abs($change),
            'quantity_before' => $currentQty,
            'quantity_after'  => $newQty,
            'reason_code'     => $params['reason'] ?? 'AI adjustment',
            'notes'           => 'Created via AI assistant',
            'created_at'      => now(),
        ]);

        return ['entity' => 'inventory_movement', 'id' => $movementId, 'product_id' => $productId, 'change' => $change, 'new_qty' => $newQty];
    }

    private function executeInvoiceStatusUpdate(string $wsId, array $params): array
    {
        $invoice = DB::table('invoices')
            ->where('workspace_id', $wsId)
            ->where('invoice_number', $params['invoice_number'] ?? '')
            ->first();

        if (! $invoice) {
            throw new \InvalidArgumentException("Invoice not found: {$params['invoice_number']}");
        }

        DB::table('invoices')->where('id', $invoice->id)->update([
            'payment_status' => $params['new_status'],
            'updated_at'     => now(),
        ]);

        return ['entity' => 'invoice', 'id' => $invoice->id, 'old_status' => $invoice->payment_status, 'new_status' => $params['new_status']];
    }

    private function executeOrderStatusUpdate(string $wsId, array $params): array
    {
        $order = DB::table('orders')
            ->where('workspace_id', $wsId)
            ->where('order_number', $params['order_number'] ?? '')
            ->first();

        if (! $order) {
            throw new \InvalidArgumentException("Order not found: {$params['order_number']}");
        }

        DB::table('orders')->where('id', $order->id)->update([
            'status'     => $params['new_status'],
            'updated_at' => now(),
        ]);

        return ['entity' => 'order', 'id' => $order->id, 'old_status' => $order->status, 'new_status' => $params['new_status']];
    }

    /**
     * Execute send_email action.
     * Recipient MUST be a known contact or workspace user.
     */
    private function executeSendEmail(string $wsId, array $params): array
    {
        $recipientEmail = $params['resolved_email'] ?? null;
        $recipientName  = $params['resolved_name'] ?? $params['recipient_name'] ?? 'Recipient';

        if (! $recipientEmail) {
            // Try to resolve from contacts
            $contact = DB::table('contacts')
                ->where('workspace_id', $wsId)
                ->where('name', 'ILIKE', '%' . ($params['recipient_name'] ?? '') . '%')
                ->whereNotNull('email')
                ->first();

            if (! $contact) {
                // Try workspace members
                $member = DB::table('workspace_memberships')
                    ->join('users', 'users.id', '=', 'workspace_memberships.user_id')
                    ->where('workspace_memberships.workspace_id', $wsId)
                    ->where('users.full_name', 'ILIKE', '%' . ($params['recipient_name'] ?? '') . '%')
                    ->select('users.email', 'users.full_name as name')
                    ->first();

                if (! $member) {
                    throw new \InvalidArgumentException('Recipient not found in contacts or workspace members. Cannot send email to unknown recipients.');
                }

                $recipientEmail = $member->email;
                $recipientName  = $member->name;
            } else {
                $recipientEmail = $contact->email;
                $recipientName  = $contact->name;
            }
        }

        // Send through EmailService
        $emailService = app(\App\Services\Email\EmailService::class);
        $logId = $emailService->send(
            $wsId,
            $recipientEmail,
            $recipientName,
            new \App\Mail\InvoiceSentMail($recipientName, '', 0, '', 'USD', ''), // Generic email — body handled via raw
            'ai_send_email',
            [
                'event_name'          => 'AiActionConfirmed',
                'related_entity_type' => 'ai_email',
            ],
        );

        // Also send the actual content as raw mail
        Mail::raw($params['body'] ?? '', function ($msg) use ($recipientEmail, $recipientName, $params) {
            $msg->to($recipientEmail, $recipientName)
                ->subject($params['subject'] ?? 'Message from SmartBiz AI');
        });

        return [
            'entity'          => 'email',
            'recipient_email' => $recipientEmail,
            'recipient_name'  => $recipientName,
            'subject'         => $params['subject'] ?? '',
            'email_log_id'    => $logId,
        ];
    }
}
