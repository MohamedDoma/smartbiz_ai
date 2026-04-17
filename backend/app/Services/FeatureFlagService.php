<?php

namespace App\Services;

use App\Models\PlanFeature;
use App\Models\WorkspaceFeatureFlag;
use App\Models\WorkspaceSubscription;

/**
 * 3-level feature flag resolution:
 * 1. Platform default (hardcoded set of known features)
 * 2. Plan-level enablement (plan_features table)
 * 3. Workspace-level override (workspace_feature_flags table)
 *
 * Workspace override wins over plan, plan wins over platform default.
 */
class FeatureFlagService
{
    /**
     * Known platform features with defaults (enabled/disabled out of the box).
     */
    private const PLATFORM_DEFAULTS = [
        // ERP Modules
        'module.contacts'            => true,
        'module.products'            => true,
        'module.invoices'            => true,
        'module.orders'              => true,
        'module.payments'            => true,
        'module.inventory'           => true,
        'module.accounting'          => true,
        'module.warehouses'          => true,
        'module.production'          => false,
        'module.bom'                 => false,
        'module.recurring_expenses'  => true,
        'module.reports'             => true,
        // AI Modes
        'ai.discovery'               => true,
        'ai.chat'                    => false,
        'ai.operations'              => false,
        'ai.automation'              => false,
        // Premium Features
        'premium.multi_warehouse'    => false,
        'premium.advanced_reports'   => false,
        'premium.api_access'         => false,
        'premium.custom_roles'       => true,
        // Beta Features
        'beta.ai_insights'           => false,
        'beta.workflow_builder'      => false,
    ];

    /**
     * Check if a feature is enabled for a workspace.
     */
    public function isEnabled(string $workspaceId, string $featureKey): bool
    {
        // Level 3: Workspace override (highest priority)
        $override = WorkspaceFeatureFlag::where('workspace_id', $workspaceId)
            ->where('feature_key', $featureKey)
            ->first();
        if ($override) return $override->is_enabled;

        // Level 2: Plan-level
        $sub = WorkspaceSubscription::where('workspace_id', $workspaceId)->first();
        if ($sub) {
            $planFeature = PlanFeature::where('plan_id', $sub->plan_id)
                ->where('feature_key', $featureKey)
                ->first();
            if ($planFeature) return $planFeature->is_enabled;
        }

        // Level 1: Platform default
        return self::PLATFORM_DEFAULTS[$featureKey] ?? false;
    }

    /**
     * Resolve all features for a workspace (merged 3-level view).
     */
    public function resolveAll(string $workspaceId): array
    {
        $features = self::PLATFORM_DEFAULTS;

        // Apply plan-level
        $sub = WorkspaceSubscription::where('workspace_id', $workspaceId)->first();
        if ($sub) {
            $planFeatures = PlanFeature::where('plan_id', $sub->plan_id)->get();
            foreach ($planFeatures as $pf) {
                $features[$pf->feature_key] = $pf->is_enabled;
            }
        }

        // Apply workspace-level overrides
        $overrides = WorkspaceFeatureFlag::where('workspace_id', $workspaceId)->get();
        foreach ($overrides as $o) {
            $features[$o->feature_key] = $o->is_enabled;
        }

        return $features;
    }

    /**
     * Set a workspace-level feature override.
     */
    public function setOverride(string $workspaceId, string $featureKey, bool $enabled, ?string $reason = null, ?string $setBy = null): WorkspaceFeatureFlag
    {
        return WorkspaceFeatureFlag::updateOrCreate(
            ['workspace_id' => $workspaceId, 'feature_key' => $featureKey],
            ['is_enabled' => $enabled, 'override_reason' => $reason, 'set_by' => $setBy],
        );
    }

    /**
     * Remove a workspace-level override (revert to plan/platform default).
     */
    public function removeOverride(string $workspaceId, string $featureKey): bool
    {
        return WorkspaceFeatureFlag::where('workspace_id', $workspaceId)
            ->where('feature_key', $featureKey)
            ->delete() > 0;
    }

    /**
     * Get platform defaults.
     */
    public function getPlatformDefaults(): array
    {
        return self::PLATFORM_DEFAULTS;
    }
}
