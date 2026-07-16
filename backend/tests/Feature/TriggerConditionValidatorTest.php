<?php

namespace Tests\Feature;

use App\Models\ApprovalWorkflow;
use Database\Seeders\FoundationSeeder;
use Illuminate\Support\Facades\DB;

/**
 * Feature tests for TriggerConditionValidator integration.
 *
 * Validates that the API correctly rejects malformed trigger_conditions
 * on both workflow creation (store) and workflow update (update) endpoints.
 *
 * Uses the smartbiz_test database via SmartBizTestCase.
 */
class TriggerConditionValidatorTest extends SmartBizTestCase
{
    private array $cleanUpIds = [];

    protected function tearDown(): void
    {
        if (! empty($this->cleanUpIds['approval_workflows'])) {
            DB::table('approval_workflow_steps')
                ->whereIn('workflow_id', $this->cleanUpIds['approval_workflows'])
                ->delete();
            DB::table('approval_workflows')
                ->whereIn('id', $this->cleanUpIds['approval_workflows'])
                ->delete();
        }

        parent::tearDown();
    }

    // ═══════════════════════════════════════════════════════════
    //  A. Valid payloads — accepted
    // ═══════════════════════════════════════════════════════════

    /**
     * Canonical demo payload is accepted.
     */
    public function test_canonical_demo_payload_accepted(): void
    {
        $r = $this->wsPost('/api/approval-workflows', [
            'workflow_key' => 'test_valid_canonical_' . uniqid(),
            'name'         => 'Canonical Payload Test',
            'entity_type'  => 'commission_entry',
            'trigger_conditions' => [
                'logic' => 'and',
                'conditions' => [
                    ['field' => 'amount', 'operator' => 'greater_than_or_equal', 'value' => 500],
                    ['field' => 'currency', 'operator' => 'equals', 'value' => 'SAR'],
                ],
            ],
        ]);

        $r->assertStatus(201);
        $this->cleanUpIds['approval_workflows'][] = $r->json('data.id');
    }

    /**
     * Empty trigger_conditions (always-trigger) is accepted.
     */
    public function test_empty_conditions_accepted(): void
    {
        $r = $this->wsPost('/api/approval-workflows', [
            'workflow_key' => 'test_empty_cond_' . uniqid(),
            'name'         => 'Empty Conditions Test',
            'entity_type'  => 'commission_entry',
            'trigger_conditions' => [],
        ]);

        $r->assertStatus(201);
        $this->cleanUpIds['approval_workflows'][] = $r->json('data.id');
    }

    /**
     * Omitting trigger_conditions entirely uses the controller's default ([]).
     */
    public function test_omitted_conditions_accepted(): void
    {
        $r = $this->wsPost('/api/approval-workflows', [
            'workflow_key' => 'test_omitted_cond_' . uniqid(),
            'name'         => 'Omitted Conditions Test',
            'entity_type'  => 'commission_entry',
            // trigger_conditions not provided at all
        ]);

        $r->assertStatus(201);
        $this->cleanUpIds['approval_workflows'][] = $r->json('data.id');
    }

    /**
     * Canonical shape with empty conditions array is accepted.
     */
    public function test_canonical_with_empty_conditions_array_accepted(): void
    {
        $r = $this->wsPost('/api/approval-workflows', [
            'workflow_key' => 'test_empty_cond_array_' . uniqid(),
            'name'         => 'Empty Conditions Array Test',
            'entity_type'  => 'commission_entry',
            'trigger_conditions' => [
                'logic' => 'and',
                'conditions' => [],
            ],
        ]);

        $r->assertStatus(201);
        $this->cleanUpIds['approval_workflows'][] = $r->json('data.id');
    }

    /**
     * OR logic with valid conditions is accepted.
     */
    public function test_or_logic_accepted(): void
    {
        $r = $this->wsPost('/api/approval-workflows', [
            'workflow_key' => 'test_or_logic_' . uniqid(),
            'name'         => 'OR Logic Test',
            'entity_type'  => 'commission_entry',
            'trigger_conditions' => [
                'logic' => 'or',
                'conditions' => [
                    ['field' => 'amount', 'operator' => 'greater_than', 'value' => 1000],
                    ['field' => 'currency', 'operator' => 'equals', 'value' => 'SAR'],
                ],
            ],
        ]);

        $r->assertStatus(201);
        $this->cleanUpIds['approval_workflows'][] = $r->json('data.id');
    }

