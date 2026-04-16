<?php

namespace App\Services;

use App\Models\ProductionOrder;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;

class ProductionOrderService
{
    public function list(string $workspaceId, array $filters = []): LengthAwarePaginator
    {
        $query = ProductionOrder::where('workspace_id', $workspaceId);

        if (! empty($filters['status'])) {
            $query->where('status', $filters['status']);
        }
        if (! empty($filters['product_id'])) {
            $query->where('product_id', $filters['product_id']);
        }

        return $query->with(['product', 'warehouse'])
            ->orderByDesc('created_at')
            ->paginate($filters['per_page'] ?? 25);
    }

    public function find(string $workspaceId, string $id): ?ProductionOrder
    {
        return ProductionOrder::where('workspace_id', $workspaceId)
            ->with(['product', 'warehouse'])
            ->find($id);
    }

    public function create(string $workspaceId, string $userId, array $data): ProductionOrder
    {
        return ProductionOrder::create(array_merge($data, [
            'workspace_id' => $workspaceId,
            'created_by'   => $userId,
            'status'       => $data['status'] ?? 'planned',
        ]));
    }

    public function update(ProductionOrder $order, array $data): ProductionOrder
    {
        $order->update($data);
        return $order->fresh()->load(['product', 'warehouse']);
    }
}
