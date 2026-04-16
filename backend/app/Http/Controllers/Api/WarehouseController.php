<?php
namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\WarehouseResource;
use App\Services\WarehouseService;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class WarehouseController extends Controller
{
    public function __construct(
        private readonly WarehouseService $warehouses,
        private readonly WorkspaceContextManager $context,
    ) {}

    public function index(): JsonResponse
    {
        $list = $this->warehouses->list($this->context->workspaceId());
        return response()->json(['data' => WarehouseResource::collection($list)]);
    }

    public function show(string $id): JsonResponse
    {
        $wh = $this->warehouses->find($this->context->workspaceId(), $id);
        if (! $wh) return response()->json(['message' => 'Warehouse not found.'], 404);
        return response()->json(['data' => new WarehouseResource($wh)]);
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'name'     => ['required', 'string', 'max:255'],
            'location' => ['nullable', 'string'],
        ]);
        $wh = $this->warehouses->create($this->context->workspaceId(), $data);
        return response()->json(['data' => new WarehouseResource($wh)], 201);
    }

    public function update(Request $request, string $id): JsonResponse
    {
        $wh = $this->warehouses->find($this->context->workspaceId(), $id);
        if (! $wh) return response()->json(['message' => 'Warehouse not found.'], 404);
        $data = $request->validate(['name' => ['sometimes', 'string'], 'location' => ['sometimes', 'nullable', 'string']]);
        $updated = $this->warehouses->update($wh, $data);
        return response()->json(['data' => new WarehouseResource($updated)]);
    }

    public function destroy(string $id): JsonResponse
    {
        $wh = $this->warehouses->find($this->context->workspaceId(), $id);
        if (! $wh) return response()->json(['message' => 'Warehouse not found.'], 404);
        $this->warehouses->delete($wh);
        return response()->json(['message' => 'Warehouse deleted.']);
    }
}
