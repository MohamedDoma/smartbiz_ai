<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\FinanceExpense;
use App\Models\WorkspaceMembership;
use App\Services\FinancePostingService;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class FinanceExpenseController extends Controller
{
    private const ADMIN_ROLES = ['owner', 'admin', 'general_manager', 'accountant'];

    public function index(Request $request): JsonResponse
    {
        $wsId = app(WorkspaceContextManager::class)->workspaceId();
        $this->requireFinanceAccess($wsId, $request);

        $q = FinanceExpense::where('workspace_id', $wsId)
            ->orderByDesc('expense_date');

        if ($request->filled('status')) {
            $q->where('status', $request->input('status'));
        }

        return response()->json(['data' => $q->limit(100)->get()]);
    }

    public function show(string $id): JsonResponse
    {
        $wsId = app(WorkspaceContextManager::class)->workspaceId();
        $exp = FinanceExpense::where('workspace_id', $wsId)->findOrFail($id);
        return response()->json(['data' => $exp]);
    }

    public function store(Request $request): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $this->requireFinanceAccess($ctx->workspaceId(), $request);

        $v = $request->validate([
            'expense_date'   => 'required|date',
            'category'       => 'nullable|string|max:100',
            'description'    => 'required|string|max:2000',
            'amount'         => 'required|numeric|min:0.01',
            'currency'       => 'nullable|string|max:10',
            'payment_method' => 'nullable|string|in:cash,bank,card',
        ]);

        $user = $request->user();
        $membership = WorkspaceMembership::where('workspace_id', $ctx->workspaceId())
            ->where('user_id', $user->id)->first();

        $svc = new FinancePostingService();

        try {
            $expense = $svc->postManualExpense(
                $ctx->workspaceId(),
                $v['expense_date'],
                $v['description'],
                $v['amount'],
                $v['currency'] ?? 'LYD',
                $v['category'] ?? null,
                $v['payment_method'] ?? 'cash',
                $membership?->id,
            );
            return response()->json(['data' => $expense], 201);
        } catch (\RuntimeException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }
    }

    public function void(Request $request, string $id): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $this->requireFinanceAccess($ctx->workspaceId(), $request);

        $expense = FinanceExpense::where('workspace_id', $ctx->workspaceId())->findOrFail($id);
        if ($expense->status === 'void') {
            return response()->json(['message' => 'Expense already voided.'], 422);
        }

        $expense->update(['status' => 'void']);

        // Void linked transaction
        if ($expense->finance_transaction_id) {
            $svc = new FinancePostingService();
            try {
                $svc->voidTransaction($ctx->workspaceId(), $expense->finance_transaction_id);
            } catch (\Throwable $e) {
                // Transaction may already be voided
            }
        }

        return response()->json(['data' => $expense->fresh(), 'message' => 'Expense voided.']);
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
