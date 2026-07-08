<?php

namespace Database\Seeders;

use App\Models\BusinessTemplate;
use App\Models\BusinessTemplateCustomField;
use App\Models\BusinessTemplateModule;
use App\Models\BusinessTemplateRole;
use App\Models\BusinessTemplateWorkflow;
use Illuminate\Database\Seeder;

/**
 * Seeds idempotent business templates for SmartBiz AI.
 *
 * Uses updateOrCreate throughout so it is safe to re-run.
 */
class BusinessTemplateSeeder extends Seeder
{
    // ── Common permission sets ─────────────────────────────

    private const OWNER_PERMS = [
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
        'discovery.manage',
    ];

    private const MANAGER_PERMS = [
        'contacts.list', 'contacts.show', 'contacts.create', 'contacts.update',
        'categories.list', 'categories.show',
        'products.list', 'products.show', 'products.create', 'products.update',
        'invoices.list', 'invoices.show', 'invoices.create', 'invoices.update',
        'orders.list', 'orders.show', 'orders.create', 'orders.update',
        'payments.list', 'payments.show', 'payments.create',
        'inventory.list', 'inventory.show', 'inventory.create',
        'warehouses.list', 'warehouses.show',
        'notifications.list', 'notifications.update',
        'reports.view',
    ];

    private const SALES_PERMS = [
        'contacts.list', 'contacts.show', 'contacts.create', 'contacts.update',
        'products.list', 'products.show',
        'invoices.list', 'invoices.show', 'invoices.create',
        'orders.list', 'orders.show', 'orders.create',
        'payments.list', 'payments.show',
        'inventory.list', 'inventory.show',
        'notifications.list', 'notifications.update',
    ];

    private const FINANCE_PERMS = [
        'invoices.list', 'invoices.show', 'invoices.create', 'invoices.update',
        'payments.list', 'payments.show', 'payments.create',
        'accounts.list', 'accounts.show', 'accounts.create', 'accounts.update',
        'journal_entries.list', 'journal_entries.show', 'journal_entries.create',
        'recurring.list', 'recurring.show', 'recurring.create', 'recurring.update',
        'reports.view',
        'notifications.list', 'notifications.update',
    ];

    private const VIEWER_PERMS = [
        'contacts.list', 'contacts.show',
        'products.list', 'products.show',
        'invoices.list', 'invoices.show',
        'orders.list', 'orders.show',
        'payments.list', 'payments.show',
        'inventory.list', 'inventory.show',
        'reports.view',
        'notifications.list',
    ];

    public function run(): void
    {
        $this->seedAutomotiveDealer();
        $this->seedRetailPos();
        $this->seedWorkshopService();
        $this->seedRestaurantFnb();
        $this->seedProfessionalServices();
    }

    // ═══════════════════════════════════════════════════════
    //  1. Automotive Dealer
    // ═══════════════════════════════════════════════════════

