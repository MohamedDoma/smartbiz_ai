<?php

namespace App\Services;

/**
 * PermissionCatalog — stable list of permission keys grouped by module/category.
 *
 * Based on existing permission keys used in template-seeded roles.
 * Serves as source of truth for the frontend permission editor.
 */
class PermissionCatalog
{
    /**
     * Return the full permission catalog grouped by category.
     *
     * @return array<int, array{category: string, label: string, permissions: array}>
     */
    public static function all(): array
    {
        return [
            [
                'category' => 'ai',
                'label'    => 'AI & Advisor',
                'permissions' => [
                    ['key' => 'ai_advisor.view', 'label' => 'Access AI Advisor', 'description' => 'Can access the AI Advisor recommendations screen'],
                ],
            ],
            [
                'category' => 'contacts',
                'label'    => 'Customers & Contacts',
                'permissions' => [
                    ['key' => 'contacts.list',       'label' => 'List contacts',        'description' => 'Can view the contacts list'],
                    ['key' => 'contacts.show',       'label' => 'View contact',         'description' => 'Can view contact details'],
                    ['key' => 'contacts.create',     'label' => 'Create contact',       'description' => 'Can create new contacts'],
                    ['key' => 'contacts.update',     'label' => 'Update contact',       'description' => 'Can edit existing contacts'],
                    ['key' => 'contacts.delete',     'label' => 'Delete contact',       'description' => 'Can delete contacts'],
                    ['key' => 'contacts.own',        'label' => 'Own customers',        'description' => 'Eligible to be assigned as the responsible salesperson on customers'],
                    ['key' => 'contacts.manage_team','label' => 'Manage team customers', 'description' => 'Can view and manage customers assigned to members of the same team'],
                    ['key' => 'contacts.manage_all', 'label' => 'Manage all customers', 'description' => 'Can view and manage all customers in the workspace'],
                    ['key' => 'contacts.assign',     'label' => 'Assign customers',     'description' => 'Can assign or reassign customers to other members'],
                ],
            ],
            [
                'category' => 'products',
                'label'    => 'Products',
                'permissions' => [
                    ['key' => 'products.list',   'label' => 'List products',   'description' => 'Can view the products list'],
                    ['key' => 'products.show',   'label' => 'View product',    'description' => 'Can view product details'],
                    ['key' => 'products.create', 'label' => 'Create product',  'description' => 'Can create new products'],
                    ['key' => 'products.update', 'label' => 'Update product',  'description' => 'Can edit existing products'],
                    ['key' => 'products.delete', 'label' => 'Delete product',  'description' => 'Can delete products'],
                ],
            ],
            [
                'category' => 'categories',
                'label'    => 'Categories',
                'permissions' => [
                    ['key' => 'categories.list',   'label' => 'List categories',   'description' => 'Can view categories'],
                    ['key' => 'categories.show',   'label' => 'View category',     'description' => 'Can view category details'],
                    ['key' => 'categories.create', 'label' => 'Create category',   'description' => 'Can create categories'],
                    ['key' => 'categories.update', 'label' => 'Update category',   'description' => 'Can edit categories'],
                    ['key' => 'categories.delete', 'label' => 'Delete category',   'description' => 'Can delete categories'],
                ],
            ],
            [
                'category' => 'invoices',
                'label'    => 'Invoices',
                'permissions' => [
                    ['key' => 'invoices.list',   'label' => 'List invoices',   'description' => 'Can view the invoices list'],
                    ['key' => 'invoices.show',   'label' => 'View invoice',    'description' => 'Can view invoice details'],
                    ['key' => 'invoices.create', 'label' => 'Create invoice',  'description' => 'Can create new invoices'],
                    ['key' => 'invoices.update', 'label' => 'Update invoice',  'description' => 'Can edit existing invoices'],
                ],
            ],
            [
                'category' => 'payments',
                'label'    => 'Payments',
                'permissions' => [
                    ['key' => 'payments.list',   'label' => 'List payments',   'description' => 'Can view the payments list'],
                    ['key' => 'payments.show',   'label' => 'View payment',    'description' => 'Can view payment details'],
                    ['key' => 'payments.create', 'label' => 'Create payment',  'description' => 'Can record payments'],
                ],
            ],
            [
                'category' => 'orders',
                'label'    => 'POS & Orders',
                'permissions' => [
                    ['key' => 'pos.view',      'label' => 'Access POS',     'description' => 'Can access the point-of-sale screen (does not grant order creation or payment capabilities)'],
                    ['key' => 'orders.list',   'label' => 'List orders',   'description' => 'Can view orders'],
                    ['key' => 'orders.show',   'label' => 'View order',    'description' => 'Can view order details'],
                    ['key' => 'orders.create', 'label' => 'Create order',  'description' => 'Can create orders'],
                    ['key' => 'orders.update', 'label' => 'Update order',  'description' => 'Can edit orders'],
                ],
            ],
            [
                'category' => 'accounting',
                'label'    => 'Accounting & Journal Entries',
                'permissions' => [
                    ['key' => 'accounting.view',        'label' => 'Access accounting', 'description' => 'Can access the accounting module landing page (does not grant posting or editing entries)'],
                    ['key' => 'accounts.list',          'label' => 'List accounts',   'description' => 'Can view chart of accounts'],
                    ['key' => 'accounts.show',          'label' => 'View account',    'description' => 'Can view account details'],
                    ['key' => 'accounts.create',        'label' => 'Create account',  'description' => 'Can create accounts'],
                    ['key' => 'accounts.update',        'label' => 'Update account',  'description' => 'Can edit accounts'],
                    ['key' => 'accounts.delete',        'label' => 'Delete account',  'description' => 'Can delete accounts'],
                    ['key' => 'journal_entries.list',    'label' => 'List journal entries',  'description' => 'Can view journal entries'],
                    ['key' => 'journal_entries.show',    'label' => 'View journal entry',    'description' => 'Can view entry details'],
                    ['key' => 'journal_entries.create',  'label' => 'Create journal entry',  'description' => 'Can create journal entries'],
                    ['key' => 'journal_entries.update',  'label' => 'Update journal entry',  'description' => 'Can edit journal entries'],
                ],
            ],
            [
                'category' => 'inventory',
                'label'    => 'Inventory & Warehouses',
                'permissions' => [
                    ['key' => 'inventory.list',       'label' => 'List inventory',         'description' => 'Can view stock levels'],
                    ['key' => 'inventory.show',       'label' => 'View inventory',         'description' => 'Can view stock details'],
                    ['key' => 'inventory.create',     'label' => 'Create movements',       'description' => 'Can create stock movements'],
                    ['key' => 'warehouses.list',      'label' => 'List warehouses',        'description' => 'Can view warehouses'],
                    ['key' => 'warehouses.show',      'label' => 'View warehouse',         'description' => 'Can view warehouse details'],
                    ['key' => 'warehouses.create',    'label' => 'Create warehouse',       'description' => 'Can create warehouses'],
                    ['key' => 'warehouses.update',    'label' => 'Update warehouse',       'description' => 'Can edit warehouses'],
                    ['key' => 'warehouses.delete',    'label' => 'Delete warehouse',       'description' => 'Can delete warehouses'],
                    ['key' => 'reservations.list',    'label' => 'List reservations',      'description' => 'Can view stock reservations'],
                    ['key' => 'reservations.show',    'label' => 'View reservation',       'description' => 'Can view reservation details'],
                    ['key' => 'reservations.create',  'label' => 'Create reservation',     'description' => 'Can create stock reservations'],
                    ['key' => 'reservations.update',  'label' => 'Update reservation',     'description' => 'Can update reservations'],
                ],
            ],
            [
                'category' => 'production',
                'label'    => 'Production & BOM',
                'permissions' => [
                    ['key' => 'bom.list',           'label' => 'List BOMs',          'description' => 'Can view bills of materials'],
                    ['key' => 'bom.show',           'label' => 'View BOM',           'description' => 'Can view BOM details'],
                    ['key' => 'bom.create',         'label' => 'Create BOM',         'description' => 'Can create BOMs'],
                    ['key' => 'bom.update',         'label' => 'Update BOM',         'description' => 'Can edit BOMs'],
                    ['key' => 'bom.delete',         'label' => 'Delete BOM',         'description' => 'Can delete BOMs'],
                    ['key' => 'production.list',    'label' => 'List production orders',   'description' => 'Can view production orders'],
                    ['key' => 'production.show',    'label' => 'View production order',    'description' => 'Can view production details'],
                    ['key' => 'production.create',  'label' => 'Create production order',  'description' => 'Can create production orders'],
                    ['key' => 'production.update',  'label' => 'Update production order',  'description' => 'Can edit production orders'],
                ],
            ],
            [
                'category' => 'pipelines',
                'label'    => 'Pipelines & Sales CRM',
                'permissions' => [
                    ['key' => 'pipelines.list',               'label' => 'View pipelines',       'description' => 'Can view pipeline summaries, stages, and deal records'],
                    ['key' => 'pipelines.manage',             'label' => 'Manage pipelines',     'description' => 'Can create, edit, and delete pipeline definitions and stages'],
                    ['key' => 'pipeline_records.create',      'label' => 'Create records',       'description' => 'Can create pipeline records/deals'],
                    ['key' => 'pipeline_records.update',      'label' => 'Update records',       'description' => 'Can edit pipeline records and move between stages'],
                    ['key' => 'pipeline_records.delete',      'label' => 'Delete records',       'description' => 'Can delete pipeline records'],
                    ['key' => 'pipeline_records.own',         'label' => 'Own records',          'description' => 'Eligible to be assigned as the responsible salesperson on pipeline records'],
                    ['key' => 'pipeline_records.manage_team', 'label' => 'Manage team records', 'description' => 'Can view and manage pipeline records assigned to members of the same team'],
                    ['key' => 'pipeline_records.manage_all',  'label' => 'Manage all records',   'description' => 'Can update and delete any record regardless of assignment'],
                    ['key' => 'pipeline_records.assign',      'label' => 'Assign records',       'description' => 'Can assign or reassign pipeline records to other members'],
                ],
            ],
            [
                'category' => 'commissions',
                'label'    => 'Commissions',
                'permissions' => [
                    ['key' => 'commissions.list',            'label' => 'List commissions',            'description' => 'Can view commission entries list'],
                    ['key' => 'commissions.view_all',        'label' => 'View all commissions',        'description' => 'Can view commission entries for all members'],
                    ['key' => 'commissions.view_team',       'label' => 'View team commissions',       'description' => 'Can view commission entries for own team'],
                    ['key' => 'commissions.calculate',       'label' => 'Calculate commissions',       'description' => 'Can trigger commission calculation'],
                    ['key' => 'commissions.approve',         'label' => 'Approve commissions',         'description' => 'Can approve pending commission entries'],
                    ['key' => 'commissions.pay',             'label' => 'Pay commissions',             'description' => 'Can mark commissions as paid'],
                    ['key' => 'commissions.cancel',          'label' => 'Cancel commissions',          'description' => 'Can cancel commission entries'],
                    ['key' => 'commissions.settings.view',   'label' => 'View commission settings',   'description' => 'Can view commission plans and rules'],
                    ['key' => 'commissions.settings.manage', 'label' => 'Manage commission settings', 'description' => 'Can create and edit commission plans and rules'],
                ],
            ],
            [
                'category' => 'recurring',
                'label'    => 'Recurring Billing',
                'permissions' => [
                    ['key' => 'recurring.list',   'label' => 'List recurring',   'description' => 'Can view recurring entries'],
                    ['key' => 'recurring.show',   'label' => 'View recurring',   'description' => 'Can view recurring details'],
                    ['key' => 'recurring.create', 'label' => 'Create recurring', 'description' => 'Can create recurring entries'],
                    ['key' => 'recurring.update', 'label' => 'Update recurring', 'description' => 'Can edit recurring entries'],
                    ['key' => 'recurring.delete', 'label' => 'Delete recurring', 'description' => 'Can delete recurring entries'],
                ],
            ],
            [
                'category' => 'employees',
                'label'    => 'Employees & Invitations',
                'permissions' => [
                    ['key' => 'employees.list',    'label' => 'List employees',    'description' => 'Can view the employee list'],
                    ['key' => 'employees.show',    'label' => 'View employee',     'description' => 'Can view employee details'],
                    ['key' => 'employees.create',  'label' => 'Create/invite employee', 'description' => 'Can invite new employees'],
                    ['key' => 'employees.update',  'label' => 'Update employee',   'description' => 'Can edit employee information'],
                    ['key' => 'roles.list',        'label' => 'List roles',        'description' => 'Can view the list of roles and their permissions'],
                    ['key' => 'roles.manage',      'label' => 'Manage roles',      'description' => 'Can create, edit, and assign roles'],
                    ['key' => 'departments.list',  'label' => 'List departments',  'description' => 'Can view the departments list'],
                    ['key' => 'departments.manage','label' => 'Manage departments','description' => 'Can create, edit, and delete departments'],
                    ['key' => 'teams.list',        'label' => 'List teams',        'description' => 'Can view the teams list'],
                    ['key' => 'teams.manage',      'label' => 'Manage teams',      'description' => 'Can create, edit, and delete teams'],
                    ['key' => 'invitations.manage', 'label' => 'Manage invitations', 'description' => 'Can create and revoke invitations'],
                ],
            ],
            [
                'category' => 'reports',
                'label'    => 'Reports & Analytics',
                'permissions' => [
                    ['key' => 'reports.view', 'label' => 'View reports', 'description' => 'Can access business reports and analytics'],
                ],
            ],
            [
                'category' => 'system',
                'label'    => 'System & Settings',
                'permissions' => [
                    ['key' => 'settings.view',        'label' => 'Access settings',        'description' => 'Can access the workspace settings screen (does not grant modification)'],
                    ['key' => 'settings.manage',      'label' => 'Manage settings',        'description' => 'Can modify workspace settings, branding, and configuration'],
                    ['key' => 'notifications.list',   'label' => 'List notifications',    'description' => 'Can view notifications'],
                    ['key' => 'notifications.update', 'label' => 'Update notifications',  'description' => 'Can mark notifications as read'],
                    ['key' => 'audit.list',           'label' => 'List audit logs',        'description' => 'Can view audit trail'],
                    ['key' => 'audit.show',           'label' => 'View audit log',         'description' => 'Can view audit details'],
                    ['key' => 'discovery.manage',     'label' => 'Manage discovery',       'description' => 'Can manage workspace discovery settings'],
                ],
            ],
            [
                'category' => 'approvals',
                'label'    => 'Approvals',
                'permissions' => [
                    ['key' => 'approvals.list',    'label' => 'List approvals',     'description' => 'Can view approval requests and inbox'],
                    ['key' => 'approvals.show',    'label' => 'View approval',      'description' => 'Can view approval request details'],
                    ['key' => 'approvals.request', 'label' => 'Submit approvals',   'description' => 'Can submit new approval requests'],
                    ['key' => 'approvals.decide',  'label' => 'Decide approvals',   'description' => 'Can approve or reject approval requests (subject to workflow step configuration)'],
                    ['key' => 'approvals.manage',  'label' => 'Manage approvals',   'description' => 'Can manage approval workflows, cancel any request, and configure approval settings'],
                    ['key' => 'approvals.cancel',  'label' => 'Cancel approvals',   'description' => 'Can cancel own pending approval requests'],
                ],
            ],
        ];
    }

    /**
     * Get a flat list of all valid permission keys.
     *
     * @return string[]
     */
    public static function allKeys(): array
    {
        $keys = [];
        foreach (self::all() as $category) {
            foreach ($category['permissions'] as $perm) {
                $keys[] = $perm['key'];
            }
        }
        return $keys;
    }

    /**
     * Validate that all given permission keys exist in the catalog.
     *
     * @param  string[]  $keys
     * @return string[]  Invalid keys
     */
    public static function validateKeys(array $keys): array
    {
        $valid = self::allKeys();
        return array_values(array_diff($keys, $valid));
    }
}
