<?php

namespace App\Services\Blueprint;

use App\Services\PermissionCatalog;

/**
 * Handles role building, permission resolution, and department deduplication
 * for Blueprint generation.
 *
 * Extracted from BlueprintGenerator to keep the main generator focused on
 * orchestration. This class is stateless — all state is passed in.
 */
class BlueprintRoleBuilder
{
    /**
     * Build departments from template + discovered role departments.
     *
     * When discovered roles provide explicit department names, those are the
     * source of truth. Template departments are kept only when they represent
     * a genuinely distinct scope not covered by any discovered department.
     *
     * @param array &$registry  Output registry: normalized display name → actual key
     */
    public function buildDepartments(string $type, array $f, array &$registry, callable $generateEntityKey): array
    {
        $templateProfiles = [
            'retail'=>[['key'=>'management','name'=>'Management','status'=>'required'],['key'=>'sales','name'=>'Sales','status'=>'required'],['key'=>'warehouse','name'=>'Warehouse','status'=>'recommended'],['key'=>'finance','name'=>'Finance','status'=>'recommended']],
            'restaurant'=>[['key'=>'management','name'=>'Management','status'=>'required'],['key'=>'kitchen','name'=>'Kitchen','status'=>'required'],['key'=>'service','name'=>'Front of House','status'=>'required'],['key'=>'finance','name'=>'Finance','status'=>'recommended']],
            'service'=>[['key'=>'management','name'=>'Management','status'=>'required'],['key'=>'operations','name'=>'Operations','status'=>'required'],['key'=>'finance','name'=>'Finance','status'=>'recommended']],
            'manufacturing'=>[['key'=>'management','name'=>'Management','status'=>'required'],['key'=>'production','name'=>'Production','status'=>'required'],['key'=>'warehouse','name'=>'Warehouse','status'=>'required'],['key'=>'sales','name'=>'Sales','status'=>'recommended'],['key'=>'finance','name'=>'Finance','status'=>'recommended']],
            'distribution'=>[['key'=>'management','name'=>'Management','status'=>'required'],['key'=>'sales','name'=>'Sales','status'=>'required'],['key'=>'warehouse','name'=>'Warehouse','status'=>'required'],['key'=>'logistics','name'=>'Logistics','status'=>'recommended'],['key'=>'finance','name'=>'Finance','status'=>'recommended']],
        ];
        $templateDepts = $templateProfiles[$type] ?? $templateProfiles['service'];

        // Collect discovered departments from role_details
        $roleDetails = $f['role_details'] ?? [];
        $discoveredDeptNames = [];
        foreach ($roleDetails as $rd) {
            $deptName = $rd['department'] ?? null;
            if ($deptName) $discoveredDeptNames[] = $deptName;
        }
        $discoveredDeptNames = array_unique($discoveredDeptNames);

        $semanticCategories = $this->departmentSemanticMap();

        // Build discovered → category mapping
        $discoveredCategories = [];
        foreach ($discoveredDeptNames as $name) {
            $cat = $this->classifyDepartmentSemantic($name, $semanticCategories);
            if ($cat) $discoveredCategories[$cat] = $name;
        }

        $departments = [];
        $usedKeys = [];

        if (!empty($discoveredDeptNames)) {
            // Keep template departments only when their category is NOT covered
            foreach ($templateDepts as $dept) {
                $templateCat = $semanticCategories[$dept['key']] ?? $dept['key'];
                if (isset($discoveredCategories[$templateCat])) {
                    continue; // Discovered department covers this category
                }
                $departments[] = $dept;
                $usedKeys[] = $dept['key'];
                $registry[mb_strtolower(trim($dept['name']))] = $dept['key'];
                $registry[$dept['key']] = $dept['key'];
            }

            // Add discovered departments
            foreach ($discoveredDeptNames as $deptName) {
                $normalized = mb_strtolower(trim($deptName));
                if (isset($registry[$normalized])) continue;

                $key = $generateEntityKey('dept', $deptName, $usedKeys);
                $departments[] = [
                    'key'    => $key,
                    'name'   => $deptName,
                    'status' => 'recommended',
                ];
                $registry[$normalized] = $key;
                // Register semantic category for cross-reference
                $cat = $this->classifyDepartmentSemantic($deptName, $semanticCategories);
                if ($cat) $registry[$cat] = $key;
            }
        } else {
            // No discovered departments — use templates as-is
            foreach ($templateDepts as $dept) {
                $departments[] = $dept;
                $usedKeys[] = $dept['key'];
                $registry[mb_strtolower(trim($dept['name']))] = $dept['key'];
                $registry[$dept['key']] = $dept['key'];
            }
        }

        return $departments;
    }