    private function seedAutomotiveDealer(): void
    {
        $t = BusinessTemplate::updateOrCreate(
            ['template_key' => 'automotive_dealer'],
            [
                'name'          => 'Automotive Dealer',
                'description'   => 'For companies that sell vehicles and spare parts.',
                'industry_type' => 'automotive',
                'business_size' => null,
                'version'       => 1,
                'is_active'     => true,
                'is_default'    => false,
                'sort_order'    => 1,
            ]
        );

        // ── Modules ──
        $modules = [
            ['module_key' => 'dashboard',    'name' => 'Dashboard',        'is_required' => true],
            ['module_key' => 'customers',    'name' => 'Customers'],
            ['module_key' => 'leads',        'name' => 'Leads & CRM'],
            ['module_key' => 'vehicle_sales','name' => 'Vehicle Sales'],
            ['module_key' => 'spare_parts',  'name' => 'Spare Parts'],
            ['module_key' => 'inventory',    'name' => 'Inventory'],
            ['module_key' => 'invoices',     'name' => 'Invoices'],
            ['module_key' => 'payments',     'name' => 'Payments'],
            ['module_key' => 'employees',    'name' => 'Employees & HR'],
            ['module_key' => 'reports',      'name' => 'Reports & Analytics'],
            ['module_key' => 'finance',      'name' => 'Finance & Accounting'],
            ['module_key' => 'ai',           'name' => 'AI Assistant'],
        ];
        $this->seedModules($t, $modules);

        // ── Roles ──
        $roles = [
            ['role_key' => 'owner',                  'name' => 'Owner',                     'hierarchy_level' => 0,  'permissions' => self::OWNER_PERMS, 'is_primary_owner_role' => true],
            ['role_key' => 'general_manager',         'name' => 'General Manager',           'hierarchy_level' => 1,  'permissions' => self::OWNER_PERMS],
            ['role_key' => 'sales_manager',           'name' => 'Sales Manager',             'hierarchy_level' => 2,  'permissions' => self::MANAGER_PERMS],
            ['role_key' => 'vehicle_sales_agent',     'name' => 'Vehicle Sales Agent',       'hierarchy_level' => 3,  'permissions' => self::SALES_PERMS],
            ['role_key' => 'spare_parts_sales_agent', 'name' => 'Spare Parts Sales Agent',   'hierarchy_level' => 3,  'permissions' => self::SALES_PERMS],
            ['role_key' => 'inventory_manager',       'name' => 'Inventory Manager',         'hierarchy_level' => 3,  'permissions' => array_merge(self::VIEWER_PERMS, ['inventory.create', 'warehouses.list', 'warehouses.show', 'warehouses.create', 'warehouses.update'])],
            ['role_key' => 'accountant',              'name' => 'Accountant',                'hierarchy_level' => 3,  'permissions' => self::FINANCE_PERMS],
            ['role_key' => 'hr_manager',              'name' => 'HR Manager',                'hierarchy_level' => 3,  'permissions' => self::VIEWER_PERMS],
            ['role_key' => 'viewer',                  'name' => 'Viewer',                    'hierarchy_level' => 99, 'permissions' => self::VIEWER_PERMS],
        ];
        $this->seedRoles($t, $roles);

        // ── Workflows ──
        $workflows = [
            // Vehicle sales pipeline
            ['workflow_type' => 'sales_pipeline', 'workflow_key' => 'vehicle_sales_pipeline', 'name' => 'Vehicle Sales Pipeline',
             'config' => ['stages' => ['new_lead', 'contacted', 'qualified', 'documents_pending', 'payment_pending', 'delivery_ready', 'closed_won', 'closed_lost']]],
            // Spare parts sales flow
            ['workflow_type' => 'sales_pipeline', 'workflow_key' => 'spare_parts_sales_flow', 'name' => 'Spare Parts Sales Flow',
             'config' => ['stages' => ['inquiry', 'quotation', 'reserved', 'invoiced', 'paid', 'delivered']]],
            // Document checklist
            ['workflow_type' => 'document_checklist', 'workflow_key' => 'vehicle_sale_docs', 'name' => 'Vehicle Sale Document Checklist',
             'config' => ['items' => ['customer_id', 'driver_license', 'payment_proof', 'sales_contract', 'delivery_confirmation']]],
            // Ownership rule
            ['workflow_type' => 'ownership_rule', 'workflow_key' => 'customer_ownership', 'name' => 'Customer Ownership Rules',
             'config' => ['scope' => 'workspace', 'duplicate_warning_fields' => ['phone_number', 'email'], 'lead_owner_lock' => true]],
            // Commission rule
            ['workflow_type' => 'commission_rule', 'workflow_key' => 'sales_commission', 'name' => 'Sales Commission Configuration',
             'config' => ['type' => 'percentage', 'configurable_by' => ['department', 'role'], 'default_rate' => 2.0]],
            // Report templates
            ['workflow_type' => 'report_template', 'workflow_key' => 'daily_sales',   'name' => 'Daily Sales Report',
             'config' => ['frequency' => 'daily', 'metrics' => ['total_sales', 'deals_closed', 'new_leads']]],
            ['workflow_type' => 'report_template', 'workflow_key' => 'weekly_manager', 'name' => 'Weekly Manager Report',
             'config' => ['frequency' => 'weekly', 'metrics' => ['revenue', 'pipeline_value', 'conversion_rate', 'team_performance']]],
            ['workflow_type' => 'report_template', 'workflow_key' => 'monthly_revenue','name' => 'Monthly Revenue Report',
             'config' => ['frequency' => 'monthly', 'metrics' => ['total_revenue', 'cost_of_goods', 'gross_margin', 'expenses', 'net_profit']]],
        ];
        $this->seedWorkflows($t, $workflows);

        // ── Custom Fields ──
        $fields = [
            ['entity_type' => 'customer', 'field_key' => 'national_id',         'label' => 'National ID',            'field_type' => 'text'],
            ['entity_type' => 'customer', 'field_key' => 'customer_type',       'label' => 'Customer Type',          'field_type' => 'select',
             'options' => ['choices' => ['individual', 'company', 'government', 'fleet']]],
            ['entity_type' => 'lead',     'field_key' => 'vehicle_interest',    'label' => 'Vehicle Interest',       'field_type' => 'text'],
            ['entity_type' => 'lead',     'field_key' => 'payment_method',      'label' => 'Preferred Payment Method','field_type' => 'select',
             'options' => ['choices' => ['cash', 'installment', 'bank_transfer', 'check']]],
            ['entity_type' => 'lead',     'field_key' => 'lead_source',         'label' => 'Lead Source',            'field_type' => 'select',
             'options' => ['choices' => ['walk_in', 'phone', 'website', 'social_media', 'referral', 'advertisement']]],
            ['entity_type' => 'product',  'field_key' => 'part_number',         'label' => 'Part Number',            'field_type' => 'text'],
            ['entity_type' => 'product',  'field_key' => 'vehicle_compatibility','label' => 'Vehicle Compatibility', 'field_type' => 'text'],
            ['entity_type' => 'employee', 'field_key' => 'commission_rate',     'label' => 'Commission Rate (%)',    'field_type' => 'number',
             'validation_rules' => ['min' => 0, 'max' => 100]],
        ];
        $this->seedCustomFields($t, $fields);
    }

