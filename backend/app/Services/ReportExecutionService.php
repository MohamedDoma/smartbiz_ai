<?php

namespace App\Services;

use App\Models\ReportRun;
use App\Models\ReportTemplate;
use Illuminate\Support\Facades\DB;

/**
 * Executes report templates safely against the catalog whitelist.
 */
class ReportExecutionService
{
    private const DEFAULT_LIMIT = 100;
    private const MAX_LIMIT     = 500;

    private const ALLOWED_OPERATORS = [
        'equals', 'not_equals', 'contains',
        'greater_than', 'less_than', 'between',
        'date_from', 'date_to',
    ];

    public function __construct(private readonly ReportCatalogService $catalog)
    {
    }

    /**
     * Execute a report and return rows + summary.
     */
    public function execute(
        string $wsId,
        ReportTemplate $template,
        ?string $runByMembershipId = null,
        array $parameters = [],
    ): array {
        $startedAt = now();

        try {
            $ds = $this->catalog->getDataSource($template->data_source);
            if (!$ds) {
                throw new \InvalidArgumentException("Unknown data source: {$template->data_source}");
            }

            // Validate columns
            $allowedCols = $this->catalog->allowedColumns($template->data_source);
            $requestedCols = $template->columns;
            $validCols = array_values(array_intersect($requestedCols, $allowedCols));
            if (empty($validCols)) {
                throw new \InvalidArgumentException("No valid columns specified.");
            }

            // Build query
            $table = $ds['table'];
            $limit = min($parameters['limit'] ?? self::DEFAULT_LIMIT, self::MAX_LIMIT);

            // Set RLS context
            try {
                DB::statement("SET app.workspace_id = '{$wsId}'");
            } catch (\Throwable $e) {
                // Ignore — not all setups use RLS
            }

            $query = DB::table($table)
                ->where('workspace_id', $wsId)
                ->select($validCols);

            // Apply filters
            $this->applyFilters($query, $template->filters ?? [], $allowedCols);

            // Apply sorting
            $this->applySorting($query, $template->sort_by ?? [], $allowedCols);

            // Get rows
            $rows = $query->limit($limit)->get()->map(fn ($r) => (array) $r)->toArray();

            // Build summary
            $summary = $this->buildSummary($rows, $validCols, $ds);

            // Create run record
            $run = ReportRun::create([
                'workspace_id'       => $wsId,
                'report_template_id' => $template->id,
                'data_source'        => $template->data_source,
                'run_by_membership_id' => $runByMembershipId,
                'status'             => 'completed',
                'parameters'         => $parameters,
                'result_summary'     => $summary,
                'row_count'          => count($rows),
                'started_at'         => $startedAt,
                'finished_at'        => now(),
            ]);

            return [
                'run_id'      => $run->id,
                'template_id' => $template->id,
                'data_source' => $template->data_source,
                'columns'     => $validCols,
                'rows'        => $rows,
                'summary'     => $summary,
            ];
        } catch (\Throwable $e) {
            // Record failed run
            $run = ReportRun::create([
                'workspace_id'       => $wsId,
                'report_template_id' => $template->id,
                'data_source'        => $template->data_source,
                'run_by_membership_id' => $runByMembershipId,
                'status'             => 'failed',
                'parameters'         => $parameters,
                'error_message'      => $e->getMessage(),
                'row_count'          => 0,
                'started_at'         => $startedAt,
                'finished_at'        => now(),
            ]);

            throw $e;
        }
    }

