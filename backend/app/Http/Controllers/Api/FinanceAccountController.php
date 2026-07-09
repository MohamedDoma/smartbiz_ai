<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\FinanceAccount;
use App\Models\WorkspaceMembership;
use App\Services\FinanceBootstrapService;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class FinanceAccountController extends Controller
{
    private const ADMIN_ROLES = ['owner', 'admin', 'general_manager', 'accountant'];

    public function index(): JsonResponse
    {
        $wsId = app(WorkspaceContextManager::class)->workspaceId();
        $accounts = FinanceAccount::where('workspace_id', $wsId)
            ->where('is_active', true)->orderBy('sort_order')->get();
        return response()->json(['data' => $accounts]);
    }

    public function store(Request $request): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $this->requireFinanceAccess($ctx->workspaceId(), $request);

        $v = $request->validate([
            'code'           => 'required|string|max:20',
            'name'           => 'required|string|max:255',
            'type'           => 'required|in:asset,liability,equity,income,expense',
            'normal_balance' => 'required|in:debit,credit',
            'account_key'    => 'nullable|string|max:50',
        ]);

        $acct = FinanceAccount::create([
            'workspace_id'   => $ctx->workspaceId(),
            'code'           => $v['code'],
            'name'           => $v['name'],
            'type'           => $v['type'],
            'normal_balance' => $v['normal_balance'],
            'account_key'    => $v['account_key'] ?? null,
            'is_system'      => false,
            'is_active'      => true,
        ]);

        return response()->json(['data' => $acct], 201);
    }

    public function update(Request $request, string $id): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $this->requireFinanceAccess($ctx->workspaceId(), $request);

        $acct = FinanceAccount::where('workspace_id', $ctx->workspaceId())->findOrFail($id);

        $v = $request->validate([
            'name'      => 'sometimes|string|max:255',
            'is_active' => 'sometimes|boolean',
        ]);

        $acct->update($v);
        return response()->json(['data' => $acct->fresh()]);
    }

    public function bootstrap(Request $request): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $this->requireFinanceAccess($ctx->workspaceId(), $request);

        $svc = new FinanceBootstrapService();
        $result = $svc->bootstrap($ctx->workspaceId());

        return response()->json([
            'message' => "Finance bootstrapped ({$result['created']} accounts created).",
            'data'    => $result['accounts'],
        ]);
    }

    private function requireFinanceAccess(string $wsId, Request $request): void
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
        if (empty(array_intersect($keys, self::ADMIN_ROLES))) {
            abort(403, 'Insufficient permissions for finance.');
        }
    }
}
