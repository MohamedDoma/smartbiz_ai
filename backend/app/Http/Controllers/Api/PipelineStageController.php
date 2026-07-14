<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Pipeline;
use App\Models\PipelineStage;
use App\Services\PipelineAuditService;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

class PipelineStageController extends Controller
{
    public function index(string $pipelineId): JsonResponse
    {
        $wsId = app(WorkspaceContextManager::class)->workspaceId();
        Pipeline::where('workspace_id', $wsId)->findOrFail($pipelineId);

        $stages = PipelineStage::where('pipeline_id', $pipelineId)
            ->where('workspace_id', $wsId)
            ->withCount('records')
            ->orderBy('sort_order')
            ->get();

        return response()->json([
            'data' => $stages->map(fn ($s) => $this->fmt($s)),
        ]);
    }

    public function store(Request $request, string $pipelineId): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        Pipeline::where('workspace_id', $ctx->workspaceId())->findOrFail($pipelineId);

        $validated = $request->validate([
            'name'        => 'required|string|max:255',
            'description' => 'nullable|string|max:1000',
            'status_type' => 'nullable|string|in:open,won,lost,completed,cancelled',
            'sort_order'  => 'nullable|integer|min:0',
        ]);

        $stage = PipelineStage::create([
            'workspace_id' => $ctx->workspaceId(),
            'pipeline_id'  => $pipelineId,
            'stage_key'    => Str::slug($validated['name'], '_'),
            'name'         => $validated['name'],
            'description'  => $validated['description'] ?? null,
            'status_type'  => $validated['status_type'] ?? 'open',
            'sort_order'   => $validated['sort_order'] ?? 0,
            'is_active'    => true,
        ]);

        PipelineAuditService::log($ctx->workspaceId(), 'created', 'pipeline_stage', $stage->id, null, [
            'name' => $stage->name, 'pipeline_id' => $pipelineId, 'status_type' => $stage->status_type,
        ]);

        return response()->json(['data' => $this->fmt($stage)], 201);
    }

    public function update(Request $request, string $id): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $stage = PipelineStage::where('workspace_id', $ctx->workspaceId())->findOrFail($id);

        $validated = $request->validate([
            'name'        => 'sometimes|required|string|max:255',
            'description' => 'nullable|string|max:1000',
            'status_type' => 'nullable|string|in:open,won,lost,completed,cancelled',
            'sort_order'  => 'nullable|integer|min:0',
            'is_active'   => 'sometimes|boolean',
        ]);

        if (isset($validated['name'])) {
            $validated['stage_key'] = Str::slug($validated['name'], '_');
        }

        $oldValues = $stage->only(['name', 'description', 'status_type', 'sort_order', 'is_active']);
        $stage->update($validated);
        $diff = PipelineAuditService::diff($oldValues, $stage->only(array_keys($oldValues)));
        if (!empty($diff)) {
            PipelineAuditService::log($ctx->workspaceId(), 'updated', 'pipeline_stage', $stage->id, $oldValues, $diff);
        }

        return response()->json(['data' => $this->fmt($stage->fresh())]);
    }

    public function destroy(Request $request, string $id): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $stage = PipelineStage::where('workspace_id', $ctx->workspaceId())->findOrFail($id);

        $activeCount = $stage->records()->where('status', 'open')->count();
        $stage->update(['is_active' => false]);

        PipelineAuditService::log($ctx->workspaceId(), 'deleted', 'pipeline_stage', $stage->id, [
            'name' => $stage->name, 'had_open_records' => $activeCount > 0,
        ]);

        if ($activeCount > 0) {
            return response()->json(['message' => 'Stage deactivated (has open records).'], 200);
        }

        return response()->json(['message' => 'Stage deactivated.']);
    }

    private function fmt(PipelineStage $s): array
    {
        return [
            'id'           => $s->id,
            'pipeline_id'  => $s->pipeline_id,
            'stage_key'    => $s->stage_key,
            'name'         => $s->name,
            'description'  => $s->description,
            'status_type'  => $s->status_type,
            'sort_order'   => $s->sort_order,
            'is_active'    => $s->is_active,
            'records_count' => $s->records_count ?? null,
            'created_at'   => $s->created_at?->toIso8601String(),
        ];
    }
}
