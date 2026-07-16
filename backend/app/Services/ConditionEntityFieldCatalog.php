<?php

namespace App\Services;

use App\Contracts\ConditionEntitySchemaProvider;

/**
 * ConditionEntityFieldCatalog — Registry of entity field schemas for approval trigger conditions.
 *
 * Central registry that aggregates all ConditionEntitySchemaProvider implementations
 * and resolves field schemas for a given entity type. The catalog handles:
 *
 *  - Provider registration (additive, extensible)
 *  - Module-enablement filtering (workspace-scoped via enabled_modules)
 *  - Operator whitelist enforcement (all field operators must be valid)
 *  - Entity type resolution for the condition builder UI
 *
 * Design:
 *  - Stateless after construction (no mutable state between requests)
 *  - Does NOT query the database directly — delegates module checks to callers
 *    or accepts a workspace-scoped enabled_modules list for filtering
 *  - New entity types are added by implementing ConditionEntitySchemaProvider
 *    and registering in the service provider
 *
 * The operator whitelist is sourced from TriggerConditionValidator::SUPPORTED_OPERATORS
 * to ensure catalog parity with the validation layer.
 */
class ConditionEntityFieldCatalog
{
    /**
     * Registered providers, keyed by entity type.
     *
     * @var array<string, ConditionEntitySchemaProvider>
     */
    private array $providers = [];

    /**
     * Register a schema provider for an entity type.
     *
     * If a provider for the same entity type is already registered,
     * the new one silently replaces it (last-writer-wins).
     */
    public function register(ConditionEntitySchemaProvider $provider): void
    {
        $this->providers[$provider->entityType()] = $provider;
    }



    /**
     * List all registered entity types with their metadata.
     *
     * Returns an array of entity type descriptors, optionally filtered
     * by workspace-level module enablement. Labels and module_key are
     * sourced directly from each provider — no centralized label map.
     *
     * @param array|null $enabledModules  If provided, only entity types whose
     *                                     requiredModule() is in this list (or null)
     *                                     are included. Pass null to skip filtering.
     * @return array<int, array{entity_type: string, label_en: string, label_ar: string, module_key: string|null}>
     */
    public function listEntityTypes(?array $enabledModules = null): array
    {
        $result = [];

        foreach ($this->providers as $type => $provider) {
            if ($enabledModules !== null && ! $this->isModuleEnabled($provider, $enabledModules)) {
                continue;
            }

            $result[] = [
                'entity_type' => $type,
                'label_en'    => $provider->labelEn(),
                'label_ar'    => $provider->labelAr(),
                'module_key'  => $provider->moduleKey(),
            ];
        }

        return $result;
    }

    /**
     * Resolve the full field schema for a given entity type.
     *
     * Returns the complete schema including entity metadata and all fields,
     * or null if the entity type is not registered or its module is disabled.
     * Labels and module_key are sourced from the provider.
     *
     * @param string     $entityType
     * @param array|null $enabledModules  Workspace-level enabled modules for filtering
     * @return array|null  The schema array, or null if not found/disabled
     */
    public function resolve(string $entityType, ?array $enabledModules = null): ?array
    {
        $provider = $this->providers[$entityType] ?? null;

        if (! $provider) {
            return null;
        }

        if ($enabledModules !== null && ! $this->isModuleEnabled($provider, $enabledModules)) {
            return null;
        }

        return [
            'entity_type' => $entityType,
            'label_en'    => $provider->labelEn(),
            'label_ar'    => $provider->labelAr(),
            'module_key'  => $provider->moduleKey(),
            'fields'      => $provider->fields(),
        ];
    }

    /**
     * Get the raw provider for an entity type (used by parity tests).
     */
    public function provider(string $entityType): ?ConditionEntitySchemaProvider
    {
        return $this->providers[$entityType] ?? null;
    }

    /**
     * Get all registered entity type keys (unfiltered).
     *
     * @return string[]
     */
    public function registeredEntityTypes(): array
    {
        return array_keys($this->providers);
    }

    /**
     * Check if a provider's required module is enabled.
     */
    private function isModuleEnabled(ConditionEntitySchemaProvider $provider, array $enabledModules): bool
    {
        $required = $provider->requiredModule();

        // No module requirement → always enabled
        if ($required === null) {
            return true;
        }

        return in_array($required, $enabledModules, true);
    }
}
