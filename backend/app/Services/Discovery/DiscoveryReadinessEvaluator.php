<?php

namespace App\Services\Discovery;

/**
 * Centralized deterministic readiness evaluator for discovery sessions.
 *
 * Decides whether enough information has been gathered to generate a
 * reliable ERP blueprint, using business-type-aware requirement profiles,
 * fact depth validation, and contradiction detection.
 *
 * This class is the single authority on readiness — the LLM's opinion
 * is treated as a suggestion that must pass these deterministic checks.
 */
class DiscoveryReadinessEvaluator
{
    // ═══════════════════════════════════════════════════════════════
    //  Business-type-aware readiness profiles
    // ═══════════════════════════════════════════════════════════════

    /**
     * Required information groups per business type.
     * 'critical' groups block readiness if not covered.
     * 'important' groups lower completeness but don't block.
     */
    private const READINESS_PROFILES = [
        'retail' => [
            'critical' => ['business_identity', 'scale', 'products_services', 'sales_channels', 'finance', 'geography'],
            'important' => ['customers', 'inventory', 'team_structure'],
        ],
        'restaurant' => [
            'critical' => ['business_identity', 'scale', 'products_services', 'sales_channels', 'finance', 'geography'],
            'important' => ['customers', 'inventory', 'team_structure'],
        ],
        'service' => [
            'critical' => ['business_identity', 'scale', 'products_services', 'customers', 'finance', 'geography', 'team_structure'],
            'important' => ['approvals'],
        ],
        'manufacturing' => [
            'critical' => ['business_identity', 'scale', 'products_services', 'production', 'inventory', 'suppliers', 'finance', 'geography'],
            'important' => ['sales_channels', 'team_structure', 'delivery'],
        ],
        'distribution' => [
            'critical' => ['business_identity', 'scale', 'products_services', 'sales_channels', 'inventory', 'suppliers', 'finance', 'geography'],
            'important' => ['customers', 'delivery', 'team_structure'],
        ],
        'hybrid' => [
            'critical' => ['business_identity', 'scale', 'products_services', 'sales_channels', 'finance', 'geography'],
            'important' => ['customers', 'inventory', 'team_structure'],
        ],
    ];

    /**
     * Default profile when business type is unknown or null.
     */
    private const DEFAULT_PROFILE = [
        'critical' => ['business_identity', 'scale', 'products_services', 'finance', 'geography'],
        'important' => ['customers', 'team_structure'],
    ];

    /**
     * Correction indicator patterns (case-insensitive).
     */
    private const CORRECTION_PATTERNS = [
        'correction',
        'actually',
        'i meant',
        'change that',
        'sorry, it is',
        'sorry it is',
        'not \d+, it',
        'no, we have',
        'no we have',
        'i made a mistake',
        'let me correct',
        'update that',
        'wrong, it',
    ];

    // ═══════════════════════════════════════════════════════════════
    //  Main evaluation
    // ═══════════════════════════════════════════════════════════════

