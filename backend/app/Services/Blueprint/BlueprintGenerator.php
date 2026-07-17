<?php

namespace App\Services\Blueprint;

use App\Services\PermissionCatalog;

/**
 * Maps discovery facts + business templates into canonical Blueprint schema.
 * Priority: explicit user facts → corrections → safe assumptions → template defaults.
 */
class BlueprintGenerator
{
    public function generate(string $businessType, array $knownFacts, array $assumptions = []): array
    {
        // ── Normalize locale-sensitive fact values to ISO codes ────
        // Currency, country, and language are normalized once here.
        // All downstream builders receive canonical ISO values.
        $knownFacts = $this->normalizeFactValues($knownFacts);

        $bp = BlueprintSchema::empty();
        $bp['business_profile'] = $this->buildBusinessProfile($businessType, $knownFacts);
        $bp['workspace_settings'] = $this->buildWorkspaceSettings($knownFacts, $assumptions);
        $bp['modules'] = $this->buildModules($businessType, $knownFacts);

        // ── Build departments first, creating a canonical registry ─────
        // Discovered role departments are merged into template departments.
        // The registry maps display name → actual generated key.
        $deptRegistry = [];
        $bp['departments'] = $this->buildDepartments($businessType, $knownFacts, $deptRegistry);

        // ── Build teams and roles using the department registry ─────
        $bp['teams'] = $this->buildTeams($businessType, $knownFacts, $deptRegistry);
        // Extract enabled module keys so owner permissions are scoped
        $enabledModuleKeys = array_column(
            array_filter($bp['modules'], fn(array $m) => $m['enabled']),
            'key'
        );
        $bp['roles'] = $this->buildRoles($businessType, $knownFacts, $deptRegistry, $enabledModuleKeys);

        // ── Prune template departments with no references ──────────
        // Removes unused template depts (like management/operations) when
        // discovered departments already cover the business structure.
        $bp['departments'] = $this->pruneUnusedDepartments(
            $bp['departments'], $bp['roles'], $bp['teams']
        );

        $bp['locations'] = $this->buildLocations($businessType, $knownFacts);
        $locationKeys = array_column($bp['locations'], 'key');
        $bp['warehouses'] = $this->buildWarehouses($knownFacts, $locationKeys);
        $bp['payment_methods'] = $this->buildPaymentMethods($knownFacts);
        $bp['tax_settings'] = $this->buildTaxSettings($knownFacts);
        $bp['invoice_settings'] = $this->buildInvoiceSettings($knownFacts);
        $bp['pos_settings'] = $this->buildPosSettings($knownFacts, $locationKeys);
        $bp['pipelines'] = $this->buildPipelines($businessType, $knownFacts);
        $bp['approval_workflows'] = $this->buildApprovalWorkflows($knownFacts);
        $bp['commission_rules'] = $this->buildCommissionRules($knownFacts);
        $bp['accounting_settings'] = $this->buildAccountingSettings($knownFacts);
        $bp['localization'] = $this->buildLocalization($knownFacts);
        $bp['ai_settings'] = ['enabled' => true];
        $bp['assumptions'] = $assumptions;
        $bp['missing_optional_information'] = $this->buildMissing($knownFacts);
        $bp['metadata'] = ['generator' => 'canonical_v1', 'generated_at' => now()->toISOString()];

        // ── Final referential integrity guard ─────────────────
        $this->validateLocalReferences($bp);

        return $bp;
    }

    private function buildBusinessProfile(string $type, array $f): array
    {
        return array_filter([
            'business_name' => $f['business_name'] ?? null,
            'business_description' => $f['business_description'] ?? null,
            'business_type' => $type,
            'company_size' => $f['company_size'] ?? $this->inferSize($f),
            'employee_count' => $f['employee_count'] ?? null,
            'branch_count' => $f['branch_count'] ?? null,
            'customer_types' => $f['customer_types'] ?? null,
            'sells_products' => $f['sells_products'] ?? null,
            'sells_services' => $f['sells_services'] ?? null,
            'sales_channels' => $f['sales_channels'] ?? null,
        ], fn($v) => $v !== null);
    }

    private function inferSize(array $f): string
    {
        $emp = $f['employee_count'] ?? 0;
        if ($emp <= 5) return 'micro';
        if ($emp <= 20) return 'small';
        if ($emp <= 100) return 'medium';
        return 'large';
    }

    private function buildWorkspaceSettings(array $f, array $assumptions): array
    {
        $settings = array_filter([
            'country' => $f['country'] ?? null,
            'currency' => $f['currency'] ?? null,
            'timezone' => $f['timezone'] ?? null,
            'primary_language' => $f['primary_language'] ?? null,
        ], fn($v) => $v !== null);
        // Infer timezone from country if missing
        if (empty($settings['timezone']) && !empty($settings['country'])) {
            $tz = $this->inferTimezone($settings['country']);
            if ($tz) $settings['timezone'] = $tz;
        }
        return $settings;
    }

    private function inferTimezone(string $country): ?string
    {
        // Accept both display names and ISO country codes
        $map = ['Saudi Arabia'=>'Asia/Riyadh','UAE'=>'Asia/Dubai','Egypt'=>'Africa/Cairo',
            'Jordan'=>'Asia/Amman','Kuwait'=>'Asia/Kuwait','Qatar'=>'Asia/Qatar',
            'Bahrain'=>'Asia/Bahrain','Oman'=>'Asia/Muscat','Iraq'=>'Asia/Baghdad',
            'Lebanon'=>'Asia/Beirut','Turkey'=>'Europe/Istanbul','Pakistan'=>'Asia/Karachi',
            'India'=>'Asia/Kolkata','Malaysia'=>'Asia/Kuala_Lumpur','Singapore'=>'Asia/Singapore',
            'Libya'=>'Africa/Tripoli','Morocco'=>'Africa/Casablanca','Tunisia'=>'Africa/Tunis',
            'Algeria'=>'Africa/Algiers','Sudan'=>'Africa/Khartoum','Yemen'=>'Asia/Aden',
            // ISO codes
            'SA'=>'Asia/Riyadh','AE'=>'Asia/Dubai','EG'=>'Africa/Cairo',
            'JO'=>'Asia/Amman','KW'=>'Asia/Kuwait','QA'=>'Asia/Qatar',
            'BH'=>'Asia/Bahrain','OM'=>'Asia/Muscat','IQ'=>'Asia/Baghdad',
            'LB'=>'Asia/Beirut','TR'=>'Europe/Istanbul','PK'=>'Asia/Karachi',
            'IN'=>'Asia/Kolkata','MY'=>'Asia/Kuala_Lumpur','SG'=>'Asia/Singapore',
            'LY'=>'Africa/Tripoli','MA'=>'Africa/Casablanca','TN'=>'Africa/Tunis',
            'DZ'=>'Africa/Algiers','SD'=>'Africa/Khartoum','YE'=>'Asia/Aden',
        ];
        return $map[$country] ?? null;
    }

