<?php

namespace App\Services;

use App\Models\AiCreditBalance;
use App\Models\AiUsageLog;
use App\Models\BillingSnapshot;
use App\Models\PlatformSetting;
use App\Models\Workspace;
use App\Models\WorkspaceSubscription;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

/**
 * Super-admin operations: workspace listing, AI usage overview,
 * MRR/ARR indicators, high-usage detection, billing snapshots.
 */
class SuperAdminService
{
    /**
     * List all workspaces with subscription and AI usage data.
     */
    public function listWorkspaces(): Collection
    {
        return Workspace::select('workspaces.*')
            ->leftJoin('workspace_subscriptions as ws', 'ws.workspace_id', '=', 'workspaces.id')
            ->leftJoin('ai_credit_balances as acb', 'acb.workspace_id', '=', 'workspaces.id')
            ->addSelect([
                'ws.status as subscription_status_detail',
                'ws.plan_id', 'ws.billing_cycle',
                'ws.current_employee_count', 'ws.included_employees', 'ws.overage_employee_count',
                'ws.trial_ends_at',
                'acb.included_credits', 'acb.purchased_credits', 'acb.bonus_credits',
                'acb.trial_credits', 'acb.used_credits', 'acb.hard_limit',
            ])
            ->orderBy('workspaces.created_at', 'desc')
            ->get();
    }

    /**
     * Detailed workspace view.
     */
    public function getWorkspaceDetail(string $workspaceId): ?array
    {
        $ws = Workspace::find($workspaceId);
        if (! $ws) return null;

        $sub = WorkspaceSubscription::where('workspace_id', $workspaceId)->with(['plan', 'planPrice'])->first();
        $credits = AiCreditBalance::where('workspace_id', $workspaceId)->first();

        $recentUsage = AiUsageLog::where('workspace_id', $workspaceId)
            ->orderByDesc('created_at')
            ->limit(20)
            ->get();

        $memberCount = DB::table('workspace_memberships')
            ->where('workspace_id', $workspaceId)
            ->where('status', 'active')
            ->count();

        return [
            'workspace'     => $ws,
            'subscription'  => $sub,
            'credits'       => $credits,
            'recent_usage'  => $recentUsage,
            'member_count'  => $memberCount,
        ];
    }

    /**
     * Dashboard summary: MRR, ARR, active trials, expiring trials, workspace counts.
     */
    public function dashboardSummary(): array
    {
        $subs = WorkspaceSubscription::with('planPrice')->get();

        $mrr = 0;
        $activeTrials = 0;
        $expiringTrials = 0;

        foreach ($subs as $sub) {
            if ($sub->status === 'trial') {
                $activeTrials++;
                if ($sub->trial_ends_at && $sub->trial_ends_at->diffInDays(now()) <= 7) {
                    $expiringTrials++;
                }
            }

            if (in_array($sub->status, ['active', 'trial']) && $sub->planPrice) {
                $monthlyEquiv = match ($sub->billing_cycle) {
                    'monthly'     => (float) $sub->planPrice->base_price,
                    'quarterly'   => (float) $sub->planPrice->base_price / 3,
                    'semi_annual' => (float) $sub->planPrice->base_price / 6,
                    'annual'      => (float) $sub->planPrice->base_price / 12,
                    'multi_year'  => (float) $sub->planPrice->base_price / 24,
                    default       => (float) $sub->planPrice->base_price,
                };
                // Add employee overage revenue
                $monthlyEquiv += $sub->overage_employee_count * (float) $sub->price_per_extra_employee;
                $mrr += $monthlyEquiv;
            }
        }

        $totalWorkspaces = Workspace::count();
        $activeWorkspaces = Workspace::where('is_active', true)->count();

        // AI usage totals (current month)
        $monthStart = now()->startOfMonth();
        $aiUsage = AiUsageLog::where('created_at', '>=', $monthStart)
            ->selectRaw("COUNT(*) as total_requests, COALESCE(SUM(COALESCE((metadata->>'credits_charged')::integer, 0)), 0) as total_credits")
            ->first();

        return [
            'mrr'                => round($mrr, 2),
            'arr'                => round($mrr * 12, 2),
            'total_workspaces'   => $totalWorkspaces,
            'active_workspaces'  => $activeWorkspaces,
            'active_trials'      => $activeTrials,
            'expiring_trials_7d' => $expiringTrials,
            'ai_requests_mtd'    => $aiUsage->total_requests ?? 0,
            'ai_credits_used_mtd'=> $aiUsage->total_credits ?? 0,
        ];
    }

