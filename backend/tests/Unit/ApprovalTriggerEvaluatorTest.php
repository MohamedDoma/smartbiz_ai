<?php

namespace Tests\Unit;

use App\Services\ApprovalTriggerEvaluator;
use PHPUnit\Framework\TestCase;

/**
 * Unit tests for ApprovalTriggerEvaluator::conditionsMet().
 *
 * These tests document and lock the CURRENT evaluator behavior.
 * The evaluator is tested in isolation — no database, no models.
 *
 * Discovered behavior documented in each test's docblock.
 */
class ApprovalTriggerEvaluatorTest extends TestCase
{
    private ApprovalTriggerEvaluator $evaluator;

    protected function setUp(): void
    {
        parent::setUp();
        $this->evaluator = new ApprovalTriggerEvaluator();
    }

    // ═══════════════════════════════════════════════════════════
    //  A. Empty / missing conditions
    // ═══════════════════════════════════════════════════════════

    /**
     * Empty array → always true (evaluator: "Empty or unknown shape — pass").
     */
    public function test_empty_array_returns_true(): void
    {
        $this->assertTrue($this->evaluator->conditionsMet([], ['amount' => 100]));
    }

    /**
     * Empty conditions list within canonical shape → true.
     */
    public function test_canonical_with_empty_conditions_returns_true(): void
    {
        $tree = ['logic' => 'and', 'conditions' => []];
        $this->assertTrue($this->evaluator->conditionsMet($tree, ['amount' => 100]));
    }

    /**
     * Logic key with no conditions list → true.
     * (evaluateGroup: conditions defaults to [], empty → true)
     */
    public function test_logic_only_no_conditions_key_returns_true(): void
    {
        $tree = ['logic' => 'and'];
        // This does NOT match the canonical shape check (needs both 'logic' AND 'conditions'),
        // falls through to "Empty or unknown shape — pass" → true
        $this->assertTrue($this->evaluator->conditionsMet($tree, ['amount' => 100]));
    }

    // ═══════════════════════════════════════════════════════════
    //  B. AND logic
    // ═══════════════════════════════════════════════════════════

    /**
     * AND: all conditions met → true.
     */
    public function test_and_all_match(): void
    {
        $tree = [
            'logic' => 'and',
            'conditions' => [
                ['field' => 'amount', 'operator' => 'greater_than_or_equal', 'value' => 500],
                ['field' => 'currency', 'operator' => 'equals', 'value' => 'SAR'],
            ],
        ];
        $entity = ['amount' => 1000, 'currency' => 'SAR'];

        $this->assertTrue($this->evaluator->conditionsMet($tree, $entity));
    }

    /**
     * AND: one condition fails → false.
     */
    public function test_and_one_fails(): void
    {
        $tree = [
            'logic' => 'and',
            'conditions' => [
                ['field' => 'amount', 'operator' => 'greater_than_or_equal', 'value' => 500],
                ['field' => 'currency', 'operator' => 'equals', 'value' => 'USD'],
            ],
        ];
        $entity = ['amount' => 1000, 'currency' => 'SAR'];

        $this->assertFalse($this->evaluator->conditionsMet($tree, $entity));
    }

    /**
     * AND: all conditions fail → false.
     */
    public function test_and_all_fail(): void
    {
        $tree = [
            'logic' => 'and',
            'conditions' => [
                ['field' => 'amount', 'operator' => 'greater_than', 'value' => 2000],
                ['field' => 'currency', 'operator' => 'equals', 'value' => 'USD'],
            ],
        ];
        $entity = ['amount' => 100, 'currency' => 'SAR'];

        $this->assertFalse($this->evaluator->conditionsMet($tree, $entity));
    }

    // ═══════════════════════════════════════════════════════════
    //  C. OR logic
    // ═══════════════════════════════════════════════════════════

    /**
     * OR: at least one condition met → true.
     */
    public function test_or_one_matches(): void
    {
        $tree = [
            'logic' => 'or',
            'conditions' => [
                ['field' => 'amount', 'operator' => 'greater_than', 'value' => 10000],
                ['field' => 'currency', 'operator' => 'equals', 'value' => 'SAR'],
            ],
        ];
        $entity = ['amount' => 100, 'currency' => 'SAR'];

        $this->assertTrue($this->evaluator->conditionsMet($tree, $entity));
    }