    private function buildModules(string $type, array $f): array
    {
        $profiles = [
            'retail' => ['required'=>['dashboard','customers','products','invoices','payments','orders','employees','reports','finance'],'recommended'=>['inventory','pos','commissions','ai','leads'],'optional'=>['spare_parts','parts_inventory','jobs']],
            'restaurant' => ['required'=>['dashboard','customers','products','invoices','payments','orders','employees','reports','finance'],'recommended'=>['inventory','pos','menu','tables','ai'],'optional'=>['commissions','leads']],
            'service' => ['required'=>['dashboard','customers','invoices','payments','employees','reports','finance'],'recommended'=>['projects','tasks','ai','leads'],'optional'=>['products','orders','inventory','commissions','jobs']],
            'manufacturing' => ['required'=>['dashboard','customers','products','invoices','payments','orders','employees','reports','finance','inventory'],'recommended'=>['ai'],'optional'=>['commissions','leads','pos','spare_parts']],
            'distribution' => ['required'=>['dashboard','customers','products','invoices','payments','orders','employees','reports','finance','inventory'],'recommended'=>['commissions','ai','leads'],'optional'=>['pos','spare_parts','parts_inventory']],
        ];
        $profile = $profiles[$type] ?? $profiles['service'];
        $modules = [];
        $allKeys = array_unique(array_merge($profile['required'], $profile['recommended'], $profile['optional']));
        // First pass: determine enabled modules
        $enabledKeys = [];
        foreach ($allKeys as $key) {
            if (!BlueprintSchema::isValidModuleKey($key)) continue;
            $status = in_array($key, $profile['required']) ? 'required' : (in_array($key, $profile['recommended']) ? 'recommended' : 'optional');
            $enabled = $status !== 'optional';
            // Override from facts
            if ($key === 'inventory' && ($f['uses_inventory'] ?? false)) { $status = 'required'; $enabled = true; }
            if ($key === 'inventory' && isset($f['uses_inventory']) && !$f['uses_inventory'] && $type === 'service') { $enabled = false; }
            if ($key === 'pos' && ($f['uses_pos'] ?? false)) { $status = 'recommended'; $enabled = true; }
            // Commissions requires explicit fact — template recommended alone is insufficient
            if ($key === 'commissions') {
                $hasCommissionFact = ($f['uses_commissions'] ?? false)
                    || isset($f['commission_model'])
                    || !empty($f['commission_approval_required']);
                if ($hasCommissionFact) { $status = 'recommended'; $enabled = true; }
                else { $status = 'optional'; $enabled = false; }
            }
            if ($key === 'products' && ($f['sells_products'] ?? false)) { $status = 'required'; $enabled = true; }
            if ($enabled) $enabledKeys[] = $key;
            $modules[] = ['key'=>$key, 'status'=>$status, 'enabled'=>$enabled, 'reason'=>$this->moduleReason($key, $status, $type, $f)];
        }
        // Auto-include required dependencies for enabled modules
        $depsAdded = true;
        while ($depsAdded) {
            $depsAdded = false;
            foreach ($enabledKeys as $ek) {
                foreach (BlueprintSchema::moduleDependencies($ek) as $dep) {
                    if (!in_array($dep, $enabledKeys, true) && BlueprintSchema::isValidModuleKey($dep)) {
                        $enabledKeys[] = $dep;
                        $modules[] = ['key'=>$dep, 'status'=>'required', 'enabled'=>true, 'reason'=>"Required dependency of '{$ek}'"];
                        $depsAdded = true;
                    }
                }
            }
        }
        return $modules;
    }

    private function moduleReason(string $key, string $status, string $type, array $f): string
    {
        $reasons = [
            'dashboard'=>'Core system dashboard','customers'=>'Customer management','products'=>'Product catalog',
            'invoices'=>'Invoicing','payments'=>'Payment processing','orders'=>'Order management',
            'employees'=>'Employee management','reports'=>'Business reports','finance'=>'Financial management',
            'inventory'=>'Stock tracking','pos'=>'Point of sale','commissions'=>'Sales commissions',
            'ai'=>'AI assistant','leads'=>'Lead management','projects'=>'Project management',
            'tasks'=>'Task management','menu'=>'Menu management','tables'=>'Table management',
            'spare_parts'=>'Spare parts','parts_inventory'=>'Parts inventory','jobs'=>'Job tracking',
            'vehicles'=>'Vehicle management','vehicle_sales'=>'Vehicle sales',
        ];
        return $reasons[$key] ?? "Module: {$key}";
    }

    /**
     * Build departments from template + discovered role departments.
     * Delegates to BlueprintRoleBuilder for semantic deduplication.
     *
     * @param array &$registry  Output registry: normalized display name → actual key
     */
    private function buildDepartments(string $type, array $f, array &$registry): array
    {
        $builder = new BlueprintRoleBuilder();
        return $builder->buildDepartments(
            $type, $f, $registry,
            fn(string $prefix, string $name, array &$used) => $this->generateEntityKey($prefix, $name, $used)
        );
    }