    /**
     * Evaluate readiness for blueprint generation.
     *
     * @param array       $knownFacts       Current extracted facts
     * @param ?string     $businessType     Inferred business type hint
     * @param array       $contradictions   Current contradictions list
     * @param array       $assumptions      Current assumptions list
     * @return array  Structured readiness evaluation
     */
    public function evaluate(
        array   $knownFacts,
        ?string $businessType,
        array   $contradictions = [],
        array   $assumptions = [],
    ): array {
        $profile = $this->getProfile($businessType);

        // ── Context-dependent critical promotion ─────────────────
        // Promote 'important' categories to 'critical' when the business
        // context makes them essential for a useful blueprint.
        $critical = $profile['critical'];
        $important = $profile['important'];
        $promoted = $this->adjustContextualImportance($knownFacts, $critical, $important);
        $critical = $promoted['critical'];
        $important = $promoted['important'];

        // Calculate group coverage
        $criticalMissing = [];
        $importantMissing = [];
        $optionalMissing = [];

        $criticalTotal = count($critical);
        $criticalCovered = 0;
        foreach ($critical as $group) {
            if ($this->isGroupMeaningfullyCovered($group, $knownFacts)) {
                $criticalCovered++;
            } else {
                $criticalMissing[] = $group;
            }
        }

        $importantTotal = count($important);
        $importantCovered = 0;
        foreach ($important as $group) {
            if ($this->isGroupMeaningfullyCovered($group, $knownFacts)) {
                $importantCovered++;
            } else {
                $importantMissing[] = $group;
            }
        }

        // Optional = all relevant categories not in critical or important
        $allRelevant = array_keys(DiscoveryInformationCatalog::relevantCategories($businessType));
        $profileGroups = array_merge($critical, $important);
        foreach ($allRelevant as $cat) {
            if (!in_array($cat, $profileGroups)) {
                if (!$this->isGroupMeaningfullyCovered($cat, $knownFacts)) {
                    $optionalMissing[] = $cat;
                }
            }
        }

        // Blocking contradictions
        $blockingContradictions = array_filter($contradictions, fn($c) => ($c['status'] ?? '') === 'needs_clarification');

        // Calculate completeness percentages
        $requiredCompleteness = $criticalTotal > 0
            ? (int) round(($criticalCovered / $criticalTotal) * 100)
            : 100;

        $totalGroups = $criticalTotal + $importantTotal + count($optionalMissing);
        $totalCovered = $criticalCovered + $importantCovered + (count($allRelevant) - count($profileGroups) - count($optionalMissing));
        $overallCompleteness = $totalGroups > 0
            ? (int) round(($totalCovered / max(1, $criticalTotal + $importantTotal + count($allRelevant) - count($profileGroups))) * 100)
            : 100;
        $overallCompleteness = max(0, min(100, $overallCompleteness));

        // Readiness decision: ALL critical groups must be covered
        $readyForBlueprint = empty($criticalMissing)
            && empty($blockingContradictions)
            && $requiredCompleteness >= 80;

        return [
            'overall_completeness'     => $overallCompleteness,
            'required_completeness'    => $requiredCompleteness,
            'optional_completeness'    => 0, // reserved
            'critical_missing'         => $criticalMissing,
            'important_missing'        => $importantMissing,
            'optional_missing'         => $optionalMissing,
            'blocking_contradictions'  => array_values($blockingContradictions),
            'ready_for_blueprint'      => $readyForBlueprint,
        ];
    }

    /**
     * Adjust category importance based on known facts context.
     *
     * Promotes 'important' categories to 'critical' when the business
     * context makes them essential (e.g., team_structure for multi-person businesses).
     *
     * Demotes 'critical' categories to 'important' when the business
     * context makes them unnecessary (e.g., team_structure for solo businesses).
     */
    private function adjustContextualImportance(array $knownFacts, array $critical, array $important): array
    {
        $employeeCount = $knownFacts['employee_count'] ?? null;

        // ── Demotions: solo businesses ──────────────────────────
        // team_structure is unnecessary for single-person businesses
        if (in_array('team_structure', $critical) && $employeeCount !== null && $employeeCount <= 1) {
            $critical = array_values(array_diff($critical, ['team_structure']));
            // Don't even add to important — it's irrelevant for solo
        }

        // ── Promotions: multi-person businesses ─────────────────
        // team_structure is critical for multi-person businesses
        if (in_array('team_structure', $important) && $employeeCount !== null && $employeeCount > 1) {
            $critical[] = 'team_structure';
            $important = array_values(array_diff($important, ['team_structure']));
        }

        // inventory is critical when the business explicitly uses inventory/warehouses
        if (in_array('inventory', $important) && (
            ($knownFacts['uses_inventory'] ?? false) ||
            ($knownFacts['warehouse_count'] ?? 0) > 0 ||
            !empty($knownFacts['warehouse_details'])
        )) {
            $critical[] = 'inventory';
            $important = array_values(array_diff($important, ['inventory']));
        }

        // customers is critical for service businesses (already in static profile, but enforce for dynamic)
        if (in_array('customers', $important) && (
            ($knownFacts['sells_services'] ?? false) &&
            !($knownFacts['sells_products'] ?? false)
        )) {
            $critical[] = 'customers';
            $important = array_values(array_diff($important, ['customers']));
        }

        // approvals is critical when explicitly stated as needed
        if (in_array('approvals', $important) && ($knownFacts['needs_approvals'] ?? false)) {
            $critical[] = 'approvals';
            $important = array_values(array_diff($important, ['approvals']));
        }

        return ['critical' => $critical, 'important' => $important];
    }