    /**
     * Detect workspaces exceeding thresholds.
     */
    public function highUsageWorkspaces(int $creditThresholdPercent = 80): Collection
    {
        return AiCreditBalance::whereRaw('used_credits >= (included_credits + purchased_credits + bonus_credits + trial_credits) * ? / 100', [$creditThresholdPercent])
            ->orWhereRaw('(included_credits + purchased_credits + bonus_credits + trial_credits - used_credits) <= 0')
            ->with('workspace')
            ->get();
    }

    /**
     * Global AI usage aggregation.
     */
    public function globalAiUsage(string $period = 'month'): array
    {
        $start = match ($period) {
            'week'  => now()->subWeek(),
            'month' => now()->startOfMonth(),
            'year'  => now()->startOfYear(),
            default => now()->startOfMonth(),
        };

        $byAction = AiUsageLog::where('created_at', '>=', $start)
            ->selectRaw("operation as action_type, COUNT(*) as count, COALESCE(SUM(COALESCE((metadata->>'credits_charged')::integer, 0)), 0) as credits")
            ->groupBy('operation')
            ->get();

        $byWorkspace = AiUsageLog::where('created_at', '>=', $start)
            ->selectRaw("workspace_id, COUNT(*) as count, COALESCE(SUM(COALESCE((metadata->>'credits_charged')::integer, 0)), 0) as credits")
            ->groupBy('workspace_id')
            ->orderByDesc('credits')
            ->limit(10)
            ->get();

        return [
            'period'       => $period,
            'by_action'    => $byAction,
            'top_workspaces' => $byWorkspace,
        ];
    }

    /**
     * Create a billing snapshot for a workspace period.
     */
    public function createBillingSnapshot(string $workspaceId): ?BillingSnapshot
    {
        $sub = WorkspaceSubscription::where('workspace_id', $workspaceId)->with('planPrice')->first();
        if (! $sub || ! $sub->planPrice) return null;

        $credits = AiCreditBalance::where('workspace_id', $workspaceId)->first();
        $p = $sub->planPrice;

        $aiOverage = max(0, ($credits ? $credits->used_credits : 0) - $p->included_ai_credits);
        $aiOverageCharge = $aiOverage * (float) $p->ai_overage_price_per_credit;
        $empOverageCharge = $sub->overage_employee_count * (float) $sub->price_per_extra_employee;
        $total = (float) $p->base_price + $empOverageCharge + $aiOverageCharge;

        return BillingSnapshot::create([
            'workspace_id'            => $workspaceId,
            'period_start'            => $sub->current_period_start,
            'period_end'              => $sub->current_period_end,
            'plan_name'               => $sub->plan?->name ?? 'Unknown',
            'billing_cycle'           => $sub->billing_cycle,
            'base_price'              => $p->base_price,
            'employee_count'          => $sub->current_employee_count,
            'included_employees'      => $sub->included_employees,
            'overage_employees'       => $sub->overage_employee_count,
            'employee_overage_charge' => $empOverageCharge,
            'ai_credits_included'     => $p->included_ai_credits,
            'ai_credits_used'         => $credits ? $credits->used_credits : 0,
            'ai_credits_overage'      => $aiOverage,
            'ai_overage_charge'       => $aiOverageCharge,
            'total_amount'            => $total,
            'status'                  => 'draft',
            'created_at'              => now(),
        ]);
    }

    // ── Settings management ────────────────────────────────────

    public function getSettings(): Collection
    {
        return PlatformSetting::all();
    }

    public function updateSettings(array $settings, ?string $actorId = null): void
    {
        foreach ($settings as $key => $value) {
            PlatformSetting::updateOrCreate(
                ['key' => $key],
                ['value' => (string) $value, 'updated_by' => $actorId, 'updated_at' => now()],
            );
        }
    }
}
