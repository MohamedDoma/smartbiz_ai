<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\DuplicateMatch;
use App\Models\WorkspaceMembership;
use App\Services\DuplicateDetectionService;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class DuplicateMatchController extends Controller
{

    public function check(Request $request): JsonResponse
    {
        $wsId = app(WorkspaceContextManager::class)->workspaceId();

        $v = $request->validate([
            'entity_type'       => 'required|string|in:contact,pipeline_record',
            'payload'           => 'required|array',
            'exclude_entity_id' => 'nullable|uuid',
        ]);

        $svc = new DuplicateDetectionService();
        $result = $svc->check(
            $wsId,
            $v['entity_type'],
            $v['payload'],
            $v['exclude_entity_id'] ?? null,
        );

        return response()->json(['data' => $result]);
    }

    public function index(Request $request): JsonResponse
    {
        $wsId = app(WorkspaceContextManager::class)->workspaceId();
        $q = DuplicateMatch::where('workspace_id', $wsId)
            ->with(['rule:id,name,entity_type'])
            ->orderByDesc('created_at');

        if ($request->filled('status')) $q->where('status', $request->input('status'));
        if ($request->filled('entity_type')) $q->where('entity_type', $request->input('entity_type'));

        return response()->json(['data' => $q->get()->map(fn ($m) => $this->fmt($m))]);
    }

    public function resolve(Request $request, string $id): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);

        $match = DuplicateMatch::where('workspace_id', $ctx->workspaceId())->findOrFail($id);

        if ($match->status === 'resolved') {
            return response()->json(['message' => 'Match already resolved.'], 409);
        }

        $v = $request->validate([
            'resolution' => 'required|string|in:keep_separate,duplicate_confirmed,merged_later',
        ]);

        $currentUser = $request->user();
        $membership = WorkspaceMembership::where('workspace_id', $ctx->workspaceId())
            ->where('user_id', $currentUser->id)->first();

        $match->update([
            'status'                     => 'resolved',
            'resolution'                 => $v['resolution'],
            'resolved_by_membership_id'  => $membership?->id,
            'resolved_at'                => now(),
        ]);

        return response()->json(['data' => $this->fmt($match->fresh())]);
    }

    private function fmt(DuplicateMatch $m): array
    {
        return [
            'id'                => $m->id,
            'duplicate_rule_id' => $m->duplicate_rule_id,
            'rule'              => $m->relationLoaded('rule') && $m->rule
                ? ['id' => $m->rule->id, 'name' => $m->rule->name, 'entity_type' => $m->rule->entity_type]
                : null,
            'entity_type'       => $m->entity_type,
            'source_entity_id'  => $m->source_entity_id,
            'matched_entity_id' => $m->matched_entity_id,
            'match_fields'      => $m->match_fields,
            'match_score'       => $m->match_score,
            'status'            => $m->status,
            'resolution'        => $m->resolution,
            'resolved_at'       => $m->resolved_at?->toIso8601String(),
            'created_at'        => $m->created_at?->toIso8601String(),
        ];
    }
}