    /**
     * OR: no conditions met → false.
     */
    public function test_or_none_match(): void
    {
        $tree = [
            'logic' => 'or',
            'conditions' => [
                ['field' => 'amount', 'operator' => 'greater_than', 'value' => 10000],
                ['field' => 'currency', 'operator' => 'equals', 'value' => 'USD'],
            ],
        ];
        $entity = ['amount' => 100, 'currency' => 'SAR'];

        $this->assertFalse($this->evaluator->conditionsMet($tree, $entity));
    }

    /**
     * OR: all conditions met → true.
     */
    public function test_or_all_match(): void
    {
        $tree = [
            'logic' => 'or',
            'conditions' => [
                ['field' => 'amount', 'operator' => 'greater_than', 'value' => 50],
                ['field' => 'currency', 'operator' => 'equals', 'value' => 'SAR'],
            ],
        ];
        $entity = ['amount' => 100, 'currency' => 'SAR'];

        $this->assertTrue($this->evaluator->conditionsMet($tree, $entity));
    }

    // ═══════════════════════════════════════════════════════════
    //  D. Operator: equals / not_equals
    // ═══════════════════════════════════════════════════════════

    public function test_equals_string_match(): void
    {
        $tree = ['logic' => 'and', 'conditions' => [
            ['field' => 'status', 'operator' => 'equals', 'value' => 'active'],
        ]];

        $this->assertTrue($this->evaluator->conditionsMet($tree, ['status' => 'active']));
        $this->assertFalse($this->evaluator->conditionsMet($tree, ['status' => 'inactive']));
    }

    /**
     * Loose equality: numeric string "500" equals integer 500.
     * Both are cast to string for comparison.
     */
    public function test_equals_numeric_coercion(): void
    {
        $tree = ['logic' => 'and', 'conditions' => [
            ['field' => 'amount', 'operator' => 'equals', 'value' => 500],
        ]];

        $this->assertTrue($this->evaluator->conditionsMet($tree, ['amount' => '500']));
        $this->assertTrue($this->evaluator->conditionsMet($tree, ['amount' => 500]));
        $this->assertTrue($this->evaluator->conditionsMet($tree, ['amount' => 500.0]));
    }

    /**
     * equals: null vs null → true.
     */
    public function test_equals_null_null(): void
    {
        $tree = ['logic' => 'and', 'conditions' => [
            ['field' => 'notes', 'operator' => 'equals', 'value' => null],
        ]];

        $this->assertTrue($this->evaluator->conditionsMet($tree, ['notes' => null]));
    }

    /**
     * equals: null vs non-null → false.
     */
    public function test_equals_null_vs_value(): void
    {
        $tree = ['logic' => 'and', 'conditions' => [
            ['field' => 'notes', 'operator' => 'equals', 'value' => 'something'],
        ]];

        $this->assertFalse($this->evaluator->conditionsMet($tree, ['notes' => null]));
    }

    public function test_not_equals(): void
    {
        $tree = ['logic' => 'and', 'conditions' => [
            ['field' => 'status', 'operator' => 'not_equals', 'value' => 'cancelled'],
        ]];

        $this->assertTrue($this->evaluator->conditionsMet($tree, ['status' => 'active']));
        $this->assertFalse($this->evaluator->conditionsMet($tree, ['status' => 'cancelled']));
    }

    // ═══════════════════════════════════════════════════════════
    //  E. Numeric comparison operators
    // ═══════════════════════════════════════════════════════════

    public function test_greater_than(): void
    {
        $tree = ['logic' => 'and', 'conditions' => [
            ['field' => 'amount', 'operator' => 'greater_than', 'value' => 100],
        ]];

        $this->assertTrue($this->evaluator->conditionsMet($tree, ['amount' => 200]));
        $this->assertFalse($this->evaluator->conditionsMet($tree, ['amount' => 100]));
        $this->assertFalse($this->evaluator->conditionsMet($tree, ['amount' => 50]));
    }

    public function test_greater_than_or_equal(): void
    {
        $tree = ['logic' => 'and', 'conditions' => [
            ['field' => 'amount', 'operator' => 'greater_than_or_equal', 'value' => 500],
        ]];

        $this->assertTrue($this->evaluator->conditionsMet($tree, ['amount' => 500]));
        $this->assertTrue($this->evaluator->conditionsMet($tree, ['amount' => 501]));
        $this->assertFalse($this->evaluator->conditionsMet($tree, ['amount' => 499]));
    }