    /**
     * Execute an ad-hoc report without a saved template.
     */
    public function executeAdHoc(
        string $wsId,
        string $dataSource,
        array $columns,
        array $filters = [],
        array $sortBy = [],
        ?string $runByMembershipId = null,
        array $parameters = [],
    ): array {
        $ds = $this->catalog->getDataSource($dataSource);
        if (!$ds) {
            throw new \InvalidArgumentException("Unknown data source: {$dataSource}");
        }

        $allowedCols = $this->catalog->allowedColumns($dataSource);
        $validCols = array_values(array_intersect($columns, $allowedCols));
        if (empty($validCols)) {
            throw new \InvalidArgumentException("No valid columns specified.");
        }

        $startedAt = now();
        $table = $ds['table'];
        $limit = min($parameters['limit'] ?? self::DEFAULT_LIMIT, self::MAX_LIMIT);

        try {
            DB::statement("SET app.workspace_id = '{$wsId}'");
        } catch (\Throwable $e) {
            // Ignore
        }

        $query = DB::table($table)
            ->where('workspace_id', $wsId)
            ->select($validCols);

        $this->applyFilters($query, $filters, $allowedCols);
        $this->applySorting($query, $sortBy, $allowedCols);

        $rows = $query->limit($limit)->get()->map(fn ($r) => (array) $r)->toArray();
        $summary = $this->buildSummary($rows, $validCols, $ds);

        $run = ReportRun::create([
            'workspace_id'         => $wsId,
            'data_source'          => $dataSource,
            'run_by_membership_id' => $runByMembershipId,
            'status'               => 'completed',
            'parameters'           => $parameters,
            'result_summary'       => $summary,
            'row_count'            => count($rows),
            'started_at'           => $startedAt,
            'finished_at'          => now(),
        ]);

        return [
            'run_id'      => $run->id,
            'template_id' => null,
            'data_source' => $dataSource,
            'columns'     => $validCols,
            'rows'        => $rows,
            'summary'     => $summary,
        ];
    }

    // ── Internal ─────────────────────────────────────────

    private function applyFilters($query, array $filters, array $allowedCols): void
    {
        foreach ($filters as $filter) {
            $field    = $filter['field'] ?? null;
            $operator = $filter['operator'] ?? null;
            $value    = $filter['value'] ?? null;

            if (!$field || !$operator) {
                continue;
            }
            if (!in_array($field, $allowedCols, true)) {
                continue; // silently skip unknown columns
            }
            if (!in_array($operator, self::ALLOWED_OPERATORS, true)) {
                continue;
            }

            match ($operator) {
                'equals'       => $query->where($field, '=', $value),
                'not_equals'   => $query->where($field, '!=', $value),
                'contains'     => $query->where($field, 'ILIKE', "%{$value}%"),
                'greater_than' => $query->where($field, '>', $value),
                'less_than'    => $query->where($field, '<', $value),
                'between'      => is_array($value) && count($value) === 2
                    ? $query->whereBetween($field, $value)
                    : null,
                'date_from'    => $query->where($field, '>=', $value),
                'date_to'      => $query->where($field, '<=', $value),
                default        => null,
            };
        }
    }

    private function applySorting($query, array $sortBy, array $allowedCols): void
    {
        foreach ($sortBy as $sort) {
            $field = $sort['field'] ?? null;
            $dir   = strtolower($sort['direction'] ?? 'asc');

            if (!$field || !in_array($field, $allowedCols, true)) {
                continue;
            }
            if (!in_array($dir, ['asc', 'desc'], true)) {
                $dir = 'asc';
            }

            $query->orderBy($field, $dir);
        }
    }

    private function buildSummary(array $rows, array $columns, array $ds): array
    {
        $summary = [
            'row_count'    => count($rows),
            'generated_at' => now()->toIso8601String(),
        ];

        // Column type map
        $typeMap = [];
        foreach ($ds['columns'] as $col) {
            $typeMap[$col['key']] = $col['type'];
        }

        // Totals for money/number columns
        $totals = [];
        $statusCounts = [];

        foreach ($columns as $col) {
            $type = $typeMap[$col] ?? 'text';

            if (in_array($type, ['money', 'number'], true)) {
                $sum = 0;
                foreach ($rows as $row) {
                    $sum += (float) ($row[$col] ?? 0);
                }
                $totals[$col] = number_format($sum, 2, '.', '');
            }

            if ($type === 'status') {
                $counts = [];
                foreach ($rows as $row) {
                    $v = $row[$col] ?? 'unknown';
                    $counts[$v] = ($counts[$v] ?? 0) + 1;
                }
                if (!empty($counts)) {
                    $statusCounts[$col] = $counts;
                }
            }
        }

        if (!empty($totals)) {
            $summary['totals'] = $totals;
        }
        if (!empty($statusCounts)) {
            $summary['status_counts'] = $statusCounts;
        }

        return $summary;
    }
}