    // ═══════════════════════════════════════════════════════════════
    //  Fact depth validation
    // ═══════════════════════════════════════════════════════════════

    /**
     * Check whether a category group has meaningful fact coverage.
     * A group is covered only when at least one fact key contains
     * a substantive (non-empty, non-generic) value.
     */
    public function isGroupMeaningfullyCovered(string $groupKey, array $knownFacts): bool
    {
        $cat = DiscoveryInformationCatalog::CATEGORIES[$groupKey] ?? null;
        if (!$cat) return false;

        foreach ($cat['fact_keys'] as $factKey) {
            if ($this->hasMeaningfulFact($factKey, $knownFacts)) {
                return true;
            }
        }

        return false;
    }

    /**
     * Check whether a single fact key has a meaningful value.
     *
     * Rules:
     *  - null / missing = not covered
     *  - empty string, empty array = not covered
     *  - "unknown", "none", "n/a" as sole value = not covered
     *  - boolean false = covered (it's a confirmed negative)
     *  - 0 for counts = covered (confirmed zero)
     *  - generic strings < 4 chars = not covered (e.g. "yes", "no" for descriptive fields)
     */
    public function hasMeaningfulFact(string $key, array $knownFacts): bool
    {
        if (!array_key_exists($key, $knownFacts)) {
            return false;
        }

        $value = $knownFacts[$key];

        // null is never meaningful
        if ($value === null) {
            return false;
        }

        // Boolean values are always meaningful (true = yes, false = confirmed no)
        if (is_bool($value)) {
            return true;
        }

        // Numeric values are meaningful (including 0)
        if (is_int($value) || is_float($value)) {
            return true;
        }

        // Empty arrays are not meaningful
        if (is_array($value)) {
            return !empty($value);
        }

        // String checks
        if (is_string($value)) {
            $normalized = strtolower(trim($value));

            // Empty or whitespace-only
            if ($normalized === '') {
                return false;
            }

            // Generic non-answers
            $genericValues = ['unknown', 'none', 'n/a', 'na', 'tbd', 'not sure', 'normal', 'normally', 'the usual', 'usual'];
            if (in_array($normalized, $genericValues)) {
                return false;
            }

            // For descriptive fields, require minimum substance
            $descriptiveKeys = ['business_description', 'product_types', 'production_type', 'delivery_model', 'purchase_process', 'commission_model'];
            if (in_array($key, $descriptiveKeys) && strlen($normalized) < 4) {
                return false;
            }

            return true;
        }

        return false;
    }

    /**
     * Calculate per-group coverage detail.
     */
    public function categoryCoverage(string $groupKey, array $knownFacts): array
    {
        $cat = DiscoveryInformationCatalog::CATEGORIES[$groupKey] ?? null;
        if (!$cat) return ['total' => 0, 'covered' => 0, 'keys' => []];

        $covered = [];
        foreach ($cat['fact_keys'] as $factKey) {
            if ($this->hasMeaningfulFact($factKey, $knownFacts)) {
                $covered[] = $factKey;
            }
        }

        return [
            'total'   => count($cat['fact_keys']),
            'covered' => count($covered),
            'keys'    => $covered,
        ];
    }

    // ═══════════════════════════════════════════════════════════════
    //  Contradiction detection
    // ═══════════════════════════════════════════════════════════════

