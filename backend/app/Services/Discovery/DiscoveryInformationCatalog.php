<?php

namespace App\Services\Discovery;

/**
 * DiscoveryInformationCatalog — Coverage metadata for discovery sessions.
 *
 * Defines information categories, their fact keys, importance levels,
 * and applicability conditions. This is a coverage-tracking reference
 * used by the readiness evaluator and as context for the AI analyzer.
 *
 * This catalog does NOT define question text, question order, or
 * conversational flow. The AI determines what to ask and how.
 *
 * Each category has:
 *  - key:           Stable identifier used in discovery_state
 *  - label:         Human-readable category name
 *  - fact_keys:     Fields that can be extracted from user input
 *  - importance:    'critical' | 'important' | 'optional' — base importance
 *  - relevance:     Business types where this category applies ('*' = all)
 *  - applicability: Conditions under which this category becomes relevant
 *  - prerequisites: Fact keys that should exist before this category matters
 */
class DiscoveryInformationCatalog
{
    /**
     * All valid fact keys that can be stored in discovery_state.known_facts.
     * Organized by category for validation and completeness checking.
     */
    public const CATEGORIES = [
        // ── Core Business Profile ─────────────────────────────────
        'business_identity' => [
            'label'         => 'Business Identity',
            'fact_keys'     => ['business_name', 'business_description', 'business_type_hint'],
            'importance'    => 'critical',
            'relevance'     => ['*'],
            'applicability' => 'always',
            'prerequisites' => [],
            'fallback_hint' => 'business name and primary activity',
        ],
        'geography' => [
            'label'         => 'Geography & Locale',
            'fact_keys'     => ['country', 'timezone', 'currency', 'primary_language'],
            'importance'    => 'critical',
            'relevance'     => ['*'],
            'applicability' => 'always',
            'prerequisites' => [],
            'fallback_hint' => 'operating country and currency',
        ],
        'scale' => [
            'label'         => 'Business Scale',
            'fact_keys'     => ['employee_count', 'branch_count', 'company_size'],
            'importance'    => 'critical',
            'relevance'     => ['*'],
            'applicability' => 'always',
            'prerequisites' => [],
            'fallback_hint' => 'team size and number of locations',
        ],

        // ── Operations ────────────────────────────────────────────
        'products_services' => [
            'label'         => 'Products & Services',
            'fact_keys'     => ['sells_products', 'sells_services', 'product_types', 'product_count_range'],
            'importance'    => 'critical',
            'relevance'     => ['*'],
            'applicability' => 'always',
            'prerequisites' => [],
            'fallback_hint' => 'products or services offered',
        ],
        'sales_channels' => [
            'label'         => 'Sales Channels',
            'fact_keys'     => ['sales_channels', 'uses_pos', 'uses_ecommerce', 'uses_wholesale'],
            'importance'    => 'important',
            'relevance'     => ['retail', 'restaurant', 'distribution', 'manufacturing', 'hybrid'],
            'applicability' => 'when_sells_products_or_services',
            'prerequisites' => ['sells_products', 'sells_services'],
            'fallback_hint' => 'how customers buy from them',
        ],
        'customers' => [
            'label'         => 'Customer Types',
            'fact_keys'     => ['customer_types', 'customer_count_range', 'uses_crm'],
            'importance'    => 'important',
            'relevance'     => ['*'],
            'applicability' => 'always',
            'prerequisites' => [],
            'fallback_hint' => 'types of customers served',
        ],
        'inventory' => [
            'label'         => 'Inventory & Warehousing',
            'fact_keys'     => ['uses_inventory', 'warehouse_count', 'inventory_complexity', 'warehouse_details'],
            'importance'    => 'important',
            'relevance'     => ['retail', 'distribution', 'manufacturing', 'restaurant', 'hybrid'],
            'applicability' => 'when_has_physical_goods',
            'prerequisites' => ['sells_products'],
            'fallback_hint' => 'inventory tracking and storage locations',
        ],
        'suppliers' => [
            'label'         => 'Suppliers & Purchasing',
            'fact_keys'     => ['has_suppliers', 'supplier_count_range', 'purchase_process'],
            'importance'    => 'optional',
            'relevance'     => ['retail', 'distribution', 'manufacturing', 'restaurant', 'hybrid'],
            'applicability' => 'when_has_physical_goods',
            'prerequisites' => ['sells_products'],
            'fallback_hint' => 'supplier relationships and purchasing',
        ],
        'production' => [
            'label'         => 'Manufacturing & Production',
            'fact_keys'     => ['uses_manufacturing', 'production_type', 'uses_bom'],
            'importance'    => 'important',
            'relevance'     => ['manufacturing'],
            'applicability' => 'when_manufactures',
            'prerequisites' => ['uses_manufacturing'],
            'fallback_hint' => 'production process and materials',
        ],
        'delivery' => [
            'label'         => 'Delivery & Logistics',
            'fact_keys'     => ['uses_delivery', 'delivery_model', 'fleet_owned'],
            'importance'    => 'optional',
            'relevance'     => ['distribution', 'restaurant', 'retail', 'hybrid'],
            'applicability' => 'when_delivers',
            'prerequisites' => [],
            'fallback_hint' => 'delivery methods and logistics',
        ],

        // ── Finance ───────────────────────────────────────────────
        'finance' => [
            'label'         => 'Finance & Payments',
            'fact_keys'     => ['payment_methods', 'uses_invoicing', 'uses_accounting', 'tax_requirements'],
            'importance'    => 'critical',
            'relevance'     => ['*'],
            'applicability' => 'always',
            'prerequisites' => [],
            'fallback_hint' => 'payment methods and financial management',
        ],
        'expenses' => [
            'label'         => 'Expenses & Budgets',
            'fact_keys'     => ['tracks_expenses', 'has_recurring_expenses', 'needs_budgeting'],
            'importance'    => 'optional',
            'relevance'     => ['*'],
            'applicability' => 'when_medium_or_larger',
            'prerequisites' => ['employee_count'],
            'fallback_hint' => 'expense tracking and budgeting',
        ],

        // ── Organization ──────────────────────────────────────────
        'team_structure' => [
            'label'         => 'Team & Roles',
            'fact_keys'     => ['department_count', 'role_names', 'has_teams', 'needs_permissions', 'role_details'],
            'importance'    => 'important',
            'relevance'     => ['*'],
            'applicability' => 'when_has_employees',
            'prerequisites' => ['employee_count'],
            'fallback_hint' => 'team structure and role responsibilities',
        ],

        // ── Business Rules ────────────────────────────────────────
        'approvals' => [
            'label'         => 'Approval Workflows',
            'fact_keys'     => ['needs_approvals', 'approval_types', 'discount_approval_rules', 'approval_workflows'],
            'importance'    => 'optional',
            'relevance'     => ['*'],
            'applicability' => 'when_medium_or_larger',
            'prerequisites' => ['employee_count'],
            'fallback_hint' => 'approval workflows and authorization rules',
        ],
        'pipelines' => [
            'label'         => 'Sales Pipeline',
            'fact_keys'     => ['pipeline_details'],
            'importance'    => 'optional',
            'relevance'     => ['retail', 'distribution', 'service', 'hybrid'],
            'applicability' => 'when_has_sales_process',
            'prerequisites' => [],
            'fallback_hint' => 'sales stages and deal tracking',
        ],
        'commissions' => [
            'label'         => 'Commissions & Incentives',
            'fact_keys'     => ['uses_commissions', 'commission_model', 'commission_approval_required'],
            'importance'    => 'optional',
            'relevance'     => ['retail', 'distribution', 'service', 'hybrid'],
            'applicability' => 'when_has_sales_staff',
            'prerequisites' => ['employee_count'],
            'fallback_hint' => 'commission structure and incentive rules',
        ],
    ];

