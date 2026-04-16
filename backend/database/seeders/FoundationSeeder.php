<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;

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
            'permissions'     => json_encode([
                'contacts.list', 'contacts.show', 'contacts.create', 'contacts.update', 'contacts.delete',
                'categories.list', 'categories.show', 'categories.create', 'categories.update', 'categories.delete',
                'products.list', 'products.show', 'products.create', 'products.update', 'products.delete',
                'invoices.list', 'invoices.show', 'invoices.create', 'invoices.update',
                'accounts.list', 'accounts.show', 'accounts.create', 'accounts.update', 'accounts.delete',
                'orders.list', 'orders.show', 'orders.create', 'orders.update',
                'journal_entries.list', 'journal_entries.show', 'journal_entries.create', 'journal_entries.update',
                'warehouses.list', 'warehouses.show', 'warehouses.create', 'warehouses.update', 'warehouses.delete',
                'payments.list', 'payments.show', 'payments.create',
                'inventory.list', 'inventory.show', 'inventory.create',
                'reservations.list', 'reservations.show', 'reservations.create', 'reservations.update',
                'bom.list', 'bom.show', 'bom.create', 'bom.update', 'bom.delete',
                'production.list', 'production.show', 'production.create', 'production.update',
                'recurring.list', 'recurring.show', 'recurring.create', 'recurring.update', 'recurring.delete',
                'notifications.list', 'notifications.update',
                'audit.list', 'audit.show',
                'reports.view',
            ]),
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
            ['key' => 'reports.view', 'module' => 'reports', 'entity' => 'reports', 'action' => 'view', 'scope_type' => 'workspace', 'applicable_scopes' => '{"workspace"}'],
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