    /**
     * Build roles from discovered role_details, role_names, or template defaults.
     *
     * When discovered roles exist:
     *   - The owner-like role replaces the generic Owner template
     *   - Admin is NOT added (user didn't describe one)
     *   - Permissions are derived from responsibilities, not English name matching
     *
     * Template roles (Owner+Admin+type roles) are only used when no roles
     * were discovered at all.
     */
    public function buildRoles(
        string $type, array $f, array $deptRegistry,
        callable $generateEntityKey, callable $resolveDeptKey,
        array $enabledModuleKeys = []
    ): array {
        $allPerms = PermissionCatalog::allKeys();
        $corePerms = ['ai_advisor.view','notifications.list','notifications.update'];

        // Owner gets all permissions for enabled modules + platform-level,
        // not the entire catalog (which includes disabled modules like bom/production).
        $ownerPerms = !empty($enabledModuleKeys)
            ? PermissionCatalog::keysForModules($enabledModuleKeys)
            : $allPerms;

        $roleDetails = $f['role_details'] ?? [];
        $roleNames = $f['role_names'] ?? [];

        if (!empty($roleDetails)) {
            return $this->buildDiscoveredRoles(
                $roleDetails, $ownerPerms, $corePerms, $allPerms,
                $deptRegistry, $f, $generateEntityKey, $resolveDeptKey
            );
        }

        if (!empty($roleNames)) {
            return $this->buildNamedRoles(
                $roleNames, $ownerPerms, $corePerms, $allPerms,
                $generateEntityKey
            );
        }

        return $this->buildTemplateRoles($type, $ownerPerms, $allPerms, $corePerms);
    }

    // ═══════════════════════════════════════════════════════════════
    //  Private: Role building strategies
    // ═══════════════════════════════════════════════════════════════

    /**
     * Build roles from structured discovered role_details.
     */
    private function buildDiscoveredRoles(
        array $roleDetails, array $ownerPerms, array $corePerms,
        array $allPerms, array $deptRegistry, array $f,
        callable $generateEntityKey, callable $resolveDeptKey
    ): array {
        $roles = [];
        $usedKeys = [];
        $hasOwnerLike = false;

        // Detect owner-like role
        foreach ($roleDetails as $rd) {
            if ($this->isOwnerLikeRole($rd)) {
                $hasOwnerLike = true;
                break;
            }
        }

        foreach ($roleDetails as $rd) {
            $name = $rd['name'] ?? 'Unknown';
            $responsibilities = $rd['responsibilities'] ?? [];

            if ($this->isOwnerLikeRole($rd)) {
                $usedKeys[] = 'owner';
                $role = [
                    'key'              => 'owner',
                    'name'             => $name,
                    'description'      => implode(', ', $responsibilities) ?: 'Full system access and ownership',
                    'status'           => 'required',
                    'permissions'      => $ownerPerms,
                    'is_primary_owner' => true,
                ];
                if (isset($rd['headcount'])) {
                    $role['headcount'] = (int) $rd['headcount'];
                }
                if (isset($rd['department'])) {
                    $deptKey = $resolveDeptKey($rd['department'], $deptRegistry);
                    if ($deptKey) $role['department_key'] = $deptKey;
                }
                $roles[] = $role;
                continue;
            }

            $key = $generateEntityKey('role', $name, $usedKeys);
            if (in_array($key, ['owner', 'admin'])) {
                $key = $generateEntityKey('role_' . substr(md5($name), 0, 6), $name, $usedKeys);
            }

            $perms = $this->resolvePermissionsFromResponsibilities(
                $responsibilities, $rd['department'] ?? null, $corePerms, $allPerms, $f
            );

            $role = [
                'key'         => $key,
                'name'        => $name,
                'description' => implode(', ', $responsibilities) ?: 'Operational role',
                'status'      => 'recommended',
                'permissions' => $perms,
            ];
            if (isset($rd['headcount'])) {
                $role['headcount'] = (int) $rd['headcount'];
            }
            if (isset($rd['department'])) {
                $deptKey = $resolveDeptKey($rd['department'], $deptRegistry);
                if ($deptKey) $role['department_key'] = $deptKey;
            }

            $roles[] = $role;
        }

        // Safety net: if no discovered owner was found, add a platform owner
        if (!$hasOwnerLike) {
            array_unshift($roles, [
                'key'=>'owner','name'=>'Owner','description'=>'Full system access and ownership',
                'status'=>'required','permissions'=>$ownerPerms,'is_primary_owner'=>true,
            ]);
        }

        return $roles;
    }