    // ═══════════════════════════════════════════════════════
    //  2. Retail / POS
    // ═══════════════════════════════════════════════════════

    private function seedRetailPos(): void
    {
        $t = BusinessTemplate::updateOrCreate(
            ['template_key' => 'retail_pos'],
            [
                'name'          => 'Retail / POS',
                'description'   => 'For shops, stores, and retail businesses with point-of-sale.',
                'industry_type' => 'retail',
                'version'       => 1,
                'is_active'     => true,
                'is_default'    => true,
                'sort_order'    => 2,
            ]
        );

        $this->seedModules($t, [
            ['module_key' => 'dashboard', 'name' => 'Dashboard',             'is_required' => true],
            ['module_key' => 'products',  'name' => 'Products & Categories'],
            ['module_key' => 'customers', 'name' => 'Customers'],
            ['module_key' => 'pos',       'name' => 'Point of Sale'],
            ['module_key' => 'inventory', 'name' => 'Inventory'],
            ['module_key' => 'invoices',  'name' => 'Invoices'],
            ['module_key' => 'payments',  'name' => 'Payments'],
            ['module_key' => 'employees', 'name' => 'Employees & HR'],
            ['module_key' => 'reports',   'name' => 'Reports & Analytics'],
            ['module_key' => 'finance',   'name' => 'Finance & Accounting'],
            ['module_key' => 'ai',        'name' => 'AI Assistant'],
        ]);

        $this->seedRoles($t, [
            ['role_key' => 'owner',     'name' => 'Owner',      'hierarchy_level' => 0,  'permissions' => self::OWNER_PERMS, 'is_primary_owner_role' => true],
            ['role_key' => 'manager',   'name' => 'Manager',    'hierarchy_level' => 1,  'permissions' => self::MANAGER_PERMS],
            ['role_key' => 'cashier',   'name' => 'Cashier',    'hierarchy_level' => 3,  'permissions' => self::SALES_PERMS],
            ['role_key' => 'inventory', 'name' => 'Stock Clerk','hierarchy_level' => 3,  'permissions' => array_merge(self::VIEWER_PERMS, ['inventory.create'])],
            ['role_key' => 'accountant','name' => 'Accountant', 'hierarchy_level' => 3,  'permissions' => self::FINANCE_PERMS],
            ['role_key' => 'viewer',    'name' => 'Viewer',     'hierarchy_level' => 99, 'permissions' => self::VIEWER_PERMS],
        ]);

        $this->seedWorkflows($t, [
            ['workflow_type' => 'sales_pipeline', 'workflow_key' => 'retail_sales', 'name' => 'Retail Sales Flow',
             'config' => ['stages' => ['browsing', 'cart', 'checkout', 'paid', 'fulfilled']]],
        ]);
    }