    public function test_less_than(): void
    {
        $tree = ['logic' => 'and', 'conditions' => [
            ['field' => 'amount', 'operator' => 'less_than', 'value' => 100],
        ]];

        $this->assertTrue($this->evaluator->conditionsMet($tree, ['amount' => 50]));
        $this->assertFalse($this->evaluator->conditionsMet($tree, ['amount' => 100]));
        $this->assertFalse($this->evaluator->conditionsMet($tree, ['amount' => 200]));
    }

    public function test_less_than_or_equal(): void
    {
        $tree = ['logic' => 'and', 'conditions' => [
            ['field' => 'amount', 'operator' => 'less_than_or_equal', 'value' => 100],
        ]];

        $this->assertTrue($this->evaluator->conditionsMet($tree, ['amount' => 100]));
        $this->assertTrue($this->evaluator->conditionsMet($tree, ['amount' => 50]));
        $this->assertFalse($this->evaluator->conditionsMet($tree, ['amount' => 101]));
    }

    /**
     * Numeric comparison with string values — evaluator casts to float.
     */
    public function test_numeric_comparison_with_string_values(): void
    {
        $tree = ['logic' => 'and', 'conditions' => [
            ['field' => 'amount', 'operator' => 'greater_than_or_equal', 'value' => '500'],
        ]];

        $this->assertTrue($this->evaluator->conditionsMet($tree, ['amount' => '1000']));
        $this->assertTrue($this->evaluator->conditionsMet($tree, ['amount' => 500]));
        $this->assertFalse($this->evaluator->conditionsMet($tree, ['amount' => '499']));
    }

    /**
     * Numeric comparison with null actual value → false.
     * Evaluator checks $actual !== null before comparison.
     */
    public function test_numeric_comparison_with_null_actual_returns_false(): void
    {
        $tree = ['logic' => 'and', 'conditions' => [
            ['field' => 'amount', 'operator' => 'greater_than', 'value' => 0],
        ]];

        $this->assertFalse($this->evaluator->conditionsMet($tree, ['amount' => null]));
    }

    // ═══════════════════════════════════════════════════════════
    //  F. List operators: in / not_in
    // ═══════════════════════════════════════════════════════════

    public function test_in_operator(): void
    {
        $tree = ['logic' => 'and', 'conditions' => [
            ['field' => 'currency', 'operator' => 'in', 'value' => ['SAR', 'USD', 'EUR']],
        ]];

        $this->assertTrue($this->evaluator->conditionsMet($tree, ['currency' => 'SAR']));
        $this->assertTrue($this->evaluator->conditionsMet($tree, ['currency' => 'USD']));
        $this->assertFalse($this->evaluator->conditionsMet($tree, ['currency' => 'GBP']));
    }

    /**
     * in: uses loose comparison (in_array with false strict param).
     */
    public function test_in_operator_loose_comparison(): void
    {
        $tree = ['logic' => 'and', 'conditions' => [
            ['field' => 'amount', 'operator' => 'in', 'value' => [100, 200, 300]],
        ]];

        // String "100" matches integer 100 with loose comparison
        $this->assertTrue($this->evaluator->conditionsMet($tree, ['amount' => '100']));
    }

    /**
     * in: non-array expected value → false (evaluator: is_array($expected) check).
     */
    public function test_in_operator_non_array_expected_returns_false(): void
    {
        $tree = ['logic' => 'and', 'conditions' => [
            ['field' => 'currency', 'operator' => 'in', 'value' => 'SAR'],
        ]];

        $this->assertFalse($this->evaluator->conditionsMet($tree, ['currency' => 'SAR']));
    }

    public function test_not_in_operator(): void
    {
        $tree = ['logic' => 'and', 'conditions' => [
            ['field' => 'currency', 'operator' => 'not_in', 'value' => ['SAR', 'USD']],
        ]];

        $this->assertTrue($this->evaluator->conditionsMet($tree, ['currency' => 'EUR']));
        $this->assertFalse($this->evaluator->conditionsMet($tree, ['currency' => 'SAR']));
    }

    // ═══════════════════════════════════════════════════════════
    //  G. String operator: contains
    // ═══════════════════════════════════════════════════════════

    public function test_contains_string(): void
    {
        $tree = ['logic' => 'and', 'conditions' => [
            ['field' => 'name', 'operator' => 'contains', 'value' => 'test'],
        ]];

        $this->assertTrue($this->evaluator->conditionsMet($tree, ['name' => 'this is a test deal']));
        $this->assertFalse($this->evaluator->conditionsMet($tree, ['name' => 'production deal']));
    }