    /**
     * Detect contradictions between existing facts and newly extracted facts.
     *
     * @param array  $existingFacts     Previously confirmed facts
     * @param array  $newFacts          Newly extracted facts from latest message
     * @param string $latestUserText    The user's latest message text
     * @param array  $existingContradictions  Already tracked contradictions
     * @return array Updated contradictions list
     */
    public function detectContradictions(
        array  $existingFacts,
        array  $newFacts,
        string $latestUserText,
        array  $existingContradictions = [],
    ): array {
        $contradictions = $existingContradictions;
        $isExplicitCorrection = $this->isExplicitCorrection($latestUserText);

        // Keys to compare: numeric and specific string values that can conflict
        $comparableKeys = [
            'employee_count', 'branch_count', 'warehouse_count', 'department_count',
            'country', 'currency', 'timezone', 'primary_language',
            'business_name', 'company_size',
        ];

        foreach ($newFacts as $key => $newValue) {
            if (!in_array($key, $comparableKeys)) continue;
            if (!array_key_exists($key, $existingFacts)) continue;
            if ($newValue === null) continue;

            $oldValue = $existingFacts[$key];
            if ($oldValue === null) continue;

            // Values differ
            if ($this->valuesConflict($oldValue, $newValue)) {
                if ($isExplicitCorrection) {
                    // Auto-resolve: remove any existing contradiction for this field
                    $contradictions = array_values(array_filter(
                        $contradictions,
                        fn($c) => ($c['field'] ?? '') !== $key
                    ));
                } else {
                    // Check if this contradiction already exists
                    $existingIdx = null;
                    foreach ($contradictions as $idx => $c) {
                        if (($c['field'] ?? '') === $key) {
                            $existingIdx = $idx;
                            break;
                        }
                    }

                    if ($existingIdx === null) {
                        $contradictions[] = [
                            'field'          => $key,
                            'existing_value' => $oldValue,
                            'new_value'      => $newValue,
                            'status'         => 'needs_clarification',
                        ];
                    }
                }
            }
        }

        return $contradictions;
    }

    /**
     * Resolve a contradiction when the user confirms the correct value.
     */
    public function resolveContradiction(array $contradictions, string $field, mixed $confirmedValue): array
    {
        return array_values(array_filter(
            $contradictions,
            fn($c) => ($c['field'] ?? '') !== $field
        ));
    }

    /**
     * Check if the latest user message contains explicit correction language.
     */
    public function isExplicitCorrection(string $text): bool
    {
        $lower = strtolower($text);
        foreach (self::CORRECTION_PATTERNS as $pattern) {
            if (str_contains($pattern, '\\d')) {
                // Regex pattern
                if (preg_match('/' . $pattern . '/i', $lower)) {
                    return true;
                }
            } else {
                if (str_contains($lower, $pattern)) {
                    return true;
                }
            }
        }
        return false;
    }

    /**
     * Check if two values conflict (not just different formatting).
     */
    private function valuesConflict(mixed $old, mixed $new): bool
    {
        // Same value = no conflict
        if ($old === $new) return false;

        // Numeric comparison
        if (is_numeric($old) && is_numeric($new)) {
            return (float) $old !== (float) $new;
        }

        // String comparison (case-insensitive, trimmed)
        if (is_string($old) && is_string($new)) {
            return strtolower(trim($old)) !== strtolower(trim($new));
        }

        return $old != $new;
    }

    // ═══════════════════════════════════════════════════════════════
    //  Question priority for completion gaps
    // ═══════════════════════════════════════════════════════════════

    /**
     * Get the next best question to ask based on readiness gaps.
     * Prioritizes critical_missing > important_missing > optional_missing.
     * Uses applicable categories (not raw catalog order) and fallback hints.
     *
     * @param array  $evaluation       Result from evaluate()
     * @param array  $askedCategories  Categories already asked
     * @param array  $knownFacts       Current known facts
     * @param string $locale           User's locale ('ar'|'en')
     * @return ?array  Next question {category, question} or null
     */
    public function nextQuestionForGaps(
        array  $evaluation,
        array  $askedCategories,
        array  $knownFacts,
        string $locale = 'ar',
    ): ?array {
        // Get applicable categories based on business context
        $businessType = $knownFacts['business_type_hint'] ?? null;
        $applicable = DiscoveryInformationCatalog::applicableCategories($businessType, $knownFacts);
        $applicableKeys = array_keys($applicable);

        // Priority: critical → important → optional, filtered by applicability
        $orderedMissing = array_merge(
            $evaluation['critical_missing'] ?? [],
            $evaluation['important_missing'] ?? [],
            $evaluation['optional_missing'] ?? [],
        );

        foreach ($orderedMissing as $catKey) {
            // Only ask about applicable categories
            if (!in_array($catKey, $applicableKeys)) continue;

            // Skip if already asked AND the group has some coverage
            if (in_array($catKey, $askedCategories) && $this->isGroupMeaningfullyCovered($catKey, $knownFacts)) {
                continue;
            }

            $cat = DiscoveryInformationCatalog::CATEGORIES[$catKey] ?? null;
            if (!$cat) continue;

            $question = $this->buildFallbackQuestion($catKey, $cat, $locale);

            return [
                'category' => $catKey,
                'question' => $question,
            ];
        }

        return null;
    }

