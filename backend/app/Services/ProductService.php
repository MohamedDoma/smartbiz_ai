<?php

namespace App\Services;

use App\Models\Product;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;

class ProductService
{
    public function list(string $workspaceId, array $filters = []): LengthAwarePaginator
    {
        $query = Product::where('workspace_id', $workspaceId)->active();

        if (! empty($filters['category_id'])) {
            $query->where('category_id', $filters['category_id']);
        }

        if (! empty($filters['type'])) {
            $query->where('type', $filters['type']);
        }

        if (! empty($filters['search'])) {
            $search = $filters['search'];
            $query->where(function ($q) use ($search) {
                $q->where('name', 'ilike', "%{$search}%")
                  ->orWhere('sku', 'ilike', "%{$search}%");
            });
        }

        return $query->with('category')
            ->orderBy('name')
            ->paginate($filters['per_page'] ?? 25);
    }

    public function find(string $workspaceId, string $id): ?Product
    {
        return Product::where('workspace_id', $workspaceId)
            ->with('category')
            ->where('id', $id)
            ->first();
    }

    public function create(string $workspaceId, array $data): Product
    {
        return Product::create(array_merge($data, [
            'workspace_id' => $workspaceId,
        ]));
    }

    public function update(Product $product, array $data): Product
    {
        $product->update($data);
        return $product->fresh('category');
    }

    /**
     * Soft-delete via is_deleted flag (not Laravel SoftDeletes).
     */
    public function delete(Product $product): void
    {
        $product->update(['is_deleted' => true]);
    }
}
