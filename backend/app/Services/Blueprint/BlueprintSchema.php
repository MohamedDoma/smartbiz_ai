<?php

namespace App\Services\Blueprint;

/**
 * BlueprintSchema — Canonical ERP Blueprint contract (v1.0.0).
 *
 * Defines the versioned structure for generated ERP blueprints.
 * All blueprint generation, validation, and persistence must use this contract.
 *
 * Status values for items: required, recommended, optional, unsupported
 * Module keys must come from MODULE_KEYS.
 * Permission keys must come from PermissionCatalog::allKeys().
 */
class BlueprintSchema
{
    public const VERSION = '1.0.0';

    /** Valid item status values. */
    public const VALID_STATUSES = ['required', 'recommended', 'optional', 'unsupported'];

    /**
     * Canonical module keys — sourced from seeded business template modules.
     * Any module key not in this list is invalid.
     */
    public const MODULE_KEYS = [
        'ai',
        'commissions',
        'customers',
        'dashboard',
        'employees',
        'finance',
        'inventory',
        'invoices',
        'jobs',
        'leads',
        'menu',
        'orders',
        'parts_inventory',
        'payments',
        'pos',
        'products',
        'projects',
        'reports',
        'spare_parts',
        'tables',
        'tasks',
        'vehicle_sales',
        'vehicles',
    ];

    /**
     * Module dependencies: key => [required dependency keys].
     * If module X depends on Y, enabling X requires Y.
     */
    public const MODULE_DEPENDENCIES = [
        'invoices'        => ['customers'],
        'payments'        => ['invoices'],
        'orders'          => ['products', 'customers'],
        'pos'             => ['products', 'orders', 'payments'],
        'inventory'       => ['products'],
        'spare_parts'     => ['inventory'],
        'parts_inventory' => ['inventory'],
        'commissions'     => ['employees'],
        'leads'           => ['customers'],
        'vehicle_sales'   => ['products', 'customers'],
        'vehicles'        => ['products'],
        'menu'            => ['products'],
        'tables'          => ['orders'],
        'tasks'           => ['employees'],
        'jobs'            => ['customers'],
        'projects'        => ['customers'],
    ];

    /**
     * Valid pipeline entity types supported by the system.
     */
    public const PIPELINE_ENTITY_TYPES = [
        'deal',
        'lead',
        'order',
        'contact',
    ];

    /**
     * Valid approval workflow entity types (from ConditionEntityFieldCatalog + well-known).
     */
    public const APPROVAL_ENTITY_TYPES = [
        'commission_entry',
        'discount',
        'invoice',
        'order',
        'payment',
        'purchase_order',
    ];

    /**
     * Valid trigger fields for approval workflow conditions.
     */
    public const APPROVAL_TRIGGER_FIELDS = [
        'amount',
        'discount_percent',
        'total',
    ];

    /**
     * Valid operators for approval trigger conditions.
     */
    public const APPROVAL_TRIGGER_OPERATORS = [
        'greater_than',
        'greater_than_or_equal',
        'less_than',
        'less_than_or_equal',
        'equal',
    ];

    /**
     * Supported commission calculation models.
     */
    public const COMMISSION_MODELS = [
        'percentage',
        'flat',
        'tiered',
    ];

    /**
     * Supported payment method types.
     * Sourced from payments.payment_method DB check constraint.
     */
    public const VALID_PAYMENT_TYPES = [
        'cash',
        'card',
        'credit_card',
        'bank_transfer',
        'check',
        'mobile_payment',
        'online',
        'wallet',
    ];

    /**
     * Supported location types for the canonical locations section.
     */
    public const LOCATION_TYPES = [
        'branch',
        'office',
        'store',
        'restaurant',
        'warehouse_site',
        'service_location',
        'virtual',
    ];

