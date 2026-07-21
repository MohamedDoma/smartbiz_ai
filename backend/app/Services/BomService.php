<?php

namespace App\Services;

use App\Models\BillOfMaterial;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Support\Facades\DB;

class BomService
{
    public function listByProduct(string $workspaceId, string $finalProductId): Collection
    {
        return BillOfMaterial::where('workspace_id', $workspaceId)
            ->where('final_product_id', $finalProductId)
            ->with(['rawMaterial'])
            ->get();
    }

    public function list(string $workspaceId): Collection
    {
        return BillOfMaterial::where('workspace_id', $workspaceId)
            ->with(['finalProduct', 'rawMaterial'])
            ->get();
    }

    public function find(string $workspaceId, string $id): ?BillOfMaterial
    {
        return BillOfMaterial::where('workspace_id', $workspaceId)
            ->with(['finalProduct', 'rawMaterial'])
            ->find($id);
    }

    public function create(string $workspaceId, array $data): BillOfMaterial
    {
        return DB::transaction(
            fn (): BillOfMaterial => BillOfMaterial::create(array_merge($data, [
                'workspace_id' => $workspaceId,
            ])),
        );
    }

    public function update(BillOfMaterial $bom, array $data): BillOfMaterial
    {
        return DB::transaction(function () use ($bom, $data): BillOfMaterial {
            $bom->update($data);

            return $bom->fresh();
        });
    }

    public function delete(BillOfMaterial $bom): void
    {
        $bom->delete();
    }
}