    /**
     * Build teams, resolving department_key through the canonical registry.
     */
    private function buildTeams(string $type, array $f, array $deptRegistry): array
    {
        if (($f['employee_count'] ?? 0) < 10 && !($f['has_teams'] ?? false)) return [];
        $profiles = [
            'retail'=>[['key'=>'sales_team','name'=>'Sales Team','department_key'=>'sales','purpose'=>'Direct sales']],
            'distribution'=>[['key'=>'sales_team','name'=>'Sales Team','department_key'=>'sales','purpose'=>'Customer sales'],['key'=>'warehouse_team','name'=>'Warehouse Team','department_key'=>'warehouse','purpose'=>'Stock operations']],
            'service'=>[['key'=>'delivery_team','name'=>'Delivery Team','department_key'=>'operations','purpose'=>'Service delivery']],
        ];
        $teams = $profiles[$type] ?? [];

        foreach ($teams as &$team) {
            if (isset($team['department_key'])) {
                $team['department_key'] = $this->resolveDeptKey($team['department_key'], $deptRegistry);
            }
        }
        unset($team);

        return $teams;
    }

    /**
     * Build roles. Delegates to BlueprintRoleBuilder for:
     *   - Owner/Admin deduplication with discovered roles
     *   - Responsibility-based permission resolution
     *   - Multilingual semantic matching
     */
    private function buildRoles(string $type, array $f, array $deptRegistry = [], array $enabledModuleKeys = []): array
    {
        $builder = new BlueprintRoleBuilder();
        return $builder->buildRoles(
            $type, $f, $deptRegistry,
            fn(string $prefix, string $name, array &$used) => $this->generateEntityKey($prefix, $name, $used),
            fn(string $nameOrKey, array $reg) => $this->resolveDeptKey($nameOrKey, $reg),
            $enabledModuleKeys
        );
    }

    /**
     * Remove template departments that have no references from roles or teams.
     *
     * Discovered departments are always kept (they came from the user's data).
     * Template departments (status='required'/'recommended' with template keys
     * like 'management', 'operations') are pruned when no role or team
     * references them via department_key.
     */
    private function pruneUnusedDepartments(array $departments, array $roles, array $teams): array
    {
        // Collect all referenced department keys
        $referencedKeys = [];
        foreach ($roles as $role) {
            if (isset($role['department_key'])) {
                $referencedKeys[$role['department_key']] = true;
            }
        }
        foreach ($teams as $team) {
            if (isset($team['department_key'])) {
                $referencedKeys[$team['department_key']] = true;
            }
        }

        return array_values(array_filter($departments, function (array $dept) use ($referencedKeys) {
            // Always keep departments that are referenced
            if (isset($referencedKeys[$dept['key']])) return true;

            // Keep discovered departments (non-template, generated keys)
            // Template departments use simple lowercase keys like 'management', 'sales'
            // Discovered departments use generated keys like 'dept_f155c092'
            if (str_starts_with($dept['key'], 'dept_')) return true;

            // Unreferenced template department — prune it
            return false;
        }));
    }

    /**
     * Generate a deterministic, schema-valid technical key from a display name.
     *
     * Must match: ^[a-z][a-z0-9_]{1,63}$
     *
     * For ASCII-transliterable names: produces clean snake_case.
     * For non-ASCII (Arabic/etc): uses deterministic hash with entity prefix.
     * Handles collisions by appending incremental suffixes.
     *
     * @param string $prefix Entity type prefix (role, dept, etc.)
     * @param string $name   Display name to derive key from
     * @param array  &$usedKeys Reference to array of already-used keys (updated in place)
     */
    private function generateEntityKey(string $prefix, string $name, array &$usedKeys = []): string
    {
        $cleaned = trim($name);

        // Try ASCII transliteration first
        if (function_exists('transliterator_transliterate')) {
            $ascii = transliterator_transliterate('Any-Latin; Latin-ASCII; Lower()', $cleaned);
        } else {
            $ascii = mb_strtolower($cleaned);
        }

        // Remove non-alphanumeric except spaces/underscores, then snake_case
        $ascii = preg_replace('/[^a-z0-9\s_]/', '', $ascii);
        $ascii = preg_replace('/[\s_]+/', '_', trim($ascii));

        // If transliteration produced a usable key
        if (preg_match('/^[a-z][a-z0-9_]{1,63}$/', $ascii)) {
            $candidate = $ascii;
        } else {
            // Non-ASCII name: use deterministic hash with prefix
            $hash = substr(md5($cleaned), 0, 8);
            $candidate = $prefix . '_' . $hash;
        }

        // Ensure uniqueness
        $base = $candidate;
        $suffix = 2;
        while (in_array($candidate, $usedKeys, true)) {
            $candidate = $base . '_' . $suffix;
            $suffix++;
        }
        $usedKeys[] = $candidate;

        return $candidate;
    }

    private function buildLocations(string $type, array $f): array
    {
        $country = $f['country'] ?? null;
        $timezone = $country ? $this->inferTimezone($country) : null;
        $namedLocations = $f['location_names'] ?? $f['branch_names'] ?? [];
        $branchCount = max(1, (int) ($f['branch_count'] ?? 1));
        $isVirtual = $type === 'service' && !($f['sells_products'] ?? false) && !($f['uses_pos'] ?? false) && !($f['uses_inventory'] ?? false);

        // Determine location type from business type
        $locType = match($type) {
            'restaurant' => 'restaurant',
            'retail' => 'store',
            'service' => $isVirtual ? 'virtual' : 'office',
            default => 'branch',
        };

        // Virtual company: one virtual location
        if ($isVirtual) {
            return [[
                'key' => 'main_location',
                'name' => $f['business_name'] ?? 'Main Office',
                'type' => 'virtual',
                'status' => 'required',
                'is_primary' => true,
                'country' => $country,
                'timezone' => $timezone,
            ]];
        }

        // Named locations provided
        if (!empty($namedLocations)) {
            $usedKeys = [];
            $locations = [];
            foreach ($namedLocations as $i => $name) {
                $key = $this->generateEntityKey('location', trim($name), $usedKeys);
                $locations[] = [
                    'key' => $key,
                    'name' => trim($name),
                    'type' => $locType,
                    'status' => 'recommended',
                    'is_primary' => $i === 0,
                    'country' => $country,
                    'timezone' => $timezone,
                ];
            }
            return $locations;
        }

        // Count-based: generate reviewable placeholders
        $locations = [];
        for ($i = 1; $i <= min($branchCount, 10); $i++) {
            $locations[] = [
                'key' => $branchCount === 1 ? 'main_location' : "branch_{$i}",
                'name' => $branchCount === 1 ? 'Main Location' : "Branch {$i}",
                'type' => $locType,
                'status' => 'recommended',
                'is_primary' => $i === 1,
                'country' => $country,
                'timezone' => $timezone,
            ];
        }
        return $locations;
    }

