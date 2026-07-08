<?php

namespace App\Services;

/**
 * Returns the catalog of supported report data sources, columns, and filters.
 * This catalog is the whitelist — only items listed here are allowed in reports.
 */
class ReportCatalogService
{
    /**
     * Get all supported data sources with their columns and filters.
     */
    public function getCatalog(): array
    {
        return [
            'contacts'              => $this->contacts(),
            'pipeline_records'      => $this->pipelineRecords(),
            'commission_entries'    => $this->commissionEntries(),
            'products'              => $this->products(),
            'invoices'              => $this->invoices(),
            'payments'              => $this->payments(),
            'ownership_assignments' => $this->ownershipAssignments(),
            'duplicate_matches'     => $this->duplicateMatches(),
        ];
    }

    /**
     * Get a single data source definition or null.
     */
    public function getDataSource(string $key): ?array
    {
        return $this->getCatalog()[$key] ?? null;
    }

    /**
     * Get allowed column keys for a data source.
     */
    public function allowedColumns(string $dataSource): array
    {
        $ds = $this->getDataSource($dataSource);
        return $ds ? array_column($ds['columns'], 'key') : [];
    }

    /**
     * Get allowed filter keys for a data source.
     */
    public function allowedFilters(string $dataSource): array
    {
        $ds = $this->getDataSource($dataSource);
        return $ds ? array_column($ds['filters'], 'key') : [];
    }

    // ── Data Source Definitions ──────────────────────────

    private function contacts(): array
    {
        return [
            'key'          => 'contacts',
            'display_name' => 'جهات الاتصال',
            'table'        => 'contacts',
            'columns'      => [
                ['key' => 'name',       'label' => 'الاسم',           'type' => 'text'],
                ['key' => 'type',       'label' => 'النوع',           'type' => 'status'],
                ['key' => 'phone',      'label' => 'الهاتف',          'type' => 'text'],
                ['key' => 'email',      'label' => 'البريد',          'type' => 'text'],
                ['key' => 'address',    'label' => 'العنوان',         'type' => 'text'],
                ['key' => 'tax_number', 'label' => 'الرقم الضريبي',   'type' => 'text'],
                ['key' => 'balance',    'label' => 'الرصيد',          'type' => 'money'],
                ['key' => 'created_at', 'label' => 'تاريخ الإنشاء',   'type' => 'datetime'],
            ],
            'filters'      => [
                ['key' => 'type',       'label' => 'النوع',           'type' => 'status',   'operators' => ['equals', 'not_equals']],
                ['key' => 'name',       'label' => 'الاسم',           'type' => 'text',     'operators' => ['equals', 'contains']],
                ['key' => 'created_at', 'label' => 'تاريخ الإنشاء',   'type' => 'datetime', 'operators' => ['date_from', 'date_to', 'between']],
            ],
        ];
    }

    private function pipelineRecords(): array
    {
        return [
            'key'          => 'pipeline_records',
            'display_name' => 'سجلات خط الأنابيب',
            'table'        => 'pipeline_records',
            'columns'      => [
                ['key' => 'title',               'label' => 'العنوان',          'type' => 'text'],
                ['key' => 'status',              'label' => 'الحالة',           'type' => 'status'],
                ['key' => 'value_amount',        'label' => 'القيمة',           'type' => 'money'],
                ['key' => 'currency',            'label' => 'العملة',           'type' => 'text'],
                ['key' => 'expected_close_date', 'label' => 'تاريخ الإغلاق المتوقع', 'type' => 'date'],
                ['key' => 'closed_at',           'label' => 'تاريخ الإغلاق',    'type' => 'datetime'],
                ['key' => 'description',         'label' => 'الوصف',            'type' => 'text'],
                ['key' => 'created_at',          'label' => 'تاريخ الإنشاء',    'type' => 'datetime'],
            ],
            'filters'      => [
                ['key' => 'status',       'label' => 'الحالة',           'type' => 'status',   'operators' => ['equals', 'not_equals']],
                ['key' => 'value_amount', 'label' => 'القيمة',           'type' => 'number',   'operators' => ['equals', 'greater_than', 'less_than', 'between']],
                ['key' => 'currency',     'label' => 'العملة',           'type' => 'text',     'operators' => ['equals']],
                ['key' => 'closed_at',    'label' => 'تاريخ الإغلاق',    'type' => 'datetime', 'operators' => ['date_from', 'date_to', 'between']],
                ['key' => 'created_at',   'label' => 'تاريخ الإنشاء',    'type' => 'datetime', 'operators' => ['date_from', 'date_to', 'between']],
            ],
        ];
    }

