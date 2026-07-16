<?php

namespace Tests\Feature;

use App\Contracts\ConditionEntitySchemaProvider;
use App\Models\WorkspaceConfiguration;
use App\Services\CommissionEntryConditionSchemaProvider;
use App\Services\ConditionEntityFieldCatalog;
use App\Services\TriggerConditionValidator;
use Database\Seeders\FoundationSeeder;
use Illuminate\Support\Facades\DB;

/**
 * EntityFieldCatalogTest — Comprehensive tests for the Phase 2 Entity Field Catalog.
 *
 * Covers:
 *  1. Unit tests for ConditionEntityFieldCatalog registry logic
 *  2. Unit tests for CommissionEntryConditionSchemaProvider field definitions
 *  3. Operator parity between the catalog and TriggerConditionValidator
 *  4. Field key parity between the catalog and CommissionEntryController runtime data
 *  5. API integration tests for /api/approval-entity-field-catalog
 *  6. Module enablement filtering
 *  7. Permission enforcement (403 without approvals.manage)
 *  8. 404 for unknown entity types
 */
class EntityFieldCatalogTest extends SmartBizTestCase
{
    // ═══════════════════════════════════════════════════════════
    //  1. Registry — Basic Registration & Resolution
    // ═══════════════════════════════════════════════════════════

    public function test_catalog_registers_and_resolves_provider(): void
    {
        $catalog = new ConditionEntityFieldCatalog();
        $provider = new CommissionEntryConditionSchemaProvider();

        $catalog->register($provider);

        $schema = $catalog->resolve('commission_entry');
        $this->assertNotNull($schema);
        $this->assertEquals('commission_entry', $schema['entity_type']);
        $this->assertArrayHasKey('fields', $schema);
        $this->assertArrayHasKey('label_en', $schema);
        $this->assertArrayHasKey('label_ar', $schema);
    }

    public function test_catalog_returns_null_for_unknown_entity_type(): void
    {
        $catalog = new ConditionEntityFieldCatalog();
        $catalog->register(new CommissionEntryConditionSchemaProvider());

        $this->assertNull($catalog->resolve('nonexistent_entity'));
    }

    public function test_catalog_lists_registered_entity_types(): void
    {
        $catalog = new ConditionEntityFieldCatalog();
        $catalog->register(new CommissionEntryConditionSchemaProvider());

        $types = $catalog->registeredEntityTypes();
        $this->assertContains('commission_entry', $types);
    }

    public function test_catalog_list_entity_types_returns_labels(): void
    {
        $catalog = new ConditionEntityFieldCatalog();
        $catalog->register(new CommissionEntryConditionSchemaProvider());

        $list = $catalog->listEntityTypes();
        $this->assertCount(1, $list);
        $this->assertEquals('commission_entry', $list[0]['entity_type']);
        $this->assertEquals('Commission entry', $list[0]['label_en']);
        $this->assertNotEmpty($list[0]['label_ar']);
        $this->assertEquals('commissions', $list[0]['module_key']);
    }

    // ═══════════════════════════════════════════════════════════
    //  2. Module Enablement Filtering
    // ═══════════════════════════════════════════════════════════

    public function test_catalog_filters_by_enabled_modules(): void
    {
        $catalog = new ConditionEntityFieldCatalog();
        $catalog->register(new CommissionEntryConditionSchemaProvider());

        // Module enabled → visible
        $withCommissions = $catalog->listEntityTypes(['commissions', 'crm']);
        $this->assertCount(1, $withCommissions);
        $this->assertEquals('commission_entry', $withCommissions[0]['entity_type']);

        // Module not enabled → hidden
        $withoutCommissions = $catalog->listEntityTypes(['crm', 'inventory']);
        $this->assertCount(0, $withoutCommissions);
    }

    public function test_catalog_resolve_returns_null_when_module_disabled(): void
    {
        $catalog = new ConditionEntityFieldCatalog();
        $catalog->register(new CommissionEntryConditionSchemaProvider());

        $schema = $catalog->resolve('commission_entry', ['crm']);
        $this->assertNull($schema, 'Should return null when commissions module is not enabled.');
    }

