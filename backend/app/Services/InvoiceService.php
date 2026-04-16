<?php

namespace App\Services;

use App\Models\Invoice;
use App\Models\InvoiceItem;
use App\Models\Product;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Support\Facades\DB;

class InvoiceService
{
    public function list(string $workspaceId, array $filters = []): LengthAwarePaginator
    {
        $query = Invoice::where('workspace_id', $workspaceId);

        if (! empty($filters['payment_status'])) {
            $query->where('payment_status', $filters['payment_status']);
        }

        if (! empty($filters['invoice_type'])) {
            $query->where('invoice_type', $filters['invoice_type']);
        }

        if (! empty($filters['contact_id'])) {
            $query->where('contact_id', $filters['contact_id']);
        }

        return $query->with('contact')
            ->orderByDesc('created_at')
            ->paginate($filters['per_page'] ?? 25);
    }

    public function find(string $workspaceId, string $invoiceId): ?Invoice
    {
        return Invoice::where('workspace_id', $workspaceId)
            ->with(['contact', 'items'])
            ->where('id', $invoiceId)
            ->first();
    }

    /**
     * Create an invoice with its items in a single transaction.
     *
     * Items are created as child records via the Invoice relationship,
     * enforcing the child-table access rule.
     */
    public function create(string $workspaceId, string $userId, array $data): Invoice
    {
        return DB::transaction(function () use ($workspaceId, $userId, $data) {
            $items = $data['items'] ?? [];
            unset($data['items']);

            // Calculate totals from items
            $totalAmount = 0;
            $totalDiscount = 0;
            $totalTax = 0;

            foreach ($items as &$item) {
                $lineTotal = $item['quantity'] * $item['unit_price'];
                $discount = $item['discount_amount'] ?? 0;
                $tax = $item['tax_amount'] ?? 0;
                // subtotal = line total minus discount (tax is tracked separately)
                $item['subtotal'] = $lineTotal - $discount;
                $item['discount_amount'] = $discount;
                $item['tax_amount'] = $tax;

                // Snapshot product data at time of invoice creation
                if (! empty($item['product_id'])) {
                    $product = Product::find($item['product_id']);
                    if ($product) {
                        $item['product_name_snapshot'] = $item['product_name_snapshot'] ?? $product->name;
                        $item['sku_snapshot'] = $item['sku_snapshot'] ?? $product->sku;
                    }
                }

                $totalAmount += $lineTotal;
                $totalDiscount += $discount;
                $totalTax += $tax;
            }

            $invoice = Invoice::create(array_merge($data, [
                'workspace_id'   => $workspaceId,
                'created_by'     => $userId,
                'total_amount'   => $totalAmount,
                'discount_amount'=> $totalDiscount,
                'tax_amount'     => $totalTax,
                'net_amount'     => $totalAmount - $totalDiscount,
                'payment_status' => $data['payment_status'] ?? 'unpaid',
                'invoice_type'   => $data['invoice_type'] ?? 'sale',
                'currency'       => $data['currency'] ?? 'USD',
                'exchange_rate'  => $data['exchange_rate'] ?? 1.0,
            ]));

            // Create items via relationship (child-table access rule)
            foreach ($items as $item) {
                $invoice->items()->create($item);
            }

            return $invoice->load('items');
        });
    }

    /**
     * Update only invoice-level fields (not items).
     */
    public function update(Invoice $invoice, array $data): Invoice
    {
        unset($data['items']); // Items are not updateable via this method
        $invoice->update($data);
        return $invoice->fresh(['contact', 'items']);
    }
}
