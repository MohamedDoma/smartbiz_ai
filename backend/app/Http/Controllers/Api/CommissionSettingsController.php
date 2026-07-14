<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Pipeline;
use App\Models\WorkspaceMembership;
use App\Services\PermissionResolver;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;

class CommissionSettingsController extends Controller
{
    /**
     * Return minimal pipeline + stage options for commission rule configuration.
     *
     * Requires commissions.settings.view only — never pipelines.list.
     * Returns active deal-type pipelines with all their active stages.
     */
    public function options(): JsonResponse
    {
        $ctx        = app(WorkspaceContextManager::class);
        $wsId       = $ctx->workspaceId();
        $membership = $ctx->membership();

        $this->requirePermission($membership, 'commissions.settings.view');

        $pipelines = Pipeline::where('workspace_id', $wsId)
            ->where('is_active', true)
            ->where('entity_type', 'deal')
            ->orderBy('name')
            ->with(['stages' => function ($q) use ($wsId) {
                $q->where('workspace_id', $wsId)
                  ->where('is_active', true)
                  ->orderBy('sort_order')
                  ->select(['id', 'pipeline_id', 'name', 'status_type']);
            }])
            ->get(['id', 'name', 'entity_type']);

        $data = $pipelines->map(fn (Pipeline $p) => [
            'id'          => $p->id,
            'name'        => $p->name,
            'entity_type' => $p->entity_type,
            'stages'      => $p->stages->map(fn ($s) => [
                'id'          => $s->id,
                'name'        => $s->name,
                'status_type' => $s->status_type,
            ])->values(),
        ])->values();

        return response()->json(['data' => ['pipelines' => $data]]);
    }

    private function requirePermission(?WorkspaceMembership $membership, string $permissionKey): void
    {
        $user = request()->user();
        if ($user && $user->is_super_admin) {
            return;
        }

        if (!$membership) {
            abort(403, 'Not a workspace member.');
        }

        $resolver = app(PermissionResolver::class);
        if (!$resolver->can($membership, $permissionKey)) {
            abort(403, 'Insufficient permissions.');
        }
    }
}