    public function test_catalog_resolve_returns_schema_when_module_enabled(): void
    {
        $catalog = new ConditionEntityFieldCatalog();
        $catalog->register(new CommissionEntryConditionSchemaProvider());

        $schema = $catalog->resolve('commission_entry', ['commissions']);
        $this->assertNotNull($schema);
        $this->assertEquals('commission_entry', $schema['entity_type']);
    }

    public function test_catalog_null_modules_skips_filtering(): void
    {
        $catalog = new ConditionEntityFieldCatalog();
        $catalog->register(new CommissionEntryConditionSchemaProvider());

        // null enabledModules → no filtering
        $list = $catalog->listEntityTypes(null);
        $this->assertCount(1, $list);

        $schema = $catalog->resolve('commission_entry', null);
        $this->assertNotNull($schema);
    }

    public function test_entity_with_no_required_module_always_visible(): void
    {
        $catalog = new ConditionEntityFieldCatalog();

        // Create a mock provider with no required module
        $noModuleProvider = new class implements ConditionEntitySchemaProvider {
            public function entityType(): string { return 'test_entity'; }
            public function labelEn(): string { return 'Test Entity'; }
            public function labelAr(): string { return 'كيان اختباري'; }
            public function moduleKey(): ?string { return null; }
            public function requiredModule(): ?string { return null; }
            public function fields(): array { return []; }
        };

        $catalog->register($noModuleProvider);

        // Should be visible even with restrictive module list
        $list = $catalog->listEntityTypes([]);
        $this->assertCount(1, $list);
    }

    // ═══════════════════════════════════════════════════════════
    //  3. CommissionEntry Provider — Field Schema Validation
    // ═══════════════════════════════════════════════════════════

    public function test_commission_entry_provider_entity_type(): void
    {
        $provider = new CommissionEntryConditionSchemaProvider();
        $this->assertEquals('commission_entry', $provider->entityType());
    }

    public function test_commission_entry_provider_requires_commissions_module(): void
    {
        $provider = new CommissionEntryConditionSchemaProvider();
        $this->assertEquals('commissions', $provider->requiredModule());
    }

    public function test_commission_entry_provider_declares_all_canonical_fields(): void
    {
        $provider = new CommissionEntryConditionSchemaProvider();
        $fields = $provider->fields();

        $fieldKeys = array_column($fields, 'key');

        $this->assertEqualsCanonicalizing(
            CommissionEntryConditionSchemaProvider::FIELD_KEYS,
            $fieldKeys,
            'Provider must declare exactly the canonical field keys.'
        );
    }

    public function test_commission_entry_fields_have_required_shape(): void
    {
        $provider = new CommissionEntryConditionSchemaProvider();
        $requiredKeys = ['key', 'type', 'label_en', 'label_ar', 'operators', 'options'];

        foreach ($provider->fields() as $i => $field) {
            foreach ($requiredKeys as $rk) {
                $this->assertArrayHasKey($rk, $field,
                    "Field at index {$i} is missing required key '{$rk}'.");
            }

            $this->assertIsString($field['key'], "Field {$field['key']}: 'key' must be a string.");
            $this->assertNotEmpty($field['key'], "Field at index {$i}: 'key' must not be empty.");
            $this->assertIsString($field['type'], "Field {$field['key']}: 'type' must be a string.");
            $this->assertContains($field['type'], ['number', 'string', 'enum', 'boolean', 'date'],
                "Field {$field['key']}: unknown type '{$field['type']}'.");
            $this->assertIsString($field['label_en'], "Field {$field['key']}: 'label_en' must be a string.");
            $this->assertNotEmpty($field['label_en'], "Field {$field['key']}: 'label_en' must not be empty.");
            $this->assertIsString($field['label_ar'], "Field {$field['key']}: 'label_ar' must be a string.");
            $this->assertNotEmpty($field['label_ar'], "Field {$field['key']}: 'label_ar' must not be empty.");
            $this->assertIsArray($field['operators'], "Field {$field['key']}: 'operators' must be an array.");
            $this->assertNotEmpty($field['operators'], "Field {$field['key']}: must have at least one operator.");
        }
    }