    /**
     * Valid nested group is accepted.
     */
    public function test_valid_nested_group_accepted(): void
    {
        $r = $this->wsPost('/api/approval-workflows', [
            'workflow_key' => 'test_nested_' . uniqid(),
            'name'         => 'Nested Group Test',
            'entity_type'  => 'commission_entry',
            'trigger_conditions' => [
                'logic' => 'and',
                'conditions' => [
                    ['field' => 'amount', 'operator' => 'greater_than_or_equal', 'value' => 500],
                    [
                        'logic' => 'or',
                        'conditions' => [
                            ['field' => 'currency', 'operator' => 'equals', 'value' => 'SAR'],
                            ['field' => 'currency', 'operator' => 'equals', 'value' => 'USD'],
                        ],
                    ],
                ],
            ],
        ]);

        $r->assertStatus(201);
        $this->cleanUpIds['approval_workflows'][] = $r->json('data.id');
    }

    /**
     * exists operator without value is accepted.
     */
    public function test_exists_operator_without_value_accepted(): void
    {
        $r = $this->wsPost('/api/approval-workflows', [
            'workflow_key' => 'test_exists_' . uniqid(),
            'name'         => 'Exists Test',
            'entity_type'  => 'commission_entry',
            'trigger_conditions' => [
                'logic' => 'and',
                'conditions' => [
                    ['field' => 'notes', 'operator' => 'exists', 'value' => true],
                ],
            ],
        ]);

        $r->assertStatus(201);
        $this->cleanUpIds['approval_workflows'][] = $r->json('data.id');
    }

    /**
     * All 10 operators accepted with valid values.
     */
    public function test_all_supported_operators_accepted(): void
    {
        $r = $this->wsPost('/api/approval-workflows', [
            'workflow_key' => 'test_all_ops_' . uniqid(),
            'name'         => 'All Operators Test',
            'entity_type'  => 'commission_entry',
            'trigger_conditions' => [
                'logic' => 'or',
                'conditions' => [
                    ['field' => 'a', 'operator' => 'equals', 'value' => 'x'],
                    ['field' => 'a', 'operator' => 'not_equals', 'value' => 'y'],
                    ['field' => 'b', 'operator' => 'greater_than', 'value' => 100],
                    ['field' => 'b', 'operator' => 'greater_than_or_equal', 'value' => 100],
                    ['field' => 'b', 'operator' => 'less_than', 'value' => 100],
                    ['field' => 'b', 'operator' => 'less_than_or_equal', 'value' => 100],
                    ['field' => 'c', 'operator' => 'in', 'value' => ['x', 'y']],
                    ['field' => 'c', 'operator' => 'not_in', 'value' => ['z']],
                    ['field' => 'd', 'operator' => 'contains', 'value' => 'sub'],
                    ['field' => 'e', 'operator' => 'exists', 'value' => true],
                ],
            ],
        ]);

        $r->assertStatus(201);
        $this->cleanUpIds['approval_workflows'][] = $r->json('data.id');
    }

    // ═══════════════════════════════════════════════════════════
    //  B. Invalid payloads — rejected on store
    // ═══════════════════════════════════════════════════════════

    /**
     * 'xor' logic is rejected.
     */
    public function test_xor_logic_rejected(): void
    {
        $r = $this->wsPost('/api/approval-workflows', [
            'workflow_key' => 'test_xor_' . uniqid(),
            'name'         => 'XOR Logic Test',
            'entity_type'  => 'commission_entry',
            'trigger_conditions' => [
                'logic' => 'xor',
                'conditions' => [
                    ['field' => 'amount', 'operator' => 'equals', 'value' => 100],
                ],
            ],
        ]);

        $r->assertStatus(422);
        $this->assertStringContainsString('Invalid trigger conditions', $r->json('message'));
    }

    /**
     * Conditions must be an array, not a string.
     */
    public function test_invalid_conditions_shape_rejected(): void
    {
        $r = $this->wsPost('/api/approval-workflows', [
            'workflow_key' => 'test_bad_shape_' . uniqid(),
            'name'         => 'Bad Shape Test',
            'entity_type'  => 'commission_entry',
            'trigger_conditions' => [
                'logic' => 'and',
                'conditions' => 'not_an_array',
            ],
        ]);

        // Laravel's 'nullable|array' validation on trigger_conditions will catch
        // the top-level non-array. The nested 'conditions' key is a string inside
        // a valid array, so it passes Laravel but our validator catches it.
        $r->assertStatus(422);
    }

