<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\StoreOrderRequest;
use App\Http\Resources\OrderResource;
use App\Services\OrderService;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

class OrderController extends Controller
{
    public function __construct(
        private readonly OrderService $orders,
        private readonly WorkspaceContextManager $context,
    ) {}

    public function index(Request $request): AnonymousResourceCollection
    {
        $result = $this->orders->list(
            $this->context->workspaceId(),
            $request->only(['status', 'order_type', 'contact_id', 'per_page']),
        );
        return OrderResource::collection($result);
    }

    public function show(string $id): JsonResponse
    {
        $order = $this->orders->find($this->context->workspaceId(), $id);
        if (! $order) {
            return response()->json(['message' => 'Order not found.'], 404);
        }
        return response()->json(['data' => new OrderResource($order)]);
    }

    public function store(StoreOrderRequest $request): JsonResponse
    {
        $order = $this->orders->create(
            $this->context->workspaceId(),
            $request->user()->id,
            $request->validated(),
        );
        return response()->json(['data' => new OrderResource($order)], 201);
    }

    public function update(Request $request, string $id): JsonResponse
    {
        $order = $this->orders->find($this->context->workspaceId(), $id);
        if (! $order) {
            return response()->json(['message' => 'Order not found.'], 404);
        }

        $validated = $request->validate([
            'status'       => ['sometimes', 'string', 'in:draft,confirmed,processing,completed,cancelled'],
            'notes'        => ['sometimes', 'nullable', 'string'],
            'order_number' => ['sometimes', 'nullable', 'string', 'max:100'],
            'valid_until'  => ['sometimes', 'nullable', 'date'],
        ]);

        $updated = $this->orders->update($order, $validated);
        return response()->json(['data' => new OrderResource($updated)]);
    }
}