    public function test_calculation_type_field_has_enum_options(): void
    {
        $provider = new CommissionEntryConditionSchemaProvider();
        $fields = $provider->fields();

        $calcField = null;
        foreach ($fields as $f) {
            if ($f['key'] === 'calculation_type') {
                $calcField = $f;
                break;
            }
        }

        $this->assertNotNull($calcField, 'calculation_type field must exist.');
        $this->assertEquals('enum', $calcField['type']);
        $this->assertIsArray($calcField['options']);
        $this->assertNotEmpty($calcField['options']);

        // Verify option shape
        foreach ($calcField['options'] as $option) {
            $this->assertArrayHasKey('value', $option);
            $this->assertArrayHasKey('label_en', $option);
            $this->assertArrayHasKey('label_ar', $option);
        }

        // Verify specific enum values match CommissionRuleController validation
        $optionValues = array_column($calcField['options'], 'value');
        $this->assertContains('percentage', $optionValues);
        $this->assertContains('fixed_amount', $optionValues);
    }

    // ═══════════════════════════════════════════════════════════
    //  4. PARITY — Operator Whitelist
    // ═══════════════════════════════════════════════════════════

    /**
     * Every operator declared in any field MUST be in TriggerConditionValidator::SUPPORTED_OPERATORS.
     *
     * This prevents the catalog from advertising operators that the validator
     * or evaluator cannot handle, which would cause runtime 422s or silent mismatches.
     */
    public function test_all_field_operators_are_in_supported_operators(): void
    {
        $provider = new CommissionEntryConditionSchemaProvider();
        $supported = TriggerConditionValidator::SUPPORTED_OPERATORS;

        foreach ($provider->fields() as $field) {
            foreach ($field['operators'] as $op) {
                $this->assertContains($op, $supported,
                    "Field '{$field['key']}' declares unsupported operator '{$op}'. " .
                    'All operators must be in TriggerConditionValidator::SUPPORTED_OPERATORS.'
                );
            }
        }
    }

    // ═══════════════════════════════════════════════════════════
    //  5. PARITY — Catalog ↔ Runtime evaluationData() Contract
    // ═══════════════════════════════════════════════════════════

    /**
     * The catalog's field keys must match the FIELD_KEYS constant (contract anchor).
     */
    public function test_field_keys_match_constant_contract(): void
    {
        $provider = new CommissionEntryConditionSchemaProvider();
        $fieldKeys = array_column($provider->fields(), 'key');

        $this->assertEqualsCanonicalizing(
            CommissionEntryConditionSchemaProvider::FIELD_KEYS,
            $fieldKeys,
            'Field keys in the provider must match the FIELD_KEYS constant (contract anchor).'
        );
    }

    /**
     * Every catalog field key MUST exist in evaluationData() output.
     * No extra undocumented runtime key may exist.
     *
     * This is the definitive shared-contract parity test. Because
     * CommissionEntryController now calls evaluationData() directly
     * (not a hand-built array), proving evaluationData() ↔ fields()
     * parity means the controller and catalog can never drift.
     */
    public function test_evaluation_data_keys_match_catalog_field_keys(): void
    {
        $provider = new CommissionEntryConditionSchemaProvider();

        // Build a synthetic CommissionEntry with known values
        $entry = new \App\Models\CommissionEntry();
        $entry->commission_amount = '1500.00';
        $entry->base_amount       = '10000.00';
        $entry->currency          = 'USD';
        $entry->calculation_type  = 'percentage';
        $entry->percentage_rate   = '15.0000';

        $evalData = $provider->evaluationData($entry);
        $evalKeys = array_keys($evalData);
        $catalogKeys = array_column($provider->fields(), 'key');

        // Every catalog key exists in runtime data
        foreach ($catalogKeys as $key) {
            $this->assertArrayHasKey($key, $evalData,
                "Catalog field '{$key}' is missing from evaluationData() output.");
        }

        // No extra runtime key exists outside the catalog
        foreach ($evalKeys as $key) {
            $this->assertContains($key, $catalogKeys,
                "evaluationData() returns undocumented key '{$key}' not declared in fields().");
        }

        // Exact set equality
        $this->assertEqualsCanonicalizing(
            $catalogKeys,
            $evalKeys,
            'evaluationData() keys must exactly match fields() keys — no drift allowed.'
        );
    }