    private function buildWarehouses(array $f, array $locationKeys = []): array
    {
        if (isset($f['uses_inventory']) && !$f['uses_inventory']) return [];
        if (!($f['uses_inventory'] ?? false) && !($f['warehouse_count'] ?? 0) && empty($f['warehouse_details'])) return [];

        $warehouseDetails = $f['warehouse_details'] ?? [];
        $count = max(1, count($warehouseDetails) ?: ($f['warehouse_count'] ?? (($f['branch_count'] ?? 1) > 1 ? $f['branch_count'] : 1)));

        $warehouses = [];

        if (!empty($warehouseDetails)) {
            // ── Discovered warehouses with names/purposes ──────────
            $usedKeys = [];
            foreach ($warehouseDetails as $i => $wd) {
                $name = $wd['name'] ?? ('Warehouse ' . ($i + 1));
                $key = $this->generateEntityKey('warehouse', $name, $usedKeys);

                $wh = [
                    'key'        => $key,
                    'name'       => $name,
                    'status'     => 'recommended',
                    'is_default' => $i === 0,
                    'scope'      => !empty($locationKeys) ? 'location' : 'workspace',
                ];
                if (!empty($wd['purpose'])) {
                    $wh['purpose'] = $wd['purpose'];
                }
                if (!empty($locationKeys) && isset($locationKeys[$i])) {
                    $wh['branch_key'] = $locationKeys[$i];
                } elseif (!empty($locationKeys)) {
                    $wh['branch_key'] = $locationKeys[0];
                }
                $warehouses[] = $wh;
            }
        } else {
            // ── Fallback: count-based generic names ────────────────
            for ($i = 1; $i <= min($count, 10); $i++) {
                $wh = [
                    'key'        => "warehouse_{$i}",
                    'name'       => $count === 1 ? 'Main Warehouse' : "Warehouse {$i}",
                    'status'     => 'recommended',
                    'is_default' => $i === 1,
                    'scope'      => !empty($locationKeys) ? 'location' : 'workspace',
                ];
                if (!empty($locationKeys) && isset($locationKeys[$i - 1])) {
                    $wh['branch_key'] = $locationKeys[$i - 1];
                } elseif (!empty($locationKeys)) {
                    $wh['branch_key'] = $locationKeys[0];
                }
                $warehouses[] = $wh;
            }
        }

        return $warehouses;
    }

    private function buildPaymentMethods(array $f): array
    {
        $methods = $f['payment_methods'] ?? [];
        if (empty($methods)) return [];
        $result = [];
        $seen = [];
        foreach ($methods as $m) {
            $key = is_string($m) ? strtolower(str_replace(' ', '_', $m)) : ($m['key'] ?? 'unknown');
            // Normalize common variants
            if ($key === 'credit_card') $key = 'card';
            // Skip unsupported or duplicate
            if (!in_array($key, BlueprintSchema::VALID_PAYMENT_TYPES, true)) continue;
            if (in_array($key, $seen, true)) continue;
            $seen[] = $key;
            $result[] = ['key'=>$key, 'name'=>ucfirst(str_replace('_', ' ', $key)), 'enabled'=>true];
        }
        return $result;
    }

    private function buildTaxSettings(array $f): array
    {
        $tax = $f['tax_requirements'] ?? null;
        if (!$tax || $tax === 'none') return ['tax_enabled'=>false];
        return ['tax_enabled'=>true, 'tax_model'=>'percentage', 'tax_inclusive'=>false, 'country_assumption'=>$f['country'] ?? null];
    }

    private function buildInvoiceSettings(array $f): array
    {
        if (!($f['uses_invoicing'] ?? false)) return [];
        return ['enabled'=>true,'auto_numbering'=>true,'default_due_days'=>30];
    }

    private function buildPosSettings(array $f, array $locationKeys = []): array
    {
        if (!($f['uses_pos'] ?? false)) return [];
        $pos = ['enabled' => true];
        // Reference non-virtual operating locations for POS
        if (!empty($locationKeys)) {
            $pos['location_keys'] = $locationKeys;
        }
        return $pos;
    }

    private function buildPipelines(string $type, array $f): array
    {
        if (!in_array($type, ['retail','distribution','service','hybrid'])) return [];

        // ── Discovered pipeline stages take precedence ──────────
        $pipelineDetails = $f['pipeline_details'] ?? [];
        if (!empty($pipelineDetails)) {
            $pipelines = [];
            $usedPipelineKeys = [];
            foreach ($pipelineDetails as $pd) {
                $name = $pd['name'] ?? 'Sales Pipeline';
                $key = $this->generateEntityKey('pipeline', $name, $usedPipelineKeys);

                $stages = [];
                $usedStageKeys = [];
                foreach (($pd['stages'] ?? []) as $i => $stage) {
                    $stageName = $stage['name'] ?? ('Stage ' . ($i + 1));
                    $stageKey = $this->generateEntityKey('stage', $stageName, $usedStageKeys);

                    $stages[] = [
                        'key'   => $stageKey,
                        'name'  => $stageName,
                        'order' => $stage['order'] ?? ($i + 1),
                    ];
                }

                $pipelines[] = [
                    'key'         => $key,
                    'name'        => $name,
                    'entity_type' => 'deal',
                    'stages'      => $stages,
                ];
            }
            return $pipelines;
        }

        // ── Fallback: template defaults ────────────────────────
        if ($type === 'service') {
            return [['key'=>'client_pipeline','name'=>'Client Pipeline','entity_type'=>'deal','stages'=>[
                ['key'=>'prospect','name'=>'Prospect','order'=>1],['key'=>'proposal','name'=>'Proposal','order'=>2],
                ['key'=>'negotiation','name'=>'Negotiation','order'=>3],['key'=>'won','name'=>'Won','order'=>4],['key'=>'lost','name'=>'Lost','order'=>5],
            ]]];
        }
        return [['key'=>'sales_pipeline','name'=>'Sales Pipeline','entity_type'=>'deal','stages'=>[
            ['key'=>'new','name'=>'New','order'=>1],['key'=>'qualified','name'=>'Qualified','order'=>2],
            ['key'=>'quoted','name'=>'Quoted','order'=>3],['key'=>'won','name'=>'Won','order'=>4],['key'=>'lost','name'=>'Lost','order'=>5],
        ]]];
    }