    /**
     * Generate a clarification question for a contradiction.
     */
    public function contradictionQuestion(array $contradiction): array
    {
        $field = $contradiction['field'] ?? 'unknown';
        $old = $contradiction['existing_value'] ?? '?';
        $new = $contradiction['new_value'] ?? '?';

        // Human-readable field names
        $labels = [
            'employee_count' => 'number of employees',
            'branch_count'   => 'number of branches',
            'warehouse_count' => 'number of warehouses',
            'department_count' => 'number of departments',
            'country' => 'country',
            'currency' => 'currency',
            'business_name' => 'business name',
            'company_size' => 'company size',
        ];
        $label = $labels[$field] ?? $field;

        return [
            'category' => 'clarification',
            'question' => "You previously mentioned {$old} for the {$label}, but now mentioned {$new}. Which is correct?",
        ];
    }

    // ═══════════════════════════════════════════════════════════════
    //  Fallback question generation
    // ═══════════════════════════════════════════════════════════════

    /**
     * Build a professional localized fallback question for a category.
     * Used ONLY when the AI fails to provide a conversational question.
     */
    private function buildFallbackQuestion(string $catKey, array $cat, string $locale): string
    {
        // Professional questions per critical category
        $questions = [
            'team_structure' => [
                'ar' => 'كيف يتوزع فريق العمل لديكم؟ اذكر الأدوار الأساسية، مسؤوليات كل دور، وعدد الموظفين في كل دور.',
                'en' => 'How is your team structured? Please describe the main roles, each role\'s responsibilities, and the number of employees in each role.',
            ],
            'business_identity' => [
                'ar' => 'ما اسم شركتك وما هو النشاط الأساسي الذي تقوم به؟',
                'en' => 'What is your company name and what is your primary business activity?',
            ],
            'scale' => [
                'ar' => 'كم عدد الموظفين لديكم وهل لديكم أكثر من فرع أو موقع عمل؟',
                'en' => 'How many employees do you have, and do you operate from multiple locations?',
            ],
            'products_services' => [
                'ar' => 'ما المنتجات أو الخدمات التي تقدمونها؟',
                'en' => 'What products or services do you offer?',
            ],
            'finance' => [
                'ar' => 'ما طرق الدفع المستخدمة وهل تحتاجون إلى فواتير ومحاسبة؟',
                'en' => 'What payment methods do you use, and do you need invoicing and accounting?',
            ],
            'geography' => [
                'ar' => 'في أي دولة تعمل شركتكم وما العملة المستخدمة؟',
                'en' => 'Which country does your business operate in, and what currency do you use?',
            ],
            'inventory' => [
                'ar' => 'كيف تديرون المخزون حاليًا وهل لديكم مستودعات؟',
                'en' => 'How do you currently manage inventory, and do you have warehouses?',
            ],
            'sales_channels' => [
                'ar' => 'كيف يشتري العملاء منكم — من المتجر، أونلاين، بالجملة، أو بطريقة أخرى؟',
                'en' => 'How do customers buy from you — in-store, online, wholesale, or another way?',
            ],
            'customers' => [
                'ar' => 'ما أنواع العملاء الذين تتعاملون معهم؟',
                'en' => 'What types of customers do you serve?',
            ],
            'approvals' => [
                'ar' => 'هل لديكم إجراءات موافقة على عمليات معينة مثل الخصومات أو المشتريات الكبيرة؟',
                'en' => 'Do you have approval workflows for specific operations like discounts or large purchases?',
            ],
        ];

        if (isset($questions[$catKey][$locale])) {
            return $questions[$catKey][$locale];
        }

        // Generic fallback
        $hint = $cat['fallback_hint'] ?? $cat['label'];
        return $locale === 'ar'
            ? "أخبرني أكثر عن: {$hint}"
            : "Please tell me more about: {$hint}";
    }

    // ═══════════════════════════════════════════════════════════════
    //  Helpers
    // ═══════════════════════════════════════════════════════════════

    private function getProfile(?string $businessType): array
    {
        if ($businessType && isset(self::READINESS_PROFILES[$businessType])) {
            return self::READINESS_PROFILES[$businessType];
        }
        return self::DEFAULT_PROFILE;
    }
}
