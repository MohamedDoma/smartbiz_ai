<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use App\Services\PermissionCatalog;

/**
 * Seeds deterministic certification data for RBAC, isolation, and functional tests.
 *
 * Architecture:
 *   Workspace A (primary)  — admin, owner, manager, readonly, finance, warehouse, sales, noperm
 *   Workspace B (isolation) — user_b_admin (admin of WS-B only)
 *   Cross-workspace         — user_cross has memberships in BOTH workspaces
 *
 * Safe to run multiple times — uses insertOrIgnore.
 * Does NOT conflict with FoundationSeeder (different UUID ranges).
 */
class CertificationSeeder extends Seeder
{
    // ── Workspaces ───────────────────────────────────────────────
    public const WS_A = '10000000-0000-0000-0000-000000000001'; // re-use FoundationSeeder WS
    public const WS_B = '10000000-0000-0000-0000-000000000002';

    // ── Users ────────────────────────────────────────────────────
    public const USER_ADMIN     = '20000000-0000-0000-0000-000000000001'; // re-use FoundationSeeder
    public const USER_OWNER     = 'c0000000-0000-0000-0000-000000000001';
    public const USER_MANAGER   = 'c0000000-0000-0000-0000-000000000002';
    public const USER_READONLY  = 'c0000000-0000-0000-0000-000000000003';
    public const USER_FINANCE   = 'c0000000-0000-0000-0000-000000000004';
    public const USER_WAREHOUSE = 'c0000000-0000-0000-0000-000000000005';
    public const USER_SALES     = 'c0000000-0000-0000-0000-000000000006';
    public const USER_NOPERM    = 'c0000000-0000-0000-0000-000000000007';
    public const USER_B_ADMIN   = 'c0000000-0000-0000-0000-000000000008';
    public const USER_CROSS     = 'c0000000-0000-0000-0000-000000000009';

    // ── Roles ────────────────────────────────────────────────────
    public const ROLE_ADMIN     = '40000000-0000-0000-0000-000000000001'; // re-use
    public const ROLE_OWNER     = 'c1000000-0000-0000-0000-000000000001';
    public const ROLE_MANAGER   = 'c1000000-0000-0000-0000-000000000002';
    public const ROLE_READONLY  = 'c1000000-0000-0000-0000-000000000003';
    public const ROLE_FINANCE   = 'c1000000-0000-0000-0000-000000000004';
    public const ROLE_WAREHOUSE = 'c1000000-0000-0000-0000-000000000005';
    public const ROLE_SALES     = 'c1000000-0000-0000-0000-000000000006';
    public const ROLE_NOPERM    = 'c1000000-0000-0000-0000-000000000007';
    public const ROLE_B_ADMIN   = 'c1000000-0000-0000-0000-000000000008';

    // ── Memberships ──────────────────────────────────────────────
    // WS-A memberships
    public const MEMB_A_OWNER     = 'c2000000-0000-0000-0000-000000000001';
    public const MEMB_A_MANAGER   = 'c2000000-0000-0000-0000-000000000002';
    public const MEMB_A_READONLY  = 'c2000000-0000-0000-0000-000000000003';
    public const MEMB_A_FINANCE   = 'c2000000-0000-0000-0000-000000000004';
    public const MEMB_A_WAREHOUSE = 'c2000000-0000-0000-0000-000000000005';
    public const MEMB_A_SALES     = 'c2000000-0000-0000-0000-000000000006';
    public const MEMB_A_NOPERM    = 'c2000000-0000-0000-0000-000000000007';
    public const MEMB_A_CROSS     = 'c2000000-0000-0000-0000-000000000009';
    // WS-B memberships
    public const MEMB_B_ADMIN     = 'c2000000-0000-0000-0000-000000000008';
    public const MEMB_B_CROSS     = 'c2000000-0000-0000-0000-000000000010';