    private function buildApprovalWorkflows(array $f): array
    {
        if (!($f['needs_approvals'] ?? false)) return [];

        $workflows = [];
        $discountRules = $f['discount_approval_rules'] ?? [];
        $customWorkflows = $f['approval_workflows'] ?? [];
        $commissionApproval = $f['commission_approval_required'] ?? false;

        // ── Discovered discount approval rules ────────────────────
        if (!empty($discountRules)) {
            foreach ($discountRules as $i => $rule) {
                $threshold = $rule['threshold_percent'] ?? null;
                $approverRole = $rule['approver_role'] ?? null;
                $key = 'discount_approval_' . ($i + 1);
                $name = $threshold !== null
                    ? "Discount > {$threshold}% Approval"
                    : 'Discount Approval ' . ($i + 1);

                $wf = [
                    'key'         => $key,
                    'name'        => $name,
                    'entity_type' => 'discount',
                    'steps'       => [[
                        'step_order'             => 1,
                        'name'                   => $approverRole ? "{$approverRole} Approval" : 'Manager Approval',
                        'approver_permission_key'=> 'approvals.decide',
                        'action_on_approve'      => 'finalize',
                    ]],
                ];

                if ($threshold !== null && is_numeric($threshold)) {
                    $wf['trigger_conditions'] = [
                        'logic'      => 'and',
                        'conditions' => [[
                            'field'    => 'discount_percent',
                            'operator' => $rule['operator'] ?? 'greater_than',
                            'value'    => (float) $threshold,
                        ]],
                    ];
                }

                // Store approver role as configuration data (not runtime authorization)
                if ($approverRole) {
                    $wf['recommended_approver_role'] = $approverRole;
                }

                $workflows[] = $wf;
            }
        }

        // ── Discovered custom approval workflows ──────────────────
        if (!empty($customWorkflows)) {
            foreach ($customWorkflows as $i => $aw) {
                $type = $aw['type'] ?? 'custom';
                $key = $this->generateEntityKey('approval', $type) . '_approval';
                if (strlen($key) > 64) $key = substr($key, 0, 64);

                $wf = [
                    'key'         => $key,
                    'name'        => ucwords(str_replace('_', ' ', $type)) . ' Approval',
                    'entity_type' => $aw['entity_type'] ?? 'invoice',
                    'steps'       => [[
                        'step_order'             => 1,
                        'name'                   => ($aw['approver_role'] ?? 'Manager') . ' Approval',
                        'approver_permission_key'=> $aw['required_permission'] ?? 'approvals.decide',
                        'action_on_approve'      => 'finalize',
                    ]],
                ];

                if (isset($aw['trigger'])) {
                    $wf['trigger_conditions'] = $aw['trigger'];
                }
                if (isset($aw['approver_role'])) {
                    $wf['recommended_approver_role'] = $aw['approver_role'];
                }

                $workflows[] = $wf;
            }
        }

        // ── Commission-change approval ────────────────────────────
        if ($commissionApproval) {
            $workflows[] = [
                'key'         => 'commission_change_approval',
                'name'        => 'Commission Change Approval',
                'entity_type' => 'commission_entry',
                'steps'       => [[
                    'step_order'             => 1,
                    'name'                   => 'Commission Change Review',
                    'approver_permission_key'=> 'approvals.decide',
                    'action_on_approve'      => 'finalize',
                ]],
            ];
        }

        // ── Fallback: generic high-value approval if nothing specific ──
        if (empty($workflows)) {
            $threshold = $f['approval_threshold'] ?? null;

            $workflow = [
                'key'         => 'high_value_approval',
                'name'        => 'High Value Approval',
                'entity_type' => 'invoice',
                'steps'       => [[
                    'step_order'             => 1,
                    'name'                   => 'Manager Approval',
                    'approver_permission_key'=> 'approvals.decide',
                    'action_on_approve'      => 'finalize',
                ]],
            ];

            if ($threshold !== null && is_numeric($threshold) && $threshold > 0) {
                $workflow['trigger_conditions'] = [
                    'logic'      => 'and',
                    'conditions' => [['field' => 'amount', 'operator' => 'greater_than_or_equal', 'value' => (float) $threshold]],
                ];
            } else {
                $workflow['requires_configuration'] = true;
                $workflow['configuration_note'] = 'Approval threshold not specified. Configure trigger conditions before activation.';
            }

            $workflows[] = $workflow;
        }

        return $workflows;
    }

    private function buildCommissionRules(array $f): array
    {
        if (!($f['uses_commissions'] ?? false)) return [];
        $model = $f['commission_model'] ?? 'percentage';
        if (!in_array($model, BlueprintSchema::COMMISSION_MODELS)) $model = 'percentage';
        return [['key'=>'standard_commission','name'=>'Standard Sales Commission','calculation_model'=>$model,'rate'=>5,'status'=>'recommended','requires_approval'=>true]];
    }

    private function buildAccountingSettings(array $f): array
    {
        if (!($f['uses_accounting'] ?? false)) return [];
        return ['enabled'=>true,'invoicing_integration'=>true,'payment_tracking'=>true];
    }

    private function buildLocalization(array $f): array
    {
        return array_filter([
            'primary_language'=>$f['primary_language'] ?? null,
            'currency'=>$f['currency'] ?? null,
            'country'=>$f['country'] ?? null,
        ], fn($v) => $v !== null);
    }