    /**
     * Verify evaluationData() produces the exact value types and casts
     * that the original manual mapping produced.
     *
     * amount       → (float) commission_amount
     * base_amount  → (float) base_amount
     * currency     → string, as-is
     * calculation_type → string, as-is
     * percentage_rate  → nullable, preserved as-is (not cast to float)
     */
    public function test_evaluation_data_value_types_and_casts(): void
    {
        $provider = new CommissionEntryConditionSchemaProvider();

        // Case 1: Percentage type with all fields populated
        $entry = new \App\Models\CommissionEntry();
        $entry->commission_amount = '1500.75';
        $entry->base_amount       = '10000.50';
        $entry->currency          = 'LYD';
        $entry->calculation_type  = 'percentage';
        $entry->percentage_rate   = '15.5000';

        $data = $provider->evaluationData($entry);

        $this->assertSame(1500.75, $data['amount'], 'amount must be (float) cast of commission_amount');
        $this->assertSame(10000.50, $data['base_amount'], 'base_amount must be (float) cast of base_amount');
        $this->assertSame('LYD', $data['currency'], 'currency must be string as-is');
        $this->assertSame('percentage', $data['calculation_type'], 'calculation_type must be string as-is');
        $this->assertSame('15.5000', $data['percentage_rate'], 'percentage_rate must preserve original value');

        // Case 2: Fixed amount type with null percentage_rate
        $entry2 = new \App\Models\CommissionEntry();
        $entry2->commission_amount = '500.00';
        $entry2->base_amount       = '500.00';
        $entry2->currency          = 'USD';
        $entry2->calculation_type  = 'fixed_amount';
        $entry2->percentage_rate   = null;

        $data2 = $provider->evaluationData($entry2);

        $this->assertNull($data2['percentage_rate'], 'percentage_rate null must be preserved');
        $this->assertSame('fixed_amount', $data2['calculation_type']);
        $this->assertSame(500.0, $data2['amount']);
    }

    /**
     * Verify FIELD_KEYS matches evaluationData() keys (anchor validation).
     * This catches the case where someone updates evaluationData() but
     * forgets to update the FIELD_KEYS constant.
     */
    public function test_field_keys_constant_matches_evaluation_data_keys(): void
    {
        $provider = new CommissionEntryConditionSchemaProvider();

        $entry = new \App\Models\CommissionEntry();
        $entry->commission_amount = '100.00';
        $entry->base_amount       = '1000.00';
        $entry->currency          = 'EUR';
        $entry->calculation_type  = 'percentage';
        $entry->percentage_rate   = '10.0000';

        $evalKeys = array_keys($provider->evaluationData($entry));

        $this->assertEqualsCanonicalizing(
            CommissionEntryConditionSchemaProvider::FIELD_KEYS,
            $evalKeys,
            'FIELD_KEYS constant must match the actual keys returned by evaluationData().'
        );
    }

    // ═══════════════════════════════════════════════════════════
    //  6. API Integration — List Entity Types
    // ═══════════════════════════════════════════════════════════

    public function test_api_lists_entity_types(): void
    {
        $this->ensureCommissionsModuleEnabled();

        $response = $this->wsGet('/api/approval-entity-types');

        $response->assertOk();
        $data = $response->json('data');
        $this->assertIsArray($data);

        // Should include commission_entry
        $entityTypes = array_column($data, 'entity_type');
        $this->assertContains('commission_entry', $entityTypes,
            'commission_entry should appear when the commissions module is enabled.');
    }

    public function test_api_returns_empty_when_module_disabled(): void
    {
        $this->disableCommissionsModule();

        $response = $this->wsGet('/api/approval-entity-types');

        $response->assertOk();
        $data = $response->json('data');
        $entityTypes = array_column($data, 'entity_type');
        $this->assertNotContains('commission_entry', $entityTypes,
            'commission_entry should not appear when the commissions module is disabled.');

        $this->restoreCommissionsModule();
    }

    public function test_api_field_catalog_returns_422_when_entity_type_missing(): void
    {
        $response = $this->wsGet('/api/approval-entity-field-catalog');

        $response->assertStatus(422);
        $response->assertJsonFragment(['message' => 'The entity_type parameter is required.']);
    }

    // ═══════════════════════════════════════════════════════════
    //  7. API Integration — Resolve Single Entity Schema
    // ═══════════════════════════════════════════════════════════