    // ═══════════════════════════════════════════════════════
    //  3. Workshop / Service
    // ═══════════════════════════════════════════════════════

    private function seedWorkshopService(): void
    {
        $t = BusinessTemplate::updateOrCreate(
            ['template_key' => 'workshop_service'],
            [
                'name'          => 'Workshop / Service Center',
                'description'   => 'For vehicle/equipment service workshops and repair businesses.',
                'industry_type' => 'workshop',
                'version'       => 1,
                'is_active'     => true,
                'sort_order'    => 3,
            ]
        );

        $this->seedModules($t, [
            ['module_key' => 'dashboard',       'name' => 'Dashboard',         'is_required' => true],
            ['module_key' => 'customers',       'name' => 'Customers'],
            ['module_key' => 'jobs',            'name' => 'Job Orders'],
            ['module_key' => 'vehicles',        'name' => 'Vehicle Registry'],
            ['module_key' => 'parts_inventory', 'name' => 'Parts Inventory'],
            ['module_key' => 'invoices',        'name' => 'Invoices'],
            ['module_key' => 'payments',        'name' => 'Payments'],
            ['module_key' => 'employees',       'name' => 'Employees & HR'],
            ['module_key' => 'reports',         'name' => 'Reports & Analytics'],
            ['module_key' => 'finance',         'name' => 'Finance & Accounting'],
            ['module_key' => 'ai',              'name' => 'AI Assistant'],
        ]);

        $this->seedRoles($t, [
            ['role_key' => 'owner',      'name' => 'Owner',        'hierarchy_level' => 0,  'permissions' => self::OWNER_PERMS, 'is_primary_owner_role' => true],
            ['role_key' => 'manager',    'name' => 'Shop Manager', 'hierarchy_level' => 1,  'permissions' => self::MANAGER_PERMS],
            ['role_key' => 'technician', 'name' => 'Technician',   'hierarchy_level' => 3,  'permissions' => self::SALES_PERMS],
            ['role_key' => 'receptionist','name' => 'Receptionist','hierarchy_level' => 4,  'permissions' => self::SALES_PERMS],
            ['role_key' => 'accountant', 'name' => 'Accountant',   'hierarchy_level' => 3,  'permissions' => self::FINANCE_PERMS],
            ['role_key' => 'viewer',     'name' => 'Viewer',       'hierarchy_level' => 99, 'permissions' => self::VIEWER_PERMS],
        ]);

        $this->seedWorkflows($t, [
            ['workflow_type' => 'sales_pipeline', 'workflow_key' => 'job_order_flow', 'name' => 'Job Order Flow',
             'config' => ['stages' => ['reception', 'diagnosis', 'quotation_sent', 'approved', 'in_progress', 'quality_check', 'ready', 'delivered', 'closed']]],
        ]);

        $this->seedCustomFields($t, [
            ['entity_type' => 'customer', 'field_key' => 'vehicle_make',  'label' => 'Primary Vehicle Make',  'field_type' => 'text'],
            ['entity_type' => 'customer', 'field_key' => 'vehicle_model', 'label' => 'Primary Vehicle Model', 'field_type' => 'text'],
        ]);
    }

