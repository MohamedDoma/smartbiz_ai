<?php

namespace Tests\Feature;

use App\Models\WorkspaceConfiguration;
use Database\Seeders\SmartBizDemoSeeder;

/**
 * DemoWorkspaceConfigurationTest — Tests for the demo workspace WorkspaceConfiguration.
 *
 * Verifies:
 *  1. SmartBizDemoSeeder creates WorkspaceConfiguration for the demo workspace.
 *  2. enabled_modules is an array.
 *  3. enabled_modules contains `commissions`.
 *  4. Every seeded module key is in the canonical DEMO_ENABLED_MODULES constant.
 *  5. Running the configuration seeding twice does not duplicate module keys.
 *  6. An existing extra module remains preserved.
 *  7. Existing role_configs remain preserved.
 *  8. Existing pages remain preserved.
 *  9. Existing workflows remain preserved.
 * 10. Existing automations remain preserved.
 * 11. The approval entity-types endpoint returns commission_entry with commissions enabled.
 * 12. The endpoint excludes commission_entry when commissions is removed.
 */
class DemoWorkspaceConfigurationTest extends SmartBizTestCase
{
    private const DEMO_WS = SmartBizDemoSeeder::WS;

    // ═══════════════════════════════════════════════════════════
    //  Helpers
    // ═══════════════════════════════════════════════════════════

    /**
     * Remove any workspace configuration for the demo workspace.
     * Called before tests that need to start from a clean slate.
     */
    private function deleteConfig(): void
    {
        WorkspaceConfiguration::where('workspace_id', self::DEMO_WS)->delete();
    }

    /**
     * Run the seeder's configuration method.
     */
    private function runConfigSeeder(): void
    {
        (new SmartBizDemoSeeder())->seedWorkspaceConfiguration();
    }

    /**
     * Get the current configuration for the demo workspace.
     */
    private function getConfig(): ?WorkspaceConfiguration
    {
        return WorkspaceConfiguration::where('workspace_id', self::DEMO_WS)->first();
    }

    /**
     * Original config backup for teardown.
     */
    private ?array $originalConfig = null;

    protected function setUp(): void
    {
        parent::setUp();

        // Back up any existing config so we can restore it in tearDown.
        $config = $this->getConfig();
        $this->originalConfig = $config ? $config->toArray() : null;
    }

    protected function tearDown(): void
    {
        // Restore original state.
        if ($this->originalConfig !== null) {
            WorkspaceConfiguration::updateOrCreate(
                ['workspace_id' => self::DEMO_WS],
                [
                    'enabled_modules' => $this->originalConfig['enabled_modules'] ?? [],
                    'role_configs'    => $this->originalConfig['role_configs'] ?? [],
                    'pages'           => $this->originalConfig['pages'] ?? [],
                    'workflows'       => $this->originalConfig['workflows'] ?? [],
                    'automations'     => $this->originalConfig['automations'] ?? [],
                ],
            );
        } else {
            // There was no config before the test — remove anything we created.
            $this->deleteConfig();
        }

        parent::tearDown();
    }

    // ═══════════════════════════════════════════════════════════
    //  1. Creates WorkspaceConfiguration
    // ═══════════════════════════════════════════════════════════

    public function test_seeder_creates_workspace_configuration(): void
    {
        $this->deleteConfig();

        $this->runConfigSeeder();

        $config = $this->getConfig();
        $this->assertNotNull($config, 'WorkspaceConfiguration must be created for the demo workspace.');
        $this->assertEquals(self::DEMO_WS, $config->workspace_id);
    }

    // ═══════════════════════════════════════════════════════════
    //  2. enabled_modules is an array
    // ═══════════════════════════════════════════════════════════

    public function test_enabled_modules_is_array(): void
    {
        $this->deleteConfig();
        $this->runConfigSeeder();

        $config = $this->getConfig();
        $this->assertIsArray($config->enabled_modules);
    }

    // ═══════════════════════════════════════════════════════════
    //  3. enabled_modules contains commissions
    // ═══════════════════════════════════════════════════════════

    public function test_enabled_modules_contains_commissions(): void
    {
        $this->deleteConfig();
        $this->runConfigSeeder();

        $config = $this->getConfig();
        $this->assertContains('commissions', $config->enabled_modules,
            'enabled_modules must contain commissions for the demo workspace.');
    }

