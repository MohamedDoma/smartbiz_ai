<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\WorkspaceMembership;
use App\Services\FinanceSummaryService;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class FinanceSummaryController extends Controller
{
    private const VIEW_ROLES = ['owner', 'admin', 'general_manager', 'accountant', 'manager'];

    public function summary(Request $request): JsonResponse
    {
        $wsId = app(WorkspaceContextManager::class)->workspaceId();
        $this->requireViewAccess($wsId, $request);

        $svc = new FinanceSummaryService();
        return response()->json(['data' => $svc->getSummary($wsId)]);
    }

    public function profitLoss(Request $request): JsonResponse
    {
        $wsId = app(WorkspaceContextManager::class)->workspaceId();
        $this->requireViewAccess($wsId, $request);

        $v = $request->validate([
            'from' => 'nullable|date',
            'to'   => 'nullable|date',
        ]);

        $svc = new FinanceSummaryService();
        return response()->json([
            'data' => $svc->getProfitLoss($wsId, $v['from'] ?? null, $v['to'] ?? null),
        ]);
    }

    public function accountBalances(Request $request): JsonResponse
    {
        $wsId = app(WorkspaceContextManager::class)->workspaceId();
        $this->requireViewAccess($wsId, $request);

        $svc = new FinanceSummaryService();
        return response()->json(['data' => $svc->accountBalances($wsId)]);
    }

    private function requireViewAccess(string $wsId, Request $request): void
    {
        $user = $request->user();
        if ($user->is_super_admin) {
            return;
        }
        $m = WorkspaceMembership::where('workspace_id', $wsId)
            ->where('user_id', $user->id)->where('status', 'active')->first();
        if (!$m) {
            abort(403, 'Not a member.');
        }
        $keys = $m->membershipRoles()
            ->join('roles', 'roles.id', '=', 'membership_roles.role_id')
            ->pluck('roles.role_key')->toArray();
        if (empty(array_intersect($keys, self::VIEW_ROLES))) {
            abort(403, 'Insufficient permissions.');
        }
    }
}
