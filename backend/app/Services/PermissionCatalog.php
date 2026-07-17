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
     * Each permission may include `usable_as_approver` (bool, default false).
     * Only permissions flagged as `usable_as_approver => true` are eligible
     * as `approver_permission_key` values in approval workflow steps.
     *
     * @return array<int, array{category: string, label: string, permissions: array}>
     */
    public static function all(): array
    {
        return [
            [
                'category' => 'ai',
                'label'    => 'AI & Advisor',
                'label_en' => 'AI & Advisor',
                'label_ar' => 'الذكاء الاصطناعي والمستشار',
                'permissions' => [
                    ['key' => 'ai_advisor.view', 'label' => 'Access AI Advisor', 'label_en' => 'Access AI Advisor', 'label_ar' => 'الوصول إلى المستشار الذكي', 'description' => 'Can access the AI Advisor recommendations screen'],
                ],
            ],
            [
                'category' => 'contacts',
                'label'    => 'Customers & Contacts',
                'label_en' => 'Customers & Contacts',
                'label_ar' => 'العملاء وجهات الاتصال',
                'permissions' => [
                    ['key' => 'contacts.list',       'label' => 'List contacts',        'label_en' => 'List contacts',        'label_ar' => 'عرض جهات الاتصال',     'description' => 'Can view the contacts list'],
                    ['key' => 'contacts.show',       'label' => 'View contact',         'label_en' => 'View contact',         'label_ar' => 'عرض جهة اتصال',        'description' => 'Can view contact details'],
                    ['key' => 'contacts.create',     'label' => 'Create contact',       'label_en' => 'Create contact',       'label_ar' => 'إنشاء جهة اتصال',      'description' => 'Can create new contacts'],
                    ['key' => 'contacts.update',     'label' => 'Update contact',       'label_en' => 'Update contact',       'label_ar' => 'تعديل جهة اتصال',      'description' => 'Can edit existing contacts'],
                    ['key' => 'contacts.delete',     'label' => 'Delete contact',       'label_en' => 'Delete contact',       'label_ar' => 'حذف جهة اتصال',        'description' => 'Can delete contacts'],
                    ['key' => 'contacts.own',        'label' => 'Own customers',        'label_en' => 'Own customers',        'label_ar' => 'امتلاك عملاء',          'description' => 'Eligible to be assigned as the responsible salesperson on customers'],
                    ['key' => 'contacts.manage_team','label' => 'Manage team customers', 'label_en' => 'Manage team customers', 'label_ar' => 'إدارة عملاء الفريق', 'description' => 'Can view and manage customers assigned to members of the same team'],
                    ['key' => 'contacts.manage_all', 'label' => 'Manage all customers', 'label_en' => 'Manage all customers', 'label_ar' => 'إدارة جميع العملاء',   'description' => 'Can view and manage all customers in the workspace'],
                    ['key' => 'contacts.assign',     'label' => 'Assign customers',     'label_en' => 'Assign customers',     'label_ar' => 'تعيين العملاء',         'description' => 'Can assign or reassign customers to other members'],
                ],
            ],
            [
                'category' => 'products',
                'label'    => 'Products',
                'label_en' => 'Products',
                'label_ar' => 'المنتجات',
                'permissions' => [
                    ['key' => 'products.list',   'label' => 'List products',   'label_en' => 'List products',   'label_ar' => 'عرض المنتجات',   'description' => 'Can view the products list'],
                    ['key' => 'products.show',   'label' => 'View product',    'label_en' => 'View product',    'label_ar' => 'عرض منتج',       'description' => 'Can view product details'],
                    ['key' => 'products.create', 'label' => 'Create product',  'label_en' => 'Create product',  'label_ar' => 'إنشاء منتج',     'description' => 'Can create new products'],
                    ['key' => 'products.update', 'label' => 'Update product',  'label_en' => 'Update product',  'label_ar' => 'تعديل منتج',     'description' => 'Can edit existing products'],
                    ['key' => 'products.delete', 'label' => 'Delete product',  'label_en' => 'Delete product',  'label_ar' => 'حذف منتج',       'description' => 'Can delete products'],
                ],
            ],
            [
                'category' => 'categories',
                'label'    => 'Categories',
                'label_en' => 'Categories',
                'label_ar' => 'التصنيفات',
                'permissions' => [
                    ['key' => 'categories.list',   'label' => 'List categories',   'label_en' => 'List categories',   'label_ar' => 'عرض التصنيفات',   'description' => 'Can view categories'],
                    ['key' => 'categories.show',   'label' => 'View category',     'label_en' => 'View category',     'label_ar' => 'عرض تصنيف',       'description' => 'Can view category details'],
                    ['key' => 'categories.create', 'label' => 'Create category',   'label_en' => 'Create category',   'label_ar' => 'إنشاء تصنيف',     'description' => 'Can create categories'],
                    ['key' => 'categories.update', 'label' => 'Update category',   'label_en' => 'Update category',   'label_ar' => 'تعديل تصنيف',     'description' => 'Can edit categories'],
                    ['key' => 'categories.delete', 'label' => 'Delete category',   'label_en' => 'Delete category',   'label_ar' => 'حذف تصنيف',       'description' => 'Can delete categories'],
                ],
            ],
            [
                'category' => 'invoices',
                'label'    => 'Invoices',
                'label_en' => 'Invoices',
                'label_ar' => 'الفواتير',
                'permissions' => [
                    ['key' => 'invoices.list',   'label' => 'List invoices',   'label_en' => 'List invoices',   'label_ar' => 'عرض الفواتير',   'description' => 'Can view the invoices list'],
                    ['key' => 'invoices.show',   'label' => 'View invoice',    'label_en' => 'View invoice',    'label_ar' => 'عرض فاتورة',     'description' => 'Can view invoice details'],
                    ['key' => 'invoices.create', 'label' => 'Create invoice',  'label_en' => 'Create invoice',  'label_ar' => 'إنشاء فاتورة',   'description' => 'Can create new invoices'],
                    ['key' => 'invoices.update', 'label' => 'Update invoice',  'label_en' => 'Update invoice',  'label_ar' => 'تعديل فاتورة',   'description' => 'Can edit existing invoices'],
                ],
            ],
            [
                'category' => 'payments',
                'label'    => 'Payments',
                'label_en' => 'Payments',
                'label_ar' => 'المدفوعات',
                'permissions' => [
                    ['key' => 'payments.list',   'label' => 'List payments',   'label_en' => 'List payments',   'label_ar' => 'عرض المدفوعات',   'description' => 'Can view the payments list'],
                    ['key' => 'payments.show',   'label' => 'View payment',    'label_en' => 'View payment',    'label_ar' => 'عرض دفعة',        'description' => 'Can view payment details'],
                    ['key' => 'payments.create', 'label' => 'Create payment',  'label_en' => 'Create payment',  'label_ar' => 'تسجيل دفعة',      'description' => 'Can record payments'],
                ],
            ],
            [
                'category' => 'orders',
                'label'    => 'POS & Orders',
                'label_en' => 'POS & Orders',
                'label_ar' => 'نقاط البيع والطلبات',
                'permissions' => [
                    ['key' => 'pos.view',      'label' => 'Access POS',     'label_en' => 'Access POS',     'label_ar' => 'الوصول إلى نقطة البيع', 'description' => 'Can access the point-of-sale screen (does not grant order creation or payment capabilities)'],
                    ['key' => 'orders.list',   'label' => 'List orders',   'label_en' => 'List orders',   'label_ar' => 'عرض الطلبات',   'description' => 'Can view orders'],
                    ['key' => 'orders.show',   'label' => 'View order',    'label_en' => 'View order',    'label_ar' => 'عرض طلب',       'description' => 'Can view order details'],
                    ['key' => 'orders.create', 'label' => 'Create order',  'label_en' => 'Create order',  'label_ar' => 'إنشاء طلب',     'description' => 'Can create orders'],
                    ['key' => 'orders.update', 'label' => 'Update order',  'label_en' => 'Update order',  'label_ar' => 'تعديل طلب',     'description' => 'Can edit orders'],
                ],
            ],
            [
                'category' => 'accounting',
                'label'    => 'Accounting & Journal Entries',
                'label_en' => 'Accounting & Journal Entries',
                'label_ar' => 'المحاسبة والقيود اليومية',
                'permissions' => [
                    ['key' => 'accounting.view',        'label' => 'Access accounting', 'label_en' => 'Access accounting', 'label_ar' => 'الوصول إلى المحاسبة', 'description' => 'Can access the accounting module landing page (does not grant posting or editing entries)'],
                    ['key' => 'accounts.list',          'label' => 'List accounts',   'label_en' => 'List accounts',   'label_ar' => 'عرض الحسابات',       'description' => 'Can view chart of accounts'],
                    ['key' => 'accounts.show',          'label' => 'View account',    'label_en' => 'View account',    'label_ar' => 'عرض حساب',          'description' => 'Can view account details'],
                    ['key' => 'accounts.create',        'label' => 'Create account',  'label_en' => 'Create account',  'label_ar' => 'إنشاء حساب',        'description' => 'Can create accounts'],
                    ['key' => 'accounts.update',        'label' => 'Update account',  'label_en' => 'Update account',  'label_ar' => 'تعديل حساب',        'description' => 'Can edit accounts'],
                    ['key' => 'accounts.delete',        'label' => 'Delete account',  'label_en' => 'Delete account',  'label_ar' => 'حذف حساب',          'description' => 'Can delete accounts'],
                    ['key' => 'journal_entries.list',    'label' => 'List journal entries',  'label_en' => 'List journal entries',  'label_ar' => 'عرض القيود اليومية',  'description' => 'Can view journal entries'],
                    ['key' => 'journal_entries.show',    'label' => 'View journal entry',    'label_en' => 'View journal entry',    'label_ar' => 'عرض قيد يومي',        'description' => 'Can view entry details'],
                    ['key' => 'journal_entries.create',  'label' => 'Create journal entry',  'label_en' => 'Create journal entry',  'label_ar' => 'إنشاء قيد يومي',      'description' => 'Can create journal entries'],
                    ['key' => 'journal_entries.update',  'label' => 'Update journal entry',  'label_en' => 'Update journal entry',  'label_ar' => 'تعديل قيد يومي',      'description' => 'Can edit journal entries'],
                ],
            ],
            [
                'category' => 'inventory',
                'label'    => 'Inventory & Warehouses',
                'label_en' => 'Inventory & Warehouses',
                'label_ar' => 'المخزون والمستودعات',
                'permissions' => [
                    ['key' => 'inventory.list',       'label' => 'List inventory',         'label_en' => 'List inventory',         'label_ar' => 'عرض المخزون',         'description' => 'Can view stock levels'],
                    ['key' => 'inventory.show',       'label' => 'View inventory',         'label_en' => 'View inventory',         'label_ar' => 'عرض تفاصيل المخزون', 'description' => 'Can view stock details'],
                    ['key' => 'inventory.create',     'label' => 'Create movements',       'label_en' => 'Create movements',       'label_ar' => 'إنشاء حركات',         'description' => 'Can create stock movements'],
                    ['key' => 'warehouses.list',      'label' => 'List warehouses',        'label_en' => 'List warehouses',        'label_ar' => 'عرض المستودعات',       'description' => 'Can view warehouses'],
                    ['key' => 'warehouses.show',      'label' => 'View warehouse',         'label_en' => 'View warehouse',         'label_ar' => 'عرض مستودع',          'description' => 'Can view warehouse details'],
                    ['key' => 'warehouses.create',    'label' => 'Create warehouse',       'label_en' => 'Create warehouse',       'label_ar' => 'إنشاء مستودع',        'description' => 'Can create warehouses'],
                    ['key' => 'warehouses.update',    'label' => 'Update warehouse',       'label_en' => 'Update warehouse',       'label_ar' => 'تعديل مستودع',        'description' => 'Can edit warehouses'],
                    ['key' => 'warehouses.delete',    'label' => 'Delete warehouse',       'label_en' => 'Delete warehouse',       'label_ar' => 'حذف مستودع',          'description' => 'Can delete warehouses'],
                    ['key' => 'reservations.list',    'label' => 'List reservations',      'label_en' => 'List reservations',      'label_ar' => 'عرض الحجوزات',        'description' => 'Can view stock reservations'],
                    ['key' => 'reservations.show',    'label' => 'View reservation',       'label_en' => 'View reservation',       'label_ar' => 'عرض حجز',             'description' => 'Can view reservation details'],
                    ['key' => 'reservations.create',  'label' => 'Create reservation',     'label_en' => 'Create reservation',     'label_ar' => 'إنشاء حجز',           'description' => 'Can create stock reservations'],
                    ['key' => 'reservations.update',  'label' => 'Update reservation',     'label_en' => 'Update reservation',     'label_ar' => 'تعديل حجز',           'description' => 'Can update reservations'],
                ],
            ],
            [
                'category' => 'production',
                'label'    => 'Production & BOM',
                'label_en' => 'Production & BOM',
                'label_ar' => 'الإنتاج وقوائم المواد',
                'permissions' => [
                    ['key' => 'bom.list',           'label' => 'List BOMs',          'label_en' => 'List BOMs',          'label_ar' => 'عرض قوائم المواد',       'description' => 'Can view bills of materials'],
                    ['key' => 'bom.show',           'label' => 'View BOM',           'label_en' => 'View BOM',           'label_ar' => 'عرض قائمة مواد',       'description' => 'Can view BOM details'],
                    ['key' => 'bom.create',         'label' => 'Create BOM',         'label_en' => 'Create BOM',         'label_ar' => 'إنشاء قائمة مواد',     'description' => 'Can create BOMs'],
                    ['key' => 'bom.update',         'label' => 'Update BOM',         'label_en' => 'Update BOM',         'label_ar' => 'تعديل قائمة مواد',     'description' => 'Can edit BOMs'],
                    ['key' => 'bom.delete',         'label' => 'Delete BOM',         'label_en' => 'Delete BOM',         'label_ar' => 'حذف قائمة مواد',       'description' => 'Can delete BOMs'],
                    ['key' => 'production.list',    'label' => 'List production orders',   'label_en' => 'List production orders',   'label_ar' => 'عرض أوامر الإنتاج',   'description' => 'Can view production orders'],
                    ['key' => 'production.show',    'label' => 'View production order',    'label_en' => 'View production order',    'label_ar' => 'عرض أمر إنتاج',       'description' => 'Can view production details'],
                    ['key' => 'production.create',  'label' => 'Create production order',  'label_en' => 'Create production order',  'label_ar' => 'إنشاء أمر إنتاج',     'description' => 'Can create production orders'],
                    ['key' => 'production.update',  'label' => 'Update production order',  'label_en' => 'Update production order',  'label_ar' => 'تعديل أمر إنتاج',     'description' => 'Can edit production orders'],
                ],
            ],
            [
                'category' => 'pipelines',
                'label'    => 'Pipelines & Sales CRM',
                'label_en' => 'Pipelines & Sales CRM',
                'label_ar' => 'قنوات البيع وإدارة العلاقات',
                'permissions' => [
                    ['key' => 'pipelines.list',               'label' => 'View pipelines',       'label_en' => 'View pipelines',       'label_ar' => 'عرض قنوات البيع',       'description' => 'Can view pipeline summaries, stages, and deal records'],
                    ['key' => 'pipelines.manage',             'label' => 'Manage pipelines',     'label_en' => 'Manage pipelines',     'label_ar' => 'إدارة قنوات البيع',     'description' => 'Can create, edit, and delete pipeline definitions and stages'],
                    ['key' => 'pipeline_records.create',      'label' => 'Create records',       'label_en' => 'Create records',       'label_ar' => 'إنشاء سجلات',          'description' => 'Can create pipeline records/deals'],
                    ['key' => 'pipeline_records.update',      'label' => 'Update records',       'label_en' => 'Update records',       'label_ar' => 'تعديل سجلات',          'description' => 'Can edit pipeline records and move between stages'],
                    ['key' => 'pipeline_records.delete',      'label' => 'Delete records',       'label_en' => 'Delete records',       'label_ar' => 'حذف سجلات',            'description' => 'Can delete pipeline records'],
                    ['key' => 'pipeline_records.own',         'label' => 'Own records',          'label_en' => 'Own records',          'label_ar' => 'امتلاك سجلات',         'description' => 'Eligible to be assigned as the responsible salesperson on pipeline records'],
                    ['key' => 'pipeline_records.manage_team', 'label' => 'Manage team records', 'label_en' => 'Manage team records', 'label_ar' => 'إدارة سجلات الفريق', 'description' => 'Can view and manage pipeline records assigned to members of the same team'],
                    ['key' => 'pipeline_records.manage_all',  'label' => 'Manage all records',   'label_en' => 'Manage all records',   'label_ar' => 'إدارة جميع السجلات',   'description' => 'Can update and delete any record regardless of assignment'],
                    ['key' => 'pipeline_records.assign',      'label' => 'Assign records',       'label_en' => 'Assign records',       'label_ar' => 'تعيين سجلات',          'description' => 'Can assign or reassign pipeline records to other members'],
                ],
            ],
            [
                'category' => 'commissions',
                'label'    => 'Commissions',
                'label_en' => 'Commissions',
                'label_ar' => 'العمولات',
                'permissions' => [
                    ['key' => 'commissions.list',            'label' => 'List commissions',            'label_en' => 'List commissions',            'label_ar' => 'عرض العمولات',            'description' => 'Can view commission entries list'],
                    ['key' => 'commissions.view_own',        'label' => 'View own commissions',        'label_en' => 'View own commissions',        'label_ar' => 'عرض عمولاتي',              'description' => 'Can view only commission entries where the user is the recipient'],
                    ['key' => 'commissions.view_all',        'label' => 'View all commissions',        'label_en' => 'View all commissions',        'label_ar' => 'عرض جميع العمولات',        'description' => 'Can view commission entries for all members'],
                    ['key' => 'commissions.view_team',       'label' => 'View team commissions',       'label_en' => 'View team commissions',       'label_ar' => 'عرض عمولات الفريق',       'description' => 'Can view commission entries for own team'],
                    ['key' => 'commissions.calculate',       'label' => 'Calculate commissions',       'label_en' => 'Calculate commissions',       'label_ar' => 'حساب العمولات',           'description' => 'Can trigger commission calculation'],
                    ['key' => 'commissions.approve',         'label' => 'Approve commissions',         'label_en' => 'Approve commissions', 'label_ar' => 'اعتماد العمولات', 'description' => 'Can approve pending commission entries', 'usable_as_approver' => true],
                    ['key' => 'commissions.pay',             'label' => 'Pay commissions',             'label_en' => 'Pay commissions',             'label_ar' => 'دفع العمولات',             'description' => 'Can mark commissions as paid'],
                    ['key' => 'commissions.cancel',          'label' => 'Cancel commissions',          'label_en' => 'Cancel commissions',          'label_ar' => 'إلغاء العمولات',           'description' => 'Can cancel commission entries'],
                    ['key' => 'commissions.settings.view',   'label' => 'View commission settings',   'label_en' => 'View commission settings',   'label_ar' => 'عرض إعدادات العمولات',   'description' => 'Can view commission plans and rules'],
                    ['key' => 'commissions.settings.manage', 'label' => 'Manage commission settings', 'label_en' => 'Manage commission settings', 'label_ar' => 'إدارة إعدادات العمولات', 'description' => 'Can create and edit commission plans and rules'],
                ],
            ],
            [
                'category' => 'recurring',
                'label'    => 'Recurring Billing',
                'label_en' => 'Recurring Billing',
                'label_ar' => 'الفوترة المتكررة',
                'permissions' => [
                    ['key' => 'recurring.list',   'label' => 'List recurring',   'label_en' => 'List recurring',   'label_ar' => 'عرض المتكررة',   'description' => 'Can view recurring entries'],
                    ['key' => 'recurring.show',   'label' => 'View recurring',   'label_en' => 'View recurring',   'label_ar' => 'عرض تفاصيل',     'description' => 'Can view recurring details'],
                    ['key' => 'recurring.create', 'label' => 'Create recurring', 'label_en' => 'Create recurring', 'label_ar' => 'إنشاء متكررة',   'description' => 'Can create recurring entries'],
                    ['key' => 'recurring.update', 'label' => 'Update recurring', 'label_en' => 'Update recurring', 'label_ar' => 'تعديل متكررة',   'description' => 'Can edit recurring entries'],
                    ['key' => 'recurring.delete', 'label' => 'Delete recurring', 'label_en' => 'Delete recurring', 'label_ar' => 'حذف متكررة',     'description' => 'Can delete recurring entries'],
                ],
            ],
            [
                'category' => 'employees',
                'label'    => 'Employees & Invitations',
                'label_en' => 'Employees & Invitations',
                'label_ar' => 'الموظفون والدعوات',
                'permissions' => [
                    ['key' => 'employees.list',    'label' => 'List employees',    'label_en' => 'List employees',    'label_ar' => 'عرض الموظفين',    'description' => 'Can view the employee list'],
                    ['key' => 'employees.show',    'label' => 'View employee',     'label_en' => 'View employee',     'label_ar' => 'عرض موظف',        'description' => 'Can view employee details'],
                    ['key' => 'employees.create',  'label' => 'Create/invite employee', 'label_en' => 'Create/invite employee', 'label_ar' => 'إنشاء/دعوة موظف', 'description' => 'Can invite new employees'],
                    ['key' => 'employees.update',  'label' => 'Update employee',   'label_en' => 'Update employee',   'label_ar' => 'تعديل موظف',      'description' => 'Can edit employee information'],
                    ['key' => 'roles.list',        'label' => 'List roles',        'label_en' => 'List roles',        'label_ar' => 'عرض الأدوار',      'description' => 'Can view the list of roles and their permissions'],
                    ['key' => 'roles.manage',      'label' => 'Manage roles',      'label_en' => 'Manage roles',      'label_ar' => 'إدارة الأدوار',    'description' => 'Can create, edit, and assign roles'],
                    ['key' => 'departments.list',  'label' => 'List departments',  'label_en' => 'List departments',  'label_ar' => 'عرض الأقسام',      'description' => 'Can view the departments list'],
                    ['key' => 'departments.manage','label' => 'Manage departments','label_en' => 'Manage departments','label_ar' => 'إدارة الأقسام',    'description' => 'Can create, edit, and delete departments'],
                    ['key' => 'teams.list',        'label' => 'List teams',        'label_en' => 'List teams',        'label_ar' => 'عرض الفرق',       'description' => 'Can view the teams list'],
                    ['key' => 'teams.manage',      'label' => 'Manage teams',      'label_en' => 'Manage teams',      'label_ar' => 'إدارة الفرق',     'description' => 'Can create, edit, and delete teams'],
                    ['key' => 'invitations.manage', 'label' => 'Manage invitations', 'label_en' => 'Manage invitations', 'label_ar' => 'إدارة الدعوات', 'description' => 'Can create and revoke invitations'],
                ],
            ],
            [
                'category' => 'reports',
                'label'    => 'Reports & Analytics',
                'label_en' => 'Reports & Analytics',
                'label_ar' => 'التقارير والتحليلات',
                'permissions' => [
                    ['key' => 'reports.view', 'label' => 'View reports', 'label_en' => 'View reports', 'label_ar' => 'عرض التقارير', 'description' => 'Can access business reports and analytics'],
                ],
            ],
            [
                'category' => 'system',
                'label'    => 'System & Settings',
                'label_en' => 'System & Settings',
                'label_ar' => 'النظام والإعدادات',
                'permissions' => [
                    ['key' => 'settings.view',        'label' => 'Access settings',        'label_en' => 'Access settings',        'label_ar' => 'الوصول إلى الإعدادات',  'description' => 'Can access the workspace settings screen (does not grant modification)'],
                    ['key' => 'settings.manage',      'label' => 'Manage settings',        'label_en' => 'Manage settings',        'label_ar' => 'إدارة الإعدادات',       'description' => 'Can modify workspace settings, branding, and configuration'],
                    ['key' => 'notifications.list',   'label' => 'List notifications',    'label_en' => 'List notifications',    'label_ar' => 'عرض الإشعارات',        'description' => 'Can view notifications'],
                    ['key' => 'notifications.update', 'label' => 'Update notifications',  'label_en' => 'Update notifications',  'label_ar' => 'تحديث الإشعارات',      'description' => 'Can mark notifications as read'],
                    ['key' => 'audit.list',           'label' => 'List audit logs',        'label_en' => 'List audit logs',        'label_ar' => 'عرض سجل التدقيق',      'description' => 'Can view audit trail'],
                    ['key' => 'audit.show',           'label' => 'View audit log',         'label_en' => 'View audit log',         'label_ar' => 'عرض تفاصيل التدقيق', 'description' => 'Can view audit details'],
                    ['key' => 'discovery.manage',     'label' => 'Manage discovery',       'label_en' => 'Manage discovery',       'label_ar' => 'إدارة الاكتشاف',        'description' => 'Can manage workspace discovery settings'],
                ],
            ],
            [
                'category' => 'approvals',
                'label'    => 'Approvals',
                'label_en' => 'Approvals',
                'label_ar' => 'الموافقات',
                'permissions' => [
                    ['key' => 'approvals.list',    'label' => 'List approvals',     'label_en' => 'List approvals',     'label_ar' => 'عرض الموافقات',       'description' => 'Can view approval requests and inbox'],
                    ['key' => 'approvals.show',    'label' => 'View approval',      'label_en' => 'View approval',      'label_ar' => 'عرض موافقة',          'description' => 'Can view approval request details'],
                    ['key' => 'approvals.request', 'label' => 'Submit approvals',   'label_en' => 'Submit approvals',   'label_ar' => 'تقديم موافقات',        'description' => 'Can submit new approval requests'],
                    ['key' => 'approvals.decide',  'label' => 'Decide approvals',   'label_en' => 'Decide approvals', 'label_ar' => 'اتخاذ قرار الموافقة', 'description' => 'Can approve or reject approval requests (subject to workflow step configuration)', 'usable_as_approver' => true],
                    ['key' => 'approvals.manage',  'label' => 'Manage approvals',   'label_en' => 'Manage approvals',   'label_ar' => 'إدارة الموافقات',     'description' => 'Can manage approval workflows, cancel any request, and configure approval settings'],
                    ['key' => 'approvals.cancel',  'label' => 'Cancel approvals',   'label_en' => 'Cancel approvals',   'label_ar' => 'إلغاء الموافقات',       'description' => 'Can cancel own pending approval requests'],
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
     * Get a flat list of permission keys that are eligible as workflow approvers.
     *
     * Only permissions with `usable_as_approver => true` are returned.
     *
     * @return string[]
     */
    public static function approverKeys(): array
    {
        $keys = [];
        foreach (self::all() as $category) {
            foreach ($category['permissions'] as $perm) {
                if (! empty($perm['usable_as_approver'])) {
                    $keys[] = $perm['key'];
                }
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

    /**
     * Map PermissionCatalog categories to Blueprint module keys.
     *
     * Categories mapped to null are platform-level and always available.
     * Categories mapped to a string are only active when that Blueprint module is enabled.
     *
     * @return array<string, string|null>
     */
    public static function categoryModuleMap(): array
    {
        return [
            'ai'          => 'ai',
            'contacts'    => 'customers',
            'products'    => 'products',
            'categories'  => 'products',
            'invoices'    => 'invoices',
            'payments'    => 'payments',
            'orders'      => 'orders',
            'accounting'  => 'finance',
            'inventory'   => 'inventory',
            'production'  => null,       // only available via manufacturing module
            'pipelines'   => 'leads',
            'commissions' => 'commissions',
            'recurring'   => 'invoices',
            'employees'   => null,       // platform: always available
            'reports'     => null,       // platform: always available
            'system'      => null,       // platform: always available
            'approvals'   => null,       // platform: always available
        ];
    }

    /**
     * Return permission keys filtered to those accessible given enabled Blueprint modules.
     *
     * Platform-level permissions (employees, system, approvals, reports) are always included.
     * Module-specific permissions are included only when their module is in $enabledModules.
     * The 'production' category requires a 'manufacturing' module to be enabled.
     *
     * @param string[] $enabledModules  Blueprint module keys that are enabled
     * @return string[]
     */
    public static function keysForModules(array $enabledModules): array
    {
        $map = self::categoryModuleMap();
        $enabledSet = array_flip($enabledModules);
        $keys = [];

        foreach (self::all() as $group) {
            $category = $group['category'];
            $requiredModule = $map[$category] ?? null;

            // Platform-level categories (null mapping) are always included
            if ($requiredModule === null) {
                // Special case: production category needs manufacturing module
                if ($category === 'production') {
                    if (!isset($enabledSet['manufacturing'])) continue;
                }
                // Other null-mapped categories are always available
            } else {
                // Module-specific: skip if module not enabled
                if (!isset($enabledSet[$requiredModule])) continue;
            }

            foreach ($group['permissions'] as $perm) {
                $keys[] = $perm['key'];
            }
        }

        return $keys;
    }
}