    /**
     * Known currencies (subset for validation; accept any 3-letter uppercase code).
     */
    public const COMMON_CURRENCIES = [
        'SAR', 'AED', 'USD', 'EUR', 'GBP', 'EGP', 'KWD', 'QAR', 'BHD', 'OMR',
        'JOD', 'LBP', 'IQD', 'MAD', 'TND', 'DZD', 'LYD', 'SDG', 'TRY', 'PKR',
        'INR', 'BDT', 'MYR', 'SGD', 'IDR', 'PHP', 'THB', 'VND', 'CNY', 'JPY',
        'KRW', 'AUD', 'CAD', 'CHF', 'SEK', 'NOK', 'DKK', 'PLN', 'CZK', 'HUF',
        'BRL', 'MXN', 'ARS', 'CLP', 'COP', 'PEN', 'ZAR', 'NGN', 'KES', 'GHS',
    ];

    /**
     * Required top-level fields in every valid Blueprint.
     */
    public const REQUIRED_FIELDS = [
        'schema_version',
        'business_profile',
        'modules',
        'metadata',
    ];

    /**
     * All valid top-level section keys.
     */
    public const ALL_SECTIONS = [
        'schema_version',
        'business_profile',
        'workspace_settings',
        'modules',
        'departments',
        'teams',
        'roles',
        'warehouses',
        'locations',
        'payment_methods',
        'tax_settings',
        'invoice_settings',
        'pos_settings',
        'pipelines',
        'approval_workflows',
        'commission_rules',
        'accounting_settings',
        'localization',
        'ai_settings',
        'assumptions',
        'missing_optional_information',
        'metadata',
    ];

    /**
     * Build a default empty canonical Blueprint structure.
     */
    public static function empty(): array
    {
        return [
            'schema_version'              => self::VERSION,
            'business_profile'            => [],
            'workspace_settings'          => [],
            'modules'                     => [],
            'departments'                 => [],
            'teams'                       => [],
            'roles'                       => [],
            'warehouses'                  => [],
            'locations'                   => [],
            'payment_methods'             => [],
            'tax_settings'                => [],
            'invoice_settings'            => [],
            'pos_settings'                => [],
            'pipelines'                   => [],
            'approval_workflows'          => [],
            'commission_rules'            => [],
            'accounting_settings'         => [],
            'localization'                => [],
            'ai_settings'                 => [],
            'assumptions'                 => [],
            'missing_optional_information'=> [],
            'metadata'                    => [],
        ];
    }

    /**
     * Check if a module key is valid.
     */
    public static function isValidModuleKey(string $key): bool
    {
        return in_array($key, self::MODULE_KEYS, true);
    }

    /**
     * Check if a status value is valid.
     */
    public static function isValidStatus(string $status): bool
    {
        return in_array($status, self::VALID_STATUSES, true);
    }

    /**
     * Get the dependencies for a module key.
     * Returns an empty array if no dependencies exist.
     */
    public static function moduleDependencies(string $key): array
    {
        return self::MODULE_DEPENDENCIES[$key] ?? [];
    }

    /**
     * Detect whether a blueprint uses the legacy (pre-1.0.0) format.
     *
     * Legacy blueprints have 'enabled_modules' at top level and no 'schema_version'.
     */
    public static function isLegacyFormat(array $blueprint): bool
    {
        return !isset($blueprint['schema_version']) && isset($blueprint['enabled_modules']);
    }

    /**
     * Validate a Blueprint-local reference key.
     *
     * Local keys must be readable identifiers: ^[a-z][a-z0-9_]{1,63}$
     * UUID-shaped and numeric-only values are rejected.
     *
     * This must NOT be applied to permission keys (which use dots)
     * or module keys (validated separately via MODULE_KEYS).
     */
    public static function isValidLocalKey(string $key): bool
    {
        // Reject UUID-shaped values
        if (self::isUuidShaped($key)) {
            return false;
        }
        // Must match safe local key format
        return (bool) preg_match('/^[a-z][a-z0-9_]{1,63}$/', $key);
    }

    /**
     * Detect UUID-shaped strings (8-4-4-4-12 hex or 32 hex chars).
     */
    public static function isUuidShaped(string $value): bool
    {
        return (bool) preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i', $value)
            || (bool) preg_match('/^[0-9a-f]{32}$/i', $value);
    }
}
