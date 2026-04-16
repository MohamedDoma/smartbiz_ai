<?php
namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\ProductionOrderResource;
use App\Services\ProductionOrderService;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

class ProductionOrderController extends Controller
{
    public function __construct(
        private readonly ProductionOrderService $orders,
        private readonly WorkspaceContextManager $context,
    ) {}

    public function index(Request $request): AnonymousResourceCollection
    {
        return ProductionOrderResource::collection(
            $this->orders->list($this->context->workspaceId(), $request->only(['status', 'product_id', 'per_page']))
        );
    }

    public function show(string $id): JsonResponse
    {
        $o = $this->orders->find($this->context->workspaceId(), $id);
        if (! $o) return response()->json(['message' => 'Production order not found.'], 404);
        return response()->json(['data' => new ProductionOrderResource($o)]);
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'product_id'               => ['required', 'uuid'],
            'target_quantity'          => ['required', 'numeric', 'gt:0'],
            'warehouse_id'             => ['nullable', 'uuid'],
            'production_order_number'  => ['nullable', 'string', 'max:50'],
            'start_date'               => ['nullable', 'date'],
            'end_date'                 => ['nullable', 'date', 'after_or_equal:start_date'],
        ]);
        $o = $this->orders->create($this->context->workspaceId(), $request->user()->id, $data);
        return response()->json(['data' => new ProductionOrderResource($o)], 201);
    }

    public function update(Request $request, string $id): JsonResponse
    {
        $o = $this->orders->find($this->context->workspaceId(), $id);
        if (! $o) return response()->json(['message' => 'Production order not found.'], 404);
        $data = $request->validate([
            'status'          => ['sometimes', 'in:planned,in_progress,done,cancelled'],
            'target_quantity' => ['sometimes', 'numeric', 'gt:0'],
            'start_date'      => ['sometimes', 'nullable', 'date'],
            'end_date'        => ['sometimes', 'nullable', 'date'],
        ]);
        $updated = $this->orders->update($o, $data);
        return response()->json(['data' => new ProductionOrderResource($updated)]);
    }
}
