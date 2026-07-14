<?php

namespace App\Console\Commands;

use App\Models\CommissionPlan;
use App\Models\CommissionRule;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/**
 * Step 59.3 Part 4 — Non-destructive demo commission plan & rule sync.
 *
 * Creates (or reuses) exactly one CommissionPlan and one CommissionRule
 * for the demo workspace's automotive deal pipeline.
 *
 * - Idempotent — safe to run repeatedly without creating duplicates
 * - Non-destructive — preserves all existing plans, rules, entries
 * - Uses DB transaction for live writes
 * - Does NOT backfill commissions for previously-won deals
 *
 * Usage:
 *   php artisan smartbiz:sync-demo-commission-rule --workspace=<uuid>
 *   php artisan smartbiz:sync-demo-commission-rule --workspace=<uuid> --dry-run
 */
class SyncDemoCommissionRuleCommand extends Command
{
    protected $signature = 'smartbiz:sync-demo-commission-rule
        {--workspace= : Required. Workspace UUID}
        {--dry-run : Preview changes without writing to the database}';

    protected $description = 'Upsert a demo commission plan and percentage rule for the automotive deal pipeline.';

    private const PLAN_NAME = 'Demo Automotive Sales Commission';
    private const PLAN_KEY = 'demo_auto_sales_commission';
    private const TRIGGER_STATUS = 'won';
    private const TARGET_TYPE = 'assigned_employee';
    private const CALCULATION_TYPE = 'percentage';
    private const PERCENTAGE_RATE = 2.00;

    public function handle(): int
    {
        $wsId   = $this->option('workspace');
        $dryRun = $this->option('dry-run');

        // ── 1. Validate workspace ────────────────────────────────
        if (!$wsId) {
            $this->error('❌ --workspace is required.');
            $this->line('   Usage: php artisan smartbiz:sync-demo-commission-rule --workspace=<uuid>');
            return self::FAILURE;
        }

        if (!preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i', $wsId)) {
            $this->error("❌ Invalid workspace UUID: {$wsId}");
            return self::FAILURE;
        }

        $workspace = DB::table('workspaces')->where('id', $wsId)->first();
        if (!$workspace) {
            $this->error("❌ Workspace not found: {$wsId}");
            return self::FAILURE;
        }

        $mode = $dryRun ? '🔍 DRY RUN' : '🔧 LIVE';
        $this->info('');
        $this->info('╔══════════════════════════════════════════════════╗');
        $this->info("║  {$mode} — Demo Commission Rule Sync");
        $this->info("║  Workspace: {$workspace->name}");
        $this->info("║  ID: {$wsId}");
        $this->info('╚══════════════════════════════════════════════════╝');
        $this->info('');

        // ── 2. Locate the deal pipeline ──────────────────────────
        $pipelines = DB::table('pipelines')
            ->where('workspace_id', $wsId)
            ->where('entity_type', 'deal')
            ->where('name', 'مبيعات السيارات')
            ->where('is_active', true)
            ->get();

        if ($pipelines->isEmpty()) {
            $this->error("❌ No active deal pipeline named 'مبيعات السيارات' found in workspace {$wsId}.");
            return self::FAILURE;
        }

        if ($pipelines->count() > 1) {
            $this->error("❌ Multiple pipelines named 'مبيعات السيارات' found ({$pipelines->count()}). Expected exactly 1.");
            return self::FAILURE;
        }

        $pipeline = $pipelines->first();
        $currency = $workspace->default_currency ?? 'LYD';

        $this->info("Pipeline: {$pipeline->name}");
        $this->info("Pipeline ID: {$pipeline->id}");
        $this->info("Currency: {$currency}");
        $this->info('');

        // ── 3. Upsert plan & rule ────────────────────────────────
        if ($dryRun) {
            $this->previewChanges($wsId, $pipeline, $currency);
        } else {
            DB::transaction(function () use ($wsId, $pipeline, $currency) {
                $this->applyChanges($wsId, $pipeline, $currency);
            });
        }

        return self::SUCCESS;
    }

    /**
     * Preview what would change (dry-run mode).
     */
    private function previewChanges(string $wsId, object $pipeline, string $currency): void
    {
        // Check plan
        $existingPlan = CommissionPlan::where('workspace_id', $wsId)
            ->where('name', self::PLAN_NAME)
            ->first();

        if ($existingPlan) {
            $this->line("📋 Plan: '{$existingPlan->name}' already exists (id: {$existingPlan->id})");
            $planStatus = $existingPlan->is_active ? '✅ active' : '⚠️ inactive → would activate';
        } else {
            $this->line("📋 Plan: '" . self::PLAN_NAME . "' would be CREATED");
            $planStatus = '🆕 would create';
        }

        // Check rule
        $existingRule = null;
        if ($existingPlan) {
            $existingRule = CommissionRule::where('workspace_id', $wsId)
                ->where('commission_plan_id', $existingPlan->id)
                ->where('pipeline_id', $pipeline->id)
                ->where('trigger_status', self::TRIGGER_STATUS)
                ->where('target_type', self::TARGET_TYPE)
                ->where('calculation_type', self::CALCULATION_TYPE)
                ->first();
        }

        if ($existingRule) {
            $ruleStatus = '✅ exists';
            $changes = [];
            if ((float) $existingRule->percentage_rate !== self::PERCENTAGE_RATE) {
                $changes[] = "percentage_rate: {$existingRule->percentage_rate} → " . self::PERCENTAGE_RATE;
            }
            if (!$existingRule->is_active) {
                $changes[] = 'is_active: false → true';
            }
            if ($existingRule->currency !== $currency) {
                $changes[] = "currency: {$existingRule->currency} → {$currency}";
            }
            if (empty($changes)) {
                $ruleStatus = '✅ unchanged';
            } else {
                $ruleStatus = '🔄 would update: ' . implode(', ', $changes);
            }
        } else {
            $ruleStatus = '🆕 would create';
        }

        $this->info('');
        $this->table(
            ['Component', 'Status'],
            [
                ['CommissionPlan', $planStatus],
                ['CommissionRule', $ruleStatus],
            ]
        );

        $this->info('');
        $this->table(
            ['Field', 'Value'],
            [
                ['Plan Name', self::PLAN_NAME],
                ['Plan Key', self::PLAN_KEY],
                ['Plan applies_to', 'pipeline_record'],
                ['Rule pipeline_id', $pipeline->id],
                ['Rule trigger_status', self::TRIGGER_STATUS],
                ['Rule target_type', self::TARGET_TYPE],
                ['Rule calculation_type', self::CALCULATION_TYPE],
                ['Rule percentage_rate', self::PERCENTAGE_RATE],
                ['Rule currency', $currency],
            ]
        );

        $this->warn('');
        $this->warn('DRY RUN — no changes were written. Remove --dry-run to apply.');
    }