    // ═══════════════════════════════════════════════════════════
    //  4. Every module key is in canonical constant
    // ═══════════════════════════════════════════════════════════

    public function test_every_module_key_is_in_canonical_source(): void
    {
        $this->deleteConfig();
        $this->runConfigSeeder();

        $config = $this->getConfig();
        $canonical = SmartBizDemoSeeder::DEMO_ENABLED_MODULES;

        foreach ($config->enabled_modules as $mod) {
            $this->assertContains($mod, $canonical,
                "Module '{$mod}' is not in DEMO_ENABLED_MODULES.");
        }
    }

    // ═══════════════════════════════════════════════════════════
    //  5. Running twice does not duplicate module keys
    // ═══════════════════════════════════════════════════════════

    public function test_idempotent_no_duplicate_modules(): void
    {
        $this->deleteConfig();

        $this->runConfigSeeder();
        $this->runConfigSeeder(); // Second run

        $config = $this->getConfig();
        $modules = $config->enabled_modules;
        $this->assertCount(count(array_unique($modules)), $modules,
            'Running the seeder twice must not duplicate module keys.');
    }

    // ═══════════════════════════════════════════════════════════
    //  6. Existing extra module remains preserved
    // ═══════════════════════════════════════════════════════════

    public function test_existing_extra_module_preserved(): void
    {
        $this->deleteConfig();

        // Pre-seed with an extra custom module.
        WorkspaceConfiguration::create([
            'workspace_id'    => self::DEMO_WS,
            'enabled_modules' => ['custom_module_xyz'],
            'role_configs'    => [],
            'pages'           => [],
            'workflows'       => [],
            'automations'     => [],
        ]);

        $this->runConfigSeeder();

        $config = $this->getConfig();
        $this->assertContains('custom_module_xyz', $config->enabled_modules,
            'Existing extra modules must be preserved after seeding.');
        $this->assertContains('commissions', $config->enabled_modules,
            'Canonical modules must be added alongside existing extras.');
    }

    // ═══════════════════════════════════════════════════════════
    //  7. Existing role_configs remain preserved
    // ═══════════════════════════════════════════════════════════

    public function test_existing_role_configs_preserved(): void
    {
        $this->deleteConfig();

        WorkspaceConfiguration::create([
            'workspace_id'    => self::DEMO_WS,
            'enabled_modules' => ['commissions'],
            'role_configs'    => ['owner' => ['homepage' => '/custom']],
            'pages'           => [],
            'workflows'       => [],
            'automations'     => [],
        ]);

        $this->runConfigSeeder();

        $config = $this->getConfig();
        $this->assertIsArray($config->role_configs);
        $this->assertEquals('/custom', $config->role_configs['owner']['homepage'],
            'Existing role_configs must not be overwritten by the seeder.');
    }

    // ═══════════════════════════════════════════════════════════
    //  8. Existing pages remain preserved
    // ═══════════════════════════════════════════════════════════

    public function test_existing_pages_preserved(): void
    {
        $this->deleteConfig();

        WorkspaceConfiguration::create([
            'workspace_id'    => self::DEMO_WS,
            'enabled_modules' => [],
            'role_configs'    => [],
            'pages'           => ['dashboard', 'custom_page'],
            'workflows'       => [],
            'automations'     => [],
        ]);

        $this->runConfigSeeder();

        $config = $this->getConfig();
        $this->assertContains('custom_page', $config->pages,
            'Existing pages must not be overwritten.');
    }

    // ═══════════════════════════════════════════════════════════
    //  9. Existing workflows remain preserved
    // ═══════════════════════════════════════════════════════════

    public function test_existing_workflows_preserved(): void
    {
        $this->deleteConfig();

        $existingWorkflow = ['name' => 'custom_wf', 'description' => 'Test'];
        WorkspaceConfiguration::create([
            'workspace_id'    => self::DEMO_WS,
            'enabled_modules' => [],
            'role_configs'    => [],
            'pages'           => [],
            'workflows'       => [$existingWorkflow],
            'automations'     => [],
        ]);

        $this->runConfigSeeder();

        $config = $this->getConfig();
        $this->assertContains($existingWorkflow, $config->workflows,
            'Existing workflows must not be overwritten.');
    }