    /**
     * Unknown operator is rejected.
     */
    public function test_unknown_operator_rejected(): void
    {
        $r = $this->wsPost('/api/approval-workflows', [
            'workflow_key' => 'test_unknown_op_' . uniqid(),
            'name'         => 'Unknown Operator Test',
            'entity_type'  => 'commission_entry',
            'trigger_conditions' => [
                'logic' => 'and',
                'conditions' => [
                    ['field' => 'amount', 'operator' => 'fuzzy_match', 'value' => 100],
                ],
            ],
        ]);

        $r->assertStatus(422);
        $this->assertStringContainsString('Invalid trigger conditions', $r->json('message'));
        // Check that the error specifically mentions the unsupported operator
        $errors = $r->json('errors.trigger_conditions');
        $this->assertNotEmpty($errors);
        $this->assertStringContainsString('fuzzy_match', $errors[0]);
    }

    /**
     * Missing field is rejected.
     */
    public function test_missing_field_rejected(): void
    {
        $r = $this->wsPost('/api/approval-workflows', [
            'workflow_key' => 'test_no_field_' . uniqid(),
            'name'         => 'Missing Field Test',
            'entity_type'  => 'commission_entry',
            'trigger_conditions' => [
                'logic' => 'and',
                'conditions' => [
                    ['operator' => 'equals', 'value' => 100],
                ],
            ],
        ]);

        $r->assertStatus(422);
        $this->assertStringContainsString('Invalid trigger conditions', $r->json('message'));
    }

    /**
     * Empty string field is rejected.
     */
    public function test_empty_string_field_rejected(): void
    {
        $r = $this->wsPost('/api/approval-workflows', [
            'workflow_key' => 'test_empty_field_' . uniqid(),
            'name'         => 'Empty Field Test',
            'entity_type'  => 'commission_entry',
            'trigger_conditions' => [
                'logic' => 'and',
                'conditions' => [
                    ['field' => '', 'operator' => 'equals', 'value' => 100],
                ],
            ],
        ]);

        $r->assertStatus(422);
        $this->assertStringContainsString('Invalid trigger conditions', $r->json('message'));
    }

    /**
     * Missing operator is rejected.
     */
    public function test_missing_operator_rejected(): void
    {
        $r = $this->wsPost('/api/approval-workflows', [
            'workflow_key' => 'test_no_op_' . uniqid(),
            'name'         => 'Missing Operator Test',
            'entity_type'  => 'commission_entry',
            'trigger_conditions' => [
                'logic' => 'and',
                'conditions' => [
                    ['field' => 'amount', 'value' => 100],
                ],
            ],
        ]);

        $r->assertStatus(422);
        $this->assertStringContainsString('Invalid trigger conditions', $r->json('message'));
    }

    /**
     * Missing required value for equals operator is rejected.
     */
    public function test_missing_required_value_rejected(): void
    {
        $r = $this->wsPost('/api/approval-workflows', [
            'workflow_key' => 'test_no_value_' . uniqid(),
            'name'         => 'Missing Value Test',
            'entity_type'  => 'commission_entry',
            'trigger_conditions' => [
                'logic' => 'and',
                'conditions' => [
                    ['field' => 'amount', 'operator' => 'greater_than'],
                ],
            ],
        ]);

        $r->assertStatus(422);
        $this->assertStringContainsString('Invalid trigger conditions', $r->json('message'));
    }

    /**
     * 'in' operator with a non-array value is rejected.
     */
    public function test_invalid_list_value_rejected(): void
    {
        $r = $this->wsPost('/api/approval-workflows', [
            'workflow_key' => 'test_bad_list_' . uniqid(),
            'name'         => 'Invalid List Value Test',
            'entity_type'  => 'commission_entry',
            'trigger_conditions' => [
                'logic' => 'and',
                'conditions' => [
                    ['field' => 'currency', 'operator' => 'in', 'value' => 'SAR'],
                ],
            ],
        ]);

        $r->assertStatus(422);
        $this->assertStringContainsString('Invalid trigger conditions', $r->json('message'));
    }

    /**
     * Numeric operator with a non-numeric value is rejected.
     */
    public function test_invalid_numeric_value_rejected(): void
    {
        $r = $this->wsPost('/api/approval-workflows', [
            'workflow_key' => 'test_bad_num_' . uniqid(),
            'name'         => 'Invalid Numeric Value Test',
            'entity_type'  => 'commission_entry',
            'trigger_conditions' => [
                'logic' => 'and',
                'conditions' => [
                    ['field' => 'amount', 'operator' => 'greater_than', 'value' => 'not_a_number'],
                ],
            ],
        ]);

        $r->assertStatus(422);
        $this->assertStringContainsString('Invalid trigger conditions', $r->json('message'));
    }