    /**
     * contains: null actual → false.
     */
    public function test_contains_null_actual_returns_false(): void
    {
        $tree = ['logic' => 'and', 'conditions' => [
            ['field' => 'name', 'operator' => 'contains', 'value' => 'test'],
        ]];

        $this->assertFalse($this->evaluator->conditionsMet($tree, ['name' => null]));
    }

    /**
     * contains: non-string actual → false.
     * Evaluator checks is_string($actual).
     */
    public function test_contains_non_string_actual_returns_false(): void
    {
        $tree = ['logic' => 'and', 'conditions' => [
            ['field' => 'amount', 'operator' => 'contains', 'value' => '10'],
        ]];

        // Integer 100 is not a string → false
        $this->assertFalse($this->evaluator->conditionsMet($tree, ['amount' => 100]));
    }

    // ═══════════════════════════════════════════════════════════
    //  H. Existence operator: exists
    // ═══════════════════════════════════════════════════════════

    /**
     * exists with value=true: field must be non-null.
     */
    public function test_exists_true(): void
    {
        $tree = ['logic' => 'and', 'conditions' => [
            ['field' => 'notes', 'operator' => 'exists', 'value' => true],
        ]];

        $this->assertTrue($this->evaluator->conditionsMet($tree, ['notes' => 'has content']));
        $this->assertFalse($this->evaluator->conditionsMet($tree, ['notes' => null]));
    }

    /**
     * exists with value=false: field must be null.
     */
    public function test_exists_false(): void
    {
        $tree = ['logic' => 'and', 'conditions' => [
            ['field' => 'notes', 'operator' => 'exists', 'value' => false],
        ]];

        $this->assertTrue($this->evaluator->conditionsMet($tree, ['notes' => null]));
        $this->assertFalse($this->evaluator->conditionsMet($tree, ['notes' => 'has content']));
    }

    /**
     * exists with no value: truthy check → ($expected ? non-null : null).
     * null is falsy in PHP → checks that field IS null.
     */
    public function test_exists_no_value(): void
    {
        $tree = ['logic' => 'and', 'conditions' => [
            ['field' => 'notes', 'operator' => 'exists'],
        ]];

        // value defaults to null, null is falsy → checks ($actual === null)
        $this->assertTrue($this->evaluator->conditionsMet($tree, ['notes' => null]));
        $this->assertFalse($this->evaluator->conditionsMet($tree, ['notes' => 'content']));
    }

    // ═══════════════════════════════════════════════════════════
    //  I. Missing fields
    // ═══════════════════════════════════════════════════════════

    /**
     * Missing field in entity data → $actual defaults to null.
     */
    public function test_missing_field_defaults_to_null(): void
    {
        $tree = ['logic' => 'and', 'conditions' => [
            ['field' => 'nonexistent', 'operator' => 'equals', 'value' => null],
        ]];

        $this->assertTrue($this->evaluator->conditionsMet($tree, ['amount' => 100]));
    }

    /**
     * Missing field with greater_than → false (null !== null check).
     */
    public function test_missing_field_numeric_comparison_returns_false(): void
    {
        $tree = ['logic' => 'and', 'conditions' => [
            ['field' => 'nonexistent', 'operator' => 'greater_than', 'value' => 0],
        ]];

        $this->assertFalse($this->evaluator->conditionsMet($tree, ['amount' => 100]));
    }

    // ═══════════════════════════════════════════════════════════
    //  J. Malformed conditions
    // ═══════════════════════════════════════════════════════════

    /**
     * Condition with no 'field' key → evaluator returns true (skip).
     */
    public function test_condition_without_field_returns_true(): void
    {
        $tree = ['logic' => 'and', 'conditions' => [
            ['operator' => 'equals', 'value' => 'something'],
        ]];

        $this->assertTrue($this->evaluator->conditionsMet($tree, ['amount' => 100]));
    }

    /**
     * Condition with field=null → evaluator returns true (skip).
     */
    public function test_condition_with_null_field_returns_true(): void
    {
        $tree = ['logic' => 'and', 'conditions' => [
            ['field' => null, 'operator' => 'equals', 'value' => 'something'],
        ]];

        $this->assertTrue($this->evaluator->conditionsMet($tree, ['amount' => 100]));
    }

    /**
     * Unknown operator → evaluator returns true (default case in match).
     */
    public function test_unknown_operator_returns_true(): void
    {
        $tree = ['logic' => 'and', 'conditions' => [
            ['field' => 'amount', 'operator' => 'fancy_new_op', 'value' => 100],
        ]];

        $this->assertTrue($this->evaluator->conditionsMet($tree, ['amount' => 200]));
    }