    /**
     * Build roles from flat role name list (no structured details).
     */
    private function buildNamedRoles(
        array $roleNames, array $ownerPerms, array $corePerms,
        array $allPerms, callable $generateEntityKey
    ): array {
        $roles = [
            ['key'=>'owner','name'=>'Owner','description'=>'Full system access and ownership',
             'status'=>'required','permissions'=>$ownerPerms,'is_primary_owner'=>true],
        ];
        $usedKeys = ['owner'];

        foreach ($roleNames as $name) {
            $key = $generateEntityKey('role', $name, $usedKeys);
            if (in_array($key, ['owner', 'admin'])) continue;

            $perms = $this->resolvePermissionsFromResponsibilities(
                [], null, $corePerms, $allPerms, []
            );

            $roles[] = [
                'key'         => $key,
                'name'        => ucwords(str_replace('_', ' ', $name)),
                'description' => 'Operational role',
                'status'      => 'recommended',
                'permissions' => $perms,
            ];
        }
        return $roles;
    }

    /**
     * Build template roles (when no discovered roles exist at all).
     * Only this path includes both Owner and Admin.
     */
    private function buildTemplateRoles(
        string $type, array $ownerPerms, array $adminPerms, array $corePerms
    ): array {
        $viewFinance = ['accounting.view','accounts.list','accounts.show','accounts.create','accounts.update','accounts.delete','journal_entries.list','journal_entries.show','journal_entries.create','journal_entries.update','invoices.list','invoices.show','invoices.create','invoices.update','payments.list','payments.show','payments.create','reports.view'];
        $salesPerms = array_merge($corePerms,['contacts.list','contacts.show','contacts.create','contacts.update','contacts.own','contacts.manage_team','products.list','products.show','invoices.list','invoices.show','invoices.create','orders.list','orders.show','orders.create','orders.update','payments.list','payments.show','payments.create','pipelines.list','pipeline_records.create','pipeline_records.update','pipeline_records.own','pipeline_records.manage_team','reports.view']);
        $inventoryPerms = array_merge($corePerms,['products.list','products.show','inventory.list','inventory.show','inventory.create','warehouses.list','warehouses.show','warehouses.create','warehouses.update','reservations.list','reservations.show','reservations.create','reservations.update']);
        $cashierPerms = array_merge($corePerms,['pos.view','orders.list','orders.show','orders.create','orders.update','invoices.list','invoices.show','invoices.create','payments.list','payments.show','payments.create','products.list','products.show']);

        $roles = [
            ['key'=>'owner','name'=>'Owner','description'=>'Full system access and ownership','status'=>'required','permissions'=>$ownerPerms,'is_primary_owner'=>true],
            ['key'=>'admin','name'=>'Admin','description'=>'Full system access and user management','status'=>'required','permissions'=>$adminPerms],
        ];

        $typeRoles = match($type) {
            'retail' => [
                ['key'=>'store_manager','name'=>'Store Manager','description'=>'Sales, inventory, limited reports','status'=>'recommended','department_key'=>'sales','permissions'=>array_merge($salesPerms,$inventoryPerms)],
                ['key'=>'cashier','name'=>'Cashier','description'=>'POS and payment processing','status'=>'recommended','department_key'=>'sales','permissions'=>$cashierPerms],
                ['key'=>'inventory_clerk','name'=>'Inventory Clerk','description'=>'Stock management','status'=>'recommended','department_key'=>'warehouse','permissions'=>$inventoryPerms],
                ['key'=>'accountant','name'=>'Accountant','description'=>'Financial management','status'=>'recommended','department_key'=>'finance','permissions'=>array_merge($corePerms,$viewFinance)],
            ],
            'restaurant' => [
                ['key'=>'manager','name'=>'Restaurant Manager','description'=>'Floor operations and reports','status'=>'recommended','department_key'=>'management','permissions'=>array_merge($salesPerms,$inventoryPerms)],
                ['key'=>'waiter','name'=>'Waiter','description'=>'Order taking and POS','status'=>'recommended','department_key'=>'service','permissions'=>$cashierPerms],
                ['key'=>'kitchen_staff','name'=>'Kitchen Staff','description'=>'Order queue and inventory','status'=>'recommended','department_key'=>'kitchen','permissions'=>array_merge($corePerms,['orders.list','orders.show','orders.update','inventory.list','inventory.show','products.list','products.show'])],
                ['key'=>'accountant','name'=>'Accountant','description'=>'Financial management','status'=>'optional','department_key'=>'finance','permissions'=>array_merge($corePerms,$viewFinance)],
            ],
            'service' => [
                ['key'=>'project_manager','name'=>'Project Manager','description'=>'Client and project management','status'=>'recommended','department_key'=>'operations','permissions'=>array_merge($corePerms,['contacts.list','contacts.show','contacts.create','contacts.update','contacts.own','contacts.manage_team','invoices.list','invoices.show','invoices.create','invoices.update','orders.list','orders.show','orders.create','orders.update','payments.list','payments.show','reports.view','pipelines.list','pipeline_records.create','pipeline_records.update','pipeline_records.own'])],
                ['key'=>'team_member','name'=>'Team Member','description'=>'View projects and tasks','status'=>'recommended','department_key'=>'operations','permissions'=>array_merge($corePerms,['orders.list','orders.show','contacts.list','contacts.show','products.list','products.show'])],
                ['key'=>'accountant','name'=>'Accountant','description'=>'Financial management','status'=>'recommended','department_key'=>'finance','permissions'=>array_merge($corePerms,$viewFinance)],
            ],
            'manufacturing' => [
                ['key'=>'production_manager','name'=>'Production Manager','description'=>'Production and BOM management','status'=>'required','department_key'=>'production','permissions'=>array_merge($corePerms,['products.list','products.show','products.create','products.update','bom.list','bom.show','bom.create','bom.update','bom.delete','production.list','production.show','production.create','production.update','inventory.list','inventory.show','inventory.create','warehouses.list','warehouses.show','reports.view'])],
                ['key'=>'warehouse_staff','name'=>'Warehouse Staff','description'=>'Stock movements','status'=>'recommended','department_key'=>'warehouse','permissions'=>$inventoryPerms],
                ['key'=>'accountant','name'=>'Accountant','description'=>'Financial management','status'=>'recommended','department_key'=>'finance','permissions'=>array_merge($corePerms,$viewFinance)],
            ],
            'distribution' => [
                ['key'=>'sales_manager','name'=>'Sales Manager','description'=>'Sales and customer management','status'=>'recommended','department_key'=>'sales','permissions'=>$salesPerms],
                ['key'=>'warehouse_manager','name'=>'Warehouse Manager','description'=>'Inventory and shipping','status'=>'required','department_key'=>'warehouse','permissions'=>$inventoryPerms],
                ['key'=>'accountant','name'=>'Accountant','description'=>'Financial management','status'=>'recommended','department_key'=>'finance','permissions'=>array_merge($corePerms,$viewFinance)],
            ],
            default => [
                ['key'=>'manager','name'=>'Manager','description'=>'Operations management','status'=>'recommended','permissions'=>array_merge($salesPerms,$inventoryPerms)],
                ['key'=>'accountant','name'=>'Accountant','description'=>'Financial management','status'=>'recommended','permissions'=>array_merge($corePerms,$viewFinance)],
            ],
        };

        return array_merge($roles, $typeRoles);
    }

