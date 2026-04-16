<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\StoreProductRequest;
use App\Http\Requests\UpdateProductRequest;
use App\Http\Resources\ProductResource;
use App\Services\ProductService;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

class ProductController extends Controller
{
    public function __construct(
        private readonly ProductService $products,
        private readonly WorkspaceContextManager $context,
    ) {}

    public function index(Request $request): AnonymousResourceCollection
    {
        $result = $this->products->list(
            $this->context->workspaceId(),
            $request->only(['category_id', 'type', 'search', 'per_page']),
        );
        return ProductResource::collection($result);
    }

    public function show(string $id): JsonResponse
    {
        $product = $this->products->find($this->context->workspaceId(), $id);
        if (! $product) {
            return response()->json(['message' => 'Product not found.'], 404);
        }
        return response()->json(['data' => new ProductResource($product)]);
    }

    public function store(StoreProductRequest $request): JsonResponse
    {
        $product = $this->products->create(
            $this->context->workspaceId(),
            $request->validated(),
        );
        return response()->json(['data' => new ProductResource($product)], 201);
    }

    public function update(UpdateProductRequest $request, string $id): JsonResponse
    {
        $product = $this->products->find($this->context->workspaceId(), $id);
        if (! $product) {
            return response()->json(['message' => 'Product not found.'], 404);
        }
        $updated = $this->products->update($product, $request->validated());
        return response()->json(['data' => new ProductResource($updated)]);
    }

    /**
     * Soft-delete via is_deleted flag.
     */
    public function destroy(string $id): JsonResponse
    {
        $product = $this->products->find($this->context->workspaceId(), $id);
        if (! $product) {
            return response()->json(['message' => 'Product not found.'], 404);
        }
        $this->products->delete($product);
        return response()->json(['message' => 'Product deleted.']);
    }
}
