<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;

/**
 * Seeds platform-level data: plans, pricing, settings, super-admin flag.
 * Safe to re-run (uses insertOrIgnore / updateOrInsert).
 */
class PlatformSeeder extends Seeder
{
    // Deterministic UUIDs for plans
    public const PLAN_FREE       = 'a0000000-0000-0000-0000-000000000001';
    public const PLAN_STARTER    = 'a0000000-0000-0000-0000-000000000002';
    public const PLAN_PRO        = 'a0000000-0000-0000-0000-000000000003';
    public const PLAN_ENTERPRISE = 'a0000000-0000-0000-0000-000000000004';

    // Deterministic UUIDs for pricing
    public const PRICE_FREE_M      = 'b0000000-0000-0000-0000-000000000001';
    public const PRICE_STARTER_M   = 'b0000000-0000-0000-0000-000000000002';
    public const PRICE_STARTER_A   = 'b0000000-0000-0000-0000-000000000003';
    public const PRICE_PRO_M       = 'b0000000-0000-0000-0000-000000000004';
    public const PRICE_PRO_A       = 'b0000000-0000-0000-0000-000000000005';
    public const PRICE_PRO_Q       = 'b0000000-0000-0000-0000-000000000006';
    public const PRICE_ENT_A       = 'b0000000-0000-0000-0000-000000000007';

    public function run(): void
    {
        $this->seedPlans();
        $this->seedPricing();
        $this->seedPlanFeatures();
        $this->seedSettings();
        $this->seedSuperAdmin();

        $this->command->info('Platform seed data created: 4 plans, 7 pricing rows, features, settings, super-admin.');
    }

    private function seedPlans(): void
    {
        $plans = [
            ['id' => self::PLAN_FREE,       'name' => 'Free',       'slug' => 'free',       'description' => 'Basic free tier for trying SmartBiz AI',     'max_employees' => 3,   'max_workspaces' => 1, 'sort_order' => 0],
            ['id' => self::PLAN_STARTER,    'name' => 'Starter',    'slug' => 'starter',    'description' => 'For small businesses getting started',        'max_employees' => 10,  'max_workspaces' => 1, 'sort_order' => 1],
            ['id' => self::PLAN_PRO,        'name' => 'Professional','slug' => 'professional','description' => 'Full-featured plan for growing businesses', 'max_employees' => 50,  'max_workspaces' => 3, 'sort_order' => 2],
            ['id' => self::PLAN_ENTERPRISE, 'name' => 'Enterprise', 'slug' => 'enterprise', 'description' => 'Custom enterprise plan with dedicated support','max_employees' => 500, 'max_workspaces' => 10,'sort_order' => 3],
        ];

        foreach ($plans as $p) {
            DB::table('platform_plans')->insertOrIgnore(array_merge($p, [
                'is_active'  => true,
                'created_at' => now(),
                'updated_at' => now(),
            ]));
        }
    }

    private function seedPricing(): void
    {
        $prices = [
            ['id' => self::PRICE_FREE_M,    'plan_id' => self::PLAN_FREE,       'billing_cycle' => 'monthly', 'base_price' => 0,      'included_employees' => 3,  'price_per_employee' => 0,    'included_ai_credits' => 20,   'ai_overage_price_per_credit' => 0],
            ['id' => self::PRICE_STARTER_M, 'plan_id' => self::PLAN_STARTER,    'billing_cycle' => 'monthly', 'base_price' => 29.00,  'included_employees' => 5,  'price_per_employee' => 5.00, 'included_ai_credits' => 100,  'ai_overage_price_per_credit' => 0.10],
            ['id' => self::PRICE_STARTER_A, 'plan_id' => self::PLAN_STARTER,    'billing_cycle' => 'annual',  'base_price' => 290.00, 'included_employees' => 5,  'price_per_employee' => 5.00, 'included_ai_credits' => 100,  'ai_overage_price_per_credit' => 0.08],
            ['id' => self::PRICE_PRO_M,     'plan_id' => self::PLAN_PRO,        'billing_cycle' => 'monthly', 'base_price' => 79.00,  'included_employees' => 15, 'price_per_employee' => 7.00, 'included_ai_credits' => 500,  'ai_overage_price_per_credit' => 0.05],
            ['id' => self::PRICE_PRO_A,     'plan_id' => self::PLAN_PRO,        'billing_cycle' => 'annual',  'base_price' => 790.00, 'included_employees' => 15, 'price_per_employee' => 7.00, 'included_ai_credits' => 500,  'ai_overage_price_per_credit' => 0.04],
            ['id' => self::PRICE_PRO_Q,     'plan_id' => self::PLAN_PRO,        'billing_cycle' => 'quarterly','base_price' => 210.00,'included_employees' => 15, 'price_per_employee' => 7.00, 'included_ai_credits' => 500,  'ai_overage_price_per_credit' => 0.05],
            ['id' => self::PRICE_ENT_A,     'plan_id' => self::PLAN_ENTERPRISE, 'billing_cycle' => 'annual',  'base_price' => 2990.00,'included_employees' => 50, 'price_per_employee' => 10.00,'included_ai_credits' => 5000, 'ai_overage_price_per_credit' => 0.03],
        ];

        foreach ($prices as $p) {
            DB::table('platform_plan_prices')->insertOrIgnore(array_merge($p, [
                'currency' => 'USD',
                'is_active' => true,
                'effective_from' => '2026-01-01',
                'created_at' => now(),
                'updated_at' => now(),
            ]));
        }
    }