    // ── Business data ────────────────────────────────────────────
    public const CONTACT_A1   = 'c3000000-0000-0000-0000-000000000001';
    public const CONTACT_A2   = 'c3000000-0000-0000-0000-000000000002';
    public const CONTACT_B1   = 'c3000000-0000-0000-0000-000000000003';
    public const CATEGORY_A1  = 'c4000000-0000-0000-0000-000000000001';
    public const CATEGORY_A2  = 'c4000000-0000-0000-0000-000000000002';
    public const PRODUCT_A1   = 'c5000000-0000-0000-0000-000000000001';
    public const PRODUCT_A2   = 'c5000000-0000-0000-0000-000000000002';
    public const PRODUCT_B1   = 'c5000000-0000-0000-0000-000000000003';
    public const WAREHOUSE_A1 = 'c6000000-0000-0000-0000-000000000001';
    public const WAREHOUSE_B1 = 'c6000000-0000-0000-0000-000000000002';
    public const ACCOUNT_A1   = 'c7000000-0000-0000-0000-000000000001';
    public const ACCOUNT_A2   = 'c7000000-0000-0000-0000-000000000002';
    public const ACCOUNT_B1   = 'c7000000-0000-0000-0000-000000000003';
    public const INVOICE_A1   = 'c8000000-0000-0000-0000-000000000001';
    public const ORDER_A1     = 'c9000000-0000-0000-0000-000000000001';

    public const PASSWORD = 'CertTest2026!';

    public function run(): void
    {
        $this->seedWorkspaces();
        $this->seedUsers();
        $this->seedRoles();
        $this->seedMemberships();
        $this->seedMembershipRoles();
        $this->seedBusinessData();

        $this->command->info('Certification seed data created.');
    }

    private function seedWorkspaces(): void
    {
        // WS-A already exists from FoundationSeeder, but insertOrIgnore is safe
        DB::table('workspaces')->insertOrIgnore([
            [
                'id' => self::WS_A,
                'name' => 'Workspace Alpha',
                'industry_type' => 'technology',
                'business_size' => 'small',
                'subscription_status' => 'active',
                'default_locale' => 'en',
                'default_currency' => 'USD',
                'timezone' => 'UTC',
                'is_active' => true,
                'created_at' => now(),
                'updated_at' => now(),
            ],
            [
                'id' => self::WS_B,
                'name' => 'Workspace Bravo',
                'industry_type' => 'retail',
                'business_size' => 'medium',
                'subscription_status' => 'active',
                'default_locale' => 'en',
                'default_currency' => 'USD',
                'timezone' => 'UTC',
                'is_active' => true,
                'created_at' => now(),
                'updated_at' => now(),
            ],
        ]);
    }

    private function seedUsers(): void
    {
        $pw = Hash::make(self::PASSWORD);
        $users = [
            ['id' => self::USER_OWNER,     'full_name' => 'Owner User',     'email' => 'owner@cert.test'],
            ['id' => self::USER_MANAGER,   'full_name' => 'Manager User',   'email' => 'manager@cert.test'],
            ['id' => self::USER_READONLY,  'full_name' => 'Readonly User',  'email' => 'readonly@cert.test'],
            ['id' => self::USER_FINANCE,   'full_name' => 'Finance User',   'email' => 'finance@cert.test'],
            ['id' => self::USER_WAREHOUSE, 'full_name' => 'Warehouse User', 'email' => 'warehouse@cert.test'],
            ['id' => self::USER_SALES,     'full_name' => 'Sales User',     'email' => 'sales@cert.test'],
            ['id' => self::USER_NOPERM,    'full_name' => 'NoPerm User',    'email' => 'noperm@cert.test'],
            ['id' => self::USER_B_ADMIN,   'full_name' => 'WS-B Admin',     'email' => 'b_admin@cert.test'],
            ['id' => self::USER_CROSS,     'full_name' => 'Cross User',     'email' => 'cross@cert.test'],
        ];

        foreach ($users as $u) {
            DB::table('users')->insertOrIgnore(array_merge($u, [
                'phone_number'  => '+1' . substr(md5($u['id']), 0, 10),
                'password_hash' => $pw,
                'is_active'     => true,
                'created_at'    => now(),
                'updated_at'    => now(),
            ]));
        }
    }

