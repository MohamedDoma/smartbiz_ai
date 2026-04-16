<?php

namespace App\Services;

use App\Models\ProductCategory;
use Illuminate\Database\Eloquent\Collection;

class ProductCategoryService
{
    public function list(string $workspaceId): Collection
    {
        return ProductCategory::where('workspace_id', $workspaceId)
            ->with('children')
            ->whereNull('parent_id')
            ->orderBy('name')
            ->get();
    }

    public function all(string $workspaceId): Collection
    {
        return ProductCategory::where('workspace_id', $workspaceId)
            ->orderBy('name')
            ->get();
    }

    public function find(string $workspaceId, string $id): ?ProductCategory
    {
        return ProductCategory::where('workspace_id', $workspaceId)
            ->with('children')
            ->where('id', $id)
            ->first();
    }

    public function create(string $workspaceId, array $data): ProductCategory
    {
        return ProductCategory::create(array_merge($data, [
            'workspace_id' => $workspaceId,
        ]));
    }

    public function update(ProductCategory $category, array $data): ProductCategory
    {
        $category->update($data);
        return $category->fresh();
    }

    public function delete(ProductCategory $category): void
    {
        $category->delete();
    }
}
