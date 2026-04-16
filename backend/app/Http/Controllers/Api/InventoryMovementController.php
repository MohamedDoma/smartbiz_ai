<?php
namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\StoreInventoryMovementRequest;
use App\Http\Resources\InventoryMovementResource;
use App\Services\InventoryMovementService;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

class InventoryMovementController extends Controller
{
    public function __construct(
        private readonly InventoryMovementService $movements,
        private readonly WorkspaceContextManager $context,
    ) {}

    public function index(Request $request): AnonymousResourceCollection
    {
        return InventoryMovementResource::collection(
            $this->movements->list($this->context->workspaceId(), $request->only(['warehouse_id', 'product_id', 'movement_type', 'per_page']))
        );
    }

    public function show(string $id): JsonResponse
    {
        $m = $this->movements->find($this->context->workspaceId(), $id);
        if (! $m) return response()->json(['message' => 'Inventory movement not found.'], 404);
        return response()->json(['data' => new InventoryMovementResource($m)]);
    }

    /**
     * Create inventory movement. Auto-calculates quantity_before/after.
     * No update endpoint — movements are IMMUTABLE.
     */
    public function store(StoreInventoryMovementRequest $request): JsonResponse
    {
        try {
            $movement = $this->movements->create(
                $this->context->workspaceId(),
                $request->user()->id,
                $request->validated(),
            );
            return response()->json(['data' => new InventoryMovementResource($movement)], 201);
        } catch (\App\Exceptions\InsufficientStockException $e) {
            return response()->json(['message' => $e->getMessage(), 'error' => 'insufficient_stock'], 422);
        }
    }

    /**
     * Inventory levels read layer.
     */
    public function levels(Request $request): JsonResponse
    {
        $levels = $this->movements->getInventoryLevels(
            $this->context->workspaceId(),
            $request->only(['warehouse_id', 'product_id']),
        );
        return response()->json(['data' => $levels]);
    }
}