    private function seedRoles(): void
    {
        // Derived from the canonical PermissionCatalog — prevents test-vs-production drift.
        $allPerms = PermissionCatalog::allKeys();

        $readOnly = array_filter($allPerms, fn ($p) =>
            str_ends_with($p, '.list') || str_ends_with($p, '.show') || $p === 'reports.view'
        );

        $financePerms = [
            'invoices.list','invoices.show','invoices.create','invoices.update',
            'payments.list','payments.show','payments.create',
            'accounts.list','accounts.show','accounts.create','accounts.update','accounts.delete',
            'journal_entries.list','journal_entries.show','journal_entries.create','journal_entries.update',
            'recurring.list','recurring.show','recurring.create','recurring.update','recurring.delete',
            'reports.view',
            'notifications.list','notifications.update',
        ];

        $warehousePerms = [
            'warehouses.list','warehouses.show','warehouses.create','warehouses.update','warehouses.delete',
            'inventory.list','inventory.show','inventory.create',
            'reservations.list','reservations.show','reservations.create','reservations.update',
            'products.list','products.show',
            'notifications.list','notifications.update',
        ];

        $salesPerms = [
            'contacts.list','contacts.show','contacts.create','contacts.update','contacts.delete',
            'products.list','products.show',
            'invoices.list','invoices.show','invoices.create','invoices.update',
            'orders.list','orders.show','orders.create','orders.update',
            'payments.list','payments.show',
            'notifications.list','notifications.update',
            'pipelines.list',
        ];

        $managerPerms = array_values(array_diff($allPerms, [
            'accounts.delete', 'warehouses.delete', 'bom.delete',
            'categories.delete', 'products.delete', 'recurring.delete',
        ]));

        $roles = [
            // Owner (WS-A) — same as admin
            [
                'id' => self::ROLE_OWNER,
                'workspace_id' => self::WS_A,
                'name' => 'Owner',
                'role_key' => 'owner',
                'permissions' => $allPerms,
                'description' => 'Workspace owner with full access',
                'hierarchy_level' => 0,
            ],
            // Manager (WS-A) — all except deletes on critical entities
            [
                'id' => self::ROLE_MANAGER,
                'workspace_id' => self::WS_A,
                'name' => 'Manager',
                'role_key' => 'manager',
                'permissions' => $managerPerms,
                'description' => 'Manager: full access except critical deletes',
                'hierarchy_level' => 2,
            ],
            // Readonly (WS-A) — *.list + *.show + reports.view only
            [
                'id' => self::ROLE_READONLY,
                'workspace_id' => self::WS_A,
                'name' => 'Read Only',
                'role_key' => 'readonly',
                'permissions' => array_values($readOnly),
                'description' => 'View-only access',
                'hierarchy_level' => 5,
            ],
            // Finance (WS-A)
            [
                'id' => self::ROLE_FINANCE,
                'workspace_id' => self::WS_A,
                'name' => 'Finance',
                'role_key' => 'finance',
                'permissions' => $financePerms,
                'description' => 'Accounting and financial operations',
                'hierarchy_level' => 3,
            ],
            // Warehouse (WS-A)
            [
                'id' => self::ROLE_WAREHOUSE,
                'workspace_id' => self::WS_A,
                'name' => 'Warehouse',
                'role_key' => 'warehouse',
                'permissions' => $warehousePerms,
                'description' => 'Inventory and warehouse operations',
                'hierarchy_level' => 3,
            ],
            // Sales (WS-A)
            [
                'id' => self::ROLE_SALES,
                'workspace_id' => self::WS_A,
                'name' => 'Sales',
                'role_key' => 'sales',
                'permissions' => $salesPerms,
                'description' => 'Sales and CRM operations',
                'hierarchy_level' => 3,
            ],
            // NoPerm (WS-A) — zero permissions for 403 baseline
            [
                'id' => self::ROLE_NOPERM,
                'workspace_id' => self::WS_A,
                'name' => 'No Permissions',
                'role_key' => 'noperm',
                'permissions' => [],
                'description' => 'Zero permissions test role',
                'hierarchy_level' => 99,
            ],
            // WS-B Admin
            [
                'id' => self::ROLE_B_ADMIN,
                'workspace_id' => self::WS_B,
                'name' => 'Admin',
                'role_key' => 'admin',
                'permissions' => $allPerms,
                'description' => 'Full admin for Workspace B',
                'hierarchy_level' => 1,
            ],
        ];

        foreach ($roles as $r) {
            $r['permissions'] = json_encode($r['permissions']);
            $r['is_system']    = true;
            $r['is_default']   = false;
            $r['is_deletable'] = false;
            $r['created_at']   = now();
            $r['updated_at']   = now();
            DB::table('roles')->upsert($r, ['id'], ['permissions', 'updated_at']);
        }
    }

