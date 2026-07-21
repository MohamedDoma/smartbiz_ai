<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\FinanceTransaction;
use App\Models\WorkspaceMembership;
use App\Services\FinancePostingService;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class FinanceTransactionController extends Controller
{

    public function index(Request $request): JsonResponse
    {
        $wsId = app(WorkspaceContextManager::class)->workspaceId();

        $q = FinanceTransaction::where('workspace_id', $wsId)
            ->with('lines.account:id,code,name')
            ->orderByDesc('transaction_date')
            ->orderByDesc('created_at');

        if ($request->filled('status')) {
            $q->where('status', $request->input('status'));
        }

        return response()->json(['data' => $q->limit(100)->get()]);
    }

    public function show(string $id): JsonResponse
    {
        $wsId = app(WorkspaceContextManager::class)->workspaceId();
        $txn = FinanceTransaction::where('workspace_id', $wsId)
            ->with('lines.account:id,code,name')->findOrFail($id);
        return response()->json(['data' => $txn]);
    }

    public function store(Request $request): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);

        $v = $request->validate([
            'transaction_date'              => 'required|date',
            'description'                   => 'nullable|string|max:2000',
            'currency'                      => 'nullable|string|max:10',
            'lines'                         => 'required|array|min:2',
            'lines.*.finance_account_id'    => 'required|uuid',
            'lines.*.debit_amount'          => 'required|numeric|min:0',
            'lines.*.credit_amount'         => 'required|numeric|min:0',
            'lines.*.description'           => 'nullable|string|max:500',
        ]);

        $user = $request->user();
        $membership = WorkspaceMembership::where('workspace_id', $ctx->workspaceId())
            ->where('user_id', $user->id)->first();

        $svc = new FinancePostingService();

        try {
            $txn = $svc->createTransaction(
                $ctx->workspaceId(),
                $v['transaction_date'],
                $v['description'] ?? null,
                $v['lines'],
                $v['currency'] ?? 'LYD',
                $membership?->id,
            );
            return response()->json(['data' => $txn], 201);
        } catch (\InvalidArgumentException $e) {
            return response()->json(['message' => $e->getMessage(), 'error' => 'validation_error'], 422);
        }
    }

    public function void(Request $request, string $id): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);

        $svc = new FinancePostingService();
        try {
            $txn = $svc->voidTransaction($ctx->workspaceId(), $id);
            return response()->json(['data' => $txn, 'message' => 'Transaction voided.']);
        } catch (\RuntimeException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }
    }

    /**
     * Post commission entry to finance.
     */
    public function postCommissionEntry(Request $request, string $id): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);

        $user = $request->user();
        $membership = WorkspaceMembership::where('workspace_id', $ctx->workspaceId())
            ->where('user_id', $user->id)->first();

        $svc = new FinancePostingService();
        try {
            $txn = $svc->postCommissionEntry($ctx->workspaceId(), $id, $membership?->id);
            return response()->json(['data' => $txn, 'message' => 'Commission posted to finance.'], 201);
        } catch (\RuntimeException $e) {
            return response()->json(['message' => $e->getMessage()], 409);
        } catch (\InvalidArgumentException $e) {
            return response()->json(['message' => $e->getMessage(), 'error' => 'validation_error'], 422);
        }
    }

    /**
     * Post invoice to finance.
     */
    public function postInvoice(Request $request, string $id): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);

        $user = $request->user();
        $membership = WorkspaceMembership::where('workspace_id', $ctx->workspaceId())
            ->where('user_id', $user->id)->first();

        $svc = new FinancePostingService();
        try {
            $txn = $svc->postInvoice($ctx->workspaceId(), $id, $membership?->id);
            return response()->json(['data' => $txn, 'message' => 'Invoice posted to finance.'], 201);
        } catch (\RuntimeException $e) {
            return response()->json(['message' => $e->getMessage()], 409);
        }
    }

    /**
     * Post payment to finance.
     */
    public function postPayment(Request $request, string $id): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);

        $user = $request->user();
        $membership = WorkspaceMembership::where('workspace_id', $ctx->workspaceId())
            ->where('user_id', $user->id)->first();

        $svc = new FinancePostingService();
        try {
            $txn = $svc->postPayment($ctx->workspaceId(), $id, $membership?->id);
            return response()->json(['data' => $txn, 'message' => 'Payment posted to finance.'], 201);
        } catch (\RuntimeException $e) {
            return response()->json(['message' => $e->getMessage()], 409);
        }
    }
}
