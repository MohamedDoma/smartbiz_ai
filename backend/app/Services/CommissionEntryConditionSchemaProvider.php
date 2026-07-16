<?php

namespace App\Services;

use App\Contracts\ConditionEntitySchemaProvider;
use App\Models\CommissionEntry;

/**
 * CommissionEntryConditionSchemaProvider — Field catalog AND runtime mapper
 * for commission_entry trigger conditions.
 *
 * This class is the SINGLE SOURCE OF TRUTH for which fields are available
 * in approval workflow trigger conditions for commission entries.
 *
 * It serves two roles:
 *  1. Schema provider (implements ConditionEntitySchemaProvider) — tells the
 *     condition builder UI which fields exist, their types, and allowed operators.
 *  2. Runtime mapper (evaluationData) — extracts the exact field values from a
 *     CommissionEntry model instance for use by ApprovalTriggerEvaluator.
 *
 * CRITICAL CONTRACT:
 *   CommissionEntryController MUST call evaluationData() instead of building
 *   its own $entityData array. This eliminates the possibility of drift between
 *   the catalog schema and the runtime evaluation data.
 *
 *   The FIELD_KEYS constant is derived from evaluationData() and validated by
 *   parity tests in EntityFieldCatalogTest.
 *
 * Canonical field mapping:
 *   'amount'           → (float) $entry->commission_amount
 *   'base_amount'      → (float) $entry->base_amount
 *   'currency'         → $entry->currency
 *   'calculation_type' → $entry->calculation_type
 *   'percentage_rate'  → $entry->percentage_rate  (nullable, preserved as-is)
 *
 * Canonical calculation_type enum values (sourced from CommissionRuleController
 * validation rule 'in:percentage,fixed_amount'):
 *   'percentage', 'fixed_amount'
 */
class CommissionEntryConditionSchemaProvider implements ConditionEntitySchemaProvider
{
    /**
     * Canonical calculation_type enum values.
     *
     * Source of truth: CommissionRuleController store/update validation
     * rule 'in:percentage,fixed_amount'. This constant must stay in sync.
     */
    public const CALCULATION_TYPES = ['percentage', 'fixed_amount'];

    /**
     * The canonical field keys for commission_entry trigger conditions.
     *
     * Derived from evaluationData(). Parity tests validate that these keys
     * match both the fields() schema and the evaluationData() output.
     */
    public const FIELD_KEYS = [
        'amount',
        'base_amount',
        'currency',
        'calculation_type',
        'percentage_rate',
    ];

    public function entityType(): string
    {
        return 'commission_entry';
    }

    public function labelEn(): string
    {
        return 'Commission entry';
    }

    public function labelAr(): string
    {
        return 'سجل عمولة';
    }

    public function moduleKey(): ?string
    {
        return 'commissions';
    }

    public function requiredModule(): ?string
    {
        return 'commissions';
    }

    /**
     * Extract evaluation data from a CommissionEntry for trigger condition matching.
     *
     * This is the SINGLE mapping point used by CommissionEntryController when
     * building data for ApprovalTriggerEvaluator::evaluate(). The returned
     * array keys MUST exactly match FIELD_KEYS and the keys in fields().
     *
     * Type casts replicate the exact behavior of the original manual mapping:
     *  - amount:          (float) cast on commission_amount (was: (float) $entry->commission_amount)
     *  - base_amount:     (float) cast on base_amount      (was: (float) $entry->base_amount)
     *  - currency:        string, passed as-is              (was: $entry->currency)
     *  - calculation_type: string, passed as-is             (was: $entry->calculation_type)
     *  - percentage_rate: nullable, passed as-is            (was: $entry->percentage_rate)
     *
     * @param CommissionEntry $entry The commission entry to extract data from
     * @return array<string, mixed> Keyed by FIELD_KEYS values
     */
    public function evaluationData(CommissionEntry $entry): array
    {
        return [
            'amount'           => (float) $entry->commission_amount,
            'base_amount'      => (float) $entry->base_amount,
            'currency'         => $entry->currency,
            'calculation_type' => $entry->calculation_type,
            'percentage_rate'  => $entry->percentage_rate,
        ];
    }

    public function fields(): array
    {
        return [
            [
                'key'       => 'amount',
                'type'      => 'number',
                'label_en'  => 'Commission Amount',
                'label_ar'  => 'مبلغ العمولة',
                'operators' => [
                    'equals',
                    'not_equals',
                    'greater_than',
                    'greater_than_or_equal',
                    'less_than',
                    'less_than_or_equal',
                ],
                'options'   => null,
            ],
            [
                'key'       => 'base_amount',
                'type'      => 'number',
                'label_en'  => 'Base Amount',
                'label_ar'  => 'المبلغ الأساسي',
                'operators' => [
                    'equals',
                    'not_equals',
                    'greater_than',
                    'greater_than_or_equal',
                    'less_than',
                    'less_than_or_equal',
                ],
                'options'   => null,
            ],
            [
                'key'       => 'currency',
                'type'      => 'string',
                'label_en'  => 'Currency',
                'label_ar'  => 'العملة',
                'operators' => [
                    'equals',
                    'not_equals',
                    'in',
                    'not_in',
                ],
                'options'   => null,
            ],
            [
                'key'       => 'calculation_type',
                'type'      => 'enum',
                'label_en'  => 'Calculation Type',
                'label_ar'  => 'نوع الحساب',
                'operators' => [
                    'equals',
                    'not_equals',
                    'in',
                    'not_in',
                ],
                'options'   => array_map(fn (string $val) => [
                    'value'    => $val,
                    'label_en' => ucwords(str_replace('_', ' ', $val)),
                    'label_ar' => match ($val) {
                        'percentage'   => 'نسبة مئوية',
                        'fixed_amount' => 'مبلغ ثابت',
                        default        => $val,
                    },
                ], self::CALCULATION_TYPES),
            ],
            [
                'key'       => 'percentage_rate',
                'type'      => 'number',
                'label_en'  => 'Percentage Rate',
                'label_ar'  => 'نسبة العمولة',
                'operators' => [
                    'equals',
                    'not_equals',
                    'greater_than',
                    'greater_than_or_equal',
                    'less_than',
                    'less_than_or_equal',
                ],
                'options'   => null,
            ],
        ];
    }
}