    private function seedMemberships(): void
    {
        $base = ['status' => 'active', 'hire_date' => '2026-01-01', 'base_salary' => 0, 'annual_leave_balance' => 21, 'assigned_warehouses' => '[]', 'joined_at' => now(), 'created_at' => now(), 'updated_at' => now()];

        $memberships = [
            // WS-A members
            ['id' => self::MEMB_A_OWNER,     'workspace_id' => self::WS_A, 'user_id' => self::USER_OWNER],
            ['id' => self::MEMB_A_MANAGER,   'workspace_id' => self::WS_A, 'user_id' => self::USER_MANAGER],
            ['id' => self::MEMB_A_READONLY,  'workspace_id' => self::WS_A, 'user_id' => self::USER_READONLY],
            ['id' => self::MEMB_A_FINANCE,   'workspace_id' => self::WS_A, 'user_id' => self::USER_FINANCE],
            ['id' => self::MEMB_A_WAREHOUSE, 'workspace_id' => self::WS_A, 'user_id' => self::USER_WAREHOUSE],
            ['id' => self::MEMB_A_SALES,     'workspace_id' => self::WS_A, 'user_id' => self::USER_SALES],
            ['id' => self::MEMB_A_NOPERM,    'workspace_id' => self::WS_A, 'user_id' => self::USER_NOPERM],
            ['id' => self::MEMB_A_CROSS,     'workspace_id' => self::WS_A, 'user_id' => self::USER_CROSS],
            // WS-B members
            ['id' => self::MEMB_B_ADMIN,     'workspace_id' => self::WS_B, 'user_id' => self::USER_B_ADMIN],
            ['id' => self::MEMB_B_CROSS,     'workspace_id' => self::WS_B, 'user_id' => self::USER_CROSS],
        ];

        foreach ($memberships as $m) {
            DB::table('workspace_memberships')->insertOrIgnore(array_merge($m, $base));
        }
    }

