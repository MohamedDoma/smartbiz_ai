<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Workspace;
use App\Models\WorkspaceSubscription;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class PlatformWorkspaceController extends Controller
{
    public function index(): JsonResponse
    {
        $workspaces = Workspace::withCount('activeMemberships')
            ->orderByDesc('created_at')
            ->get()
            ->map(fn ($w) => $this->fmt($w));

        return response()->json(['data' => $workspaces]);
    }

    public function show(string $id): JsonResponse
    {
        $workspace = Workspace::withCount('activeMemberships')
            ->findOrFail($id);

        $sub = WorkspaceSubscription::where('workspace_id', $id)->first();

        $data = $this->fmt($workspace);
        $data['subscription'] = $sub ? [
            'id'                    => $sub->id,
            'plan_id'               => $sub->plan_id ?? null,
            'status'                => $sub->status,
            'trial_ends_at'         => $sub->trial_ends_at?->toIso8601String(),
            'current_period_end'    => $sub->current_period_end?->toIso8601String(),
            'included_employees'    => $sub->included_employees ?? null,
        ] : null;

        return response()->json(['data' => $data]);
    }

    public function updateStatus(Request $request, string $id): JsonResponse
    {
        $v = $request->validate([
            'status' => 'required|string|in:active,suspended,cancelled',
        ]);

        $workspace = Workspace::findOrFail($id);
        $workspace->update([
            'status'    => $v['status'],
            'is_active' => $v['status'] === 'active',
        ]);

        return response()->json(['data' => $this->fmt($workspace->fresh())]);
    }

    public function updateSubscription(Request $request, string $id): JsonResponse
    {
        $v = $request->validate([
            'subscription_status' => 'nullable|string|in:trial,active,past_due,suspended,cancelled',
            'plan_key'            => 'nullable|string|max:50',
            'trial_ends_at'       => 'nullable|date',
            'notes'               => 'nullable|string|max:2000',
        ]);

        $workspace = Workspace::findOrFail($id);

        if (isset($v['subscription_status'])) {
            $workspace->update(['subscription_status' => $v['subscription_status']]);
        }

        // Update WorkspaceSubscription if exists
        $sub = WorkspaceSubscription::where('workspace_id', $id)->first();
        if ($sub) {
            $updates = [];
            if (isset($v['subscription_status'])) $updates['status'] = $v['subscription_status'];
            if (isset($v['trial_ends_at'])) $updates['trial_ends_at'] = $v['trial_ends_at'];
            if (!empty($updates)) $sub->update($updates);
        }

        return response()->json(['data' => $this->fmt($workspace->fresh())]);
    }

    private function fmt(Workspace $w): array
    {
        return [
            'id'                  => $w->id,
            'name'                => $w->name,
            'industry_type'       => $w->industry_type,
            'business_size'       => $w->business_size,
            'status'              => $w->status,
            'subscription_status' => $w->subscription_status,
            'is_active'           => $w->is_active,
            'members_count'       => $w->active_memberships_count ?? null,
            'default_locale'      => $w->default_locale,
            'created_at'          => $w->created_at?->toIso8601String(),
        ];
    }
}
