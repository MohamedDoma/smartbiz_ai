<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use App\Services\PermissionCatalog;

/**
 * Seeds minimal deterministic data for integration testing.
 *
 * Creates: 1 workspace, 1 user, 1 membership, 1 role, 1 membership_role,
 * and a set of permission_definitions for the Contacts module.
 *
 * Safe to run multiple times — uses upsert-style INSERT ... ON CONFLICT DO NOTHING.
 */
class FoundationSeeder extends Seeder
{
    // Deterministic UUIDs for testing
    public const WORKSPACE_ID  = '10000000-0000-0000-0000-000000000001';
    public const USER_ID       = '20000000-0000-0000-0000-000000000001';
    public const MEMBERSHIP_ID = '30000000-0000-0000-0000-000000000001';
    public const ROLE_ID       = '40000000-0000-0000-0000-000000000001';
    public const MR_ID         = '50000000-0000-0000-0000-000000000001';

    public const USER_EMAIL    = 'admin@smartbiz.test';
    public const USER_PASSWORD = 'SmartBiz2026!';

    public function run(): void
    {
        // 1. Workspace
        DB::table('workspaces')->insertOrIgnore([
            'id'                  => self::WORKSPACE_ID,
            'name'                => 'Test Workspace',
            'industry_type'       => 'technology',
            'business_size'       => 'small',
            'subscription_status' => 'active',
            'default_locale'      => 'en',
            'default_currency'    => 'USD',
            'timezone'            => 'UTC',
            'is_active'           => true,
            'created_at'          => now(),
            'updated_at'          => now(),
        ]);

        // 2. User
        DB::table('users')->insertOrIgnore([
            'id'            => self::USER_ID,
            'full_name'     => 'Admin User',
            'email'         => self::USER_EMAIL,
            'phone_number'  => '+10000000000',
            'password_hash' => Hash::make(self::USER_PASSWORD),
            'is_active'     => true,
            'created_at'    => now(),
            'updated_at'    => now(),
        ]);

        // 3. Workspace Membership
        DB::table('workspace_memberships')->insertOrIgnore([
            'id'           => self::MEMBERSHIP_ID,
            'workspace_id' => self::WORKSPACE_ID,
            'user_id'      => self::USER_ID,
            'status'       => 'active',
            'hire_date'    => now()->toDateString(),
            'base_salary'  => 0,
            'annual_leave_balance' => 21,
            'assigned_warehouses'  => '[]',
            'joined_at'    => now(),
            'created_at'   => now(),
            'updated_at'   => now(),
        ]);

        // 4. Role (admin with full permissions)
        DB::table('roles')->insertOrIgnore([
            'id'              => self::ROLE_ID,
            'workspace_id'    => self::WORKSPACE_ID,
            'name'            => 'Admin',
            'role_key'        => 'admin',
            'permissions'     => json_encode(PermissionCatalog::allKeys()),
            'description'     => 'Full administrative access',
            'hierarchy_level' => 1,
            'is_system'       => true,
            'is_default'      => false,
            'is_deletable'    => false,
            'created_at'      => now(),
            'updated_at'      => now(),
        ]);

        // 5. Membership Role assignment
        DB::table('membership_roles')->insertOrIgnore([
            'id'            => self::MR_ID,
            'workspace_id'  => self::WORKSPACE_ID,
            'membership_id' => self::MEMBERSHIP_ID,
            'role_id'       => self::ROLE_ID,
            'is_primary'    => true,
            'assigned_at'   => now(),
        ]);

        // 6. Permission definitions (reference data)
        $permissions = [
            // Contacts
            ['key' => 'contacts.list',   'module' => 'crm', 'entity' => 'contacts', 'action' => 'list',   'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'contacts.show',   'module' => 'crm', 'entity' => 'contacts', 'action' => 'show',   'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'contacts.create', 'module' => 'crm', 'entity' => 'contacts', 'action' => 'create', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'contacts.update', 'module' => 'crm', 'entity' => 'contacts', 'action' => 'update', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'contacts.delete', 'module' => 'crm', 'entity' => 'contacts', 'action' => 'delete', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            // Categories
            ['key' => 'categories.list',   'module' => 'inventory', 'entity' => 'categories', 'action' => 'list',   'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'categories.show',   'module' => 'inventory', 'entity' => 'categories', 'action' => 'show',   'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'categories.create', 'module' => 'inventory', 'entity' => 'categories', 'action' => 'create', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'categories.update', 'module' => 'inventory', 'entity' => 'categories', 'action' => 'update', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'categories.delete', 'module' => 'inventory', 'entity' => 'categories', 'action' => 'delete', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            // Products
            ['key' => 'products.list',   'module' => 'inventory', 'entity' => 'products', 'action' => 'list',   'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'products.show',   'module' => 'inventory', 'entity' => 'products', 'action' => 'show',   'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'products.create', 'module' => 'inventory', 'entity' => 'products', 'action' => 'create', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'products.update', 'module' => 'inventory', 'entity' => 'products', 'action' => 'update', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'products.delete', 'module' => 'inventory', 'entity' => 'products', 'action' => 'delete', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            // Invoices (no delete — financial immutable)
            ['key' => 'invoices.list',   'module' => 'finance', 'entity' => 'invoices', 'action' => 'list',   'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'invoices.show',   'module' => 'finance', 'entity' => 'invoices', 'action' => 'show',   'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'invoices.create', 'module' => 'finance', 'entity' => 'invoices', 'action' => 'create', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'invoices.update', 'module' => 'finance', 'entity' => 'invoices', 'action' => 'update', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            // Accounts
            ['key' => 'accounts.list',   'module' => 'finance', 'entity' => 'accounts', 'action' => 'list',   'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'accounts.show',   'module' => 'finance', 'entity' => 'accounts', 'action' => 'show',   'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'accounts.create', 'module' => 'finance', 'entity' => 'accounts', 'action' => 'create', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'accounts.update', 'module' => 'finance', 'entity' => 'accounts', 'action' => 'update', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'accounts.delete', 'module' => 'finance', 'entity' => 'accounts', 'action' => 'delete', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            // Orders (no delete — business records)
            ['key' => 'orders.list',   'module' => 'sales', 'entity' => 'orders', 'action' => 'list',   'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'orders.show',   'module' => 'sales', 'entity' => 'orders', 'action' => 'show',   'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'orders.create', 'module' => 'sales', 'entity' => 'orders', 'action' => 'create', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'orders.update', 'module' => 'sales', 'entity' => 'orders', 'action' => 'update', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            // Journal Entries (no delete — financial immutable)
            ['key' => 'journal_entries.list',   'module' => 'finance', 'entity' => 'journal_entries', 'action' => 'list',   'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'journal_entries.show',   'module' => 'finance', 'entity' => 'journal_entries', 'action' => 'show',   'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'journal_entries.create', 'module' => 'finance', 'entity' => 'journal_entries', 'action' => 'create', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'journal_entries.update', 'module' => 'finance', 'entity' => 'journal_entries', 'action' => 'update', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            // Warehouses
            ['key' => 'warehouses.list',   'module' => 'inventory', 'entity' => 'warehouses', 'action' => 'list',   'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'warehouses.show',   'module' => 'inventory', 'entity' => 'warehouses', 'action' => 'show',   'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'warehouses.create', 'module' => 'inventory', 'entity' => 'warehouses', 'action' => 'create', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'warehouses.update', 'module' => 'inventory', 'entity' => 'warehouses', 'action' => 'update', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'warehouses.delete', 'module' => 'inventory', 'entity' => 'warehouses', 'action' => 'delete', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            // Payments (no delete — financial records)
            ['key' => 'payments.list',   'module' => 'finance', 'entity' => 'payments', 'action' => 'list',   'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'payments.show',   'module' => 'finance', 'entity' => 'payments', 'action' => 'show',   'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'payments.create', 'module' => 'finance', 'entity' => 'payments', 'action' => 'create', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            // Inventory (immutable — no update/delete)
            ['key' => 'inventory.list',   'module' => 'inventory', 'entity' => 'inventory_movements', 'action' => 'list',   'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'inventory.show',   'module' => 'inventory', 'entity' => 'inventory_movements', 'action' => 'show',   'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'inventory.create', 'module' => 'inventory', 'entity' => 'inventory_movements', 'action' => 'create', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            // Stock Reservations
            ['key' => 'reservations.list',   'module' => 'inventory', 'entity' => 'stock_reservations', 'action' => 'list',   'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'reservations.show',   'module' => 'inventory', 'entity' => 'stock_reservations', 'action' => 'show',   'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'reservations.create', 'module' => 'inventory', 'entity' => 'stock_reservations', 'action' => 'create', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'reservations.update', 'module' => 'inventory', 'entity' => 'stock_reservations', 'action' => 'update', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            // BOM
            ['key' => 'bom.list',   'module' => 'production', 'entity' => 'bill_of_materials', 'action' => 'list',   'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'bom.show',   'module' => 'production', 'entity' => 'bill_of_materials', 'action' => 'show',   'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'bom.create', 'module' => 'production', 'entity' => 'bill_of_materials', 'action' => 'create', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'bom.update', 'module' => 'production', 'entity' => 'bill_of_materials', 'action' => 'update', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'bom.delete', 'module' => 'production', 'entity' => 'bill_of_materials', 'action' => 'delete', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            // Production Orders (no delete)
            ['key' => 'production.list',   'module' => 'production', 'entity' => 'production_orders', 'action' => 'list',   'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'production.show',   'module' => 'production', 'entity' => 'production_orders', 'action' => 'show',   'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'production.create', 'module' => 'production', 'entity' => 'production_orders', 'action' => 'create', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'production.update', 'module' => 'production', 'entity' => 'production_orders', 'action' => 'update', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            // Recurring Expenses
            ['key' => 'recurring.list',   'module' => 'finance', 'entity' => 'recurring_expenses', 'action' => 'list',   'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'recurring.show',   'module' => 'finance', 'entity' => 'recurring_expenses', 'action' => 'show',   'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'recurring.create', 'module' => 'finance', 'entity' => 'recurring_expenses', 'action' => 'create', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'recurring.update', 'module' => 'finance', 'entity' => 'recurring_expenses', 'action' => 'update', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'recurring.delete', 'module' => 'finance', 'entity' => 'recurring_expenses', 'action' => 'delete', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            // Notifications
            ['key' => 'notifications.list',   'module' => 'system', 'entity' => 'notifications', 'action' => 'list',   'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'notifications.update', 'module' => 'system', 'entity' => 'notifications', 'action' => 'update', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            // Audit Logs (read-only)
            ['key' => 'audit.list', 'module' => 'system', 'entity' => 'audit_logs', 'action' => 'list', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'audit.show', 'module' => 'system', 'entity' => 'audit_logs', 'action' => 'show', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            // Reports
            ['key' => 'reports.view',   'module' => 'reports', 'entity' => 'reports', 'action' => 'view',   'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'reports.run',    'module' => 'reports', 'entity' => 'reports', 'action' => 'run',    'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'reports.manage', 'module' => 'reports', 'entity' => 'reports', 'action' => 'manage', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            // Pipelines
            ['key' => 'pipelines.list',              'module' => 'crm', 'entity' => 'pipelines',        'action' => 'list',       'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'pipelines.manage',            'module' => 'crm', 'entity' => 'pipelines',        'action' => 'manage',     'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'pipeline_records.create',     'module' => 'crm', 'entity' => 'pipeline_records', 'action' => 'create',     'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'pipeline_records.update',     'module' => 'crm', 'entity' => 'pipeline_records', 'action' => 'update',     'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace","own"}'],
            ['key' => 'pipeline_records.delete',     'module' => 'crm', 'entity' => 'pipeline_records', 'action' => 'delete',     'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace","own"}'],
            ['key' => 'pipeline_records.manage_all', 'module' => 'crm', 'entity' => 'pipeline_records', 'action' => 'manage_all', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'pipeline_records.assign',     'module' => 'crm', 'entity' => 'pipeline_records', 'action' => 'assign',     'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            // Commissions
            ['key' => 'commissions.list',      'module' => 'crm', 'entity' => 'commission_entries', 'action' => 'list',      'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'commissions.view_own',  'module' => 'crm', 'entity' => 'commission_entries', 'action' => 'view_own',  'scope_type' => 'workspace', 'applicable_scopes' => '{"own"}'],
            ['key' => 'commissions.view_all',  'module' => 'crm', 'entity' => 'commission_entries', 'action' => 'view_all',  'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'commissions.view_team', 'module' => 'crm', 'entity' => 'commission_entries', 'action' => 'view_team', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'commissions.calculate', 'module' => 'crm', 'entity' => 'commission_entries', 'action' => 'calculate', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'commissions.approve',   'module' => 'crm', 'entity' => 'commission_entries', 'action' => 'approve',   'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'commissions.pay',       'module' => 'crm', 'entity' => 'commission_entries', 'action' => 'pay',       'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'commissions.cancel',    'module' => 'crm', 'entity' => 'commission_entries', 'action' => 'cancel',    'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            // Commission Settings
            ['key' => 'commissions.settings.view',   'module' => 'crm', 'entity' => 'commission_settings', 'action' => 'view',   'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'commissions.settings.manage', 'module' => 'crm', 'entity' => 'commission_settings', 'action' => 'manage', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            // Document Checklists
            ['key' => 'document_checklists.view',   'module' => 'crm', 'entity' => 'document_checklists', 'action' => 'view',   'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'document_checklists.manage', 'module' => 'crm', 'entity' => 'document_checklists', 'action' => 'manage', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            // Ownership Assignments
            ['key' => 'ownership.view',   'module' => 'crm', 'entity' => 'ownership_assignments', 'action' => 'view',   'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'ownership.manage', 'module' => 'crm', 'entity' => 'ownership_assignments', 'action' => 'manage', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            // Data Quality / Duplicates
            ['key' => 'duplicates.view',    'module' => 'crm', 'entity' => 'duplicates', 'action' => 'view',    'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'duplicates.check',   'module' => 'crm', 'entity' => 'duplicates', 'action' => 'check',   'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'duplicates.manage',  'module' => 'crm', 'entity' => 'duplicates', 'action' => 'manage',  'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'duplicates.resolve', 'module' => 'crm', 'entity' => 'duplicates', 'action' => 'resolve', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            // ── Navigation-gate & module-access permissions ─────
            // AI
            ['key' => 'ai.chat',            'module' => 'ai', 'entity' => 'ai_chat',     'action' => 'chat',    'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'ai.actions',         'module' => 'ai', 'entity' => 'ai_actions',  'action' => 'confirm', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'ai.insights.view',   'module' => 'ai', 'entity' => 'ai_insights', 'action' => 'view',    'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'ai.insights.manage', 'module' => 'ai', 'entity' => 'ai_insights', 'action' => 'manage',  'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'ai.manage',          'module' => 'ai', 'entity' => 'ai',          'action' => 'manage',  'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'ai_advisor.view',    'module' => 'ai', 'entity' => 'ai_advisor',  'action' => 'view',    'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'ai_advisor.manage',  'module' => 'ai', 'entity' => 'ai_advisor',  'action' => 'manage',  'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            // POS
            ['key' => 'pos.view', 'module' => 'sales', 'entity' => 'pos', 'action' => 'view', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            // Accounting module gate
            ['key' => 'accounting.view', 'module' => 'finance', 'entity' => 'accounting', 'action' => 'view', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'finance.view',     'module' => 'finance', 'entity' => 'finance_operations', 'action' => 'view',   'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'finance.manage',   'module' => 'finance', 'entity' => 'finance_operations', 'action' => 'manage', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'finance.post',     'module' => 'finance', 'entity' => 'finance_operations', 'action' => 'post',   'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            // Employees
            ['key' => 'employees.list',   'module' => 'people', 'entity' => 'employees', 'action' => 'list',   'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'employees.show',   'module' => 'people', 'entity' => 'employees', 'action' => 'show',   'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'employees.create', 'module' => 'people', 'entity' => 'employees', 'action' => 'create', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'employees.update', 'module' => 'people', 'entity' => 'employees', 'action' => 'update', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            // Roles
            ['key' => 'roles.list',   'module' => 'people', 'entity' => 'roles', 'action' => 'list',   'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'roles.manage', 'module' => 'people', 'entity' => 'roles', 'action' => 'manage', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            // Departments
            ['key' => 'departments.list',   'module' => 'people', 'entity' => 'departments', 'action' => 'list',   'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'departments.manage', 'module' => 'people', 'entity' => 'departments', 'action' => 'manage', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            // Teams
            ['key' => 'teams.list',   'module' => 'people', 'entity' => 'teams', 'action' => 'list',   'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'teams.manage', 'module' => 'people', 'entity' => 'teams', 'action' => 'manage', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            // Invitations
            ['key' => 'invitations.manage', 'module' => 'people', 'entity' => 'invitations', 'action' => 'manage', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            // Settings
            ['key' => 'settings.view',   'module' => 'system', 'entity' => 'settings', 'action' => 'view',   'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'settings.manage', 'module' => 'system', 'entity' => 'settings', 'action' => 'manage', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            // Workspace Billing
            ['key' => 'billing.manual_payment', 'module' => 'billing', 'entity' => 'manual_payments', 'action' => 'create', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            // Discovery
            ['key' => 'discovery.manage', 'module' => 'system', 'entity' => 'discovery', 'action' => 'manage', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            // Approvals
            ['key' => 'approvals.list',    'module' => 'approvals', 'entity' => 'approval_requests',  'action' => 'list',    'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'approvals.show',    'module' => 'approvals', 'entity' => 'approval_requests',  'action' => 'show',    'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'approvals.request', 'module' => 'approvals', 'entity' => 'approval_requests',  'action' => 'request', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'approvals.decide',  'module' => 'approvals', 'entity' => 'approval_requests',  'action' => 'decide',  'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'approvals.manage',  'module' => 'approvals', 'entity' => 'approval_workflows', 'action' => 'manage',  'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'approvals.cancel',  'module' => 'approvals', 'entity' => 'approval_requests',  'action' => 'cancel',  'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            // ── Scope-based contact & pipeline permissions ──────
            ['key' => 'contacts.own',         'module' => 'crm', 'entity' => 'contacts',         'action' => 'own',         'scope_type' => 'workspace',       'applicable_scopes' => '{"own"}'],
            ['key' => 'contacts.manage_team', 'module' => 'crm', 'entity' => 'contacts',         'action' => 'manage_team', 'scope_type' => 'workspace',      'applicable_scopes' => '{"team"}'],
            ['key' => 'contacts.manage_all',  'module' => 'crm', 'entity' => 'contacts',         'action' => 'manage_all',  'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'contacts.assign',      'module' => 'crm', 'entity' => 'contacts',         'action' => 'assign',      'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
            ['key' => 'pipeline_records.own',         'module' => 'crm', 'entity' => 'pipeline_records', 'action' => 'own',         'scope_type' => 'workspace',  'applicable_scopes' => '{"own"}'],
            ['key' => 'pipeline_records.manage_team', 'module' => 'crm', 'entity' => 'pipeline_records', 'action' => 'manage_team', 'scope_type' => 'workspace', 'applicable_scopes' => '{"team"}'],
        ];

        foreach ($permissions as $perm) {
            DB::table('permission_definitions')->insertOrIgnore(array_merge($perm, [
                'created_at' => now(),
            ]));
        }

        $this->command->info('Foundation seed data created.');
        $this->command->info("Login: " . self::USER_EMAIL . " / " . self::USER_PASSWORD);
    }
}