    // ═══════════════════════════════════════════════════════════
    //  10. Existing automations remain preserved
    // ═══════════════════════════════════════════════════════════

    public function test_existing_automations_preserved(): void
    {
        $this->deleteConfig();

        $existingAuto = ['name' => 'custom_auto', 'trigger' => 'test'];
        WorkspaceConfiguration::create([
            'workspace_id'    => self::DEMO_WS,
            'enabled_modules' => [],
            'role_configs'    => [],
            'pages'           => [],
            'workflows'       => [],
            'automations'     => [$existingAuto],
        ]);

        $this->runConfigSeeder();

        $config = $this->getConfig();
        $this->assertContains($existingAuto, $config->automations,
            'Existing automations must not be overwritten.');
    }

    /**
     * Original test-workspace config backup.
     */
    private ?array $originalTestWsConfig = null;

    /**
     * Helper: get/delete/set config for the test workspace used by wsGet().
     */
    private function getTestWsConfig(): ?WorkspaceConfiguration
    {
        return WorkspaceConfiguration::where('workspace_id', $this->workspaceId)->first();
    }

    private function deleteTestWsConfig(): void
    {
        WorkspaceConfiguration::where('workspace_id', $this->workspaceId)->delete();
    }

    private function backupTestWsConfig(): void
    {
        $c = $this->getTestWsConfig();
        $this->originalTestWsConfig = $c ? $c->toArray() : null;
    }

    private function restoreTestWsConfig(): void
    {
        if ($this->originalTestWsConfig !== null) {
            WorkspaceConfiguration::updateOrCreate(
                ['workspace_id' => $this->workspaceId],
                [
                    'enabled_modules' => $this->originalTestWsConfig['enabled_modules'] ?? [],
                    'role_configs'    => $this->originalTestWsConfig['role_configs'] ?? [],
                    'pages'           => $this->originalTestWsConfig['pages'] ?? [],
                    'workflows'       => $this->originalTestWsConfig['workflows'] ?? [],
                    'automations'     => $this->originalTestWsConfig['automations'] ?? [],
                ],
            );
        } else {
            $this->deleteTestWsConfig();
        }
    }

    // ═══════════════════════════════════════════════════════════
    //  11. Endpoint returns commission_entry after config present
    // ═══════════════════════════════════════════════════════════

    public function test_entity_types_returns_commission_entry_after_config(): void
    {
        $this->backupTestWsConfig();

        // Ensure commissions is enabled for the test workspace.
        WorkspaceConfiguration::updateOrCreate(
            ['workspace_id' => $this->workspaceId],
            [
                'enabled_modules' => SmartBizDemoSeeder::DEMO_ENABLED_MODULES,
                'role_configs'    => [],
                'pages'           => [],
                'workflows'       => [],
                'automations'     => [],
            ],
        );

        $response = $this->wsGet('/api/approval-entity-types');
        $response->assertOk();

        $data = $response->json('data');
        $entityTypes = array_column($data, 'entity_type');
        $this->assertContains('commission_entry', $entityTypes,
            'commission_entry must appear when commissions module is enabled via WorkspaceConfiguration.');

        $this->restoreTestWsConfig();
    }

    // ═══════════════════════════════════════════════════════════
    //  12. Endpoint excludes commission_entry when removed
    // ═══════════════════════════════════════════════════════════

    public function test_entity_types_excludes_commission_entry_when_removed(): void
    {
        $this->backupTestWsConfig();

        // Create config WITHOUT commissions for the test workspace.
        WorkspaceConfiguration::updateOrCreate(
            ['workspace_id' => $this->workspaceId],
            [
                'enabled_modules' => ['dashboard', 'inventory'],
                'role_configs'    => [],
                'pages'           => [],
                'workflows'       => [],
                'automations'     => [],
            ],
        );

        $response = $this->wsGet('/api/approval-entity-types');
        $response->assertOk();

        $data = $response->json('data');
        $entityTypes = array_column($data, 'entity_type');
        $this->assertNotContains('commission_entry', $entityTypes,
            'commission_entry must not appear when commissions is intentionally excluded.');

        $this->restoreTestWsConfig();
    }
}