    /**
     * Condition with no operator → defaults to 'equals'.
     */
    public function test_missing_operator_defaults_to_equals(): void
    {
        $tree = ['logic' => 'and', 'conditions' => [
            ['field' => 'currency', 'value' => 'SAR'],
        ]];

        $this->assertTrue($this->evaluator->conditionsMet($tree, ['currency' => 'SAR']));
        $this->assertFalse($this->evaluator->conditionsMet($tree, ['currency' => 'USD']));
    }

    // ═══════════════════════════════════════════════════════════
    //  K. Nested groups (evaluator supports recursion)
    // ═══════════════════════════════════════════════════════════

    /**
     * Nested group inside conditions array.
     * Amount >= 500 AND (currency = SAR OR currency = USD)
     */
    public function test_nested_group(): void
    {
        $tree = [
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
        ];

        $this->assertTrue($this->evaluator->conditionsMet($tree, ['amount' => 600, 'currency' => 'SAR']));
        $this->assertTrue($this->evaluator->conditionsMet($tree, ['amount' => 600, 'currency' => 'USD']));
        $this->assertFalse($this->evaluator->conditionsMet($tree, ['amount' => 600, 'currency' => 'EUR']));
        $this->assertFalse($this->evaluator->conditionsMet($tree, ['amount' => 100, 'currency' => 'SAR']));
    }

    /**
     * Double-nested groups.
     */
    public function test_double_nested_group(): void
    {
        $tree = [
            'logic' => 'or',
            'conditions' => [
                [
                    'logic' => 'and',
                    'conditions' => [
                        ['field' => 'amount', 'operator' => 'greater_than', 'value' => 1000],
                        [
                            'logic' => 'or',
                            'conditions' => [
                                ['field' => 'currency', 'operator' => 'equals', 'value' => 'SAR'],
                                ['field' => 'currency', 'operator' => 'equals', 'value' => 'USD'],
                            ],
                        ],
                    ],
                ],
                ['field' => 'status', 'operator' => 'equals', 'value' => 'vip'],
            ],
        ];

        // Matches inner AND+OR
        $this->assertTrue($this->evaluator->conditionsMet($tree, [
            'amount' => 2000, 'currency' => 'SAR', 'status' => 'normal',
        ]));

        // Matches outer OR via status
        $this->assertTrue($this->evaluator->conditionsMet($tree, [
            'amount' => 10, 'currency' => 'EUR', 'status' => 'vip',
        ]));

        // Matches neither
        $this->assertFalse($this->evaluator->conditionsMet($tree, [
            'amount' => 10, 'currency' => 'EUR', 'status' => 'normal',
        ]));
    }

    // ═══════════════════════════════════════════════════════════
    //  L. Legacy flat array format
    // ═══════════════════════════════════════════════════════════

    /**
     * Flat array of conditions (no logic key) → treated as AND.
     */
    public function test_flat_array_treated_as_and(): void
    {
        $tree = [
            ['field' => 'amount', 'operator' => 'greater_than', 'value' => 100],
            ['field' => 'currency', 'operator' => 'equals', 'value' => 'SAR'],
        ];

        $this->assertTrue($this->evaluator->conditionsMet($tree, ['amount' => 200, 'currency' => 'SAR']));
        $this->assertFalse($this->evaluator->conditionsMet($tree, ['amount' => 200, 'currency' => 'USD']));
        $this->assertFalse($this->evaluator->conditionsMet($tree, ['amount' => 50, 'currency' => 'SAR']));
    }

    // ═══════════════════════════════════════════════════════════
    //  M. Demo workflow payload (regression)
    // ═══════════════════════════════════════════════════════════

    /**
     * Exact canonical demo payload from sync_demo_approval_workflows.php.
     */
    public function test_canonical_demo_payload(): void
    {
        $tree = [
            'logic' => 'and',
            'conditions' => [
                ['field' => 'amount', 'operator' => 'greater_than_or_equal', 'value' => 500],
                ['field' => 'currency', 'operator' => 'equals', 'value' => 'SAR'],
            ],
        ];

        // Should trigger: amount >= 500 AND currency = SAR
        $this->assertTrue($this->evaluator->conditionsMet($tree, [
            'amount' => 1000.0, 'currency' => 'SAR',
        ]));

        // Boundary: exactly 500
        $this->assertTrue($this->evaluator->conditionsMet($tree, [
            'amount' => 500, 'currency' => 'SAR',
        ]));

        // Below threshold
        $this->assertFalse($this->evaluator->conditionsMet($tree, [
            'amount' => 499.99, 'currency' => 'SAR',
        ]));

        // Wrong currency
        $this->assertFalse($this->evaluator->conditionsMet($tree, [
            'amount' => 1000, 'currency' => 'USD',
        ]));
    }

