<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\FinanceSummaryService;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class FinanceSummaryController extends Controller
{

    public function summary(Request $request): JsonResponse
    {
        $wsId = app(WorkspaceContextManager::class)->workspaceId();

        $svc = new FinanceSummaryService();
        return response()->json(['data' => $svc->getSummary($wsId)]);
    }

    public function profitLoss(Request $request): JsonResponse
    {
        $wsId = app(WorkspaceContextManager::class)->workspaceId();

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

        $svc = new FinanceSummaryService();
        return response()->json(['data' => $svc->accountBalances($wsId)]);
    }
}