    // ═══════════════════════════════════════════════════════════════
    //  Owner detection
    // ═══════════════════════════════════════════════════════════════

    /**
     * Detect whether a discovered role represents the business owner/founder.
     *
     * Uses semantic signals from role name, responsibilities and scope —
     * not hardcoded language-specific names.
     */
    private function isOwnerLikeRole(array $rd): bool
    {
        $name = mb_strtolower(trim($rd['name'] ?? ''));
        $responsibilities = array_map('mb_strtolower', $rd['responsibilities'] ?? []);
        $respText = implode(' ', $responsibilities);

        // English owner signals
        if (in_array($name, ['owner', 'founder', 'ceo', 'business owner', 'managing director'])) {
            return true;
        }

        // Arabic owner signals
        $ownerNames = ['مالك', 'صاحب', 'مؤسس', 'المدير العام', 'مدير عام', 'رئيس تنفيذي'];
        foreach ($ownerNames as $ownerName) {
            if (mb_strpos($name, $ownerName) !== false) return true;
        }

        // Responsibility signals: "manages the entire company"
        $ownerSignals = ['يدير الشركة', 'إدارة الشركة', 'manages the company',
            'full access', 'manages everything', 'يدير كل شيء', 'إدارة كاملة', 'بالكامل'];
        foreach ($ownerSignals as $signal) {
            if (mb_strpos($respText, $signal) !== false) return true;
        }

        return false;
    }

