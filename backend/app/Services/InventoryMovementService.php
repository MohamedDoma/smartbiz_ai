<?php

namespace App\Services;

use App\Models\InventoryMovement;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Support\Facades\DB;

class InventoryMovementService
{
    /**
     * Movement types that INCREASE stock (positive quantity_change).
     */
    const INCREASE_TYPES = [
        'purchase_receipt', 'return_restock', 'adjustment_increase',
        'transfer_in', 'production_output', 'opening_balance',
    ];

    /**
     * Movement types that DECREASE stock (negative quantity_change).
     */
    const DECREASE_TYPES = [
        'sale_shipment', 'return_dispose', 'supplier_return',
        'adjustment_decrease', 'transfer_out', 'production_consume',
        'damage', 'shrinkage', 'expired',
    ];

    public function list(string $workspaceId, array $filters = []): LengthAwarePaginator
    {
        $query = InventoryMovement::where('workspace_id', $workspaceId);

        if (! empty($filters['warehouse_id'])) {
            $query->where('warehouse_id', $filters['warehouse_id']);
        }
        if (! empty($filters['product_id'])) {
            $query->where('product_id', $filters['product_id']);
        }
        if (! empty($filters['movement_type'])) {
            $query->where('movement_type', $filters['movement_type']);
        }

        return $query->with(['warehouse', 'product'])
            ->orderByDesc('created_at')
            ->paginate($filters['per_page'] ?? 25);
    }

    public function find(string $workspaceId, string $id): ?InventoryMovement
    {
        return InventoryMovement::where('workspace_id', $workspaceId)
            ->with(['warehouse', 'product'])
            ->find($id);
    }

    /**
     * Create an inventory movement.
     * Automatically calculates quantity_before and quantity_after
     * by reading the last movement for this product+warehouse.
     *
     * NOTE: This table is IMMUTABLE — the DB trigger blocks updates.
     */
    public function create(string $workspaceId, string $userId, array $data): InventoryMovement
    {
        return DB::transaction(function () use ($workspaceId, $userId, $data) {
            $movementType = $data['movement_type'];
            $quantityChange = abs((float) $data['quantity_change']);

            // Enforce sign based on movement type
            if (in_array($movementType, self::DECREASE_TYPES)) {
                $quantityChange = -$quantityChange;
            }

            // Get current stock level for this product+warehouse
            $currentLevel = $this->getCurrentStockLevel(
                $workspaceId,
                $data['warehouse_id'],
                $data['product_id'],
            );

            $quantityAfter = $currentLevel + $quantityChange;

            // Prevent negative stock
            if ($quantityAfter < 0) {
                throw new \App\Exceptions\InsufficientStockException(
                    "Insufficient stock: current level is {$currentLevel}, " .
                    "attempted change of {$quantityChange} would result in negative stock."
                );
            }

            return InventoryMovement::create([
                'workspace_id'    => $workspaceId,
                'warehouse_id'    => $data['warehouse_id'],
                'product_id'      => $data['product_id'],
                'variant_id'      => $data['variant_id'] ?? null,
                'batch_id'        => $data['batch_id'] ?? null,
                'movement_type'   => $movementType,
                'quantity_change'  => $quantityChange,
                'quantity_before'  => $currentLevel,
                'quantity_after'   => $quantityAfter,
                'unit_cost'        => $data['unit_cost'] ?? null,
                'total_cost'       => isset($data['unit_cost']) ? abs($quantityChange) * $data['unit_cost'] : null,
                'reference_type'   => $data['reference_type'] ?? null,
                'reference_id'     => $data['reference_id'] ?? null,
                'created_by'       => $userId,
                'reason_code'      => $data['reason_code'] ?? null,
                'notes'            => $data['notes'] ?? null,
            ]);
        });
    }

    /**
     * Get current stock level for a product in a specific warehouse.
     * Uses the last movement's quantity_after as current level.
     */
    public function getCurrentStockLevel(string $workspaceId, string $warehouseId, string $productId): float
    {
        $lastMovement = InventoryMovement::where('workspace_id', $workspaceId)
            ->where('warehouse_id', $warehouseId)
            ->where('product_id', $productId)
            ->orderByDesc('created_at')
            ->orderByDesc('id')
            ->first();

        return $lastMovement ? (float) $lastMovement->quantity_after : 0;
    }

    /**
     * Get inventory levels across all warehouses for a workspace.
     */
    public function getInventoryLevels(string $workspaceId, array $filters = []): array
    {
        $query = DB::table('inventory_movements')
            ->select([
                'warehouse_id',
                'product_id',
                DB::raw("(SELECT name FROM warehouses WHERE id = inventory_movements.warehouse_id) as warehouse_name"),
                DB::raw("(SELECT name FROM products WHERE id = inventory_movements.product_id) as product_name"),
                DB::raw("(SELECT sku FROM products WHERE id = inventory_movements.product_id) as sku"),
            ])
            ->where('workspace_id', $workspaceId)
            ->groupBy('warehouse_id', 'product_id');

        if (! empty($filters['warehouse_id'])) {
            $query->where('warehouse_id', $filters['warehouse_id']);
        }
        if (! empty($filters['product_id'])) {
            $query->where('product_id', $filters['product_id']);
        }

        $groups = $query->get();
        $levels = [];

        foreach ($groups as $group) {
            $currentQty = $this->getCurrentStockLevel($workspaceId, $group->warehouse_id, $group->product_id);

            // Check low stock alert
            $minAlert = DB::table('products')
                ->where('id', $group->product_id)
                ->value('min_stock_alert');

            $levels[] = [
                'warehouse_id'   => $group->warehouse_id,
                'warehouse_name' => $group->warehouse_name,
                'product_id'     => $group->product_id,
                'product_name'   => $group->product_name,
                'sku'            => $group->sku,
                'current_stock'  => $currentQty,
                'min_stock_alert'=> $minAlert,
                'low_stock'      => $minAlert !== null && $currentQty <= (float) $minAlert,
            ];
        }

        return $levels;
    }
}