    // ═══════════════════════════════════════════════════════════
    //  N. Logic case-insensitivity
    // ═══════════════════════════════════════════════════════════

    public function test_logic_is_case_insensitive(): void
    {
        $tree = [
            'logic' => 'AND',
            'conditions' => [
                ['field' => 'amount', 'operator' => 'equals', 'value' => 100],
            ],
        ];

        $this->assertTrue($this->evaluator->conditionsMet($tree, ['amount' => 100]));
    }

    /**
     * Unknown logic value → evaluateGroup returns false.
     *
     * With logic='xor':
     *  - Neither 'or' short-circuit (line 127) nor 'and' short-circuit (line 131) fires
     *  - Loop completes without early return
     *  - Final return: $logic === 'and' → false (because 'xor' !== 'and')
     *
     * This means unknown logic values effectively reject all conditions.
     */
    public function test_unknown_logic_returns_false(): void
    {
        $tree = [
            'logic' => 'xor',
            'conditions' => [
                ['field' => 'a', 'operator' => 'equals', 'value' => 1],
                ['field' => 'b', 'operator' => 'equals', 'value' => 2],
            ],
        ];

        // Even when all conditions match, unknown logic returns false
        $this->assertFalse($this->evaluator->conditionsMet($tree, ['a' => 1, 'b' => 2]));
        $this->assertFalse($this->evaluator->conditionsMet($tree, ['a' => 1, 'b' => 99]));
    }

    // ═══════════════════════════════════════════════════════════
    //  O. Evaluator-Validator Operator Parity
    // ═══════════════════════════════════════════════════════════

    /**
     * Every operator accepted by TriggerConditionValidator::SUPPORTED_OPERATORS
     * is implemented by the evaluator's match expression, and vice versa.
     *
     * This test extracts operators directly from the evaluator's source code
     * (the match arms in evaluateSingle) and compares them to the validator's
     * public constant. This prevents drift without duplicating hardcoded lists.
     */
    public function test_evaluator_validator_operator_parity(): void
    {
        // 1. Get validator's declared operators
        $validatorOps = \App\Services\TriggerConditionValidator::SUPPORTED_OPERATORS;

        // 2. Extract evaluator's operators from source code match expression
        $reflector = new \ReflectionClass(ApprovalTriggerEvaluator::class);
        $sourceFile = $reflector->getFileName();
        $source = file_get_contents($sourceFile);

        // Extract the match block from evaluateSingle
        // The match expression uses 'operator_name' => as arms
        preg_match('/return match\s*\(\$operator\)\s*\{(.*?)\};/s', $source, $matchBlock);
        $this->assertNotEmpty($matchBlock, 'Could not find the match($operator) block in evaluator source.');

        // Extract individual operator strings from match arms (e.g., 'equals', 'not_equals')
        preg_match_all("/'([a-z_]+)'/", $matchBlock[1], $operatorMatches);
        $evaluatorOps = $operatorMatches[1];

        // Remove 'default' if captured (it's not an operator)
        $evaluatorOps = array_filter($evaluatorOps, fn ($op) => $op !== 'default');
        $evaluatorOps = array_values(array_unique($evaluatorOps));

        sort($evaluatorOps);
        $sortedValidatorOps = $validatorOps;
        sort($sortedValidatorOps);

        // 3. Assert bidirectional parity
        $inValidatorNotEvaluator = array_diff($sortedValidatorOps, $evaluatorOps);
        $inEvaluatorNotValidator = array_diff($evaluatorOps, $sortedValidatorOps);

        $this->assertEmpty(
            $inValidatorNotEvaluator,
            'Operators in Validator but NOT in Evaluator match arms: ' . implode(', ', $inValidatorNotEvaluator)
        );
        $this->assertEmpty(
            $inEvaluatorNotValidator,
            'Operators in Evaluator match arms but NOT in Validator: ' . implode(', ', $inEvaluatorNotValidator)
        );

        // Sanity: we expect exactly 10 operators
        $this->assertCount(10, $evaluatorOps, 'Expected exactly 10 operators in evaluator.');
        $this->assertCount(10, $validatorOps, 'Expected exactly 10 operators in validator.');
    }
}