    // ═══════════════════════════════════════════════════════════════
    //  Responsibility-based permission resolution
    // ═══════════════════════════════════════════════════════════════

    /**
     * Resolve permissions from discovered responsibilities and department scope.
     *
     * Maps Arabic and English responsibility descriptions to permission groups.
     * Ensures least privilege — only grants permissions for described actions.
     */
    public function resolvePermissionsFromResponsibilities(
        array $responsibilities, ?string $department,
        array $corePerms, array $allPerms, array $facts
    ): array {
        $perms = $corePerms;

        $respText = mb_strtolower(implode(' ', $responsibilities));
        $deptLower = mb_strtolower($department ?? '');

        // ── Sales / CRM ──────────────────────────────────────────
        // Customer contacts and basic sales operations
        $salesContactSignals = ['مبيعات', 'عملاء', 'عروض', 'أسعار',
            'sales', 'customers', 'quotation'];
        $hasSalesContacts = $this->matchesAnySignal($respText, $salesContactSignals)
            || $this->matchesAnySignal($deptLower, ['مبيعات', 'sales']);

        if ($hasSalesContacts) {
            $perms = array_merge($perms, [
                'contacts.list','contacts.show','contacts.create','contacts.update','contacts.own',
                'products.list','products.show',
                'invoices.list','invoices.show','invoices.create',
                'orders.list','orders.show','orders.create','orders.update',
                'payments.list','payments.show',
            ]);
        }

        // ── Pipeline / Deals ─────────────────────────────────────
        // Only when responsibilities explicitly mention pipeline/deal/lead/opportunity
        $pipelineSignals = ['فرص', 'صفقات', 'pipeline', 'leads', 'opportunities', 'deals'];
        $hasPipeline = $this->matchesAnySignal($respText, $pipelineSignals);

        if ($hasPipeline) {
            $perms = array_merge($perms, [
                'pipelines.list',
                'pipeline_records.create','pipeline_records.update','pipeline_records.own',
            ]);
        }

        // ── Sales management (team supervision, reports) ─────────
        $mgmtSignals = ['يتابع فريق', 'يدير فريق', 'يتابع الصفقات', 'مدير',
            'manager', 'manage team', 'supervise', 'team lead', 'مشرف'];
        $isManager = $this->matchesAnySignal($respText, $mgmtSignals);

        if ($isManager && $hasSalesContacts) {
            $perms = array_merge($perms, [
                'contacts.manage_team','reports.view',
            ]);
            if ($hasPipeline) {
                $perms[] = 'pipeline_records.manage_team';
            }
        }

        // ── Inventory / Warehouse ────────────────────────────────
        $inventorySignals = ['مخزون', 'مستودع', 'منتجات', 'حركة', 'استلام', 'صرف',
            'inventory', 'warehouse', 'stock', 'products', 'receiving', 'issuing'];
        $hasInventory = $this->matchesAnySignal($respText, $inventorySignals)
            || $this->matchesAnySignal($deptLower, ['مخزون', 'مستودع', 'warehouse', 'inventory']);

        if ($hasInventory) {
            $perms = array_merge($perms, [
                'products.list','products.show',
                'inventory.list','inventory.show','inventory.create',
                'warehouses.list','warehouses.show',
                'reservations.list','reservations.show',
            ]);
        }

        // ── Inventory management (product CRUD, warehouse config) ─
        $inventoryMgmtSignals = ['مسؤول عن المنتجات', 'مسؤول عن المستودع', 'مدير مخزون',
            'inventory manager', 'warehouse manager', 'product management'];
        if ($this->matchesAnySignal($respText, $inventoryMgmtSignals)
            || ($isManager && $hasInventory)) {
            $perms = array_merge($perms, [
                'products.create','products.update',
                'warehouses.create','warehouses.update',
                'reservations.create','reservations.update',
                'reports.view',
            ]);
        }

        // ── Finance / Accounting ─────────────────────────────────
        $financeSignals = ['فواتير', 'مدفوعات', 'مصروفات', 'تقارير مالية', 'محاسب',
            'invoices', 'payments', 'expenses', 'financial', 'accounting', 'accountant'];
        $hasFinance = $this->matchesAnySignal($respText, $financeSignals)
            || $this->matchesAnySignal($deptLower, ['مالية', 'محاسبة', 'finance', 'accounting']);

        if ($hasFinance) {
            $perms = array_merge($perms, [
                'accounting.view',
                'accounts.list','accounts.show','accounts.create','accounts.update',
                'journal_entries.list','journal_entries.show','journal_entries.create','journal_entries.update',
                'invoices.list','invoices.show','invoices.create','invoices.update',
                'payments.list','payments.show','payments.create',
                'reports.view',
            ]);
        }

        // ── POS / Cashier ────────────────────────────────────────
        $posSignals = ['نقطة البيع', 'كاشير', 'عمليات الدفع', 'pos', 'cashier', 'point of sale'];
        $hasPOS = $this->matchesAnySignal($respText, $posSignals);

        if ($hasPOS) {
            $perms = array_merge($perms, [
                'pos.view',
                'orders.list','orders.show','orders.create','orders.update',
                'invoices.list','invoices.show','invoices.create',
                'payments.list','payments.show','payments.create',
                'products.list','products.show',
            ]);
        }

        // Deduplicate, filter to valid catalog keys, sort
        $perms = array_values(array_unique($perms));
        $perms = array_values(array_intersect($perms, $allPerms));
        sort($perms);

        return $perms;
    }