    public function test_api_resolves_commission_entry_schema(): void
    {
        $this->ensureCommissionsModuleEnabled();

        $response = $this->wsGet('/api/approval-entity-field-catalog?entity_type=commission_entry');

        $response->assertOk();
        $data = $response->json('data');

        $this->assertEquals('commission_entry', $data['entity_type']);
        $this->assertArrayHasKey('label_en', $data);
        $this->assertArrayHasKey('label_ar', $data);
        $this->assertArrayHasKey('fields', $data);
        $this->assertIsArray($data['fields']);
        $this->assertNotEmpty($data['fields']);

        // Verify field structure
        $firstField = $data['fields'][0];
        $this->assertArrayHasKey('key', $firstField);
        $this->assertArrayHasKey('type', $firstField);
        $this->assertArrayHasKey('label_en', $firstField);
        $this->assertArrayHasKey('label_ar', $firstField);
        $this->assertArrayHasKey('operators', $firstField);

        // Verify all canonical fields are present
        $fieldKeys = array_column($data['fields'], 'key');
        $this->assertEqualsCanonicalizing(
            CommissionEntryConditionSchemaProvider::FIELD_KEYS,
            $fieldKeys,
        );
    }

    public function test_api_returns_404_for_unknown_entity_type(): void
    {
        $response = $this->wsGet('/api/approval-entity-field-catalog?entity_type=nonexistent_entity');
        $response->assertStatus(404);
        $response->assertJsonFragment(['message' => "Entity type 'nonexistent_entity' is not available for trigger conditions in this workspace."]);
    }

    public function test_api_returns_404_when_module_disabled_for_entity(): void
    {
        $this->disableCommissionsModule();

        $response = $this->wsGet('/api/approval-entity-field-catalog?entity_type=commission_entry');
        $response->assertStatus(404);

        $this->restoreCommissionsModule();
    }

    // ═══════════════════════════════════════════════════════════
    //  8. API Integration — Permission Enforcement
    // ═══════════════════════════════════════════════════════════

    public function test_api_requires_authentication(): void
    {
        $response = $this->withHeaders([
            'X-Workspace-Id' => $this->workspaceId,
            'Accept'         => 'application/json',
        ])->getJson('/api/approval-entity-field-catalog');

        $response->assertStatus(401);
    }

    // ═══════════════════════════════════════════════════════════
    //  9. Registry — Last-Writer-Wins Replacement
    // ═══════════════════════════════════════════════════════════

    public function test_catalog_replaces_provider_on_re_registration(): void
    {
        $catalog = new ConditionEntityFieldCatalog();

        $provider1 = new CommissionEntryConditionSchemaProvider();
        $catalog->register($provider1);

        // Create a provider with the same entity type but different fields
        $provider2 = new class implements ConditionEntitySchemaProvider {
            public function entityType(): string { return 'commission_entry'; }
            public function labelEn(): string { return 'Custom'; }
            public function labelAr(): string { return 'مخصص'; }
            public function moduleKey(): ?string { return null; }
            public function requiredModule(): ?string { return null; }
            public function fields(): array {
                return [['key' => 'custom', 'type' => 'string', 'label_en' => 'Custom', 'label_ar' => 'مخصص', 'operators' => ['equals'], 'options' => null]];
            }
        };
        $catalog->register($provider2);

        $schema = $catalog->resolve('commission_entry');
        $this->assertCount(1, $schema['fields'], 'Second registration should replace the first.');
        $this->assertEquals('custom', $schema['fields'][0]['key']);
    }

    // ═══════════════════════════════════════════════════════════
    //  10. API Integration — Supported Operators in Response
    // ═══════════════════════════════════════════════════════════

    public function test_api_includes_supported_operators_in_entity_type_response(): void
    {
        $this->ensureCommissionsModuleEnabled();

        $response = $this->wsGet('/api/approval-entity-field-catalog?entity_type=commission_entry');
        $response->assertOk();

        $operators = $response->json('supported_operators');
        $this->assertIsArray($operators);
        $this->assertEqualsCanonicalizing(
            TriggerConditionValidator::SUPPORTED_OPERATORS,
            $operators,
        );
    }

    // ═══════════════════════════════════════════════════════════
    //  Helpers — Module Enablement Management
    // ═══════════════════════════════════════════════════════════

    /**
     * Original enabled_modules value for tearDown restoration.
     */
    private ?array $originalEnabledModules = null;

    /**
     * Ensure the commissions module is in the workspace's enabled_modules.
     */
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

    /**
     * Remove commissions from workspace's enabled_modules.
     */
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

    /**
     * Restore original enabled_modules state.
     */
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