    // ═══════════════════════════════════════════════════════
    //  4. Restaurant / F&B
    // ═══════════════════════════════════════════════════════

    private function seedRestaurantFnb(): void
    {
        $t = BusinessTemplate::updateOrCreate(
            ['template_key' => 'restaurant_fnb'],
            [
                'name'          => 'Restaurant / F&B',
                'description'   => 'For restaurants, cafés, and food & beverage businesses.',
                'industry_type' => 'restaurant',
                'version'       => 1,
                'is_active'     => true,
                'sort_order'    => 4,
            ]
        );

        $this->seedModules($t, [
            ['module_key' => 'dashboard', 'name' => 'Dashboard',             'is_required' => true],
            ['module_key' => 'menu',      'name' => 'Menu Management'],
            ['module_key' => 'orders',    'name' => 'Orders'],
            ['module_key' => 'tables',    'name' => 'Table Management'],
            ['module_key' => 'inventory', 'name' => 'Inventory & Supplies'],
            ['module_key' => 'invoices',  'name' => 'Invoices'],
            ['module_key' => 'payments',  'name' => 'Payments'],
            ['module_key' => 'employees', 'name' => 'Employees & HR'],
            ['module_key' => 'reports',   'name' => 'Reports & Analytics'],
            ['module_key' => 'finance',   'name' => 'Finance & Accounting'],
            ['module_key' => 'ai',        'name' => 'AI Assistant'],
        ]);

        $this->seedRoles($t, [
            ['role_key' => 'owner',     'name' => 'Owner',        'hierarchy_level' => 0,  'permissions' => self::OWNER_PERMS, 'is_primary_owner_role' => true],
            ['role_key' => 'manager',   'name' => 'Manager',      'hierarchy_level' => 1,  'permissions' => self::MANAGER_PERMS],
            ['role_key' => 'cashier',   'name' => 'Cashier',      'hierarchy_level' => 3,  'permissions' => self::SALES_PERMS],
            ['role_key' => 'waiter',    'name' => 'Waiter/Server','hierarchy_level' => 4,  'permissions' => ['orders.list', 'orders.show', 'orders.create', 'notifications.list']],
            ['role_key' => 'chef',      'name' => 'Chef/Kitchen', 'hierarchy_level' => 4,  'permissions' => ['orders.list', 'orders.show', 'inventory.list', 'inventory.show', 'notifications.list']],
            ['role_key' => 'viewer',    'name' => 'Viewer',       'hierarchy_level' => 99, 'permissions' => self::VIEWER_PERMS],
        ]);

        $this->seedWorkflows($t, [
            ['workflow_type' => 'sales_pipeline', 'workflow_key' => 'order_flow', 'name' => 'Order Flow',
             'config' => ['stages' => ['placed', 'preparing', 'ready', 'served', 'paid', 'closed']]],
        ]);
    }

    // ═══════════════════════════════════════════════════════
    //  5. Professional Services
    // ═══════════════════════════════════════════════════════