    private function buildMissing(array $f): array
    {
        $missing = [];
        if (!isset($f['employee_count'])) $missing[] = 'Employee count not specified';
        if (!isset($f['country'])) $missing[] = 'Operating country not specified';
        if (!isset($f['currency'])) $missing[] = 'Currency not specified';
        if (!isset($f['tax_requirements'])) $missing[] = 'Tax requirements not specified';
        return $missing;
    }

    /**
     * Resolve a department display name or template key to an actual department key
     * using the canonical department registry.
     *
     * Lookup order:
     *   1. Exact match by normalized display name
     *   2. Exact match by key (for template references like 'sales', 'finance')
     *   3. Return null if unresolvable (let the role have no department_key)
     */
    private function resolveDeptKey(string $nameOrKey, array $deptRegistry): ?string
    {
        // Try normalized display name first
        $normalized = mb_strtolower(trim($nameOrKey));
        if (isset($deptRegistry[$normalized])) {
            return $deptRegistry[$normalized];
        }

        // Try exact key match (for template role references like 'sales')
        $keyForm = strtolower(trim($nameOrKey));
        if (isset($deptRegistry[$keyForm])) {
            return $deptRegistry[$keyForm];
        }

        return null;
    }

    /**
     * Final referential integrity guard.
     *
     * Verifies all local cross-entity references resolve to existing entities.
     * Throws a RuntimeException with details if any reference is broken.
     * This catches generator bugs before Blueprint persistence.
     */
    private function validateLocalReferences(array $bp): void
    {
        $errors = [];

        // Collect valid keys from each entity collection
        $deptKeys = array_column($bp['departments'] ?? [], 'key');
        $teamKeys = array_column($bp['teams'] ?? [], 'key');
        $roleKeys = array_column($bp['roles'] ?? [], 'key');
        $locationKeys = array_column($bp['locations'] ?? [], 'key');
        $pipelineKeys = array_column($bp['pipelines'] ?? [], 'key');

        // Roles → departments
        foreach ($bp['roles'] ?? [] as $i => $role) {
            $deptRef = $role['department_key'] ?? null;
            if ($deptRef && !in_array($deptRef, $deptKeys, true)) {
                $errors[] = "roles.{$i}.department_key: '{$deptRef}' not found in departments (role: {$role['key']})";
            }
            $teamRef = $role['team_key'] ?? null;
            if ($teamRef && !in_array($teamRef, $teamKeys, true)) {
                $errors[] = "roles.{$i}.team_key: '{$teamRef}' not found in teams (role: {$role['key']})";
            }
        }

        // Teams → departments
        foreach ($bp['teams'] ?? [] as $i => $team) {
            $deptRef = $team['department_key'] ?? null;
            if ($deptRef && !in_array($deptRef, $deptKeys, true)) {
                $errors[] = "teams.{$i}.department_key: '{$deptRef}' not found in departments (team: {$team['key']})";
            }
        }

        // Departments → parent departments
        foreach ($bp['departments'] ?? [] as $i => $dept) {
            $parentRef = $dept['parent_department_key'] ?? null;
            if ($parentRef && !in_array($parentRef, $deptKeys, true)) {
                $errors[] = "departments.{$i}.parent_department_key: '{$parentRef}' not found in departments";
            }
        }

        // Warehouses → locations
        foreach ($bp['warehouses'] ?? [] as $i => $wh) {
            $branchRef = $wh['branch_key'] ?? null;
            if ($branchRef && !empty($locationKeys) && !in_array($branchRef, $locationKeys, true)) {
                $errors[] = "warehouses.{$i}.branch_key: '{$branchRef}' not found in locations (warehouse: {$wh['key']})";
            }
        }

        // Pipeline stages (internal consistency)
        foreach ($bp['pipelines'] ?? [] as $i => $pipeline) {
            $stageKeys = array_column($pipeline['stages'] ?? [], 'key');
            if (count($stageKeys) !== count(array_unique($stageKeys))) {
                $errors[] = "pipelines.{$i}.stages: duplicate stage keys detected (pipeline: {$pipeline['key']})";
            }
        }

        // ── Generator consistency guards ──────────────────────────

        // Duplicate role keys
        if (count($roleKeys) !== count(array_unique($roleKeys))) {
            $dups = array_diff_assoc($roleKeys, array_unique($roleKeys));
            $errors[] = "roles: duplicate keys detected: " . implode(', ', $dups);
        }

        // Duplicate department keys
        if (count($deptKeys) !== count(array_unique($deptKeys))) {
            $dups = array_diff_assoc($deptKeys, array_unique($deptKeys));
            $errors[] = "departments: duplicate keys detected: " . implode(', ', $dups);
        }

        // Unknown permissions (validate against catalog)
        $allValidPerms = PermissionCatalog::allKeys();
        foreach ($bp['roles'] ?? [] as $i => $role) {
            $unknown = array_diff($role['permissions'] ?? [], $allValidPerms);
            if (!empty($unknown)) {
                $errors[] = "roles.{$i}.permissions: unknown permission keys: " . implode(', ', $unknown) . " (role: {$role['key']})";
            }
            // Duplicate permissions within a single role
            $perms = $role['permissions'] ?? [];
            if (count($perms) !== count(array_unique($perms))) {
                $errors[] = "roles.{$i}.permissions: duplicate permissions detected (role: {$role['key']})";
            }
        }

        if (!empty($errors)) {
            throw new \RuntimeException(
                "Blueprint referential integrity violation:\n" . implode("\n", $errors)
            );
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  Locale-Sensitive Fact Normalization
    // ═══════════════════════════════════════════════════════════════

    /**
     * Normalize locale-sensitive discovery facts to canonical ISO values.
     *
     * Called once at the top of generate() so every downstream builder
     * receives clean, validated ISO codes.
     */
    private function normalizeFactValues(array $f): array
    {
        // Normalize country first (needed as currency fallback)
        if (isset($f['country'])) {
            $f['country'] = $this->normalizeCountryCode($f['country']);
        }

        // Normalize currency using country as fallback
        if (isset($f['currency'])) {
            $f['currency'] = $this->normalizeCurrencyCode(
                $f['currency'],
                $f['country'] ?? null,
            );
        }

        // Normalize language
        if (isset($f['primary_language'])) {
            $f['primary_language'] = $this->normalizeLanguageCode($f['primary_language']);
        }

        return $f;
    }

    /**
     * Normalize a currency value to a valid uppercase ISO 4217 code.
     *
     * Resolution order:
     *   1. Already a valid 3-letter ISO code → uppercase and return
     *   2. English currency name via ICU CLDR reverse lookup
     *   3. Arabic currency name via built-in map
     *   4. Country-code fallback (ISO 3166 → ISO 4217)
     *   5. Throw RuntimeException if unresolvable
     */
    private function normalizeCurrencyCode(mixed $currencyValue, ?string $countryCode = null): string
    {
        if (!is_string($currencyValue) || trim($currencyValue) === '') {
            if ($countryCode) {
                return $this->currencyFromCountry($countryCode)
                    ?? throw new \RuntimeException("Cannot resolve currency: empty value, country={$countryCode}");
            }
            throw new \RuntimeException("Cannot resolve currency: empty value, no country fallback");
        }

        $input = trim($currencyValue);

        // 1. Already a valid 3-letter ISO code
        $upper = strtoupper($input);
        if (preg_match('/^[A-Z]{3}$/', $upper) && $this->isValidIsoCurrency($upper)) {
            return $upper;
        }

        // 2. English name reverse lookup via ICU CLDR
        if (extension_loaded('intl')) {
            $resolved = $this->currencyFromCldrName($input, 'en');
            if ($resolved) return $resolved;
        }

        // 3. Arabic currency name map
        $resolved = $this->currencyFromArabicName($input);
        if ($resolved) return $resolved;

        // 4. Country-code fallback
        if ($countryCode) {
            $resolved = $this->currencyFromCountry($countryCode);
            if ($resolved) return $resolved;
        }

        throw new \RuntimeException(
            "Cannot resolve currency to ISO 4217 code: " .
            "value=\"{$input}\", country=" . ($countryCode ?? 'null')
        );
    }

    /**
     * Check if a 3-letter code is a valid ISO 4217 currency.
     */
    private function isValidIsoCurrency(string $code): bool
    {
        if (extension_loaded('intl')) {
            $bundle = \ResourceBundle::create('en', 'ICUDATA-curr');
            if ($bundle) {
                $currencies = $bundle->get('Currencies');
                if ($currencies && $currencies->get($code) !== null) {
                    return true;
                }
            }
        }
        // Fallback: accept any 3-letter uppercase as potentially valid
        return preg_match('/^[A-Z]{3}$/', $code) === 1;
    }

    /**
     * Reverse-lookup a currency display name to its ISO code via ICU CLDR.
     */
    private function currencyFromCldrName(string $name, string $locale): ?string
    {
        $bundle = \ResourceBundle::create($locale, 'ICUDATA-curr');
        if (!$bundle) return null;

        $currencies = $bundle->get('Currencies');
        if (!$currencies) return null;

        $normalized = mb_strtolower(trim($name));
        foreach ($currencies as $code => $entry) {
            $cldrName = $entry->get(1);
            if ($cldrName && mb_strtolower($cldrName) === $normalized) {
                return $code;
            }
        }
        return null;
    }

    /**
     * Map common Arabic currency names to ISO 4217 codes.
     *
     * Covers MENA, Gulf, North Africa, South/Southeast Asia and major
     * world currencies. Uses normalized forms for reliable matching.
     */
    private function currencyFromArabicName(string $input): ?string
    {
        static $map = null;
        if ($map === null) {
            $map = [
                // North Africa
                'الدينار الليبي' => 'LYD', 'دينار ليبي' => 'LYD',
                'الجنيه المصري' => 'EGP', 'جنيه مصري' => 'EGP',
                'الدرهم المغربي' => 'MAD', 'درهم مغربي' => 'MAD',
                'الدينار التونسي' => 'TND', 'دينار تونسي' => 'TND',
                'الدينار الجزائري' => 'DZD', 'دينار جزائري' => 'DZD',
                'الجنيه السوداني' => 'SDG', 'جنيه سوداني' => 'SDG',
                // Gulf / Middle East
                'الريال السعودي' => 'SAR', 'ريال سعودي' => 'SAR',
                'الدرهم الإماراتي' => 'AED', 'درهم إماراتي' => 'AED',
                'الدينار الكويتي' => 'KWD', 'دينار كويتي' => 'KWD',
                'الريال القطري' => 'QAR', 'ريال قطري' => 'QAR',
                'الدينار البحريني' => 'BHD', 'دينار بحريني' => 'BHD',
                'الريال العماني' => 'OMR', 'ريال عماني' => 'OMR',
                'الدينار العراقي' => 'IQD', 'دينار عراقي' => 'IQD',
                'الدينار الأردني' => 'JOD', 'دينار أردني' => 'JOD',
                'الليرة اللبنانية' => 'LBP', 'ليرة لبنانية' => 'LBP',
                'الليرة السورية' => 'SYP', 'ليرة سورية' => 'SYP',
                'الشيكل الإسرائيلي' => 'ILS', 'شيكل' => 'ILS',
                'الريال اليمني' => 'YER', 'ريال يمني' => 'YER',
                // Major world currencies
                'الدولار الأمريكي' => 'USD', 'دولار أمريكي' => 'USD', 'دولار' => 'USD',
                'اليورو' => 'EUR', 'يورو' => 'EUR',
                'الجنيه الاسترليني' => 'GBP', 'جنيه استرليني' => 'GBP', 'جنيه بريطاني' => 'GBP',
                'الليرة التركية' => 'TRY', 'ليرة تركية' => 'TRY',
                // Asia
                'الروبية الباكستانية' => 'PKR', 'روبية باكستانية' => 'PKR',
                'الروبية الهندية' => 'INR', 'روبية هندية' => 'INR',
                'الرينغيت الماليزي' => 'MYR', 'رينغيت ماليزي' => 'MYR',
                'الدولار السنغافوري' => 'SGD', 'دولار سنغافوري' => 'SGD',
            ];
        }

        $normalized = trim($input);
        if (isset($map[$normalized])) {
            return $map[$normalized];
        }

        // Try case-insensitive match
        $lower = mb_strtolower($normalized);
        foreach ($map as $name => $code) {
            if (mb_strtolower($name) === $lower) {
                return $code;
            }
        }

        return null;
    }

    /**
     * Map ISO 3166-1 alpha-2 country codes to their primary ISO 4217 currency.
     */
    private function currencyFromCountry(string $countryCode): ?string
    {
        $map = [
            'LY'=>'LYD','SA'=>'SAR','AE'=>'AED','EG'=>'EGP','JO'=>'JOD',
            'KW'=>'KWD','QA'=>'QAR','BH'=>'BHD','OM'=>'OMR','IQ'=>'IQD',
            'LB'=>'LBP','SY'=>'SYP','YE'=>'YER','SD'=>'SDG','MA'=>'MAD',
            'TN'=>'TND','DZ'=>'DZD','US'=>'USD','GB'=>'GBP','EU'=>'EUR',
            'TR'=>'TRY','PK'=>'PKR','IN'=>'INR','MY'=>'MYR','SG'=>'SGD',
            'ID'=>'IDR','TH'=>'THB','JP'=>'JPY','CN'=>'CNY','KR'=>'KRW',
            'AU'=>'AUD','CA'=>'CAD','CH'=>'CHF','BR'=>'BRL','MX'=>'MXN',
            'ZA'=>'ZAR','NG'=>'NGN','KE'=>'KES','GH'=>'GHS','TZ'=>'TZS',
        ];
        $upper = strtoupper(trim($countryCode));
        return $map[$upper] ?? null;
    }

    /**
     * Normalize a country display name (any language) to an ISO 3166-1 alpha-2 code.
     */
    private function normalizeCountryCode(string $country): string
    {
        $trimmed = trim($country);

        // Already a valid 2-letter ISO code
        if (preg_match('/^[A-Z]{2}$/', strtoupper($trimmed))) {
            return strtoupper($trimmed);
        }

        // English name lookup
        $englishMap = [
            'saudi arabia'=>'SA','united arab emirates'=>'AE','uae'=>'AE',
            'egypt'=>'EG','jordan'=>'JO','kuwait'=>'KW','qatar'=>'QA',
            'bahrain'=>'BH','oman'=>'OM','iraq'=>'IQ','lebanon'=>'LB',
            'syria'=>'SY','yemen'=>'YE','sudan'=>'SD','libya'=>'LY',
            'morocco'=>'MA','tunisia'=>'TN','algeria'=>'DZ','turkey'=>'TR',
            'pakistan'=>'PK','india'=>'IN','malaysia'=>'MY','singapore'=>'SG',
            'indonesia'=>'ID','thailand'=>'TH','japan'=>'JP','china'=>'CN',
            'south korea'=>'KR','australia'=>'AU','canada'=>'CA',
            'united kingdom'=>'GB','uk'=>'GB','united states'=>'US','usa'=>'US',
            'germany'=>'DE','france'=>'FR','spain'=>'ES','italy'=>'IT',
            'brazil'=>'BR','mexico'=>'MX','south africa'=>'ZA',
            'nigeria'=>'NG','kenya'=>'KE','ghana'=>'GH','tanzania'=>'TZ',
            'switzerland'=>'CH','netherlands'=>'NL','sweden'=>'SE',
        ];
        $lower = mb_strtolower($trimmed);
        if (isset($englishMap[$lower])) {
            return $englishMap[$lower];
        }

        // Arabic name lookup
        $arabicMap = [
            'ليبيا'=>'LY','السعودية'=>'SA','المملكة العربية السعودية'=>'SA',
            'الإمارات'=>'AE','الإمارات العربية المتحدة'=>'AE',
            'مصر'=>'EG','الأردن'=>'JO','الكويت'=>'KW','قطر'=>'QA',
            'البحرين'=>'BH','عمان'=>'OM','سلطنة عمان'=>'OM',
            'العراق'=>'IQ','لبنان'=>'LB','سوريا'=>'SY','اليمن'=>'YE',
            'السودان'=>'SD','المغرب'=>'MA','تونس'=>'TN','الجزائر'=>'DZ',
            'تركيا'=>'TR','باكستان'=>'PK','الهند'=>'IN','ماليزيا'=>'MY',
            'سنغافورة'=>'SG','إندونيسيا'=>'ID','تايلاند'=>'TH',
            'اليابان'=>'JP','الصين'=>'CN','كوريا الجنوبية'=>'KR',
            'أستراليا'=>'AU','كندا'=>'CA','بريطانيا'=>'GB',
            'المملكة المتحدة'=>'GB','أمريكا'=>'US','الولايات المتحدة'=>'US',
            'ألمانيا'=>'DE','فرنسا'=>'FR','إسبانيا'=>'ES','إيطاليا'=>'IT',
            'البرازيل'=>'BR','المكسيك'=>'MX','جنوب أفريقيا'=>'ZA',
            'نيجيريا'=>'NG','كينيا'=>'KE','طرابلس'=>'LY',
        ];
        if (isset($arabicMap[$trimmed])) {
            return $arabicMap[$trimmed];
        }

        // Return original as-is (inferTimezone and other helpers accept display names)
        return $trimmed;
    }

    /**
     * Normalize a language display name to a standard language code.
     */
    private function normalizeLanguageCode(string $language): string
    {
        $map = [
            'العربية'=>'ar','عربي'=>'ar','arabic'=>'ar',
            'الإنجليزية'=>'en','إنجليزي'=>'en','english'=>'en',
            'التركية'=>'tr','تركي'=>'tr','turkish'=>'tr',
            'الأردية'=>'ur','أردو'=>'ur','urdu'=>'ur',
            'الفرنسية'=>'fr','فرنسي'=>'fr','french'=>'fr',
            'الإسبانية'=>'es','spanish'=>'es',
            'الملايوية'=>'ms','malay'=>'ms',
            'الهندية'=>'hi','hindi'=>'hi',
            'الصينية'=>'zh','chinese'=>'zh',
        ];
        $normalized = mb_strtolower(trim($language));
        return $map[$normalized] ?? $language;
    }
}