    private function commissionEntries(): array
    {
        return [
            'key'          => 'commission_entries',
            'display_name' => 'العمولات',
            'table'        => 'commission_entries',
            'columns'      => [
                ['key' => 'base_amount',       'label' => 'المبلغ الأساسي',   'type' => 'money'],
                ['key' => 'commission_amount', 'label' => 'مبلغ العمولة',     'type' => 'money'],
                ['key' => 'currency',          'label' => 'العملة',           'type' => 'text'],
                ['key' => 'calculation_type',  'label' => 'نوع الحساب',       'type' => 'status'],
                ['key' => 'percentage_rate',   'label' => 'نسبة العمولة',     'type' => 'number'],
                ['key' => 'status',            'label' => 'الحالة',           'type' => 'status'],
                ['key' => 'calculated_at',     'label' => 'تاريخ الحساب',     'type' => 'datetime'],
                ['key' => 'created_at',        'label' => 'تاريخ الإنشاء',    'type' => 'datetime'],
            ],
            'filters'      => [
                ['key' => 'status',            'label' => 'الحالة',           'type' => 'status',   'operators' => ['equals', 'not_equals']],
                ['key' => 'commission_amount', 'label' => 'مبلغ العمولة',     'type' => 'number',   'operators' => ['greater_than', 'less_than', 'between']],
                ['key' => 'calculated_at',     'label' => 'تاريخ الحساب',     'type' => 'datetime', 'operators' => ['date_from', 'date_to', 'between']],
                ['key' => 'created_at',        'label' => 'تاريخ الإنشاء',    'type' => 'datetime', 'operators' => ['date_from', 'date_to', 'between']],
            ],
        ];
    }

    private function products(): array
    {
        return [
            'key'          => 'products',
            'display_name' => 'المنتجات',
            'table'        => 'products',
            'columns'      => [
                ['key' => 'name',            'label' => 'الاسم',           'type' => 'text'],
                ['key' => 'sku',             'label' => 'الرمز',           'type' => 'text'],
                ['key' => 'type',            'label' => 'النوع',           'type' => 'status'],
                ['key' => 'base_price',      'label' => 'السعر',           'type' => 'money'],
                ['key' => 'cost_price',      'label' => 'التكلفة',         'type' => 'money'],
                ['key' => 'min_stock_alert', 'label' => 'حد المخزون',      'type' => 'number'],
                ['key' => 'created_at',      'label' => 'تاريخ الإنشاء',   'type' => 'datetime'],
            ],
            'filters'      => [
                ['key' => 'type',       'label' => 'النوع',           'type' => 'status',   'operators' => ['equals', 'not_equals']],
                ['key' => 'name',       'label' => 'الاسم',           'type' => 'text',     'operators' => ['equals', 'contains']],
                ['key' => 'base_price', 'label' => 'السعر',           'type' => 'number',   'operators' => ['greater_than', 'less_than', 'between']],
                ['key' => 'created_at', 'label' => 'تاريخ الإنشاء',   'type' => 'datetime', 'operators' => ['date_from', 'date_to', 'between']],
            ],
        ];
    }

    private function invoices(): array
    {
        return [
            'key'          => 'invoices',
            'display_name' => 'الفواتير',
            'table'        => 'invoices',
            'columns'      => [
                ['key' => 'invoice_number',  'label' => 'رقم الفاتورة',    'type' => 'text'],
                ['key' => 'invoice_type',    'label' => 'نوع الفاتورة',    'type' => 'status'],
                ['key' => 'status',          'label' => 'الحالة',          'type' => 'status'],
                ['key' => 'currency',        'label' => 'العملة',          'type' => 'text'],
                ['key' => 'total_amount',    'label' => 'الإجمالي',        'type' => 'money'],
                ['key' => 'discount_amount', 'label' => 'الخصم',           'type' => 'money'],
                ['key' => 'net_amount',      'label' => 'الصافي',          'type' => 'money'],
                ['key' => 'issue_date',      'label' => 'تاريخ الإصدار',   'type' => 'date'],
                ['key' => 'due_date',        'label' => 'تاريخ الاستحقاق', 'type' => 'date'],
                ['key' => 'created_at',      'label' => 'تاريخ الإنشاء',   'type' => 'datetime'],
            ],
            'filters'      => [
                ['key' => 'status',       'label' => 'الحالة',          'type' => 'status',   'operators' => ['equals', 'not_equals']],
                ['key' => 'invoice_type', 'label' => 'نوع الفاتورة',    'type' => 'status',   'operators' => ['equals']],
                ['key' => 'net_amount',   'label' => 'الصافي',          'type' => 'number',   'operators' => ['greater_than', 'less_than', 'between']],
                ['key' => 'issue_date',   'label' => 'تاريخ الإصدار',   'type' => 'datetime', 'operators' => ['date_from', 'date_to', 'between']],
                ['key' => 'created_at',   'label' => 'تاريخ الإنشاء',   'type' => 'datetime', 'operators' => ['date_from', 'date_to', 'between']],
            ],
        ];
    }