    // ═══════════════════════════════════════════════════════════════
    //  Department semantic classification
    // ═══════════════════════════════════════════════════════════════

    /**
     * Map of department keys and names to semantic categories.
     */
    private function departmentSemanticMap(): array
    {
        return [
            // Template keys
            'management' => 'management', 'sales' => 'sales', 'warehouse' => 'warehouse',
            'finance' => 'finance', 'operations' => 'operations', 'kitchen' => 'kitchen',
            'service' => 'service', 'production' => 'production', 'logistics' => 'logistics',
            // English names
            'accounting' => 'finance', 'inventory' => 'warehouse',
            // Arabic names
            'الإدارة' => 'management', 'إدارة' => 'management',
            'المبيعات' => 'sales', 'مبيعات' => 'sales',
            'المستودع' => 'warehouse', 'المستودعات' => 'warehouse', 'مستودع' => 'warehouse',
            'المخزون' => 'warehouse', 'مخزون' => 'warehouse',
            'المالية' => 'finance', 'مالية' => 'finance', 'المحاسبة' => 'finance', 'محاسبة' => 'finance',
            'العمليات' => 'operations', 'عمليات' => 'operations',
            'الإنتاج' => 'production', 'إنتاج' => 'production',
            'المطبخ' => 'kitchen', 'الخدمة' => 'service',
            'اللوجستيات' => 'logistics', 'الشحن' => 'logistics',
        ];
    }

    /**
     * Classify a department name to its semantic category.
     */
    private function classifyDepartmentSemantic(string $name, array $map): ?string
    {
        $normalized = mb_strtolower(trim($name));
        if (isset($map[$normalized])) return $map[$normalized];
        if (isset($map[trim($name)])) return $map[trim($name)];
        return null;
    }

    /**
     * Check if text contains any of the given signal keywords.
     */
    private function matchesAnySignal(string $text, array $signals): bool
    {
        foreach ($signals as $signal) {
            if (mb_strpos($text, $signal) !== false) return true;
        }
        return false;
    }
}
