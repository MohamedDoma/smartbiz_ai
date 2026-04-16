<?php

namespace App\Services;

use App\Models\Warehouse;
use Illuminate\Database\Eloquent\Collection;

class WarehouseService
{
    public function list(string $workspaceId): Collection
    {
        return Warehouse::where('workspace_id', $workspaceId)
            ->orderBy('name')
            ->get();
    }

    public function find(string $workspaceId, string $id): ?Warehouse
    {
        return Warehouse::where('workspace_id', $workspaceId)->find($id);
    }

    public function create(string $workspaceId, array $data): Warehouse
    {
        return Warehouse::create(array_merge($data, [
            'workspace_id' => $workspaceId,
        ]));
    }

    public function update(Warehouse $warehouse, array $data): Warehouse
    {
        $warehouse->update($data);
        return $warehouse->fresh();
    }

    public function delete(Warehouse $warehouse): void
    {
        $warehouse->delete();
    }
}
