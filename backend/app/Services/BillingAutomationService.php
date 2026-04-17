<?php

namespace App\Services;

use App\Models\AiCreditBalance;
use App\Models\WorkspaceSubscription;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * Scheduled billing automation tasks:
 * trial expiration, billing snapshot generation,
 * employee count sync, and monthly credit reset.
 */
class BillingAutomationService
{
    public function __construct(
        private readonly SuperAdminService $admin,
        private readonly AiCreditService  $credits,
    ) {}

    /**
     * Process expired trials — suspend or downgrade.
     */
    public function processExpiredTrials(): array
    {
        $expired = WorkspaceSubscription::where('status', 'trial')
            ->where('trial_ends_at', '<', now())
            ->get();

        $processed = [];
        foreach ($expired as $sub) {
            $sub->update(['status' => 'suspended']);
            Log::info("Trial expired for workspace {$sub->workspace_id}, subscription suspended.");
            $processed[] = $sub->workspace_id;
        }

        return $processed;
    }

    /**
     * Generate billing snapshots for subscriptions at period end.
     */
    public function generatePeriodSnapshots(): array
    {
        $subs = WorkspaceSubscription::whereIn('status', ['active', 'past_due'])
            ->where('current_period_end', '<=', now()->addDay())
            ->get();

        $generated = [];
        foreach ($subs as $sub) {
            $snapshot = $this->admin->createBillingSnapshot($sub->workspace_id);
            if ($snapshot) {
                $generated[] = $sub->workspace_id;
            }
        }

        return $generated;
    }

    /**
     * Sync employee counts for all active subscriptions.
     */
    public function syncAllEmployeeCounts(): array
    {
        $subs = WorkspaceSubscription::whereIn('status', ['active', 'trial', 'past_due'])->get();

        $synced = [];
        foreach ($subs as $sub) {
            $count = DB::table('workspace_memberships')
                ->where('workspace_id', $sub->workspace_id)
                ->where('status', 'active')
                ->count();

            $billable = max($count, $sub->included_employees ?? 0);
            $overage  = max(0, $count - ($sub->included_employees ?? 0));

            $sub->update([
                'current_employee_count'  => $count,
                'billable_employee_count' => $billable,
                'overage_employee_count'  => $overage,
            ]);

            $synced[] = ['workspace_id' => $sub->workspace_id, 'count' => $count, 'overage' => $overage];
        }

        return $synced;
    }

    /**
     * Monthly AI credit reset for all active subscriptions.
     */
    public function resetMonthlyCredits(): array
    {
        $balances = AiCreditBalance::where('period_end', '<=', now())->get();

        $reset = [];
        foreach ($balances as $bal) {
            $sub = WorkspaceSubscription::where('workspace_id', $bal->workspace_id)
                ->whereIn('status', ['active'])
                ->with('planPrice')
                ->first();

            if (! $sub || ! $sub->planPrice) continue;

            $this->credits->monthlyReset($bal->workspace_id, $sub->planPrice->included_ai_credits);
            $reset[] = $bal->workspace_id;
        }

        return $reset;
    }
}