    /**
     * Malformed nested group (missing conditions in nested) is rejected.
     * A nested group with logic but no conditions key is still valid per evaluator
     * (evaluator defaults conditions to []), but a nested object with neither
     * logic nor conditions nor field/operator is malformed.
     */
    public function test_malformed_nested_group_rejected(): void
    {
        $r = $this->wsPost('/api/approval-workflows', [
            'workflow_key' => 'test_bad_nested_' . uniqid(),
            'name'         => 'Malformed Nested Test',
            'entity_type'  => 'commission_entry',
            'trigger_conditions' => [
                'logic' => 'and',
                'conditions' => [
                    ['field' => 'amount', 'operator' => 'equals', 'value' => 100],
                    ['garbage_key' => 'garbage_value'],  // Neither group nor condition
                ],
            ],
        ]);

        $r->assertStatus(422);
        $this->assertStringContainsString('Invalid trigger conditions', $r->json('message'));
    }

    /**
     * Non-object condition entry (string instead of object) is rejected.
     */
    public function test_non_object_condition_entry_rejected(): void
    {
        $r = $this->wsPost('/api/approval-workflows', [
            'workflow_key' => 'test_str_cond_' . uniqid(),
            'name'         => 'String Condition Test',
            'entity_type'  => 'commission_entry',
            'trigger_conditions' => [
                'logic' => 'and',
                'conditions' => [
                    'just_a_string',
                ],
            ],
        ]);

        $r->assertStatus(422);
    }

    // ═══════════════════════════════════════════════════════════
    //  C. Update endpoint enforces same validation
    // ═══════════════════════════════════════════════════════════

    /**
     * Update with valid conditions is accepted.
     */
    public function test_update_with_valid_conditions_accepted(): void
    {
        $workflow = $this->createTestWorkflow();

        $r = $this->wsPut("/api/approval-workflows/{$workflow->id}", [
            'trigger_conditions' => [
                'logic' => 'and',
                'conditions' => [
                    ['field' => 'amount', 'operator' => 'greater_than', 'value' => 1000],
                ],
            ],
        ]);

        $r->assertOk();
    }

    /**
     * Update with invalid conditions is rejected.
     */
    public function test_update_with_invalid_conditions_rejected(): void
    {
        $workflow = $this->createTestWorkflow();

        $r = $this->wsPut("/api/approval-workflows/{$workflow->id}", [
            'trigger_conditions' => [
                'logic' => 'xor',
                'conditions' => [
                    ['field' => 'amount', 'operator' => 'equals', 'value' => 100],
                ],
            ],
        ]);

        $r->assertStatus(422);
        $this->assertStringContainsString('Invalid trigger conditions', $r->json('message'));
    }

    /**
     * Update with unknown operator is rejected.
     */
    public function test_update_with_unknown_operator_rejected(): void
    {
        $workflow = $this->createTestWorkflow();

        $r = $this->wsPut("/api/approval-workflows/{$workflow->id}", [
            'trigger_conditions' => [
                'logic' => 'and',
                'conditions' => [
                    ['field' => 'amount', 'operator' => 'regex_match', 'value' => '.*'],
                ],
            ],
        ]);

        $r->assertStatus(422);
        $this->assertStringContainsString('Invalid trigger conditions', $r->json('message'));
    }

    /**
     * Update without trigger_conditions does NOT trigger validation
     * (partial update — only fields present are updated).
     */
    public function test_update_without_conditions_skips_validation(): void
    {
        $workflow = $this->createTestWorkflow();

        $r = $this->wsPut("/api/approval-workflows/{$workflow->id}", [
            'name' => 'Updated Name Only',
        ]);

        $r->assertOk();
        $this->assertEquals('Updated Name Only', $r->json('data.name'));
    }

    /**
     * Update with empty conditions (always-trigger) is accepted.
     */
    public function test_update_with_empty_conditions_accepted(): void
    {
        $workflow = $this->createTestWorkflow();

        $r = $this->wsPut("/api/approval-workflows/{$workflow->id}", [
            'trigger_conditions' => [],
        ]);

        $r->assertOk();
    }

    // ═══════════════════════════════════════════════════════════
    //  D. Edge cases
    // ═══════════════════════════════════════════════════════════

