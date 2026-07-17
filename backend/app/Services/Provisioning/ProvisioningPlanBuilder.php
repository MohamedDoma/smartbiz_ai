<?php

namespace App\Services\Provisioning;

use App\Models\DiscoveryBlueprint;
use App\Services\Blueprint\BlueprintSchema;

/**
 * Builds a deterministic, versionable execution plan from a canonical Blueprint.
 *
 * The plan describes what entity-provisioning steps will be executed in Task 1.6B+.
 * It does NOT create any real workspace entities.
 *
 * Priority: canonical Blueprint JSON → normalized operations → summary + warnings.
 */
class ProvisioningPlanBuilder
{
    /**
     * Build a normalized execution plan from a validated canonical Blueprint.
     *
     * @param  DiscoveryBlueprint  $blueprint  Validated canonical Blueprint record
     * @param  string              $workspaceId Authenticated workspace ID
     * @return array               Deterministic execution plan
     */
    public function build(DiscoveryBlueprint $blueprint, string $workspaceId): array
    {
        $bp = $blueprint->blueprint;

        $operations = $this->buildOperations($bp);
        $summary    = $this->buildSummary($operations);
        $warnings   = $this->buildWarnings($bp, $operations);

        return [
            'schema_version'    => $bp['schema_version'] ?? BlueprintSchema::VERSION,
            'blueprint_id'      => $blueprint->id,
            'blueprint_version' => $blueprint->version,
            'workspace_id'      => $workspaceId,
            'operations'        => $operations,
            'summary'           => $summary,
            'warnings'          => $warnings,
        ];
    }

    /**
     * Build the operations section from Blueprint payload.
     */
    private function buildOperations(array $bp): array
    {
        return [
            'workspace_settings'   => $this->extractWorkspaceSettings($bp),
            'modules'              => $this->extractModules($bp),
            'locations'            => $bp['locations'] ?? [],
            'departments'          => $bp['departments'] ?? [],
            'teams'                => $bp['teams'] ?? [],
            'roles'                => $this->extractRoles($bp),
            'warehouses'           => $bp['warehouses'] ?? [],
            'pipelines'            => $bp['pipelines'] ?? [],
            'approval_workflows'   => $bp['approval_workflows'] ?? [],
            'commission_rules'     => $bp['commission_rules'] ?? [],
            'payment_methods'      => $bp['payment_methods'] ?? [],
            'tax_settings'         => $bp['tax_settings'] ?? [],
            'invoice_settings'     => $bp['invoice_settings'] ?? [],
            'pos_settings'         => $bp['pos_settings'] ?? [],
            'accounting_settings'  => $bp['accounting_settings'] ?? [],
        ];
    }

    /**
     * Extract workspace settings from Blueprint.
     */
    private function extractWorkspaceSettings(array $bp): array
    {
        $ws = $bp['workspace_settings'] ?? [];
        $profile = $bp['business_profile'] ?? [];

        return array_filter([
            'business_type'     => $profile['business_type'] ?? null,
            'business_name'     => $profile['business_name'] ?? null,
            'country'           => $ws['country'] ?? null,
            'currency'          => $ws['currency'] ?? null,
            'timezone'          => $ws['timezone'] ?? null,
            'primary_language'  => $ws['primary_language'] ?? null,
        ], fn($v) => $v !== null);
    }

    /**
     * Extract enabled modules from Blueprint modules array.
     */
    private function extractModules(array $bp): array
    {
        $modules = $bp['modules'] ?? [];
        if (!is_array($modules)) return [];

        return array_values(array_map(fn($m) => [
            'key'     => $m['key'],
            'enabled' => $m['enabled'] ?? false,
            'status'  => $m['status'] ?? 'optional',
        ], $modules));
    }

    /**
     * Extract roles with full permission arrays for entity creation.
     *
     * Operations preserve complete data needed by CoreEntityProvisioner.
     * Summary uses counts only.
     */
    private function extractRoles(array $bp): array
    {
        $roles = $bp['roles'] ?? [];
        if (!is_array($roles)) return [];

        return array_values(array_map(fn($r) => [
            'key'              => $r['key'],
            'name'             => $r['name'],
            'description'      => $r['description'] ?? '',
            'status'           => $r['status'] ?? 'recommended',
            'department_key'   => $r['department_key'] ?? null,
            'permissions'      => $r['permissions'] ?? [],
            'permission_count' => count($r['permissions'] ?? []),
            'is_primary_owner' => $r['is_primary_owner'] ?? false,
        ], $roles));
    }

