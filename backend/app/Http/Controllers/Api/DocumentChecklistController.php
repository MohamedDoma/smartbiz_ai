<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\DocumentChecklist;
use App\Models\Pipeline;
use App\Models\PipelineStage;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

class DocumentChecklistController extends Controller
{

    public function index(Request $request): JsonResponse
    {
        $wsId = app(WorkspaceContextManager::class)->workspaceId();

        $query = DocumentChecklist::where('workspace_id', $wsId)
            ->with(['pipeline:id,name', 'stage:id,name'])
            ->withCount('items')
            ->orderBy('sort_order');

        if ($request->filled('pipeline_id')) {
            $query->where(fn ($q) => $q->where('pipeline_id', $request->input('pipeline_id'))->orWhereNull('pipeline_id'));
        }
        if ($request->filled('stage_id')) {
            $query->where(fn ($q) => $q->where('stage_id', $request->input('stage_id'))->orWhereNull('stage_id'));
        }

        return response()->json(['data' => $query->get()->map(fn ($c) => $this->fmt($c))]);
    }

    public function store(Request $request): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);

        $validated = $request->validate([
            'name'        => 'required|string|max:255',
            'description' => 'nullable|string|max:2000',
            'pipeline_id' => 'nullable|uuid',
            'stage_id'    => 'nullable|uuid',
            'sort_order'  => 'nullable|integer|min:0',
        ]);

        $wsId = $ctx->workspaceId();

        if (!empty($validated['pipeline_id'])) {
            if (!Pipeline::where('workspace_id', $wsId)->where('id', $validated['pipeline_id'])->exists()) {
                return response()->json(['message' => 'Pipeline not found.'], 422);
            }
        }
        if (!empty($validated['stage_id'])) {
            $stageQ = PipelineStage::where('workspace_id', $wsId)->where('id', $validated['stage_id']);
            if (!empty($validated['pipeline_id'])) {
                $stageQ->where('pipeline_id', $validated['pipeline_id']);
            }
            if (!$stageQ->exists()) {
                return response()->json(['message' => 'Stage not found or does not belong to pipeline.'], 422);
            }
        }

        $checklist = DocumentChecklist::create([
            'workspace_id'  => $wsId,
            'pipeline_id'   => $validated['pipeline_id'] ?? null,
            'stage_id'      => $validated['stage_id'] ?? null,
            'checklist_key' => Str::slug($validated['name'], '_'),
            'name'          => $validated['name'],
            'description'   => $validated['description'] ?? null,
            'is_active'     => true,
            'sort_order'    => $validated['sort_order'] ?? 0,
        ]);

        return response()->json(['data' => $this->fmt($checklist)], 201);
    }

    public function show(string $id): JsonResponse
    {
        $wsId = app(WorkspaceContextManager::class)->workspaceId();
        $checklist = DocumentChecklist::where('workspace_id', $wsId)
            ->with(['pipeline:id,name', 'stage:id,name', 'items' => fn ($q) => $q->where('is_active', true)->orderBy('sort_order')])
            ->withCount('items')
            ->findOrFail($id);

        return response()->json(['data' => $this->fmt($checklist)]);
    }

    public function update(Request $request, string $id): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);

        $checklist = DocumentChecklist::where('workspace_id', $ctx->workspaceId())->findOrFail($id);

        $validated = $request->validate([
            'name'        => 'sometimes|required|string|max:255',
            'description' => 'nullable|string|max:2000',
            'is_active'   => 'sometimes|boolean',
            'sort_order'  => 'nullable|integer|min:0',
        ]);

        if (isset($validated['name'])) {
            $validated['checklist_key'] = Str::slug($validated['name'], '_');
        }

        $checklist->update($validated);
        return response()->json(['data' => $this->fmt($checklist->fresh())]);
    }

    public function destroy(Request $request, string $id): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);

        $checklist = DocumentChecklist::where('workspace_id', $ctx->workspaceId())->findOrFail($id);
        $checklist->update(['is_active' => false]);

        return response()->json(['message' => 'Checklist deactivated.']);
    }

    private function fmt(DocumentChecklist $c): array
    {
        return [
            'id'          => $c->id,
            'workspace_id' => $c->workspace_id,
            'pipeline_id' => $c->pipeline_id,
            'pipeline'    => $c->relationLoaded('pipeline') && $c->pipeline ? ['id' => $c->pipeline->id, 'name' => $c->pipeline->name] : null,
            'stage_id'    => $c->stage_id,
            'stage'       => $c->relationLoaded('stage') && $c->stage ? ['id' => $c->stage->id, 'name' => $c->stage->name] : null,
            'checklist_key' => $c->checklist_key,
            'name'        => $c->name,
            'description' => $c->description,
            'is_active'   => $c->is_active,
            'sort_order'  => $c->sort_order,
            'items_count' => $c->items_count ?? null,
            'items'       => $c->relationLoaded('items')
                ? $c->items->map(fn ($i) => [
                    'id' => $i->id, 'title' => $i->title, 'is_required' => $i->is_required,
                    'accepted_file_types' => $i->accepted_file_types, 'max_file_size_mb' => $i->max_file_size_mb,
                    'sort_order' => $i->sort_order, 'is_active' => $i->is_active,
                ])->toArray()
                : null,
            'created_at' => $c->created_at?->toIso8601String(),
        ];
    }
}
