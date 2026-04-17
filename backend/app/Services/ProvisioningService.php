<?php

namespace App\Services;

use App\Models\DiscoveryBlueprint;
use App\Models\ProvisioningRun;
use App\Models\WorkspaceConfiguration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * ERP Provisioning Engine.
 * Transforms discovery blueprints into workspace configurations.
 */
class ProvisioningService
{
    /**
     * Preview: generate config from blueprint without applying.
     */
    public function preview(string $workspaceId, string $blueprintId): array
    {
        $blueprint = DiscoveryBlueprint::where('workspace_id', $workspaceId)
            ->where('id', $blueprintId)
            ->firstOrFail();

        $config = $this->buildConfig($blueprint);

        // Create preview run
        $run = ProvisioningRun::create([
            'workspace_id' => $workspaceId,
            'blueprint_id' => $blueprintId,
            'status'       => 'preview',
            'config'       => $config,
            'version'      => $this->nextVersion($workspaceId),
            'created_at'   => now(),
        ]);

        return [
            'run_id' => $run->id,
            'status' => 'preview',
            'config' => $config,
        ];
    }

    /**
     * Apply: provision workspace with blueprint config.
     */
    public function apply(string $workspaceId, string $blueprintId, string $userId): array
    {
        return DB::transaction(function () use ($workspaceId, $blueprintId, $userId) {
            $blueprint = DiscoveryBlueprint::where('workspace_id', $workspaceId)
                ->where('id', $blueprintId)
                ->firstOrFail();

            $config = $this->buildConfig($blueprint);

            // Capture current config for rollback
            $existing = WorkspaceConfiguration::where('workspace_id', $workspaceId)->first();
            $rollbackConfig = $existing ? [
                'enabled_modules' => $existing->enabled_modules,
                'role_configs'    => $existing->role_configs,
                'pages'           => $existing->pages,
                'workflows'       => $existing->workflows,
                'automations'     => $existing->automations,
            ] : null;

            // Create run
            $run = ProvisioningRun::create([
                'workspace_id'  => $workspaceId,
                'blueprint_id'  => $blueprintId,
                'status'        => 'applied',
                'config'        => $config,
                'applied_by'    => $userId,
                'applied_at'    => now(),
                'version'       => $this->nextVersion($workspaceId),
                'rollback_config' => $rollbackConfig,
                'created_at'    => now(),
            ]);

            // Upsert workspace configuration
            WorkspaceConfiguration::updateOrCreate(
                ['workspace_id' => $workspaceId],
                [
                    'enabled_modules'     => $config['enabled_modules'],
                    'role_configs'        => $config['role_configs'],
                    'pages'               => $config['pages'],
                    'workflows'           => $config['workflows'],
                    'automations'         => $config['automations'],
                    'provisioning_run_id' => $run->id,
                ],
            );

            Log::info("Provisioning applied for workspace {$workspaceId}, run {$run->id}");

            return [
                'run_id'  => $run->id,
                'status'  => 'applied',
                'version' => $run->version,
                'config'  => $config,
            ];
        });
    }

    /**
     * Rollback: revert to previous configuration.
     */
    public function rollback(string $workspaceId, string $runId, string $userId): array
    {
        return DB::transaction(function () use ($workspaceId, $runId, $userId) {
            $run = ProvisioningRun::where('workspace_id', $workspaceId)
                ->where('id', $runId)
                ->where('status', 'applied')
                ->firstOrFail();

            $rb = $run->rollback_config ?? [
                'enabled_modules' => [],
                'role_configs'    => [],
                'pages'           => [],
                'workflows'       => [],
                'automations'     => [],
            ];

            WorkspaceConfiguration::updateOrCreate(
                ['workspace_id' => $workspaceId],
                [
                    'enabled_modules'     => $rb['enabled_modules'] ?? [],
                    'role_configs'        => $rb['role_configs'] ?? [],
                    'pages'               => $rb['pages'] ?? [],
                    'workflows'           => $rb['workflows'] ?? [],
                    'automations'         => $rb['automations'] ?? [],
                    'provisioning_run_id' => null,
                ],
            );

            $run->update(['status' => 'rolled_back']);

            return ['run_id' => $run->id, 'status' => 'rolled_back'];
        });
    }

    /**
     * Get active workspace configuration.
     */
    public function getActiveConfig(string $workspaceId): ?WorkspaceConfiguration
    {
        return WorkspaceConfiguration::where('workspace_id', $workspaceId)->first();
    }

    /**
     * Update module enablement.
     */
    public function updateModules(string $workspaceId, array $modules): WorkspaceConfiguration
    {
        $config = WorkspaceConfiguration::firstOrCreate(
            ['workspace_id' => $workspaceId],
            ['enabled_modules' => [], 'role_configs' => [], 'pages' => [], 'workflows' => [], 'automations' => []],
        );

        $config->update(['enabled_modules' => $modules]);
        return $config->fresh();
    }

    /**
     * Update a specific role's configuration.
     */
    public function updateRoleConfig(string $workspaceId, string $role, array $roleConfig): WorkspaceConfiguration
    {
        $config = WorkspaceConfiguration::firstOrCreate(
            ['workspace_id' => $workspaceId],
            ['enabled_modules' => [], 'role_configs' => [], 'pages' => [], 'workflows' => [], 'automations' => []],
        );

        $roles = $config->role_configs;
        $roles[$role] = array_merge($roles[$role] ?? [], $roleConfig);
        $config->update(['role_configs' => $roles]);

        return $config->fresh();
    }

    // ── Private helpers ───────────────────────────────────────

    /**
     * Build a normalized config from a blueprint.
     */
    private function buildConfig(DiscoveryBlueprint $blueprint): array
    {
        $bp = $blueprint->blueprint;

        // Build role_configs: merge role_homepages, role_navigation, etc.
        $roleConfigs = [];
        $roles = $bp['recommended_roles'] ?? [];
        foreach ($roles as $role) {
            $name = $role['name'];
            $roleConfigs[$name] = [
                'description'      => $role['description'] ?? '',
                'homepage'         => $bp['role_homepages'][$name] ?? '/dashboard',
                'navigation'       => $bp['role_navigation'][$name] ?? [],
                'quick_actions'    => $bp['role_quick_actions'][$name] ?? [],
                'allowed_screens'  => $bp['role_allowed_screens'][$name] ?? [],
                'dashboard_widgets' => $bp['role_dashboard_widgets'][$name] ?? [],
            ];
        }

        return [
            'business_type'   => $bp['business_type'] ?? $blueprint->business_type,
            'enabled_modules' => $bp['enabled_modules'] ?? [],
            'optional_modules' => $bp['optional_modules'] ?? [],
            'role_configs'    => $roleConfigs,
            'pages'           => $bp['recommended_pages'] ?? [],
            'workflows'       => $bp['recommended_workflows'] ?? [],
            'automations'     => $bp['recommended_automations'] ?? [],
            'dashboards'      => $bp['recommended_dashboards'] ?? [],
        ];
    }

    private function nextVersion(string $workspaceId): int
    {
        return (ProvisioningRun::where('workspace_id', $workspaceId)->max('version') ?? 0) + 1;
    }
}