    /**
     * Build summary counts for the plan.
     */
    private function buildSummary(array $operations): array
    {
        $enabledModules = array_filter($operations['modules'], fn($m) => $m['enabled']);

        return [
            'locations'            => count($operations['locations']),
            'departments'          => count($operations['departments']),
            'teams'                => count($operations['teams']),
            'roles'                => count($operations['roles']),
            'enabled_modules'      => count($enabledModules),
            'total_modules'        => count($operations['modules']),
            'warehouses'           => count($operations['warehouses']),
            'pipelines'            => count($operations['pipelines']),
            'approval_workflows'   => count($operations['approval_workflows']),
            'commission_rules'     => count($operations['commission_rules']),
            'payment_methods'      => count($operations['payment_methods']),
            'has_tax_settings'     => !empty($operations['tax_settings']),
            'has_pos_settings'     => !empty($operations['pos_settings']),
            'has_accounting'       => !empty($operations['accounting_settings']),
        ];
    }

    /**
     * Collect warnings about the plan.
     */
    private function buildWarnings(array $bp, array $operations): array
    {
        $warnings = [];

        // Check for workflows requiring configuration
        foreach ($operations['approval_workflows'] as $wf) {
            if (!empty($wf['requires_configuration'])) {
                $warnings[] = "Approval workflow '{$wf['key']}' requires configuration before activation.";
            }
        }

        // Check for placeholder location names
        foreach ($operations['locations'] as $loc) {
            if (preg_match('/^Branch \d+$/', $loc['name'] ?? '')) {
                $warnings[] = "Location '{$loc['key']}' has a placeholder name. Review before finalizing.";
            }
        }

        // Missing optional information from Blueprint
        $missing = $bp['missing_optional_information'] ?? [];
        if (!empty($missing)) {
            foreach ($missing as $m) {
                $warnings[] = "Missing: {$m}";
            }
        }

        return $warnings;
    }

    /**
     * Build a mapping of Blueprint fields → WorkspaceConfiguration fields.
     * Used for previewing what will be written to WorkspaceConfiguration.
     */
    public function buildConfigMapping(array $bp, string $blueprintId, int $blueprintVersion): array
    {
        $modules = $bp['modules'] ?? [];
        $enabledModuleKeys = array_column(
            array_filter($modules, fn($m) => $m['enabled'] ?? false),
            'key'
        );

        $roles = $bp['roles'] ?? [];
        $roleConfigs = [];
        foreach ($roles as $r) {
            $roleConfigs[$r['key']] = [
                'name'             => $r['name'],
                'description'      => $r['description'] ?? '',
                'department_key'   => $r['department_key'] ?? null,
                'permission_count' => count($r['permissions'] ?? []),
            ];
        }

        return [
            'enabled_modules' => $enabledModuleKeys,
            'role_configs'    => $roleConfigs,
            'pages'           => [],  // Populated by template or Flutter, not Blueprint
            'workflows'       => $this->extractWorkflowSummary($bp),
            'automations'     => [],  // No Blueprint-level automations yet
            'blueprint_meta'  => [
                'schema_version'    => $bp['schema_version'] ?? BlueprintSchema::VERSION,
                'blueprint_id'      => $blueprintId,
                'blueprint_version' => $blueprintVersion,
                'provisioned_at'    => null,  // Set when actually applied
            ],
        ];
    }

    /**
     * Extract a workflow summary for the config.
     */
    private function extractWorkflowSummary(array $bp): array
    {
        $workflows = [];
        foreach ($bp['approval_workflows'] ?? [] as $wf) {
            $workflows[] = [
                'key'         => $wf['key'],
                'name'        => $wf['name'],
                'entity_type' => $wf['entity_type'],
                'step_count'  => count($wf['steps'] ?? []),
                'active'      => empty($wf['requires_configuration']),
            ];
        }
        return $workflows;
    }
}
