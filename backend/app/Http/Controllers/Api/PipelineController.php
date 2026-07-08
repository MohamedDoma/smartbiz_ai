<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Pipeline;
use App\Models\WorkspaceMembership;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

class PipelineController extends Controller
{
    private const ADMIN_ROLE_KEYS = ['owner', 'admin', 'general_manager', 'manager'];

    public function index(): JsonResponse
    {
        $wsId = app(WorkspaceContextManager::class)->workspaceId();

        $pipelines = Pipeline::where('workspace_id', $wsId)
            ->withCount(['stages', 'records'])
            ->orderBy('sort_order')
            ->orderBy('name')
            ->get();

        return response()->json([
            'data' => $pipelines->map(fn ($p) => $this->formatPipeline($p)),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $this->requireAdmin($ctx->workspaceId(), $request);

        $validated = $request->validate([
            'name'        => 'required|string|max:255',
            'description' => 'nullable|string|max:2000',
            'entity_type' => 'nullable|string|max:50',
            'sort_order'  => 'nullable|integer|min:0',
        ]);

        $pipeline = Pipeline::create([
            'workspace_id' => $ctx->workspaceId(),
            'pipeline_key' => Str::slug($validated['name'], '_'),
            'name'         => $validated['name'],
            'description'  => $validated['description'] ?? null,
            'entity_type'  => $validated['entity_type'] ?? 'generic',
            'is_active'    => true,
            'sort_order'   => $validated['sort_order'] ?? 0,
        ]);

        return response()->json(['data' => $this->formatPipeline($pipeline)], 201);
    }

    public function show(string $id): JsonResponse
    {
        $wsId = app(WorkspaceContextManager::class)->workspaceId();

        $pipeline = Pipeline::where('workspace_id', $wsId)
            ->withCount(['stages', 'records'])
            ->findOrFail($id);

        $pipeline->load(['stages', 'customFields' => fn ($q) => $q->where('is_active', true)->orderBy('sort_order')]);

        return response()->json(['data' => $this->formatPipeline($pipeline)]);
    }

    public function update(Request $request, string $id): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $this->requireAdmin($ctx->workspaceId(), $request);

        $pipeline = Pipeline::where('workspace_id', $ctx->workspaceId())->findOrFail($id);

        $validated = $request->validate([
            'name'        => 'sometimes|required|string|max:255',
            'description' => 'nullable|string|max:2000',
            'entity_type' => 'nullable|string|max:50',
            'is_active'   => 'sometimes|boolean',
            'sort_order'  => 'nullable|integer|min:0',
        ]);

        if (isset($validated['name'])) {
            $validated['pipeline_key'] = Str::slug($validated['name'], '_');
        }

        $pipeline->update($validated);

        return response()->json(['data' => $this->formatPipeline($pipeline->fresh())]);
    }

    public function destroy(Request $request, string $id): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $this->requireAdmin($ctx->workspaceId(), $request);

        $pipeline = Pipeline::where('workspace_id', $ctx->workspaceId())->findOrFail($id);
        $pipeline->update(['is_active' => false]);

        return response()->json(['message' => 'Pipeline deactivated.']);
    }

    private function formatPipeline(Pipeline $p): array
    {
        return [
            'id'           => $p->id,
            'workspace_id' => $p->workspace_id,
            'pipeline_key' => $p->pipeline_key,
            'name'         => $p->name,
            'description'  => $p->description,
            'entity_type'  => $p->entity_type,
            'is_active'    => $p->is_active,
            'sort_order'   => $p->sort_order,
            'stages_count' => $p->stages_count ?? null,
            'records_count' => $p->records_count ?? null,
            'stages'       => $p->relationLoaded('stages')
                ? $p->stages->map(fn ($s) => [
                    'id' => $s->id, 'name' => $s->name, 'status_type' => $s->status_type,
                    'sort_order' => $s->sort_order, 'is_active' => $s->is_active,
                ])->toArray()
                : null,
            'custom_fields' => $p->relationLoaded('customFields')
                ? $p->customFields->map(fn ($f) => [
                    'id' => $f->id, 'field_key' => $f->field_key, 'label' => $f->label,
                    'field_type' => $f->field_type, 'is_required' => $f->is_required,
                    'options' => $f->options,
                ])->toArray()
                : null,
            'created_at' => $p->created_at?->toIso8601String(),
        ];
    }

    private function requireAdmin(string $wsId, Request $request): void
    {
        $user = $request->user();
        if ($user->is_super_admin) return;
        $membership = WorkspaceMembership::where('workspace_id', $wsId)
            ->where('user_id', $user->id)->where('status', 'active')->first();
        if (! $membership) abort(403, 'Not a member.');
        $roleKeys = $membership->membershipRoles()
            ->join('roles', 'roles.id', '=', 'membership_roles.role_id')
            ->pluck('roles.role_key')->toArray();
        if (empty(array_intersect($roleKeys, self::ADMIN_ROLE_KEYS))) {
            abort(403, 'Insufficient permissions.');
        }
    }
}
