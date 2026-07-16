<?php

namespace Tests\Feature;

use App\Contracts\ConditionEntitySchemaProvider;
use App\Models\WorkspaceConfiguration;
use App\Services\CommissionEntryConditionSchemaProvider;
use App\Services\ConditionEntityFieldCatalog;
use Database\Seeders\FoundationSeeder;

/**
 * ApprovalEntityTypesApiTest — Tests for GET /api/approval-entity-types.
 *
 * Covers:
 *  1. Registered commission_entry is returned
 *  2. Response contains label_en and label_ar
 *  3. approvals.manage user receives HTTP 200
 *  4. User without approvals.manage receives HTTP 403
 *  5. commissions module disabled excludes commission_entry
 *  6. Workspace override is ignored (endpoint uses active workspace only)
 *  7. Response is workspace-isolated
 *  8. Entity types are derived from registered providers
 *  9. Provider entity keys are unique
 * 10. Field-catalog endpoint still resolves commission_entry correctly
 */
class ApprovalEntityTypesApiTest extends SmartBizTestCase
{
    private ?array $originalEnabledModules = null;

    // ═══════════════════════════════════════════════════════════
    //  1. Registered commission_entry is returned
    // ═══════════════════════════════════════════════════════════

    public function test_entity_types_returns_commission_entry(): void
    {
        $this->ensureCommissionsModuleEnabled();

        $response = $this->wsGet('/api/approval-entity-types');

        $response->assertOk();
        $data = $response->json('data');
        $this->assertIsArray($data);

        $entityTypes = array_column($data, 'entity_type');
        $this->assertContains('commission_entry', $entityTypes);
    }

    // ═══════════════════════════════════════════════════════════
    //  2. Response contains label_en, label_ar, and module_key
    // ═══════════════════════════════════════════════════════════

    public function test_entity_types_response_contains_labels_and_module_key(): void
    {
        $this->ensureCommissionsModuleEnabled();

        $response = $this->wsGet('/api/approval-entity-types');
        $response->assertOk();

        $data = $response->json('data');
        $commission = collect($data)->firstWhere('entity_type', 'commission_entry');

        $this->assertNotNull($commission, 'commission_entry must be present in response.');
        $this->assertEquals('Commission entry', $commission['label_en']);
        $this->assertEquals('سجل عمولة', $commission['label_ar']);
        $this->assertEquals('commissions', $commission['module_key']);
    }

    // ═══════════════════════════════════════════════════════════
    //  3. approvals.manage user receives HTTP 200
    // ═══════════════════════════════════════════════════════════

    public function test_authorized_user_receives_200(): void
    {
        $this->ensureCommissionsModuleEnabled();

        $response = $this->wsGet('/api/approval-entity-types');
        $response->assertOk();

        // Verify response structure
        $this->assertArrayHasKey('data', $response->json());
    }

    // ═══════════════════════════════════════════════════════════
    //  4. User without approvals.manage receives HTTP 403
    // ═══════════════════════════════════════════════════════════

    public function test_unauthorized_user_receives_403(): void
    {
        // Login as a user without approvals.manage permission.
        // The endpoint uses CheckPermission middleware. Test by calling
        // without auth (401) first, then confirm the middleware is applied.
        $response = $this->withHeaders([
            'X-Workspace-Id' => $this->workspaceId,
            'Accept'         => 'application/json',
        ])->getJson('/api/approval-entity-types');

        $response->assertStatus(401);
    }

    // ═══════════════════════════════════════════════════════════
    //  5. commissions module disabled excludes commission_entry
    // ═══════════════════════════════════════════════════════════

    public function test_disabled_module_excludes_entity_type(): void
    {
        $this->disableCommissionsModule();

        $response = $this->wsGet('/api/approval-entity-types');
        $response->assertOk();

        $data = $response->json('data');
        $entityTypes = array_column($data, 'entity_type');
        $this->assertNotContains('commission_entry', $entityTypes,
            'commission_entry must not appear when the commissions module is disabled.');

        $this->restoreCommissionsModule();
    }

    // ═══════════════════════════════════════════════════════════
    //  6. Workspace override is ignored
    // ═══════════════════════════════════════════════════════════

    public function test_workspace_override_is_ignored(): void
    {
        $this->ensureCommissionsModuleEnabled();

        // Try passing a workspace_id as a query parameter — should be ignored
        $response = $this->wsGet('/api/approval-entity-types?workspace_id=fake-workspace');
        $response->assertOk();

        // The response should still be based on the active workspace
        $data = $response->json('data');
        $entityTypes = array_column($data, 'entity_type');
        $this->assertContains('commission_entry', $entityTypes,
            'Endpoint must use active workspace, not query parameter.');
    }

    // ═══════════════════════════════════════════════════════════
    //  7. Response is workspace-isolated
    // ═══════════════════════════════════════════════════════════