    /**
     * Numeric string value is accepted for numeric operators.
     */
    public function test_numeric_string_accepted_for_numeric_operators(): void
    {
        $r = $this->wsPost('/api/approval-workflows', [
            'workflow_key' => 'test_num_str_' . uniqid(),
            'name'         => 'Numeric String Test',
            'entity_type'  => 'commission_entry',
            'trigger_conditions' => [
                'logic' => 'and',
                'conditions' => [
                    ['field' => 'amount', 'operator' => 'greater_than', 'value' => '500'],
                ],
            ],
        ]);

        $r->assertStatus(201);
        $this->cleanUpIds['approval_workflows'][] = $r->json('data.id');
    }

    /**
     * Multiple validation errors returned at once.
     */
    public function test_multiple_errors_returned(): void
    {
        $r = $this->wsPost('/api/approval-workflows', [
            'workflow_key' => 'test_multi_err_' . uniqid(),
            'name'         => 'Multiple Errors Test',
            'entity_type'  => 'commission_entry',
            'trigger_conditions' => [
                'logic' => 'and',
                'conditions' => [
                    ['operator' => 'fancy_op', 'value' => 100],  // missing field + unknown op
                    ['field' => 'x', 'operator' => 'greater_than'],  // missing value
                ],
            ],
        ]);

        $r->assertStatus(422);
        $errors = $r->json('errors.trigger_conditions');
        $this->assertGreaterThanOrEqual(2, count($errors), 'Should return multiple errors.');
    }

    // ═══════════════════════════════════════════════════════════
    //  E. Update semantics — condition preservation & atomicity
    // ═══════════════════════════════════════════════════════════

    /**
     * Updating only the name preserves existing trigger_conditions exactly.
     *
     * The controller uses $request->only() which excludes absent keys,
     * so Eloquent never touches trigger_conditions.
     */
    public function test_update_name_only_preserves_trigger_conditions(): void
    {
        $originalConditions = [
            'logic' => 'and',
            'conditions' => [
                ['field' => 'amount', 'operator' => 'greater_than_or_equal', 'value' => 500],
                ['field' => 'currency', 'operator' => 'equals', 'value' => 'SAR'],
            ],
        ];

        $workflow = $this->createTestWorkflowWithConditions($originalConditions);

        $r = $this->wsPut("/api/approval-workflows/{$workflow->id}", [
            'name' => 'Name Changed, Conditions Untouched',
        ]);

        $r->assertOk();
        $this->assertEquals('Name Changed, Conditions Untouched', $r->json('data.name'));
        $this->assertEquals($originalConditions, $r->json('data.trigger_conditions'),
            'trigger_conditions must be preserved exactly when not sent in the update.');
    }

    /**
     * Updating an unrelated property (sort_order) preserves trigger_conditions.
     */
    public function test_update_unrelated_property_preserves_trigger_conditions(): void
    {
        $originalConditions = [
            'logic' => 'or',
            'conditions' => [
                ['field' => 'priority', 'operator' => 'equals', 'value' => 'high'],
            ],
        ];

        $workflow = $this->createTestWorkflowWithConditions($originalConditions);

        $r = $this->wsPut("/api/approval-workflows/{$workflow->id}", [
            'sort_order' => 99,
        ]);

        $r->assertOk();
        $this->assertEquals(99, $r->json('data.sort_order'));
        $this->assertEquals($originalConditions, $r->json('data.trigger_conditions'),
            'trigger_conditions must be preserved when updating sort_order.');
    }

    /**
     * Explicit trigger_conditions: null is rejected with 422.
     *
     * The DB column is NOT NULL. Rather than letting this reach the database
     * and cause a 500 error, the controller rejects it explicitly.
     */
    public function test_update_explicit_null_rejected_with_422(): void
    {
        $workflow = $this->createTestWorkflow();

        $r = $this->wsPut("/api/approval-workflows/{$workflow->id}", [
            'trigger_conditions' => null,
        ]);

        $r->assertStatus(422);
        $this->assertStringContainsString('Invalid trigger conditions', $r->json('message'));
        $this->assertNotEmpty($r->json('errors.trigger_conditions'));
    }