    /**
     * Minimum required categories for a blueprint to be safely generated.
     * At least one fact must exist in each of these categories.
     */
    public const MINIMUM_REQUIRED = [
        'business_identity',
        'scale',
        'products_services',
    ];

    /**
     * Get all valid fact keys across all categories.
     */
    public static function allFactKeys(): array
    {
        $keys = [];
        foreach (self::CATEGORIES as $cat) {
            $keys = array_merge($keys, $cat['fact_keys']);
        }
        return array_unique($keys);
    }

    /**
     * Get categories relevant to a specific business type.
     * Returns categories filtered by relevance, sorted by importance.
     */
    public static function relevantCategories(?string $businessType): array
    {
        $importanceOrder = ['critical' => 0, 'important' => 1, 'optional' => 2];
        $result = [];
        foreach (self::CATEGORIES as $key => $cat) {
            if (in_array('*', $cat['relevance']) || ($businessType && in_array($businessType, $cat['relevance']))) {
                $result[$key] = $cat;
            }
        }

        // Sort by importance (critical first)
        uasort($result, fn($a, $b) =>
            ($importanceOrder[$a['importance']] ?? 3) <=> ($importanceOrder[$b['importance']] ?? 3)
        );
        return $result;
    }

    /**
     * Get categories that are applicable given the current known facts.
     * Filters out categories whose prerequisites are not met or whose
     * applicability conditions indicate irrelevance.
     */
    public static function applicableCategories(?string $businessType, array $knownFacts): array
    {
        $relevant = self::relevantCategories($businessType);
        $applicable = [];

        $employeeCount = $knownFacts['employee_count'] ?? null;

        foreach ($relevant as $key => $cat) {
            $condition = $cat['applicability'] ?? 'always';

            switch ($condition) {
                case 'always':
                    $applicable[$key] = $cat;
                    break;
                case 'when_sells_products_or_services':
                    if (($knownFacts['sells_products'] ?? false) || ($knownFacts['sells_services'] ?? false) || empty($knownFacts)) {
                        $applicable[$key] = $cat;
                    }
                    break;
                case 'when_has_physical_goods':
                    if (($knownFacts['sells_products'] ?? false) || ($knownFacts['uses_inventory'] ?? false) || empty($knownFacts)) {
                        $applicable[$key] = $cat;
                    }
                    break;
                case 'when_manufactures':
                    if (($knownFacts['uses_manufacturing'] ?? false)) {
                        $applicable[$key] = $cat;
                    }
                    break;
                case 'when_delivers':
                    if (($knownFacts['uses_delivery'] ?? false) || empty($knownFacts)) {
                        $applicable[$key] = $cat;
                    }
                    break;
                case 'when_has_employees':
                    if ($employeeCount === null || $employeeCount > 1) {
                        $applicable[$key] = $cat;
                    }
                    break;
                case 'when_medium_or_larger':
                    if ($employeeCount === null || $employeeCount >= 5) {
                        $applicable[$key] = $cat;
                    }
                    break;
                case 'when_has_sales_process':
                    if (($knownFacts['sells_products'] ?? false) || ($knownFacts['sells_services'] ?? false) || empty($knownFacts)) {
                        $applicable[$key] = $cat;
                    }
                    break;
                case 'when_has_sales_staff':
                    if ($employeeCount === null || $employeeCount >= 2) {
                        $applicable[$key] = $cat;
                    }
                    break;
                default:
                    $applicable[$key] = $cat;
                    break;
            }
        }

        return $applicable;
    }