    private function seedMembershipRoles(): void
    {
        $mrs = [
            // WS-A
            ['id' => 'c2100000-0000-0000-0000-000000000001', 'workspace_id' => self::WS_A, 'membership_id' => self::MEMB_A_OWNER,     'role_id' => self::ROLE_OWNER],
            ['id' => 'c2100000-0000-0000-0000-000000000002', 'workspace_id' => self::WS_A, 'membership_id' => self::MEMB_A_MANAGER,   'role_id' => self::ROLE_MANAGER],
            ['id' => 'c2100000-0000-0000-0000-000000000003', 'workspace_id' => self::WS_A, 'membership_id' => self::MEMB_A_READONLY,  'role_id' => self::ROLE_READONLY],
            ['id' => 'c2100000-0000-0000-0000-000000000004', 'workspace_id' => self::WS_A, 'membership_id' => self::MEMB_A_FINANCE,   'role_id' => self::ROLE_FINANCE],
            ['id' => 'c2100000-0000-0000-0000-000000000005', 'workspace_id' => self::WS_A, 'membership_id' => self::MEMB_A_WAREHOUSE, 'role_id' => self::ROLE_WAREHOUSE],
            ['id' => 'c2100000-0000-0000-0000-000000000006', 'workspace_id' => self::WS_A, 'membership_id' => self::MEMB_A_SALES,     'role_id' => self::ROLE_SALES],
            ['id' => 'c2100000-0000-0000-0000-000000000007', 'workspace_id' => self::WS_A, 'membership_id' => self::MEMB_A_NOPERM,    'role_id' => self::ROLE_NOPERM],
            ['id' => 'c2100000-0000-0000-0000-000000000009', 'workspace_id' => self::WS_A, 'membership_id' => self::MEMB_A_CROSS,     'role_id' => self::ROLE_READONLY],
            // WS-B
            ['id' => 'c2100000-0000-0000-0000-000000000008', 'workspace_id' => self::WS_B, 'membership_id' => self::MEMB_B_ADMIN,     'role_id' => self::ROLE_B_ADMIN],
            ['id' => 'c2100000-0000-0000-0000-000000000010', 'workspace_id' => self::WS_B, 'membership_id' => self::MEMB_B_CROSS,     'role_id' => self::ROLE_B_ADMIN],
        ];

        foreach ($mrs as $mr) {
            DB::table('membership_roles')->insertOrIgnore(array_merge($mr, [
                'is_primary'  => true,
                'assigned_at' => now(),
            ]));
        }
    }

