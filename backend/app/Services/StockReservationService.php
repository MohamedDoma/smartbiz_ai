<?php

namespace App\Services;

use App\Models\StockReservation;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;

class StockReservationService
{
    public function list(string $workspaceId, array $filters = []): LengthAwarePaginator
    {
        $query = StockReservation::where('workspace_id', $workspaceId);

        if (! empty($filters['status'])) {
            $query->where('status', $filters['status']);
        }
        if (! empty($filters['order_id'])) {
            $query->where('order_id', $filters['order_id']);
        }
        if (! empty($filters['product_id'])) {
            $query->where('product_id', $filters['product_id']);
        }
        if (! empty($filters['warehouse_id'])) {
            $query->where('warehouse_id', $filters['warehouse_id']);
        }

        return $query->with(['order', 'warehouse', 'product'])
            ->orderByDesc('created_at')
            ->paginate($filters['per_page'] ?? 25);
    }

    public function find(string $workspaceId, string $id): ?StockReservation
    {
        return StockReservation::where('workspace_id', $workspaceId)
            ->with(['order', 'warehouse', 'product'])
            ->find($id);
    }

    public function create(string $workspaceId, array $data): StockReservation
    {
        return StockReservation::create(array_merge($data, [
            'workspace_id'       => $workspaceId,
            'status'             => 'active',
            'reserved_at'        => now(),
            'fulfilled_quantity'  => 0,
            'released_quantity'   => 0,
        ]));
    }

    /**
     * Release a reservation (cancel it).
     */
    public function release(StockReservation $reservation): StockReservation
    {
        if ($reservation->status === 'released') {
            throw new \InvalidArgumentException('Reservation is already released.');
        }

        $remaining = (float) $reservation->reserved_quantity
            - (float) $reservation->fulfilled_quantity;

        $reservation->update([
            'released_quantity' => $remaining,
            'status'            => 'released',
            'released_at'       => now(),
        ]);

        return $reservation->fresh();
    }

    /**
     * Fulfill a reservation (fully or partially).
     */
    public function fulfill(StockReservation $reservation, float $quantity): StockReservation
    {
        if ($reservation->status === 'released') {
            throw new \InvalidArgumentException('Cannot fulfill a released reservation.');
        }

        $newFulfilled = (float) $reservation->fulfilled_quantity + $quantity;
        $max = (float) $reservation->reserved_quantity - (float) $reservation->released_quantity;

        if ($newFulfilled > $max) {
            throw new \InvalidArgumentException(
                "Cannot fulfill {$quantity}: would exceed reserved quantity. " .
                "Max fulfillable: " . ($max - (float) $reservation->fulfilled_quantity)
            );
        }

        $status = $newFulfilled >= (float) $reservation->reserved_quantity
            ? 'fulfilled'
            : 'partially_fulfilled';

        $reservation->update([
            'fulfilled_quantity' => $newFulfilled,
            'status'             => $status,
            'fulfilled_at'       => $status === 'fulfilled' ? now() : $reservation->fulfilled_at,
        ]);

        return $reservation->fresh();
    }
}
