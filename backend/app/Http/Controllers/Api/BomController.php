<?php
namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\BomResource;
use App\Services\BomService;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class BomController extends Controller
{
    public function __construct(
        private readonly BomService $bom,
        private readonly WorkspaceContextManager $context,
    ) {}

    public function index(Request $request): JsonResponse
    {
        $wsId = $this->context->workspaceId();
        $list = $request->has('final_product_id')
            ? $this->bom->listByProduct($wsId, $request->input('final_product_id'))
            : $this->bom->list($wsId);
        return response()->json(['data' => BomResource::collection($list)]);
    }

    public function show(string $id): JsonResponse
    {
        $b = $this->bom->find($this->context->workspaceId(), $id);
        if (! $b) return response()->json(['message' => 'BOM entry not found.'], 404);
        return response()->json(['data' => new BomResource($b)]);
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'final_product_id'  => ['required', 'uuid'],
            'raw_material_id'   => ['required', 'uuid'],
            'quantity_required' => ['required', 'numeric', 'gt:0'],
        ]);
        $b = $this->bom->create($this->context->workspaceId(), $data);
        return response()->json(['data' => new BomResource($b)], 201);
    }

    public function update(Request $request, string $id): JsonResponse
    {
        $b = $this->bom->find($this->context->workspaceId(), $id);
        if (! $b) return response()->json(['message' => 'BOM entry not found.'], 404);
        $data = $request->validate(['quantity_required' => ['sometimes', 'numeric', 'gt:0']]);
        $updated = $this->bom->update($b, $data);
        return response()->json(['data' => new BomResource($updated)]);
    }

    public function destroy(string $id): JsonResponse
    {
        $b = $this->bom->find($this->context->workspaceId(), $id);
        if (! $b) return response()->json(['message' => 'BOM entry not found.'], 404);
        $this->bom->delete($b);
        return response()->json(['message' => 'BOM entry deleted.']);
    }
}
