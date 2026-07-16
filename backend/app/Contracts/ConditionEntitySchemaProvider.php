<?php

namespace App\Contracts;

/**
 * ConditionEntitySchemaProvider — Interface for entity-specific field metadata providers.
 *
 * Each entity that supports approval workflow trigger conditions must implement
 * this interface. The catalog registry discovers and invokes these providers
 * to build the field schema for the condition builder.
 *
 * Providers are stateless, workspace-agnostic, and must NOT query the database.
 * They return canonical metadata about which fields exist, their data types,
 * supported operators, and localized labels.
 *
 * Design principles:
 *  - Zero business-type logic (no "car sales" or "real estate" knowledge)
 *  - Zero workspace-specific data (no DB queries)
 *  - Fields declared here MUST match the keys passed to ApprovalTriggerEvaluator
 *    at runtime (see CommissionEntryController::autoSubmitApprovalIfRequired)
 *  - Operators declared per-field MUST be a subset of TriggerConditionValidator::SUPPORTED_OPERATORS
 */
interface ConditionEntitySchemaProvider
{
    /**
     * The entity type key that this provider handles.
     *
     * Must match the entity_type value stored in approval_workflows.entity_type.
     * Example: 'commission_entry'
     */
    public function entityType(): string;

    /**
     * English display label for this entity type.
     *
     * Used by the entity-types discovery endpoint and the condition builder UI.
     * Must NOT be derived from the entity key — each provider declares its own label.
     * Example: 'Commission entry'
     */
    public function labelEn(): string;

    /**
     * Arabic display label for this entity type.
     *
     * Example: 'سجل عمولة'
     */
    public function labelAr(): string;

    /**
     * The module key that identifies this provider's feature module.
     *
     * Used by the entity-types endpoint to include module_key in the response,
     * and by the catalog for enablement filtering.
     * Example: 'commissions'
     */
    public function moduleKey(): ?string;

    /**
     * The feature flag key required for this entity type to be available.
     *
     * Used by the catalog to filter out entity types whose module is not
     * enabled for the workspace. Return null if the entity is always available.
     *
     * Must correspond to a key recognized by FeatureFlagService.
     * Example: 'module.commissions' (future), currently checked via enabled_modules.
     */
    public function requiredModule(): ?string;

    /**
     * Return the field schema for this entity type.
     *
     * Each element in the returned array describes a single field:
     *
     *  [
     *      'key'        => 'amount',                          // The field key used in trigger_conditions JSON
     *      'type'       => 'number',                          // Data type: 'number', 'string', 'enum'
     *      'label_en'   => 'Commission Amount',               // English display label
     *      'label_ar'   => 'مبلغ العمولة',                    // Arabic display label
     *      'operators'  => ['equals', 'greater_than', ...],   // Allowed operators (subset of TriggerConditionValidator::SUPPORTED_OPERATORS)
     *      'options'    => null,                               // For 'enum' type: array of allowed values; null otherwise
     *  ]
     *
     * @return array<int, array{
     *     key: string,
     *     type: string,
     *     label_en: string,
     *     label_ar: string,
     *     operators: string[],
     *     options: array<int, array{value: string, label_en: string, label_ar: string}>|null,
     * }>
     */
    public function fields(): array;
}