    private function payments(): array
    {
        return [
            'key'          => 'payments',
            'display_name' => 'المدفوعات',
            'table'        => 'payments',
            'columns'      => [
                ['key' => 'payment_number', 'label' => 'رقم الدفعة',      'type' => 'text'],
                ['key' => 'amount',         'label' => 'المبلغ',           'type' => 'money'],
                ['key' => 'currency',       'label' => 'العملة',           'type' => 'text'],
                ['key' => 'payment_method', 'label' => 'طريقة الدفع',     'type' => 'status'],
                ['key' => 'status',         'label' => 'الحالة',           'type' => 'status'],
                ['key' => 'payment_date',   'label' => 'تاريخ الدفع',     'type' => 'date'],
                ['key' => 'created_at',     'label' => 'تاريخ الإنشاء',    'type' => 'datetime'],
            ],
            'filters'      => [
                ['key' => 'status',         'label' => 'الحالة',           'type' => 'status',   'operators' => ['equals', 'not_equals']],
                ['key' => 'payment_method', 'label' => 'طريقة الدفع',     'type' => 'status',   'operators' => ['equals']],
                ['key' => 'amount',         'label' => 'المبلغ',           'type' => 'number',   'operators' => ['greater_than', 'less_than', 'between']],
                ['key' => 'payment_date',   'label' => 'تاريخ الدفع',     'type' => 'datetime', 'operators' => ['date_from', 'date_to', 'between']],
                ['key' => 'created_at',     'label' => 'تاريخ الإنشاء',    'type' => 'datetime', 'operators' => ['date_from', 'date_to', 'between']],
            ],
        ];
    }

    private function ownershipAssignments(): array
    {
        return [
            'key'          => 'ownership_assignments',
            'display_name' => 'تعيينات الملكية',
            'table'        => 'ownership_assignments',
            'columns'      => [
                ['key' => 'entity_type',  'label' => 'نوع الكيان',     'type' => 'status'],
                ['key' => 'entity_id',    'label' => 'معرف الكيان',    'type' => 'text'],
                ['key' => 'source',       'label' => 'المصدر',         'type' => 'status'],
                ['key' => 'status',       'label' => 'الحالة',         'type' => 'status'],
                ['key' => 'assigned_at',  'label' => 'تاريخ التعيين',  'type' => 'datetime'],
                ['key' => 'created_at',   'label' => 'تاريخ الإنشاء',  'type' => 'datetime'],
            ],
            'filters'      => [
                ['key' => 'entity_type', 'label' => 'نوع الكيان', 'type' => 'status', 'operators' => ['equals']],
                ['key' => 'status',      'label' => 'الحالة',     'type' => 'status', 'operators' => ['equals', 'not_equals']],
                ['key' => 'source',      'label' => 'المصدر',     'type' => 'status', 'operators' => ['equals']],
                ['key' => 'assigned_at', 'label' => 'تاريخ التعيين', 'type' => 'datetime', 'operators' => ['date_from', 'date_to']],
            ],
        ];
    }

    private function duplicateMatches(): array
    {
        return [
            'key'          => 'duplicate_matches',
            'display_name' => 'تطابقات التكرار',
            'table'        => 'duplicate_matches',
            'columns'      => [
                ['key' => 'entity_type',       'label' => 'نوع الكيان',        'type' => 'status'],
                ['key' => 'source_entity_id',  'label' => 'الكيان المصدر',     'type' => 'text'],
                ['key' => 'matched_entity_id', 'label' => 'الكيان المطابق',    'type' => 'text'],
                ['key' => 'match_score',       'label' => 'نسبة التطابق',      'type' => 'number'],
                ['key' => 'status',            'label' => 'الحالة',            'type' => 'status'],
                ['key' => 'resolution',        'label' => 'القرار',            'type' => 'status'],
                ['key' => 'created_at',        'label' => 'تاريخ الإنشاء',     'type' => 'datetime'],
            ],
            'filters'      => [
                ['key' => 'entity_type', 'label' => 'نوع الكيان', 'type' => 'status', 'operators' => ['equals']],
                ['key' => 'status',      'label' => 'الحالة',     'type' => 'status', 'operators' => ['equals', 'not_equals']],
                ['key' => 'created_at',  'label' => 'تاريخ الإنشاء', 'type' => 'datetime', 'operators' => ['date_from', 'date_to']],
            ],
        ];
    }
}
