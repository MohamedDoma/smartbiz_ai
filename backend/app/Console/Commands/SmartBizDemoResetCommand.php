<?php

namespace App\Console\Commands;

use Database\Seeders\SmartBizDemoSeeder;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Step 59.2.0 — Clean demo database reset + full demo company seed.
 *
 * Usage:  php artisan smartbiz:demo-reset --yes
 * Safety: Refuses without --yes flag and in production environment.
 */
class SmartBizDemoResetCommand extends Command
{
    protected $signature = 'smartbiz:demo-reset {--yes : Confirm destructive reset}';
    protected $description = 'Wipe all tenant/demo data and seed one clean demo company with realistic data.';

    public function handle(): int
    {
        // ── Safety checks ────────────────────────────────────────
        if (app()->environment('production')) {
            $this->error('🚫 This command cannot run in production.');
            return self::FAILURE;
        }

        if (! $this->option('yes')) {
            $this->error('🚫 You must pass --yes to confirm. This will DELETE ALL tenant data.');
            $this->line('   Usage: php artisan smartbiz:demo-reset --yes');
            return self::FAILURE;
        }

        $this->warn('');
        $this->warn('╔══════════════════════════════════════════════════╗');
        $this->warn('║  ⚠️  DESTRUCTIVE OPERATION — DEMO RESET          ║');
        $this->warn('║  All existing tenant/business data will be wiped ║');
        $this->warn('║  and replaced with one clean demo company.       ║');
        $this->warn('╚══════════════════════════════════════════════════╝');
        $this->warn('');

        // ── Phase 1: Truncate ────────────────────────────────────
        $this->info('Phase 1: Wiping existing data...');
        $this->truncateAll();
        $this->info('✅ Data wiped.');

        // ── Phase 2: Seed ────────────────────────────────────────
        $this->info('');
        $this->info('Phase 2: Seeding demo company...');
        $seeder = new SmartBizDemoSeeder();
        $summary = $seeder->run();
        $this->info('✅ Demo company seeded.');

        // ── Phase 3: Print summary ──────────────────────────────
        $this->info('');
        $this->info('═══════════════════════════════════════════');
        $this->info('  Demo Reset Complete');
        $this->info('═══════════════════════════════════════════');
        $this->table(
            ['Item', 'Value'],
            collect($summary)->map(fn($v, $k) => [$k, $v])->values()->toArray()
        );

        $this->info('');
        $this->info('📄 Credentials: backend/docs/demo_credentials.md');
        $this->info('📄 CSV:         backend/docs/demo_credentials.csv');
        $this->info('');
        $this->info('Next steps:');
        $this->line('  1. Login as owner:   owner@demo.smartbiz.test / SmartBiz@123456');
        $this->line('  2. Login as viewer:  viewer@demo.smartbiz.test / SmartBiz@123456');
        $this->line('  3. Test AI chat:     POST /api/ai/chat { "message": "كم ملخص المالية؟" }');
        $this->line('  4. Test denied:      Login as employee, ask finance question');
        $this->info('');

        return self::SUCCESS;
    }

