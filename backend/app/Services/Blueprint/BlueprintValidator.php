<?php

namespace App\Services\Blueprint;

use App\Services\PermissionCatalog;
use App\Services\TriggerConditionValidator;

/**
 * BlueprintValidator — Centralized validation for canonical ERP blueprints.
 *
 * Returns structured validation results with errors, warnings, and a
 * normalized blueprint. Invalid blueprints are never persisted.
 *
 * All module keys are validated against BlueprintSchema::MODULE_KEYS.
 * All permission keys are validated against PermissionCatalog::allKeys().
 * All workflow entities are validated against BlueprintSchema::APPROVAL_ENTITY_TYPES.
 */
class BlueprintValidator
{
    private array $errors   = [];
    private array $warnings = [];

    /**
     * Validate a blueprint payload.
     *
     * @return array{valid: bool, errors: array, warnings: array, normalized_blueprint: array}
     */
    public function validate(array $blueprint): array
    {
        $this->errors   = [];
        $this->warnings = [];

        // Schema version
        $this->validateSchemaVersion($blueprint);

        // Top-level structure
        $this->validateTopLevelStructure($blueprint);

        // Business profile
        $this->validateBusinessProfile(is_array($blueprint['business_profile'] ?? null) ? $blueprint['business_profile'] : []);

        // Modules (type guard: skip validation if not an array — error already recorded above)
        $enabledModuleKeys = is_array($blueprint['modules'] ?? null)
            ? $this->validateModules($blueprint['modules'])
            : [];

        // Organization
        $departmentKeys = is_array($blueprint['departments'] ?? null)
            ? $this->validateDepartments($blueprint['departments'])
            : [];
        $teamKeys = is_array($blueprint['teams'] ?? null)
            ? $this->validateTeams($blueprint['teams'], $departmentKeys)
            : [];
        if (is_array($blueprint['roles'] ?? null)) {
            $this->validateRoles($blueprint['roles'], $departmentKeys, $teamKeys, $enabledModuleKeys);
        }

        // Locations
        $locationKeys = is_array($blueprint['locations'] ?? null)
            ? $this->validateLocations($blueprint['locations'])
            : [];

        // Warehouses
        if (is_array($blueprint['warehouses'] ?? null)) {
            $this->validateWarehouses($blueprint['warehouses'], $locationKeys);
        }

        // Finance
        if (is_array($blueprint['payment_methods'] ?? null)) {
            $this->validatePaymentMethods($blueprint['payment_methods']);
        }
        $this->validateTaxSettings(is_array($blueprint['tax_settings'] ?? null) ? $blueprint['tax_settings'] : []);
        $this->validateInvoiceSettings(is_array($blueprint['invoice_settings'] ?? null) ? $blueprint['invoice_settings'] : []);
        $this->validateAccountingSettings(is_array($blueprint['accounting_settings'] ?? null) ? $blueprint['accounting_settings'] : []);

        // POS
        $this->validatePosSettings(is_array($blueprint['pos_settings'] ?? null) ? $blueprint['pos_settings'] : [], $enabledModuleKeys, $locationKeys);

        // Pipelines
        if (is_array($blueprint['pipelines'] ?? null)) {
            $this->validatePipelines($blueprint['pipelines']);
        }

        // Workflows
        $roleKeys = is_array($blueprint['roles'] ?? null) ? array_column($blueprint['roles'], 'key') : [];
        if (is_array($blueprint['approval_workflows'] ?? null)) {
            $this->validateApprovalWorkflows($blueprint['approval_workflows'], $roleKeys);
        }

        // Commissions
        if (is_array($blueprint['commission_rules'] ?? null)) {
            $this->validateCommissionRules($blueprint['commission_rules']);
        }

        // Workspace settings
        $this->validateWorkspaceSettings(is_array($blueprint['workspace_settings'] ?? null) ? $blueprint['workspace_settings'] : []);

        // Localization
        $this->validateLocalization(is_array($blueprint['localization'] ?? null) ? $blueprint['localization'] : []);

        return [
            'valid'                => empty($this->errors),
            'errors'               => $this->errors,
            'warnings'             => $this->warnings,
            'normalized_blueprint' => $blueprint,
        ];
    }

