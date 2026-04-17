<?php

namespace App\Services;

use App\Models\PlanFeature;
use App\Models\PlatformPlan;
use App\Models\PlatformPlanPrice;
use Illuminate\Support\Collection;

/**
 * Manages platform plans, pricing rows, and plan features.
 */
class PlanService
{
    // ── Plans ──────────────────────────────────────────────────

    public function listPlans(bool $activeOnly = true): Collection
    {
        $q = PlatformPlan::with(['activePrices', 'features'])->orderBy('sort_order');
        if ($activeOnly) $q->where('is_active', true);
        return $q->get();
    }

    public function findPlan(string $id): ?PlatformPlan
    {
        return PlatformPlan::with(['prices', 'features'])->find($id);
    }

    public function createPlan(array $data): PlatformPlan
    {
        return PlatformPlan::create($data);
    }

    public function updatePlan(string $id, array $data): ?PlatformPlan
    {
        $plan = PlatformPlan::find($id);
        if (! $plan) return null;
        $plan->update($data);
        return $plan->fresh(['prices', 'features']);
    }

    // ── Pricing ────────────────────────────────────────────────

    public function addPricing(string $planId, array $data): PlatformPlanPrice
    {
        $data['plan_id'] = $planId;
        return PlatformPlanPrice::create($data);
    }

    public function getActivePricing(string $planId, string $billingCycle, string $currency = 'USD'): ?PlatformPlanPrice
    {
        return PlatformPlanPrice::where('plan_id', $planId)
            ->where('billing_cycle', $billingCycle)
            ->where('currency', $currency)
            ->where('is_active', true)
            ->where('effective_from', '<=', now()->toDateString())
            ->where(fn ($q) => $q->whereNull('effective_until')->orWhere('effective_until', '>=', now()->toDateString()))
            ->orderByDesc('effective_from')
            ->first();
    }

    // ── Features ───────────────────────────────────────────────

    public function setPlanFeatures(string $planId, array $features): void
    {
        foreach ($features as $key => $enabled) {
            PlanFeature::updateOrCreate(
                ['plan_id' => $planId, 'feature_key' => $key],
                ['is_enabled' => $enabled],
            );
        }
    }

    public function getPlanFeatures(string $planId): Collection
    {
        return PlanFeature::where('plan_id', $planId)->get()
            ->pluck('is_enabled', 'feature_key');
    }
}