    /**
     * Determine which categories have at least one known fact.
     */
    public static function coveredCategories(array $knownFacts): array
    {
        $covered = [];
        foreach (self::CATEGORIES as $key => $cat) {
            foreach ($cat['fact_keys'] as $factKey) {
                if (isset($knownFacts[$factKey]) && $knownFacts[$factKey] !== null) {
                    $covered[] = $key;
                    break;
                }
            }
        }
        return $covered;
    }

    /**
     * Get the highest-importance applicable category that has no known facts
     * and has not been asked already.
     *
     * Used ONLY as deterministic fallback when AI is unavailable.
     * Returns the category metadata (without question text).
     */
    public static function nextMissingCategory(?string $businessType, array $knownFacts, array $askedCategories): ?array
    {
        $applicable = self::applicableCategories($businessType, $knownFacts);
        $covered = self::coveredCategories($knownFacts);

        foreach ($applicable as $key => $cat) {
            if (in_array($key, $covered)) continue;
            if (in_array($key, $askedCategories)) continue;
            return array_merge($cat, ['key' => $key]);
        }

        return null;
    }

    /**
     * Check if minimum required information exists.
     */
    public static function meetsMinimumRequirements(array $knownFacts): bool
    {
        $covered = self::coveredCategories($knownFacts);
        foreach (self::MINIMUM_REQUIRED as $required) {
            if (!in_array($required, $covered)) {
                return false;
            }
        }
        return true;
    }

    /**
     * Calculate completeness percentage based on applicable covered categories.
     */
    public static function calculateCompleteness(?string $businessType, array $knownFacts): int
    {
        $applicable = self::applicableCategories($businessType, $knownFacts);
        $covered  = self::coveredCategories($knownFacts);

        if (empty($applicable)) return 0;

        $applicableKeys = array_keys($applicable);
        $coveredApplicable = array_intersect($covered, $applicableKeys);

        return (int) round((count($coveredApplicable) / count($applicableKeys)) * 100);
    }

    /**
     * Build a concise coverage summary for inclusion in AI prompts.
     * Describes what information categories are covered vs missing,
     * filtered by applicability to the current business context.
     */
    public static function coverageSummary(?string $businessType, array $knownFacts): array
    {
        $applicable = self::applicableCategories($businessType, $knownFacts);
        $covered = self::coveredCategories($knownFacts);

        $summary = ['covered' => [], 'missing' => []];
        foreach ($applicable as $key => $cat) {
            $entry = [
                'key'        => $key,
                'label'      => $cat['label'],
                'importance' => $cat['importance'],
            ];
            if (in_array($key, $covered)) {
                $summary['covered'][] = $entry;
            } else {
                $entry['hint'] = $cat['fallback_hint'] ?? $cat['label'];
                $summary['missing'][] = $entry;
            }
        }
        return $summary;
    }
}