    // ═══════════════════════════════════════════════════════════════
    //  Schema & Structure
    // ═══════════════════════════════════════════════════════════════

    private function validateSchemaVersion(array $bp): void
    {
        $version = $bp['schema_version'] ?? null;
        if (!$version) {
            $this->addError('schema_version', 'Schema version is required.');
            return;
        }
        if ($version !== BlueprintSchema::VERSION) {
            $this->addError('schema_version', "Unsupported schema version: {$version}. Expected: " . BlueprintSchema::VERSION . ".");
        }
    }

    private function validateTopLevelStructure(array $bp): void
    {
        foreach (BlueprintSchema::REQUIRED_FIELDS as $field) {
            if (!array_key_exists($field, $bp)) {
                $this->addError($field, "Required top-level field '{$field}' is missing.");
            }
        }
        // Reject unknown top-level keys
        foreach (array_keys($bp) as $key) {
            if (!in_array($key, BlueprintSchema::ALL_SECTIONS, true)) {
                $this->addError($key, "Unknown top-level section '{$key}'. Only canonical sections are allowed.");
            }
        }
        // Type checks for array sections
        $arraySections = ['modules', 'departments', 'teams', 'roles', 'warehouses', 'locations',
            'payment_methods', 'pipelines', 'approval_workflows', 'commission_rules',
            'assumptions', 'missing_optional_information'];
        foreach ($arraySections as $section) {
            if (isset($bp[$section]) && !is_array($bp[$section])) {
                $this->addError($section, "Section '{$section}' must be an array.");
            }
        }
        $objectSections = ['business_profile', 'workspace_settings', 'tax_settings',
            'invoice_settings', 'pos_settings', 'accounting_settings', 'localization',
            'ai_settings', 'metadata'];
        foreach ($objectSections as $section) {
            if (isset($bp[$section]) && !is_array($bp[$section])) {
                $this->addError($section, "Section '{$section}' must be an object.");
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  Business Profile
    // ═══════════════════════════════════════════════════════════════

    private function validateBusinessProfile(array $profile): void
    {
        if (empty($profile)) {
            $this->addError('business_profile', 'Business profile is required.');
            return;
        }
        if (empty($profile['business_type'])) {
            $this->addError('business_profile.business_type', 'Business type is required.');
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  Modules
    // ═══════════════════════════════════════════════════════════════

    /**
     * @return string[] Enabled module keys for cross-validation
     */
    private function validateModules(array $modules): array
    {
        $seenKeys = [];
        $enabledKeys = [];

        foreach ($modules as $i => $mod) {
            $path = "modules.{$i}";
            $key = $mod['key'] ?? null;

            if (!$key) {
                $this->addError("{$path}.key", 'Module key is required.');
                continue;
            }

            if (!BlueprintSchema::isValidModuleKey($key)) {
                $this->addError("{$path}.key", "Unknown module key: {$key}.");
                continue;
            }

            if (in_array($key, $seenKeys, true)) {
                $this->addError("{$path}.key", "Duplicate module key: {$key}.");
                continue;
            }
            $seenKeys[] = $key;

            // Status validation
            $status = $mod['status'] ?? 'recommended';
            if (!BlueprintSchema::isValidStatus($status)) {
                $this->addError("{$path}.status", "Invalid status '{$status}' for module '{$key}'.");
            }

            // Required modules cannot be disabled
            $enabled = $mod['enabled'] ?? ($status !== 'unsupported');
            if ($status === 'required' && !$enabled) {
                $this->addError("{$path}.enabled", "Required module '{$key}' cannot be disabled.");
            }

            if ($enabled) {
                $enabledKeys[] = $key;
            }
        }

        // Dependency validation — required dependencies must be satisfied
        foreach ($modules as $i => $mod) {
            $key = $mod['key'] ?? null;
            $enabled = $mod['enabled'] ?? (($mod['status'] ?? '') !== 'unsupported');
            if (!$key || !$enabled) continue;

            $deps = BlueprintSchema::moduleDependencies($key);
            foreach ($deps as $dep) {
                if (!in_array($dep, $enabledKeys, true)) {
                    $this->addError("modules.{$i}.key", "Module '{$key}' requires '{$dep}' which is not enabled.");
                }
            }
        }

        return $enabledKeys;
    }

    // ═══════════════════════════════════════════════════════════════
    //  Organization: Departments, Teams, Roles
    // ═══════════════════════════════════════════════════════════════

    /**
     * @return string[] Valid department keys
     */
    private function validateDepartments(array $departments): array
    {
        $seenKeys = [];
        $parentRefs = [];

        foreach ($departments as $i => $dept) {
            $path = "departments.{$i}";
            $key = $dept['key'] ?? null;
            if (!$key) {
                $this->addError("{$path}.key", 'Department key is required.');
                continue;
            }
            if (!$this->validateLocalKey("{$path}.key", $key)) {
                continue;
            }
            if (in_array($key, $seenKeys, true)) {
                $this->addError("{$path}.key", "Duplicate department key: {$key}.");
                continue;
            }
            $seenKeys[] = $key;

            if (!empty($dept['name']) && strlen($dept['name']) > 255) {
                $this->addError("{$path}.name", 'Department name must be 255 characters or fewer.');
            }

            // Track parent references for circular check
            $parent = $dept['parent_department_key'] ?? null;
            if ($parent) {
                $this->validateLocalKey("{$path}.parent_department_key", $parent);
                $parentRefs[$key] = $parent;
            }
        }

        // Validate parent references exist
        foreach ($parentRefs as $childKey => $parentKey) {
            if (!in_array($parentKey, $seenKeys, true)) {
                $idx = array_search($childKey, $seenKeys);
                $this->addError("departments.{$idx}.parent_department_key",
                    "Department '{$childKey}' references nonexistent parent '{$parentKey}'.");
            }
        }

        // Detect circular parent relationships
        foreach ($parentRefs as $startKey => $parentKey) {
            $visited = [$startKey];
            $current = $parentKey;
            while ($current !== null) {
                if (in_array($current, $visited, true)) {
                    $idx = array_search($startKey, $seenKeys);
                    $this->addError("departments.{$idx}.parent_department_key",
                        "Circular parent relationship detected for department '{$startKey}'.");
                    break;
                }
                $visited[] = $current;
                $current = $parentRefs[$current] ?? null;
            }
        }

        return $seenKeys;
    }

    /**
     * @return string[] Valid team keys
     */
    private function validateTeams(array $teams, array $validDeptKeys): array
    {
        $seenKeys = [];

        foreach ($teams as $i => $team) {
            $path = "teams.{$i}";
            $key = $team['key'] ?? null;
            if (!$key) {
                $this->addError("{$path}.key", 'Team key is required.');
                continue;
            }
            if (!$this->validateLocalKey("{$path}.key", $key)) {
                continue;
            }
            if (in_array($key, $seenKeys, true)) {
                $this->addError("{$path}.key", "Duplicate team key: {$key}.");
                continue;
            }
            $seenKeys[] = $key;

            // Validate department reference
            $deptRef = $team['department_key'] ?? null;
            if ($deptRef && !in_array($deptRef, $validDeptKeys, true)) {
                $this->addError("{$path}.department_key",
                    "Team '{$key}' references nonexistent department '{$deptRef}'.");
            }
        }

        return $seenKeys;
    }

    private function validateRoles(
        array $roles,
        array $validDeptKeys,
        array $validTeamKeys,
        array $enabledModuleKeys,
    ): void {
        $validPermKeys = PermissionCatalog::allKeys();
        $seenKeys = [];
        $seenNormalizedNames = [];

        foreach ($roles as $i => $role) {
            $path = "roles.{$i}";
            $key = $role['key'] ?? null;
            if (!$key) {
                $this->addError("{$path}.key", 'Role key is required.');
                continue;
            }
            if (!$this->validateLocalKey("{$path}.key", $key)) {
                continue;
            }
            if (in_array($key, $seenKeys, true)) {
                $this->addError("{$path}.key", "Duplicate role key: {$key}.");
                continue;
            }
            $seenKeys[] = $key;

            // Name uniqueness (normalized: lowercase trimmed)
            $name = $role['name'] ?? $key;
            $normalizedName = strtolower(trim($name));
            if (in_array($normalizedName, $seenNormalizedNames, true)) {
                $this->addError("{$path}.name", "Duplicate role name after normalization: {$name}.");
            }
            $seenNormalizedNames[] = $normalizedName;

            // Status validation
            $status = $role['status'] ?? 'recommended';
            if (!BlueprintSchema::isValidStatus($status)) {
                $this->addError("{$path}.status", "Invalid status '{$status}' for role '{$key}'.");
            }

            // Permission validation
            $permissions = $role['permissions'] ?? [];
            foreach ($permissions as $j => $permKey) {
                if (!in_array($permKey, $validPermKeys, true)) {
                    $this->addError("{$path}.permissions.{$j}", "Unknown permission key: {$permKey}.");
                }
            }

            // Department reference
            $deptRef = $role['department_key'] ?? null;
            if ($deptRef && !in_array($deptRef, $validDeptKeys, true)) {
                $this->addError("{$path}.department_key",
                    "Role '{$key}' references nonexistent department '{$deptRef}'.");
            }

            // Team reference
            $teamRef = $role['team_key'] ?? null;
            if ($teamRef && !in_array($teamRef, $validTeamKeys, true)) {
                $this->addError("{$path}.team_key",
                    "Role '{$key}' references nonexistent team '{$teamRef}'.");
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  Locations
    // ═══════════════════════════════════════════════════════════════

    /**
     * @return string[] Valid location keys
     */
    private function validateLocations(array $locations): array
    {
        $seenKeys = [];
        $primaryCount = 0;

        foreach ($locations as $i => $loc) {
            $path = "locations.{$i}";
            $key = $loc['key'] ?? null;
            if (!$key) {
                $this->addError("{$path}.key", 'Location key is required.');
                continue;
            }
            if (!$this->validateLocalKey("{$path}.key", $key)) {
                continue;
            }
            if (in_array($key, $seenKeys, true)) {
                $this->addError("{$path}.key", "Duplicate location key: {$key}.");
                continue;
            }
            $seenKeys[] = $key;

            // Name validation
            $name = $loc['name'] ?? null;
            if (empty($name) || !is_string($name)) {
                $this->addError("{$path}.name", 'Location name is required and must be a non-empty string.');
            } elseif (strlen($name) > 255) {
                $this->addError("{$path}.name", 'Location name must be 255 characters or fewer.');
            }

            // Type validation
            $type = $loc['type'] ?? null;
            if (!$type) {
                $this->addError("{$path}.type", 'Location type is required.');
            } elseif (!in_array($type, BlueprintSchema::LOCATION_TYPES, true)) {
                $this->addError("{$path}.type", "Unsupported location type: '{$type}'. Supported: " . implode(', ', BlueprintSchema::LOCATION_TYPES) . '.');
            }

            // Status validation
            $status = $loc['status'] ?? 'recommended';
            if (!BlueprintSchema::isValidStatus($status)) {
                $this->addError("{$path}.status", "Invalid status '{$status}' for location '{$key}'.");
            }

            // is_primary
            if (isset($loc['is_primary']) && !is_bool($loc['is_primary'])) {
                $this->addError("{$path}.is_primary", 'is_primary must be a boolean.');
            }
            if (!empty($loc['is_primary'])) {
                $primaryCount++;
            }

            // Optional field validation
            if (isset($loc['currency'])) {
                $cur = $loc['currency'];
                if (!is_string($cur) || !preg_match('/^[A-Z]{3}$/', $cur)) {
                    $this->addError("{$path}.currency", "Currency must be a 3-letter uppercase code, got: {$cur}.");
                }
            }
        }

        if ($primaryCount > 1) {
            $this->addError('locations', "Only one location can be marked as primary. Found {$primaryCount}.");
        }

        return $seenKeys;
    }

    // ═══════════════════════════════════════════════════════════════
    //  Warehouses
    // ═══════════════════════════════════════════════════════════════

    private function validateWarehouses(array $warehouses, array $validLocationKeys = []): void
    {
        $seenKeys = [];
        $defaultCount = 0;

        foreach ($warehouses as $i => $wh) {
            $path = "warehouses.{$i}";
            $key = $wh['key'] ?? null;
            if (!$key) {
                $this->addError("{$path}.key", 'Warehouse key is required.');
                continue;
            }
            if (!$this->validateLocalKey("{$path}.key", $key)) {
                continue;
            }
            if (in_array($key, $seenKeys, true)) {
                $this->addError("{$path}.key", "Duplicate warehouse key: {$key}.");
                continue;
            }
            $seenKeys[] = $key;

            // Branch/location reference validation
            $branchRef = $wh['branch_key'] ?? null;
            if ($branchRef) {
                if (!$this->validateLocalKey("{$path}.branch_key", $branchRef)) {
                    // Format error already recorded
                } elseif (!empty($validLocationKeys) && !in_array($branchRef, $validLocationKeys, true)) {
                    $this->addError("{$path}.branch_key",
                        "Warehouse '{$key}' references unknown location '{$branchRef}'.");
                }
            }

            if (!empty($wh['is_default'])) {
                $defaultCount++;
            }
        }

        if ($defaultCount > 1) {
            $this->addError('warehouses', "Only one warehouse can be marked as default. Found {$defaultCount}.");
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  Finance
    // ═══════════════════════════════════════════════════════════════

    private function validatePaymentMethods(array $methods): void
    {
        $seenKeys = [];
        foreach ($methods as $i => $m) {
            $path = "payment_methods.{$i}";
            $key = $m['key'] ?? null;
            if (!$key) {
                $this->addError("{$path}.key", 'Payment method key is required.');
                continue;
            }
            if (in_array($key, $seenKeys, true)) {
                $this->addError("{$path}.key", "Duplicate payment method key: {$key}.");
            }
            $seenKeys[] = $key;

            // Validate against supported payment types
            if (!in_array($key, BlueprintSchema::VALID_PAYMENT_TYPES, true)) {
                $this->addError("{$path}.key",
                    "Unsupported payment method type: '{$key}'. Supported: " . implode(', ', BlueprintSchema::VALID_PAYMENT_TYPES) . '.');
            }
        }
    }

    private function validateTaxSettings(array $tax): void
    {
        if (empty($tax)) return;

        if (isset($tax['tax_rate'])) {
            $rate = $tax['tax_rate'];
            if (!is_numeric($rate) || $rate < 0 || $rate > 100) {
                $this->addError('tax_settings.tax_rate', 'Tax rate must be a number between 0 and 100.');
            }
        }

        if (isset($tax['tax_inclusive']) && !is_bool($tax['tax_inclusive'])) {
            $this->addError('tax_settings.tax_inclusive', 'tax_inclusive must be a boolean.');
        }
    }

    private function validateInvoiceSettings(array $inv): void
    {
        // Basic structural validation only
        if (empty($inv)) return;

        if (isset($inv['default_due_days']) && (!is_int($inv['default_due_days']) || $inv['default_due_days'] < 0)) {
            $this->addError('invoice_settings.default_due_days', 'default_due_days must be a non-negative integer.');
        }
    }

    private function validateAccountingSettings(array $acc): void
    {
        if (empty($acc)) return;
        // Structural validation — no invented fields
    }

    // ═══════════════════════════════════════════════════════════════
    //  POS
    // ═══════════════════════════════════════════════════════════════

    private function validatePosSettings(array $pos, array $enabledModuleKeys, array $validLocationKeys = []): void
    {
        if (empty($pos)) return;

        if (!empty($pos['enabled']) && !in_array('pos', $enabledModuleKeys, true)) {
            $this->addWarning("POS settings enabled but 'pos' module is not enabled.");
        }

        // Validate location_keys references
        if (isset($pos['location_keys'])) {
            if (!is_array($pos['location_keys'])) {
                $this->addError('pos_settings.location_keys', 'location_keys must be an array.');
            } else {
                $seen = [];
                foreach ($pos['location_keys'] as $j => $lk) {
                    $path = "pos_settings.location_keys.{$j}";
                    if (!is_string($lk)) {
                        $this->addError($path, 'POS location key must be a string.');
                        continue;
                    }
                    if (in_array($lk, $seen, true)) {
                        $this->addError($path, "Duplicate POS location key: {$lk}.");
                        continue;
                    }
                    $seen[] = $lk;
                    if (!empty($validLocationKeys) && !in_array($lk, $validLocationKeys, true)) {
                        $this->addError($path, "POS references unknown location '{$lk}'.");
                    }
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  Pipelines
    // ═══════════════════════════════════════════════════════════════

    private function validatePipelines(array $pipelines): void
    {
        $seenKeys = [];

        foreach ($pipelines as $i => $pipeline) {
            $path = "pipelines.{$i}";
            $key = $pipeline['key'] ?? null;
            if (!$key) {
                $this->addError("{$path}.key", 'Pipeline key is required.');
                continue;
            }
            if (!$this->validateLocalKey("{$path}.key", $key)) {
                continue;
            }
            if (in_array($key, $seenKeys, true)) {
                $this->addError("{$path}.key", "Duplicate pipeline key: {$key}.");
                continue;
            }
            $seenKeys[] = $key;

            // Entity type
            $entity = $pipeline['entity_type'] ?? null;
            if ($entity && !in_array($entity, BlueprintSchema::PIPELINE_ENTITY_TYPES, true)) {
                $this->addError("{$path}.entity_type", "Unsupported pipeline entity type: {$entity}.");
            }

            // Stages
            $stages = $pipeline['stages'] ?? [];
            if (empty($stages)) {
                $this->addError("{$path}.stages", 'Pipeline must have at least one stage.');
                continue;
            }

            $stageKeys = [];
            $lastOrder = -1;
            foreach ($stages as $j => $stage) {
                $stagePath = "{$path}.stages.{$j}";
                $stageKey = $stage['key'] ?? null;
                if (!$stageKey) {
                    $this->addError("{$stagePath}.key", 'Stage key is required.');
                    continue;
                }
                $this->validateLocalKey("{$stagePath}.key", $stageKey);
                if (in_array($stageKey, $stageKeys, true)) {
                    $this->addError("{$stagePath}.key", "Duplicate stage key: {$stageKey}.");
                }
                $stageKeys[] = $stageKey;

                $order = $stage['order'] ?? ($j + 1);
                if ($order <= $lastOrder) {
                    $this->addError("{$stagePath}.order", "Invalid stage ordering: stage '{$stageKey}' order ({$order}) must be greater than previous ({$lastOrder}).");
                }
                $lastOrder = $order;
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  Approval Workflows
    // ═══════════════════════════════════════════════════════════════

    private function validateApprovalWorkflows(array $workflows, array $roleKeys): void
    {
        $seenKeys = [];
        $validApproverPermKeys = PermissionCatalog::approverKeys();

        foreach ($workflows as $i => $wf) {
            $path = "approval_workflows.{$i}";
            $key = $wf['key'] ?? null;
            if (!$key) {
                $this->addError("{$path}.key", 'Workflow key is required.');
                continue;
            }
            if (!$this->validateLocalKey("{$path}.key", $key)) {
                continue;
            }
            if (in_array($key, $seenKeys, true)) {
                $this->addError("{$path}.key", "Duplicate workflow key: {$key}.");
                continue;
            }
            $seenKeys[] = $key;

            // Entity type
            $entity = $wf['entity_type'] ?? null;
            if (!$entity) {
                $this->addError("{$path}.entity_type", 'Workflow entity_type is required.');
            } elseif (!in_array($entity, BlueprintSchema::APPROVAL_ENTITY_TYPES, true)) {
                $this->addError("{$path}.entity_type", "Unsupported workflow entity type: {$entity}.");
            }

            // Trigger conditions (structural validation)
            if (isset($wf['trigger_conditions'])) {
                $tcValidator = new TriggerConditionValidator();
                $tcErrors = $tcValidator->validate($wf['trigger_conditions']);
                if ($tcErrors) {
                    foreach ($tcErrors as $err) {
                        $this->addError("{$path}.trigger_conditions", $err);
                    }
                }
            }

            // Steps
            $steps = $wf['steps'] ?? [];
            if (empty($steps)) {
                $this->addError("{$path}.steps", 'Workflow must have at least one approval step.');
                continue;
            }

            foreach ($steps as $j => $step) {
                $stepPath = "{$path}.steps.{$j}";

                // Approver reference: either role_key or approver_permission_key
                $roleRef = $step['approver_role_key'] ?? null;
                $permRef = $step['approver_permission_key'] ?? null;

                if (!$roleRef && !$permRef) {
                    $this->addError("{$stepPath}", 'Approval step must have either approver_role_key or approver_permission_key.');
                }

                if ($roleRef) {
                    $this->validateLocalKey("{$stepPath}.approver_role_key", $roleRef);
                    if (!in_array($roleRef, $roleKeys, true)) {
                        $this->addError("{$stepPath}.approver_role_key",
                            "Approval step references role '{$roleRef}' not found in blueprint roles.");
                    }
                }

                if ($permRef && !in_array($permRef, $validApproverPermKeys, true)) {
                    $this->addError("{$stepPath}.approver_permission_key",
                        "Permission key '{$permRef}' is not usable as an approver. Valid: " . implode(', ', $validApproverPermKeys) . ".");
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  Commission Rules
    // ═══════════════════════════════════════════════════════════════

    private function validateCommissionRules(array $rules): void
    {
        $seenKeys = [];

        foreach ($rules as $i => $rule) {
            $path = "commission_rules.{$i}";
            $key = $rule['key'] ?? null;
            if ($key) {
                $this->validateLocalKey("{$path}.key", $key);
                if (in_array($key, $seenKeys, true)) {
                    $this->addError("{$path}.key", "Duplicate commission rule key: {$key}.");
                }
                $seenKeys[] = $key;
            }

            $model = $rule['calculation_model'] ?? null;
            if ($model && !in_array($model, BlueprintSchema::COMMISSION_MODELS, true)) {
                $this->addError("{$path}.calculation_model", "Unsupported commission model: {$model}.");
            }

            $rate = $rule['rate'] ?? null;
            if ($rate !== null && (is_numeric($rate) && (float)$rate < 0)) {
                $this->addError("{$path}.rate", "Commission rate cannot be negative.");
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  Workspace Settings & Localization
    // ═══════════════════════════════════════════════════════════════

    private function validateWorkspaceSettings(array $settings): void
    {
        if (empty($settings)) return;

        if (isset($settings['currency'])) {
            $cur = $settings['currency'];
            if (!is_string($cur) || !preg_match('/^[A-Z]{3}$/', $cur)) {
                $this->addError('workspace_settings.currency', "Currency must be a 3-letter uppercase code, got: {$cur}.");
            }
        }
    }

    private function validateLocalization(array $loc): void
    {
        if (empty($loc)) return;
        // Accept any structure — no invented constraints
    }

    // ═══════════════════════════════════════════════════════════════
    //  Local-Key & Error/Warning Helpers
    // ═══════════════════════════════════════════════════════════════

    /**
     * Validate that a Blueprint-local key uses the safe format.
     * Rejects UUID-shaped or non-lowercase identifiers.
     */
    private function validateLocalKey(string $path, string $key): bool
    {
        if (!BlueprintSchema::isValidLocalKey($key)) {
            $reason = BlueprintSchema::isUuidShaped($key)
                ? "Blueprint key must be a readable local reference, not a database ID: {$key}."
                : "Invalid local key format: '{$key}'. Must match ^[a-z][a-z0-9_]{1,63}$.";
            $this->addError($path, $reason);
            return false;
        }
        return true;
    }

    private function addError(string $path, string $message): void
    {
        $this->errors[$path] = $this->errors[$path] ?? [];
        $this->errors[$path][] = $message;
    }

    private function addWarning(string $message): void
    {
        $this->warnings[] = $message;
    }
}