    private function seedProfessionalServices(): void
    {
        $t = BusinessTemplate::updateOrCreate(
            ['template_key' => 'professional_services'],
            [
                'name'          => 'Professional Services',
                'description'   => 'For agencies, consultants, and service companies.',
                'industry_type' => 'services',
                'version'       => 1,
                'is_active'     => true,
                'sort_order'    => 5,
            ]
        );

        $this->seedModules($t, [
            ['module_key' => 'dashboard', 'name' => 'Dashboard',             'is_required' => true],
            ['module_key' => 'customers', 'name' => 'Clients'],
            ['module_key' => 'projects',  'name' => 'Projects'],
            ['module_key' => 'tasks',     'name' => 'Tasks & Tracking'],
            ['module_key' => 'invoices',  'name' => 'Invoices'],
            ['module_key' => 'payments',  'name' => 'Payments'],
            ['module_key' => 'employees', 'name' => 'Employees & HR'],
            ['module_key' => 'reports',   'name' => 'Reports & Analytics'],
            ['module_key' => 'finance',   'name' => 'Finance & Accounting'],
            ['module_key' => 'ai',        'name' => 'AI Assistant'],
        ]);

        $this->seedRoles($t, [
            ['role_key' => 'owner',     'name' => 'Owner',          'hierarchy_level' => 0,  'permissions' => self::OWNER_PERMS, 'is_primary_owner_role' => true],
            ['role_key' => 'manager',   'name' => 'Project Manager','hierarchy_level' => 1,  'permissions' => self::MANAGER_PERMS],
            ['role_key' => 'consultant','name' => 'Consultant',     'hierarchy_level' => 3,  'permissions' => self::SALES_PERMS],
            ['role_key' => 'accountant','name' => 'Accountant',     'hierarchy_level' => 3,  'permissions' => self::FINANCE_PERMS],
            ['role_key' => 'viewer',    'name' => 'Viewer',         'hierarchy_level' => 99, 'permissions' => self::VIEWER_PERMS],
        ]);

        $this->seedWorkflows($t, [
            ['workflow_type' => 'sales_pipeline', 'workflow_key' => 'project_flow', 'name' => 'Project Pipeline',
             'config' => ['stages' => ['proposal', 'negotiation', 'contracted', 'in_progress', 'review', 'completed', 'closed']]],
        ]);
    }

    // ═══════════════════════════════════════════════════════
    //  Seed Helpers (idempotent)
    // ═══════════════════════════════════════════════════════

    private function seedModules(BusinessTemplate $t, array $modules): void
    {
        foreach ($modules as $i => $m) {
            BusinessTemplateModule::updateOrCreate(
                ['business_template_id' => $t->id, 'module_key' => $m['module_key']],
                [
                    'name'        => $m['name'],
                    'description' => $m['description'] ?? null,
                    'is_enabled'  => $m['is_enabled'] ?? true,
                    'is_required' => $m['is_required'] ?? false,
                    'settings'    => $m['settings'] ?? null,
                    'sort_order'  => $i,
                ]
            );
        }
    }

    private function seedRoles(BusinessTemplate $t, array $roles): void
    {
        foreach ($roles as $i => $r) {
            BusinessTemplateRole::updateOrCreate(
                ['business_template_id' => $t->id, 'role_key' => $r['role_key']],
                [
                    'name'                  => $r['name'],
                    'description'           => $r['description'] ?? null,
                    'hierarchy_level'       => $r['hierarchy_level'] ?? 100,
                    'permissions'           => $r['permissions'] ?? [],
                    'is_primary_owner_role' => $r['is_primary_owner_role'] ?? false,
                    'sort_order'            => $i,
                ]
            );
        }
    }

    private function seedWorkflows(BusinessTemplate $t, array $workflows): void
    {
        foreach ($workflows as $i => $w) {
            BusinessTemplateWorkflow::updateOrCreate(
                ['business_template_id' => $t->id, 'workflow_type' => $w['workflow_type'], 'workflow_key' => $w['workflow_key']],
                [
                    'name'        => $w['name'],
                    'description' => $w['description'] ?? null,
                    'config'      => $w['config'] ?? null,
                    'is_active'   => $w['is_active'] ?? true,
                    'sort_order'  => $i,
                ]
            );
        }
    }

    private function seedCustomFields(BusinessTemplate $t, array $fields): void
    {
        foreach ($fields as $i => $f) {
            BusinessTemplateCustomField::updateOrCreate(
                ['business_template_id' => $t->id, 'entity_type' => $f['entity_type'], 'field_key' => $f['field_key']],
                [
                    'label'            => $f['label'],
                    'field_type'       => $f['field_type'],
                    'is_required'      => $f['is_required'] ?? false,
                    'options'          => $f['options'] ?? null,
                    'validation_rules' => $f['validation_rules'] ?? null,
                    'sort_order'       => $i,
                ]
            );
        }
    }
}
