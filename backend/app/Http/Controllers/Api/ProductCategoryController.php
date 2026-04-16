<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\StoreProductCategoryRequest;
use App\Http\Resources\ProductCategoryResource;
use App\Services\ProductCategoryService;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;

class ProductCategoryController extends Controller
{
    public function __construct(
        private readonly ProductCategoryService $categories,
        private readonly WorkspaceContextManager $context,
    ) {}

    public function index(): JsonResponse
    {
        $tree = $this->categories->list($this->context->workspaceId());
        return response()->json(['data' => ProductCategoryResource::collection($tree)]);
    }

    public function show(string $id): JsonResponse
    {
        $category = $this->categories->find($this->context->workspaceId(), $id);
        if (! $category) {
            return response()->json(['message' => 'Category not found.'], 404);
        }
        return response()->json(['data' => new ProductCategoryResource($category)]);
    }

    public function store(StoreProductCategoryRequest $request): JsonResponse
    {
        $category = $this->categories->create(
            $this->context->workspaceId(),
            $request->validated(),
        );
        return response()->json(['data' => new ProductCategoryResource($category)], 201);
    }

    public function update(StoreProductCategoryRequest $request, string $id): JsonResponse
    {
        $category = $this->categories->find($this->context->workspaceId(), $id);
        if (! $category) {
            return response()->json(['message' => 'Category not found.'], 404);
        }
        $updated = $this->categories->update($category, $request->validated());
        return response()->json(['data' => new ProductCategoryResource($updated)]);
    }

    public function destroy(string $id): JsonResponse
    {
        $category = $this->categories->find($this->context->workspaceId(), $id);
        if (! $category) {
            return response()->json(['message' => 'Category not found.'], 404);
        }
        $this->categories->delete($category);
        return response()->json(['message' => 'Category deleted.']);
    }
}