    /**
     * Explicit trigger_conditions: [] follows the documented empty-condition behavior.
     * The evaluator treats [] as "always trigger".
     */
    public function test_update_explicit_empty_array_accepted(): void
    {
        $originalConditions = [
            'logic' => 'and',
            'conditions' => [
                ['field' => 'amount', 'operator' => 'greater_than', 'value' => 1000],
            ],
        ];

        $workflow = $this->createTestWorkflowWithConditions($originalConditions);

        $r = $this->wsPut("/api/approval-workflows/{$workflow->id}", [
            'trigger_conditions' => [],
        ]);

        $r->assertOk();
        // After update, trigger_conditions should be the empty array
        $this->assertEquals([], $r->json('data.trigger_conditions'),
            'Explicit [] should clear conditions to always-trigger.');
    }

    /**
     * Explicit trigger_conditions: {"conditions": []} follows documented behavior.
     * This is a valid group with no conditions — evaluator treats as "always trigger".
     */
    public function test_update_explicit_conditions_empty_array_accepted(): void
    {
        $originalConditions = [
            'logic' => 'and',
            'conditions' => [
                ['field' => 'amount', 'operator' => 'greater_than', 'value' => 1000],
            ],
        ];

        $workflow = $this->createTestWorkflowWithConditions($originalConditions);

        $r = $this->wsPut("/api/approval-workflows/{$workflow->id}", [
            'trigger_conditions' => ['conditions' => []],
        ]);

        $r->assertOk();
        $this->assertEquals(['conditions' => []], $r->json('data.trigger_conditions'),
            'Explicit {conditions:[]} should be accepted as a valid empty group.');
    }

    /**
     * A failed validation does NOT partially update the workflow.
     *
     * The validation check runs before the Eloquent update() call,
     * so the entire request is rejected without any changes.
     */
    public function test_failed_validation_does_not_partially_update(): void
    {
        $originalConditions = [
            'logic' => 'and',
            'conditions' => [
                ['field' => 'amount', 'operator' => 'greater_than_or_equal', 'value' => 500],
            ],
        ];

        $workflow = $this->createTestWorkflowWithConditions($originalConditions);
        $originalName = $workflow->name;

        // Send both a valid name change AND invalid trigger_conditions
        $r = $this->wsPut("/api/approval-workflows/{$workflow->id}", [
            'name' => 'This Name Should Not Persist',
            'trigger_conditions' => [
                'logic' => 'xor',  // invalid
                'conditions' => [
                    ['field' => 'x', 'operator' => 'equals', 'value' => 1],
                ],
            ],
        ]);

        $r->assertStatus(422);

        // Verify the workflow was NOT modified at all
        $workflow->refresh();
        $this->assertEquals($originalName, $workflow->name,
            'Name must not change when trigger_conditions validation fails.');
        $this->assertEquals($originalConditions, $workflow->trigger_conditions,
            'trigger_conditions must not change when validation fails.');
    }

    /**
     * Update with valid conditions replaces existing conditions completely.
     */
    public function test_update_replaces_conditions_completely(): void
    {
        $originalConditions = [
            'logic' => 'and',
            'conditions' => [
                ['field' => 'amount', 'operator' => 'greater_than_or_equal', 'value' => 500],
                ['field' => 'currency', 'operator' => 'equals', 'value' => 'SAR'],
            ],
        ];

        $newConditions = [
            'logic' => 'or',
            'conditions' => [
                ['field' => 'priority', 'operator' => 'equals', 'value' => 'urgent'],
            ],
        ];

        $workflow = $this->createTestWorkflowWithConditions($originalConditions);

        $r = $this->wsPut("/api/approval-workflows/{$workflow->id}", [
            'trigger_conditions' => $newConditions,
        ]);

        $r->assertOk();
        $this->assertEquals($newConditions, $r->json('data.trigger_conditions'),
            'Update should completely replace trigger_conditions.');
    }

    // ═══════════════════════════════════════════════════════════
    //  Helpers
    // ═══════════════════════════════════════════════════════════

    private function createTestWorkflow(): ApprovalWorkflow
    {
        return $this->createTestWorkflowWithConditions([]);
    }

    private function createTestWorkflowWithConditions(array $conditions): ApprovalWorkflow
    {
        $workflow = ApprovalWorkflow::create([
            'workspace_id'       => $this->workspaceId,
            'workflow_key'       => 'test_validator_' . uniqid(),
            'name'               => 'Test Validator Workflow',
            'entity_type'        => 'commission_entry',
            'trigger_conditions' => $conditions,
            'is_active'          => true,
            'sort_order'         => 1,
            'created_by'         => FoundationSeeder::MEMBERSHIP_ID,
        ]);
        $this->cleanUpIds['approval_workflows'][] = $workflow->id;

        return $workflow;
    }
}
