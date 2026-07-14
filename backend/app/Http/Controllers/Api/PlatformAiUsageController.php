<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * Step 59.1 — Platform AI Usage Controller (Super Admin only).
 *
 * GET /api/platform/ai-usage             — summary
 * GET /api/platform/ai-usage/workspaces  — per-workspace breakdown
 */
class PlatformAiUsageController extends Controller
{
    /**
     * GET /api/platform/ai-usage
     */
    public function summary(Request $request): JsonResponse
    {
        $period = $request->input('period', '30d');
        $since  = $this->periodToDate($period);

        // Aggregate totals
        $totals = DB::table('ai_usage_logs')
            ->where('created_at', '>=', $since)
            ->selectRaw("
                COUNT(*) as total_requests,
                COUNT(*) FILTER (WHERE success = TRUE) as successful_requests,
                COUNT(*) FILTER (WHERE success = FALSE) as failed_requests,
                COALESCE(SUM(input_tokens), 0) as total_input_tokens,
                COALESCE(SUM(output_tokens), 0) as total_output_tokens,
                COALESCE(SUM(total_tokens), 0) as total_tokens,
                COALESCE(SUM(estimated_cost_usd), 0) as estimated_total_cost
            ")
            ->first();

        // Usage by day
        $byDay = DB::table('ai_usage_logs')
            ->where('created_at', '>=', $since)
            ->selectRaw("
                DATE(created_at) as date,
                COUNT(*) as requests,
                COALESCE(SUM(total_tokens), 0) as tokens,
                COALESCE(SUM(estimated_cost_usd), 0) as cost
            ")
            ->groupByRaw('DATE(created_at)')
            ->orderByRaw('DATE(created_at)')
            ->get();

        // Usage by model
        $byModel = DB::table('ai_usage_logs')
            ->where('created_at', '>=', $since)
            ->selectRaw("
                model,
                COUNT(*) as requests,
                COALESCE(SUM(total_tokens), 0) as tokens,
                COALESCE(SUM(estimated_cost_usd), 0) as cost
            ")
            ->groupBy('model')
            ->orderByDesc('requests')
            ->get();

        // Usage by operation
        $byOperation = DB::table('ai_usage_logs')
            ->where('created_at', '>=', $since)
            ->selectRaw("
                operation,
                COUNT(*) as requests,
                COALESCE(SUM(total_tokens), 0) as tokens,
                COALESCE(SUM(estimated_cost_usd), 0) as cost
            ")
            ->groupBy('operation')
            ->orderByDesc('requests')
            ->get();

        // Recent errors
        $recentErrors = DB::table('ai_usage_logs')
            ->where('success', false)
            ->where('created_at', '>=', $since)
            ->orderByDesc('created_at')
            ->limit(10)
            ->get(['id', 'workspace_id', 'user_id', 'model', 'operation',
                   'error_code', 'error_message', 'created_at']);

        return response()->json([
            'data' => [
                'period'              => $period,
                'total_requests'      => (int) $totals->total_requests,
                'successful_requests' => (int) $totals->successful_requests,
                'failed_requests'     => (int) $totals->failed_requests,
                'total_input_tokens'  => (int) $totals->total_input_tokens,
                'total_output_tokens' => (int) $totals->total_output_tokens,
                'total_tokens'        => (int) $totals->total_tokens,
                'estimated_total_cost' => round((float) $totals->estimated_total_cost, 4),
                'by_day'              => $byDay,
                'by_model'            => $byModel,
                'by_operation'        => $byOperation,
                'recent_errors'       => $recentErrors,
                'budget' => [
                    'monthly_usd' => config('ai.budget.monthly_usd', 30),
                    'daily_limit'  => config('ai.budget.daily_message_limit', 200),
                    'monthly_limit' => config('ai.budget.monthly_message_limit', 3000),
                ],
            ],
        ]);
    }

    /**
     * GET /api/platform/ai-usage/workspaces
     */
    public function workspaces(Request $request): JsonResponse
    {
        $since = $this->periodToDate($request->input('period', '30d'));

        $workspaces = DB::table('ai_usage_logs')
            ->where('ai_usage_logs.created_at', '>=', $since)
            ->leftJoin('workspaces', 'ai_usage_logs.workspace_id', '=', 'workspaces.id')
            ->selectRaw("
                ai_usage_logs.workspace_id,
                workspaces.name as workspace_name,
                COUNT(*) as total_requests,
                COALESCE(SUM(ai_usage_logs.total_tokens), 0) as total_tokens,
                COALESCE(SUM(ai_usage_logs.estimated_cost_usd), 0) as estimated_cost,
                COUNT(*) FILTER (WHERE ai_usage_logs.success = FALSE) as failed_requests
            ")
            ->groupBy('ai_usage_logs.workspace_id', 'workspaces.name')
            ->orderByDesc('total_requests')
            ->limit(50)
            ->get();

        return response()->json(['data' => $workspaces]);
    }

    private function periodToDate(string $period): string
    {
        return match ($period) {
            '7d'  => now()->subDays(7)->toDateTimeString(),
            '30d' => now()->subDays(30)->toDateTimeString(),
            '6m'  => now()->subMonths(6)->toDateTimeString(),
            '1y'  => now()->subYear()->toDateTimeString(),
            default => now()->subDays(30)->toDateTimeString(),
        };
    }
}
