<?php

namespace App\Services;

use App\Models\AiCreditBalance;
use App\Models\PlatformPlanPrice;
use App\Models\PlatformSetting;
use App\Models\WorkspaceSubscription;
use Illuminate\Support\Facades\DB;

/**
 * Manages workspace subscriptions: plan assignment, trial logic,
 * employee count tracking, status transitions.
 */
class SubscriptionService
{
    /**
     * Assign a plan to a workspace.
     */
    public function assignPlan(
        string $workspaceId,
        string $planId,
        string $planPriceId,
        string $billingCycle,
        bool   $isTrial = false,
    ): WorkspaceSubscription {
        $pricing = PlatformPlanPrice::findOrFail($planPriceId);

        $trialDays = $this->resolveTrialDays();
        $start = now();

        if ($isTrial) {
            $end = $start->copy()->addDays($trialDays);
        } else {
            $end = $this->calculatePeriodEnd($start, $billingCycle);
        }

        return DB::transaction(function () use ($workspaceId, $planId, $planPriceId, $billingCycle, $pricing, $isTrial, $start, $end) {
            $sub = WorkspaceSubscription::updateOrCreate(
                ['workspace_id' => $workspaceId],
                [
                    'plan_id'                  => $planId,
                    'plan_price_id'            => $planPriceId,
                    'status'                   => $isTrial ? 'trial' : 'active',
                    'billing_cycle'            => $billingCycle,
                    'current_period_start'     => $start,
                    'current_period_end'       => $end,
                    'trial_ends_at'            => $isTrial ? $end : null,
                    'included_employees'       => $pricing->included_employees,
                    'price_per_extra_employee' => $pricing->price_per_employee,
                ],
            );

            // Initialize AI credit balance for the workspace
            AiCreditBalance::updateOrCreate(
                ['workspace_id' => $workspaceId],
                [
                    'included_credits' => $pricing->included_ai_credits,
                    'trial_credits'    => $isTrial ? $this->resolveTrialCredits() : 0,
                    'used_credits'     => 0,
                    'period_start'     => $start,
                    'period_end'       => $end,
                ],
            );

            return $sub;
        });
    }

    /**
     * Extend a workspace's trial period.
     */
    public function extendTrial(string $workspaceId, int $extraDays): ?WorkspaceSubscription
    {
        $sub = WorkspaceSubscription::where('workspace_id', $workspaceId)->first();
        if (! $sub) return null;

        $newEnd = ($sub->trial_ends_at ?? now())->copy()->addDays($extraDays);
        $sub->update([
            'trial_ends_at'        => $newEnd,
            'current_period_end'   => $newEnd,
            'status'               => 'trial',
        ]);

        return $sub->fresh();
    }

    /**
     * Activate a trial subscription (convert to active).
     */
    public function activateSubscription(string $workspaceId): ?WorkspaceSubscription
    {
        $sub = WorkspaceSubscription::where('workspace_id', $workspaceId)->first();
        if (! $sub) return null;

        $start = now();
        $end = $this->calculatePeriodEnd($start, $sub->billing_cycle);

        $sub->update([
            'status'               => 'active',
            'trial_ends_at'        => null,
            'current_period_start' => $start,
            'current_period_end'   => $end,
        ]);

        return $sub->fresh();
    }

    /**
     * Suspend a workspace subscription.
     */
    public function suspendSubscription(string $workspaceId, string $status = 'suspended'): ?WorkspaceSubscription
    {
        $sub = WorkspaceSubscription::where('workspace_id', $workspaceId)->first();
        if (! $sub) return null;

        $sub->update(['status' => $status]);
        return $sub->fresh();
    }

    /**
     * Sync employee count from active memberships.
     */
    public function syncEmployeeCount(string $workspaceId): ?WorkspaceSubscription
    {
        $sub = WorkspaceSubscription::where('workspace_id', $workspaceId)->first();
        if (! $sub) return null;

        $count = DB::table('workspace_memberships')
            ->where('workspace_id', $workspaceId)
            ->where('status', 'active')
            ->count();

        $billable = max($count, $sub->included_employees);
        $overage  = max(0, $count - $sub->included_employees);

        $sub->update([
            'current_employee_count'  => $count,
            'billable_employee_count' => $billable,
            'overage_employee_count'  => $overage,
        ]);

        return $sub->fresh();
    }

    /**
     * Check if workspace can add more employees.
     */
    public function canAddEmployee(string $workspaceId): array
    {
        $sub = WorkspaceSubscription::where('workspace_id', $workspaceId)->with('plan')->first();
        if (! $sub || ! $sub->plan) {
            return ['allowed' => false, 'reason' => 'No active subscription.'];
        }

        if ($sub->current_employee_count >= $sub->plan->max_employees) {
            return ['allowed' => false, 'reason' => 'Employee limit reached.', 'max' => $sub->plan->max_employees, 'current' => $sub->current_employee_count];
        }

        $isOverage = $sub->current_employee_count >= $sub->included_employees;
        return ['allowed' => true, 'is_overage' => $isOverage, 'price_per_extra' => $sub->price_per_extra_employee];
    }

    // ── Helpers ────────────────────────────────────────────────

    private function resolveTrialDays(): int
    {
        $promoEnabled = PlatformSetting::find('launch_promo_enabled');
        if ($promoEnabled && strtolower($promoEnabled->value) === 'true') {
            $promoDays = PlatformSetting::find('launch_promo_trial_days');
            if ($promoDays) return (int) $promoDays->value;
        }

        $default = PlatformSetting::find('default_trial_days');
        return $default ? (int) $default->value : 14;
    }

    private function resolveTrialCredits(): int
    {
        $setting = PlatformSetting::find('default_ai_credits_trial');
        return $setting ? (int) $setting->value : 50;
    }

    private function calculatePeriodEnd($start, string $cycle): \Carbon\Carbon
    {
        return match ($cycle) {
            'monthly'     => $start->copy()->addMonth(),
            'quarterly'   => $start->copy()->addMonths(3),
            'semi_annual' => $start->copy()->addMonths(6),
            'annual'      => $start->copy()->addYear(),
            'multi_year'  => $start->copy()->addYears(2),
            default       => $start->copy()->addMonth(),
        };
    }
}
