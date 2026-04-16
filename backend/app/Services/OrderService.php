<?php

namespace App\Services;

use App\Models\Order;
use App\Models\Product;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Support\Facades\DB;

class OrderService
{
    public function list(string $workspaceId, array $filters = []): LengthAwarePaginator
    {
        $query = Order::where('workspace_id', $workspaceId);

        if (! empty($filters['status'])) {
            $query->where('status', $filters['status']);
        }

        if (! empty($filters['order_type'])) {
            $query->where('order_type', $filters['order_type']);
        }

        if (! empty($filters['contact_id'])) {
            $query->where('contact_id', $filters['contact_id']);
        }

        return $query->with('contact')
            ->orderByDesc('created_at')
            ->paginate($filters['per_page'] ?? 25);
    }

    public function find(string $workspaceId, string $id): ?Order
    {
        return Order::where('workspace_id', $workspaceId)
            ->with(['contact', 'items'])
            ->where('id', $id)
            ->first();
    }

    /**
     * Create order with items in a single transaction.
     * Items are always created via Order::items() (child-table rule).
     */
    public function create(string $workspaceId, string $userId, array $data): Order
    {
        return DB::transaction(function () use ($workspaceId, $userId, $data) {
            $items = $data['items'] ?? [];
            unset($data['items']);

            $totalAmount = 0;

            foreach ($items as &$item) {
                $subtotal = $item['quantity'] * $item['unit_price'];
                $item['subtotal'] = $subtotal;

                // Snapshot product data
                if (! empty($item['product_id'])) {
                    $product = Product::find($item['product_id']);
                    if ($product) {
                        $item['product_name_snapshot'] = $item['product_name_snapshot'] ?? $product->name;
                        $item['sku_snapshot'] = $item['sku_snapshot'] ?? $product->sku;
                    }
                }

                $totalAmount += $subtotal;
            }

            $order = Order::create(array_merge($data, [
                'workspace_id'  => $workspaceId,
                'created_by'    => $userId,
                'total_amount'  => $totalAmount,
                'status'        => $data['status'] ?? 'draft',
                'currency'      => $data['currency'] ?? 'USD',
                'exchange_rate' => $data['exchange_rate'] ?? 1.0,
            ]));

            foreach ($items as $item) {
                $order->items()->create($item);
            }

            return $order->load('items');
        });
    }

    public function update(Order $order, array $data): Order
    {
        unset($data['items']);
        $order->update($data);
        return $order->fresh(['contact', 'items']);
    }
}