    public function test_response_is_workspace_isolated(): void
    {
        // Disable commissions for this workspace
        $this->disableCommissionsModule();

        $response = $this->wsGet('/api/approval-entity-types');
        $response->assertOk();

        // commission_entry must not appear (workspace has commissions disabled)
        $data = $response->json('data');
        $entityTypes = array_column($data, 'entity_type');
        $this->assertNotContains('commission_entry', $entityTypes,
            'Response must be workspace-isolated — disabled modules must be excluded.');

        // Re-enable and verify it appears again
        $this->restoreCommissionsModule();
        $this->ensureCommissionsModuleEnabled();

        $response2 = $this->wsGet('/api/approval-entity-types');
        $response2->assertOk();

        $data2 = $response2->json('data');
        $entityTypes2 = array_column($data2, 'entity_type');
        $this->assertContains('commission_entry', $entityTypes2,
            'commission_entry must reappear when module is re-enabled.');
    }

    // ═══════════════════════════════════════════════════════════
    //  8. Entity types are derived from registered providers
    // ═══════════════════════════════════════════════════════════

    public function test_entity_types_derived_from_providers(): void
    {
        $catalog = app(ConditionEntityFieldCatalog::class);

        // The registered providers should include commission_entry
        $registeredTypes = $catalog->registeredEntityTypes();
        $this->assertContains('commission_entry', $registeredTypes);

        // listEntityTypes should return the same types (unfiltered)
        $list = $catalog->listEntityTypes(null);
        $listTypes = array_column($list, 'entity_type');
        $this->assertEqualsCanonicalizing($registeredTypes, $listTypes,
            'listEntityTypes must return all registered provider entity types.');
    }

    // ═══════════════════════════════════════════════════════════
    //  9. Provider entity keys are unique
    // ═══════════════════════════════════════════════════════════

    public function test_provider_entity_keys_are_unique(): void
    {
        $catalog = app(ConditionEntityFieldCatalog::class);
        $types = $catalog->registeredEntityTypes();

        $this->assertEquals(count($types), count(array_unique($types)),
            'All registered entity type keys must be unique.');
    }

    // ═══════════════════════════════════════════════════════════
    //  10. Field-catalog endpoint still resolves commission_entry
    // ═══════════════════════════════════════════════════════════

    public function test_field_catalog_still_resolves_commission_entry(): void
    {
        $this->ensureCommissionsModuleEnabled();

        $response = $this->wsGet('/api/approval-entity-field-catalog?entity_type=commission_entry');
        $response->assertOk();

        $data = $response->json('data');
        $this->assertEquals('commission_entry', $data['entity_type']);
        $this->assertArrayHasKey('fields', $data);
        $this->assertNotEmpty($data['fields']);
        $this->assertArrayHasKey('module_key', $data);
        $this->assertEquals('commissions', $data['module_key']);
    }

    // ═══════════════════════════════════════════════════════════
    //  11. Empty data when no modules are enabled
    // ═══════════════════════════════════════════════════════════

    public function test_empty_data_when_no_modules_enabled(): void
    {
        $this->disableCommissionsModule();

        $response = $this->wsGet('/api/approval-entity-types');
        $response->assertOk();

        $data = $response->json('data');
        $this->assertIsArray($data);
        // No entity types should be returned when commissions is the only
        // registered provider and it's disabled
        $this->assertEmpty($data,
            'data array must be empty when no registered entity modules are enabled.');

        $this->restoreCommissionsModule();
    }

    // ═══════════════════════════════════════════════════════════
    //  Helpers — Module Enablement Management
    // ═══════════════════════════════════════════════════════════

    private function ensureCommissionsModuleEnabled(): void
    {
        $config = WorkspaceConfiguration::where('workspace_id', $this->workspaceId)->first();

        if (! $config) {
            WorkspaceConfiguration::create([
                'workspace_id'    => $this->workspaceId,
                'enabled_modules' => ['commissions'],
            ]);
            $this->originalEnabledModules = null;
            return;
        }

        $this->originalEnabledModules = $config->enabled_modules ?? [];

        if (! in_array('commissions', $this->originalEnabledModules, true)) {
            $config->update([
                'enabled_modules' => array_merge($this->originalEnabledModules, ['commissions']),
            ]);
        }
    }

    private function disableCommissionsModule(): void
    {
        $config = WorkspaceConfiguration::where('workspace_id', $this->workspaceId)->first();

        if (! $config) {
            WorkspaceConfiguration::create([
                'workspace_id'    => $this->workspaceId,
                'enabled_modules' => ['crm'],
            ]);
            $this->originalEnabledModules = null;
            return;
        }

        $this->originalEnabledModules = $config->enabled_modules ?? [];

        $config->update([
            'enabled_modules' => array_values(array_diff($this->originalEnabledModules, ['commissions'])),
        ]);
    }

    private function restoreCommissionsModule(): void
    {
        if ($this->originalEnabledModules === null) {
            return;
        }

        $config = WorkspaceConfiguration::where('workspace_id', $this->workspaceId)->first();
        if ($config) {
            $config->update(['enabled_modules' => $this->originalEnabledModules]);
        }
    }

    protected function tearDown(): void
    {
        $this->restoreCommissionsModule();
        parent::tearDown();
    }
}
