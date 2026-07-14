<?php

namespace App\Services;

use App\Models\ApprovalWorkflow;

/**
 * ApprovalTriggerEvaluator — Generic condition evaluator for approval workflows.
 *
 * Reads a workflow's `trigger_conditions` column and evaluates them against
 * an arbitrary entity data array. Returns the workflow if the entity meets the
 * conditions and should be submitted for approval.
 *
 * Condition format (canonical JSON):
 *  {
 *    "logic": "and",           // "and" or "or"
 *    "conditions": [
 *      {"field": "amount", "operator": "greater_than_or_equal", "value": 500},
 *      {"field": "currency", "operator": "equals", "value": "SAR"}
 *    ]
 *  }
 *
 * Supported operators:
 *  - equals, not_equals
 *  - greater_than, greater_than_or_equal
 *  - less_than, less_than_or_equal
 *  - in, not_in
 *  - contains
 *  - exists
 *
 * Design:
 *  - Zero hardcoded entity types or business rules
 *  - Generic field/operator/value conditions
 *  - Supports AND/OR logic combinators
 *  - Empty conditions = always trigger
 */
class ApprovalTriggerEvaluator
{
    /**
     * Determine if the given entity data triggers an approval workflow.
     *
     * @param string $entityType  e.g. "commission_entry", "invoice"
     * @param string $workspaceId
     * @param array  $entityData  Key-value pairs from the entity
     *
     * @return ApprovalWorkflow|null  The matching workflow, or null if no trigger
     */
    public function evaluate(string $entityType, string $workspaceId, array $entityData): ?ApprovalWorkflow
    {
        $workflow = ApprovalWorkflow::where('workspace_id', $workspaceId)
            ->forEntity($entityType)
            ->active()
            ->orderBy('sort_order')
            ->first();

        if (!$workflow) {
            return null;
        }

        $conditions = $workflow->trigger_conditions ?? [];

        // No conditions = always trigger (workflow applies to all entities of this type)
        if (empty($conditions)) {
            return $workflow;
        }

        if ($this->conditionsMet($conditions, $entityData)) {
            return $workflow;
        }

        return null;
    }

    /**
     * Evaluate a condition tree against entity data.
     *
     * Accepts either:
     *  - A condition tree: {"logic": "and|or", "conditions": [...]}
     *  - A flat array of conditions (legacy compat — treated as AND)
     *
     * @param array $conditionTree  From workflow trigger_conditions column
     * @param array $entityData     Key-value pairs from the entity
     *
     * @return bool  True if conditions are met
     */
    public function conditionsMet(array $conditionTree, array $entityData): bool
    {
        // Detect canonical shape: {"logic": "...", "conditions": [...]}
        if (isset($conditionTree['logic']) && isset($conditionTree['conditions'])) {
            return $this->evaluateGroup($conditionTree, $entityData);
        }

        // Flat conditions array (no logic key) → treat as AND
        if (isset($conditionTree[0]) && is_array($conditionTree[0])) {
            foreach ($conditionTree as $condition) {
                if (!$this->evaluateSingle($condition, $entityData)) {
                    return false;
                }
            }
            return true;
        }

        // Empty or unknown shape — pass
        return true;
    }

    /**
     * Evaluate a logic group (AND/OR) of conditions.
     */
    private function evaluateGroup(array $group, array $entityData): bool
    {
        $logic = strtolower($group['logic'] ?? 'and');
        $conditions = $group['conditions'] ?? [];

        if (empty($conditions)) {
            return true;
        }

        foreach ($conditions as $condition) {
            // Nested group
            if (isset($condition['logic']) && isset($condition['conditions'])) {
                $result = $this->evaluateGroup($condition, $entityData);
            } else {
                $result = $this->evaluateSingle($condition, $entityData);
            }

            if ($logic === 'or' && $result) {
                return true; // short-circuit OR
            }

            if ($logic === 'and' && !$result) {
                return false; // short-circuit AND
            }
        }

        // AND: all passed → true; OR: none passed → false
        return $logic === 'and';
    }

    /**
     * Evaluate a single condition: {"field": "...", "operator": "...", "value": ...}
     */
    private function evaluateSingle(array $condition, array $entityData): bool
    {
        $field = $condition['field'] ?? null;
        $operator = $condition['operator'] ?? 'equals';
        $expected = $condition['value'] ?? null;

        if ($field === null) {
            return true; // malformed condition → skip
        }

        $actual = $entityData[$field] ?? null;

        return match ($operator) {
            'equals'                 => $this->looseEquals($actual, $expected),
            'not_equals'             => !$this->looseEquals($actual, $expected),
            'greater_than'           => $actual !== null && (float) $actual > (float) $expected,
            'greater_than_or_equal'  => $actual !== null && (float) $actual >= (float) $expected,
            'less_than'              => $actual !== null && (float) $actual < (float) $expected,
            'less_than_or_equal'     => $actual !== null && (float) $actual <= (float) $expected,
            'in'                     => is_array($expected) && in_array($actual, $expected, false),
            'not_in'                 => is_array($expected) && !in_array($actual, $expected, false),
            'contains'               => $actual !== null && is_string($actual) && str_contains($actual, (string) $expected),
            'exists'                 => $expected ? ($actual !== null) : ($actual === null),
            default                  => true, // unknown operator → skip
        };
    }

    /**
     * Loose equality: handles numeric strings vs integers ("500" == 500).
     */
    private function looseEquals(mixed $actual, mixed $expected): bool
    {
        if ($actual === null && $expected === null) {
            return true;
        }
        if ($actual === null || $expected === null) {
            return false;
        }

        return (string) $actual === (string) $expected;
    }
}