    /**
     * Apply the plan & rule upsert (inside a DB transaction).
     */
    private function applyChanges(string $wsId, object $pipeline, string $currency): void
    {
        // ── Plan ─────────────────────────────────────────────────
        $plan = CommissionPlan::where('workspace_id', $wsId)
            ->where('name', self::PLAN_NAME)
            ->first();

        $planBefore = $plan ? clone $plan : null;

        if ($plan) {
            $planChanged = false;
            if (!$plan->is_active) {
                $plan->is_active = true;
                $planChanged = true;
            }
            if ($plan->plan_key !== self::PLAN_KEY) {
                $plan->plan_key = self::PLAN_KEY;
                $planChanged = true;
            }
            if ($planChanged) {
                $plan->save();
                $this->info("🔄 Plan UPDATED: '{$plan->name}' (id: {$plan->id})");
            } else {
                $this->info("✅ Plan UNCHANGED: '{$plan->name}' (id: {$plan->id})");
            }
        } else {
            $plan = CommissionPlan::create([
                'workspace_id' => $wsId,
                'plan_key'     => self::PLAN_KEY,
                'name'         => self::PLAN_NAME,
                'description'  => 'Auto-generated demo commission plan for automotive sales.',
                'applies_to'   => 'pipeline_record',
                'is_active'    => true,
                'sort_order'   => 0,
            ]);
            $this->info("🆕 Plan CREATED: '{$plan->name}' (id: {$plan->id})");
        }

        // ── Rule ─────────────────────────────────────────────────
        $rule = CommissionRule::where('workspace_id', $wsId)
            ->where('commission_plan_id', $plan->id)
            ->where('pipeline_id', $pipeline->id)
            ->where('trigger_status', self::TRIGGER_STATUS)
            ->where('target_type', self::TARGET_TYPE)
            ->where('calculation_type', self::CALCULATION_TYPE)
            ->first();

        if ($rule) {
            $ruleChanged = false;
            $changes = [];

            if (bccomp((string) $rule->percentage_rate, (string) self::PERCENTAGE_RATE, 4) !== 0) {
                $changes[] = "percentage_rate: {$rule->percentage_rate} → " . self::PERCENTAGE_RATE;
                $rule->percentage_rate = self::PERCENTAGE_RATE;
                $ruleChanged = true;
            }
            if (!$rule->is_active) {
                $changes[] = 'is_active: false → true';
                $rule->is_active = true;
                $ruleChanged = true;
            }
            if ($rule->currency !== $currency) {
                $changes[] = "currency: {$rule->currency} → {$currency}";
                $rule->currency = $currency;
                $ruleChanged = true;
            }

            if ($ruleChanged) {
                $rule->save();
                $this->info('🔄 Rule UPDATED: ' . implode(', ', $changes));
            } else {
                $this->info("✅ Rule UNCHANGED (id: {$rule->id})");
            }
        } else {
            $rule = CommissionRule::create([
                'workspace_id'       => $wsId,
                'commission_plan_id' => $plan->id,
                'pipeline_id'        => $pipeline->id,
                'stage_id'           => null,
                'role_id'            => null,
                'department_id'      => null,
                'team_id'            => null,
                'target_type'        => self::TARGET_TYPE,
                'calculation_type'   => self::CALCULATION_TYPE,
                'percentage_rate'    => self::PERCENTAGE_RATE,
                'fixed_amount'       => null,
                'currency'           => $currency,
                'min_record_value'   => null,
                'max_record_value'   => null,
                'trigger_status'     => self::TRIGGER_STATUS,
                'is_active'          => true,
                'sort_order'         => 0,
            ]);
            $this->info("🆕 Rule CREATED (id: {$rule->id})");
        }

        // ── Summary ──────────────────────────────────────────────
        $this->info('');
        $this->table(
            ['Component', 'ID', 'Status'],
            [
                ['CommissionPlan', $plan->id, $planBefore ? ($plan->wasChanged() ? '🔄 Updated' : '✅ Unchanged') : '🆕 Created'],
                ['CommissionRule', $rule->id, $rule->wasRecentlyCreated ? '🆕 Created' : ($rule->wasChanged() ? '🔄 Updated' : '✅ Unchanged')],
            ]
        );

        // Count existing entries — confirm we didn't touch them
        $entryCount = DB::table('commission_entries')
            ->where('workspace_id', $wsId)
            ->count();
        $this->info('');
        $this->info("📊 Existing commission entries preserved: {$entryCount}");
        $this->info('✅ Sync complete. No commission entries were created or modified.');
    }
}
