<?php

namespace App\Services;

/**
 * TriggerConditionValidator — Structural validation for workflow trigger_conditions.
 *
 * Validates the JSON structure of trigger_conditions payloads before persistence.
 * This is a stateless, pure-logic validator with no database or entity dependencies.
 *
 * What it validates:
 *  - Top-level shape: must be an object/array with optional 'logic' and 'conditions' keys
 *  - Logic combinator: must be 'and' or 'or' (case-insensitive)
 *  - Conditions array: must be a sequential array of condition objects or nested groups
 *  - Each condition: must have a non-empty 'field' string and a valid 'operator'
 *  - Operator: must be in the set supported by ApprovalTriggerEvaluator
 *  - Value constraints: list operators require arrays, numeric operators require numeric values
 *  - Nesting: limited to MAX_NESTING_DEPTH levels to prevent abuse
 *
 * What it does NOT validate (deferred to Phase 2 Entity Field Catalog):
 *  - Whether a field name is valid for the given entity type
 *  - Whether a value is semantically valid for the field's data type
 *
 * Design:
 *  - Zero hardcoded entity types, role names, or business rules
 *  - Backward-compatible: accepts all payloads that the evaluator currently processes
 *  - Empty payloads ({}, [], null, {conditions:[]}) are valid (evaluator treats as "always trigger")
 */
class TriggerConditionValidator
{
    /**
     * Maximum nesting depth for condition groups.
     * Prevents deeply nested payloads from causing stack overflows or abuse.
     */
    public const MAX_NESTING_DEPTH = 5;

    /**
     * Operators supported by ApprovalTriggerEvaluator.
     * This list MUST stay in sync with the evaluator's match expression.
     */
    public const SUPPORTED_OPERATORS = [
        'equals',
        'not_equals',
        'greater_than',
        'greater_than_or_equal',
        'less_than',
        'less_than_or_equal',
        'in',
        'not_in',
        'contains',
        'exists',
    ];

    /**
     * Operators that require the value to be an array.
     */
    private const LIST_OPERATORS = ['in', 'not_in'];

    /**
     * Operators that perform numeric comparison (value must be numeric).
     */
    private const NUMERIC_OPERATORS = [
        'greater_than',
        'greater_than_or_equal',
        'less_than',
        'less_than_or_equal',
    ];

    /**
     * Operators that do NOT require a value at all.
     * 'exists' checks for field presence; its value is a boolean flag (true/false),
     * but the evaluator defaults to checking existence when value is missing.
     */
    private const VALUE_OPTIONAL_OPERATORS = ['exists'];

    /**
     * Validate a trigger_conditions payload.
     *
     * Returns null if valid, or an array of error messages if invalid.
     *
     * @param mixed $payload  The raw trigger_conditions value (already decoded from JSON)
     * @return array|null     Null on success, array of error strings on failure
     */
    public function validate(mixed $payload): ?array
    {
        // Null, empty array, or empty object → valid (evaluator treats as "always trigger")
        if ($payload === null || $payload === [] || $payload === (object) []) {
            return null;
        }

        if (! is_array($payload)) {
            return ['trigger_conditions must be an object or array.'];
        }

        // Empty associative array → valid
        if (empty($payload)) {
            return null;
        }

        return $this->validateNode($payload, 'trigger_conditions', 0);
    }

    /**
     * Validate a single node (group or condition).
     *
     * @param array  $node   The node to validate
     * @param string $path   Human-readable path for error messages
     * @param int    $depth  Current nesting depth
     * @return array|null    Null on success, array of error strings on failure
     */
    private function validateNode(array $node, string $path, int $depth): ?array
    {
        if ($depth > self::MAX_NESTING_DEPTH) {
            return ["{$path}: exceeds maximum nesting depth of " . self::MAX_NESTING_DEPTH . '.'];
        }

        // Detect if this is a group node (has 'logic' or 'conditions' key)
        $isGroup = isset($node['logic']) || isset($node['conditions']);

        // Detect if this is a flat array of conditions (legacy format: [{...}, {...}])
        $isFlatArray = isset($node[0]) && is_array($node[0]);

        if ($isGroup) {
            return $this->validateGroup($node, $path, $depth);
        }

        if ($isFlatArray) {
            return $this->validateFlatArray($node, $path, $depth);
        }

        // If it has 'field' or 'operator', treat as a single condition at root level
        if (isset($node['field']) || isset($node['operator'])) {
            return $this->validateSingleCondition($node, $path);
        }

        // Unknown shape with keys but not a valid group or condition
        // The evaluator returns true for unknown shapes, but we should reject on write
        // to prevent garbage data from accumulating.
        return ["{$path}: unrecognized structure. Expected a condition group {logic, conditions} or a condition {field, operator, value}."];
    }