    private function seedPlanFeatures(): void
    {
        $featureSets = [
            self::PLAN_FREE => [
                'module.contacts' => true, 'module.products' => true, 'module.invoices' => true,
                'module.payments' => true, 'module.reports' => true,
                'module.production' => false, 'module.bom' => false,
                'ai.discovery' => true, 'ai.chat' => false, 'ai.operations' => false,
                'premium.multi_warehouse' => false, 'premium.advanced_reports' => false,
            ],
            self::PLAN_STARTER => [
                'module.contacts' => true, 'module.products' => true, 'module.invoices' => true,
                'module.orders' => true, 'module.payments' => true, 'module.inventory' => true,
                'module.accounting' => true, 'module.warehouses' => true, 'module.reports' => true,
                'module.recurring_expenses' => true,
                'module.production' => false, 'module.bom' => false,
                'ai.discovery' => true, 'ai.chat' => true, 'ai.operations' => false,
                'premium.multi_warehouse' => false, 'premium.advanced_reports' => false,
            ],
            self::PLAN_PRO => [
                'module.contacts' => true, 'module.products' => true, 'module.invoices' => true,
                'module.orders' => true, 'module.payments' => true, 'module.inventory' => true,
                'module.accounting' => true, 'module.warehouses' => true, 'module.reports' => true,
                'module.recurring_expenses' => true, 'module.production' => true, 'module.bom' => true,
                'ai.discovery' => true, 'ai.chat' => true, 'ai.operations' => true,
                'premium.multi_warehouse' => true, 'premium.advanced_reports' => true,
                'premium.api_access' => true,
            ],
            self::PLAN_ENTERPRISE => [
                'module.contacts' => true, 'module.products' => true, 'module.invoices' => true,
                'module.orders' => true, 'module.payments' => true, 'module.inventory' => true,
                'module.accounting' => true, 'module.warehouses' => true, 'module.reports' => true,
                'module.recurring_expenses' => true, 'module.production' => true, 'module.bom' => true,
                'ai.discovery' => true, 'ai.chat' => true, 'ai.operations' => true, 'ai.automation' => true,
                'premium.multi_warehouse' => true, 'premium.advanced_reports' => true,
                'premium.api_access' => true, 'premium.custom_roles' => true,
                'beta.ai_insights' => true, 'beta.workflow_builder' => true,
            ],
        ];

        foreach ($featureSets as $planId => $features) {
            foreach ($features as $key => $enabled) {
                DB::table('plan_features')->insertOrIgnore([
                    'id'          => \Illuminate\Support\Str::uuid(),
                    'plan_id'     => $planId,
                    'feature_key' => $key,
                    'is_enabled'  => $enabled,
                ]);
            }
        }
    }

    private function seedSettings(): void
    {
        $settings = [
            ['key' => 'default_trial_days',        'value' => '14',    'description' => 'Default trial period in days for new workspaces'],
            ['key' => 'launch_promo_enabled',      'value' => 'false', 'description' => 'Whether launch promotion is active'],
            ['key' => 'launch_promo_trial_days',   'value' => '30',    'description' => 'Extended trial days during launch promo'],
            ['key' => 'default_ai_credits_trial',  'value' => '50',    'description' => 'AI credits given during trial period'],
            ['key' => 'ai_credit_cost.discovery_classify',  'value' => '2', 'description' => 'Credits per business classification'],
            ['key' => 'ai_credit_cost.discovery_blueprint', 'value' => '5', 'description' => 'Credits per blueprint generation'],
            ['key' => 'ai_credit_cost.ai_chat',             'value' => '1', 'description' => 'Credits per AI chat message'],
            ['key' => 'ai_credit_cost.ai_operation',        'value' => '3', 'description' => 'Credits per AI business operation'],
        ];

        foreach ($settings as $s) {
            DB::table('platform_settings')->insertOrIgnore(array_merge($s, [
                'updated_at' => now(),
            ]));
        }
    }

    private function seedSuperAdmin(): void
    {
        // Set the FoundationSeeder admin user as super-admin
        DB::table('users')
            ->where('id', FoundationSeeder::USER_ID)
            ->update(['is_super_admin' => true]);

        $this->command->info('Super-admin: ' . FoundationSeeder::USER_EMAIL);
    }
}