    /**
     * Truncate all tenant/business tables safely.
     */
    private function truncateAll(): void
    {
        // Disable FK checks for PostgreSQL
        DB::statement('SET session_replication_role = replica;');

        // Tables to truncate — ordered roughly by dependency (children first).
        // Static/reference tables and migrations are NOT included.
        $tables = [
            // AI
            'ai_tool_calls', 'ai_messages', 'ai_conversations', 'ai_usage_logs',
            'ai_insights', 'ai_recommendations', 'ai_change_requests', 'ai_execution_plans',
            'ai_memory', 'ai_credit_transactions', 'ai_credit_balances', 'ai_workspace_settings',
            // Discovery
            'discovery_messages', 'discovery_blueprints', 'discovery_sessions',
            // Commissions
            'commission_entries', 'commission_rules', 'commission_plans',
            // Documents
            'record_documents', 'document_checklist_items', 'document_checklists',
            // Reports
            'report_runs', 'report_templates',
            // Pipeline
            'custom_field_values', 'custom_fields',
            'pipeline_records', 'pipeline_stages', 'pipelines',
            // Finance
            'finance_transaction_lines', 'finance_transactions', 'finance_expenses', 'finance_settings',
            'finance_accounts', 'fiscal_periods',
            'journal_lines', 'journal_entries', 'accounts',
            // Payments & Invoices
            'payment_transactions', 'payments', 'invoice_items', 'invoices',
            'billing_payments', 'billing_invoices', 'billing_snapshots',
            // Orders
            'order_items', 'orders',
            // Inventory
            'stock_transfer_items', 'stock_transfers', 'stock_reservations',
            'inventory_movements', 'inventory_levels', 'inventory_batches', 'inventory_logs_legacy',
            'goods_received_notes', 'grn_items',
            'bill_of_materials', 'production_orders',
            // Products
            'price_list_items', 'price_lists', 'product_variants', 'products', 'product_categories',
            // Contacts
            'contacts',
            // Warehouses
            'warehouses',
            // HR
            'payroll_lines', 'payroll', 'payroll_runs',
            'leave_requests', 'leave_balances', 'leave_types', 'leaves_legacy',
            'attendance', 'shift_assignments', 'shifts',
            // CRM
            'crm_activities', 'opportunities', 'leads',
            'segment_contacts', 'segments',
            'nurturing_enrollments', 'nurturing_sequences',
            'campaign_metrics', 'campaigns',
            'loyalty_transactions', 'loyalty_accounts', 'loyalty_programs',
            'customer_credits', 'customer_subscriptions', 'coupons', 'promotions',
            'referrals', 'referral_programs',
            // Communication
            'outbound_messages', 'inbound_messages', 'message_threads', 'message_templates',
            'communication_automations', 'communication_channels', 'email_logs', 'email_settings',
            // Delivery
            'delivery_proofs', 'delivery_tracking', 'delivery_sla_breaches',
            'delivery_assignments', 'delivery_zones', 'drivers',
            'shipment_items', 'shipments',
            'cod_collections',
            // POS
            'pos_sessions', 'pos_terminals', 'dining_tables',
            // Automation / Webhooks
            'automation_logs', 'webhook_deliveries', 'webhook_events', 'webhook_subscriptions',
            // Misc
            'tasks', 'projects', 'bookings',
            'fixed_assets', 'recurring_expenses',
            'media_generation_requests', 'media_assets', 'brand_kits',
            'attachments', 'notifications',
            'export_jobs', 'import_jobs', 'sync_logs',
            'duplicate_matches', 'duplicate_rules',
            'ownership_transfer_logs', 'ownership_assignments',
            'archival_jobs', 'retention_policies',
            'audit_logs', 'impersonation_sessions',
            'approval_requests', 'idempotency_keys',
            'document_sequences', 'invoice_format_rules',
            'exchange_rates',
            // Platform
            'platform_activation_codes', 'platform_activation_campaigns',
            'platform_broadcasts', 'platform_events',
            'platform_survey_responses', 'platform_surveys',
            'platform_feature_request_votes', 'platform_feature_requests',
            // Workspace
            'workspace_template_applications',
            'workspace_subscriptions',
            'workspace_invitation_roles', 'workspace_invitations',
            'workspace_integrations', 'workspace_configurations',
            'workspace_feature_flags', 'workspace_country_packs',
            'provisioning_entity_bindings', 'provisioning_runs',
            'user_permission_overrides', 'permission_delegation_items', 'permission_delegations',
            'membership_roles', 'workspace_memberships',
            'branches',
            'teams', 'departments',
            'roles',
            // Auth
            'personal_access_tokens',
            // Business templates
            'business_template_custom_fields', 'business_template_modules',
            'business_template_roles', 'business_template_workflows', 'business_templates',
            // Users & Workspaces last
            'platform_users',
            'users', 'workspaces',
            // Taxes/units (workspace-scoped, need re-seed)
            'taxes', 'units_of_measure',
            'tax_rules', 'payroll_statutory_rules',
        ];

        $skipped = 0;
        foreach ($tables as $table) {
            if (Schema::hasTable($table)) {
                DB::table($table)->truncate();
            } else {
                $skipped++;
            }
        }

        // Re-enable FK checks
        DB::statement('SET session_replication_role = DEFAULT;');

        $this->line("   Truncated " . (count($tables) - $skipped) . " tables, skipped {$skipped} missing.");
    }
}