    /**
     * Validate a condition group: {logic: "and"|"or", conditions: [...]}
     */
    private function validateGroup(array $group, string $path, int $depth): ?array
    {
        $errors = [];

        // Validate logic combinator
        if (isset($group['logic'])) {
            $logic = strtolower((string) $group['logic']);
            if (! in_array($logic, ['and', 'or'], true)) {
                $errors[] = "{$path}.logic: must be 'and' or 'or', got '{$group['logic']}'.";
            }
        }

        // Validate conditions array
        if (isset($group['conditions'])) {
            if (! is_array($group['conditions'])) {
                $errors[] = "{$path}.conditions: must be an array.";
                return $errors;
            }

            // Sequential array check (not associative)
            if (! empty($group['conditions']) && ! array_is_list($group['conditions'])) {
                $errors[] = "{$path}.conditions: must be a sequential array, not an associative object.";
                return $errors;
            }

            foreach ($group['conditions'] as $i => $condition) {
                $childPath = "{$path}.conditions[{$i}]";

                if (! is_array($condition)) {
                    $errors[] = "{$childPath}: each condition must be an object.";
                    continue;
                }

                // Nested group detection
                if (isset($condition['logic']) || isset($condition['conditions'])) {
                    $childErrors = $this->validateGroup($condition, $childPath, $depth + 1);
                } else {
                    $childErrors = $this->validateSingleCondition($condition, $childPath);
                }

                if ($childErrors) {
                    $errors = array_merge($errors, $childErrors);
                }
            }
        } elseif (! isset($group['logic'])) {
            // Neither logic nor conditions — not a valid group
            $errors[] = "{$path}: condition group must have at least a 'logic' or 'conditions' key.";
        }

        // Having logic without conditions is valid (evaluator returns true for empty conditions)
        return empty($errors) ? null : $errors;
    }

    /**
     * Validate a flat array of conditions (legacy format without logic key).
     * Treated as implicit AND by the evaluator.
     */
    private function validateFlatArray(array $conditions, string $path, int $depth): ?array
    {
        $errors = [];

        foreach ($conditions as $i => $condition) {
            $childPath = "{$path}[{$i}]";

            if (! is_array($condition)) {
                $errors[] = "{$childPath}: each condition must be an object.";
                continue;
            }

            // Nested group in flat array
            if (isset($condition['logic']) || isset($condition['conditions'])) {
                $childErrors = $this->validateGroup($condition, $childPath, $depth + 1);
            } else {
                $childErrors = $this->validateSingleCondition($condition, $childPath);
            }

            if ($childErrors) {
                $errors = array_merge($errors, $childErrors);
            }
        }

        return empty($errors) ? null : $errors;
    }

    /**
     * Validate a single condition: {field: "...", operator: "...", value: ...}
     */
    private function validateSingleCondition(array $condition, string $path): ?array
    {
        $errors = [];

        // Field must be a non-empty string
        if (! isset($condition['field']) || ! is_string($condition['field']) || trim($condition['field']) === '') {
            $errors[] = "{$path}.field: must be a non-empty string.";
        }

        // Operator validation
        $operator = $condition['operator'] ?? null;
        if ($operator === null) {
            // The evaluator defaults to 'equals' when operator is missing,
            // but for new writes we should require it to be explicit.
            $errors[] = "{$path}.operator: is required.";
        } elseif (! is_string($operator)) {
            $errors[] = "{$path}.operator: must be a string.";
        } elseif (! in_array($operator, self::SUPPORTED_OPERATORS, true)) {
            $errors[] = "{$path}.operator: unsupported operator '{$operator}'. Supported: " . implode(', ', self::SUPPORTED_OPERATORS) . '.';
        } else {
            // Operator-specific value validation
            $valueErrors = $this->validateValueForOperator($condition, $operator, $path);
            if ($valueErrors) {
                $errors = array_merge($errors, $valueErrors);
            }
        }

        return empty($errors) ? null : $errors;
    }

    /**
     * Validate the 'value' field based on the operator's requirements.
     */
    private function validateValueForOperator(array $condition, string $operator, string $path): ?array
    {
        $errors = [];
        $hasValue = array_key_exists('value', $condition);

        // Value-optional operators (exists)
        if (in_array($operator, self::VALUE_OPTIONAL_OPERATORS, true)) {
            // 'exists' accepts any value (boolean flag) or no value at all
            return null;
        }

        // All other operators require a value
        if (! $hasValue) {
            $errors[] = "{$path}.value: is required for operator '{$operator}'.";
            return $errors;
        }

        $value = $condition['value'];

        // List operators require arrays
        if (in_array($operator, self::LIST_OPERATORS, true)) {
            if (! is_array($value)) {
                $errors[] = "{$path}.value: must be an array for operator '{$operator}'.";
            } elseif (! array_is_list($value)) {
                $errors[] = "{$path}.value: must be a sequential array (list) for operator '{$operator}'.";
            }
            return empty($errors) ? null : $errors;
        }

        // Numeric operators require numeric values
        if (in_array($operator, self::NUMERIC_OPERATORS, true)) {
            if (! is_numeric($value)) {
                $errors[] = "{$path}.value: must be numeric for operator '{$operator}', got " . gettype($value) . '.';
            }
            return empty($errors) ? null : $errors;
        }

        // equals, not_equals, contains — accept any scalar or null value
        // No further validation needed for Phase 1.

        return null;
    }
}