    private function seedBusinessData(): void
    {
        $now = now();

        // ── Contacts ──
        DB::table('contacts')->insertOrIgnore([
            ['id' => self::CONTACT_A1, 'workspace_id' => self::WS_A, 'name' => 'Cert Customer Alpha', 'type' => 'customer', 'email' => 'alpha@cert.test', 'created_at' => $now, 'updated_at' => $now],
            ['id' => self::CONTACT_A2, 'workspace_id' => self::WS_A, 'name' => 'Cert Supplier Alpha', 'type' => 'supplier', 'email' => 'supplier@cert.test', 'created_at' => $now, 'updated_at' => $now],
            ['id' => self::CONTACT_B1, 'workspace_id' => self::WS_B, 'name' => 'Cert Customer Bravo', 'type' => 'customer', 'email' => 'bravo@cert.test', 'created_at' => $now, 'updated_at' => $now],
        ]);

        // ── Product Categories ──
        DB::table('product_categories')->insertOrIgnore([
            ['id' => self::CATEGORY_A1, 'workspace_id' => self::WS_A, 'name' => 'Electronics', 'created_at' => $now, 'updated_at' => $now],
            ['id' => self::CATEGORY_A2, 'workspace_id' => self::WS_A, 'name' => 'Raw Materials', 'created_at' => $now, 'updated_at' => $now],
        ]);

        // ── Products ──
        DB::table('products')->insertOrIgnore([
            ['id' => self::PRODUCT_A1, 'workspace_id' => self::WS_A, 'name' => 'Cert Widget',       'sku' => 'CERT-W001', 'base_price' => 99.99, 'cost_price' => 50.00, 'category_id' => self::CATEGORY_A1, 'min_stock_alert' => 5, 'created_at' => $now, 'updated_at' => $now],
            ['id' => self::PRODUCT_A2, 'workspace_id' => self::WS_A, 'name' => 'Cert Raw Material', 'sku' => 'CERT-R001', 'base_price' => 10.00, 'cost_price' => 5.00, 'category_id' => self::CATEGORY_A2, 'min_stock_alert' => 20, 'created_at' => $now, 'updated_at' => $now],
            ['id' => self::PRODUCT_B1, 'workspace_id' => self::WS_B, 'name' => 'Bravo Widget',      'sku' => 'BRAVO-001', 'base_price' => 50.00, 'cost_price' => 25.00, 'category_id' => null, 'min_stock_alert' => 5, 'created_at' => $now, 'updated_at' => $now],
        ]);

        // ── Warehouses ──
        DB::table('warehouses')->insertOrIgnore([
            ['id' => self::WAREHOUSE_A1, 'workspace_id' => self::WS_A, 'name' => 'Cert Main Warehouse'],
            ['id' => self::WAREHOUSE_B1, 'workspace_id' => self::WS_B, 'name' => 'Bravo Warehouse'],
        ]);

        // ── Accounts (Chart of Accounts — no updated_at column) ──
        DB::table('accounts')->insertOrIgnore([
            ['id' => self::ACCOUNT_A1, 'workspace_id' => self::WS_A, 'code' => 'CERT-1000', 'name' => 'Cash',          'type' => 'asset',   'balance' => 50000, 'created_at' => $now],
            ['id' => self::ACCOUNT_A2, 'workspace_id' => self::WS_A, 'code' => 'CERT-4000', 'name' => 'Sales Revenue', 'type' => 'revenue', 'balance' => 0, 'created_at' => $now],
            ['id' => self::ACCOUNT_B1, 'workspace_id' => self::WS_B, 'code' => 'BRAVO-1000','name' => 'Cash B',        'type' => 'asset',   'balance' => 10000, 'created_at' => $now],
        ]);

        // ── Notifications (for WS-A user_admin and readonly) ──
        DB::table('notifications')->insertOrIgnore([
            ['id' => 'c3100000-0000-0000-0000-000000000001', 'workspace_id' => self::WS_A, 'user_id' => self::USER_ADMIN,    'title' => 'Welcome', 'message' => 'Welcome to SmartBiz', 'type' => 'info', 'is_read' => false, 'created_at' => $now],
            ['id' => 'c3100000-0000-0000-0000-000000000002', 'workspace_id' => self::WS_A, 'user_id' => self::USER_READONLY, 'title' => 'Info',    'message' => 'You have read-only access', 'type' => 'warning', 'is_read' => false, 'created_at' => $now],
            ['id' => 'c3100000-0000-0000-0000-000000000003', 'workspace_id' => self::WS_B, 'user_id' => self::USER_B_ADMIN,  'title' => 'Hello',   'message' => 'WS-B notification', 'type' => 'success', 'is_read' => false, 'created_at' => $now],
        ]);

        // ── Audit Logs ──
        DB::table('audit_logs')->insertOrIgnore([
            ['id' => 'c3200000-0000-0000-0000-000000000001', 'workspace_id' => self::WS_A, 'user_id' => self::USER_ADMIN, 'action' => 'create', 'entity_type' => 'contacts', 'entity_id' => self::CONTACT_A1, 'new_values' => json_encode(['name' => 'Cert Customer Alpha']), 'created_at' => $now],
            ['id' => 'c3200000-0000-0000-0000-000000000002', 'workspace_id' => self::WS_B, 'user_id' => self::USER_B_ADMIN, 'action' => 'create', 'entity_type' => 'contacts', 'entity_id' => self::CONTACT_B1, 'new_values' => json_encode(['name' => 'Cert Customer Bravo']), 'created_at' => $now],
        ]);

        // ── Recurring Expenses ──
        DB::table('recurring_expenses')->insertOrIgnore([
            ['id' => 'c3300000-0000-0000-0000-000000000001', 'workspace_id' => self::WS_A, 'category' => 'Office Rent', 'amount' => 3000, 'frequency' => 'monthly', 'next_due_date' => '2026-05-01', 'is_active' => true, 'created_at' => $now, 'updated_at' => $now],
        ]);

        // ── BOM ──
        DB::table('bill_of_materials')->insertOrIgnore([
            ['id' => 'c3400000-0000-0000-0000-000000000001', 'workspace_id' => self::WS_A, 'final_product_id' => self::PRODUCT_A1, 'raw_material_id' => self::PRODUCT_A2, 'quantity_required' => 5.0],
        ]);

        $this->command->info('Seeded: 2 workspaces, 10 users, 8 roles, 10 memberships, 10 MRs');
        $this->command->info('Seeded: 3 contacts, 2 categories, 3 products, 2 warehouses, 3 accounts');
        $this->command->info('Seeded: 3 notifications, 2 audit logs, 1 recurring expense, 1 BOM');
    }
}
