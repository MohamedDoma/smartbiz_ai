<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\ReportRun;
use App\Models\WorkspaceMembership;
use App\Services\ReportCatalogService;
use App\Services\ReportExecutionService;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class ReportRunController extends Controller
{
    private const ADMIN_ROLE_KEYS = ['owner', 'admin', 'general_manager', 'manager'];

    public function index(Request $request): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $wsId = $ctx->workspaceId();
        $user = $request->user();
        $membership = WorkspaceMembership::where('workspace_id', $wsId)
            ->where('user_id', $user->id)->first();

        $q = ReportRun::where('workspace_id', $wsId)
            ->with(['template:id,name,data_source'])
            ->orderByDesc('started_at');

        // Non-admin sees only their runs
        if (!$this->isAdmin($wsId, $request)) {
            $q->where('run_by_membership_id', $membership?->id);
        }

        if ($request->filled('data_source')) {
            $q->where('data_source', $request->input('data_source'));
        }

        return response()->json(['data' => $q->limit(100)->get()->map(fn ($r) => $this->fmt($r))]);
    }

    public function show(string $id): JsonResponse
    {
        $wsId = app(WorkspaceContextManager::class)->workspaceId();
        $run = ReportRun::where('workspace_id', $wsId)
            ->with(['template:id,name,data_source'])->findOrFail($id);
        return response()->json(['data' => $this->fmt($run)]);
    }

    /**
     * Ad-hoc report run (no saved template).
     */
    public function runAdHoc(Request $request): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);

        $v = $request->validate([
            'data_source'    => 'required|string|max:50',
            'columns'        => 'required|array|min:1',
            'columns.*'      => 'string',
            'filters'        => 'nullable|array',
            'filters.*.field'    => 'required_with:filters|string',
            'filters.*.operator' => 'required_with:filters|string',
            'filters.*.value'    => 'present',
            'sort_by'        => 'nullable|array',
            'sort_by.*.field'     => 'required_with:sort_by|string',
            'sort_by.*.direction' => 'nullable|string|in:asc,desc',
            'limit'          => 'nullable|integer|min:1|max:500',
        ]);

        $catalog = new ReportCatalogService();

        // Validate data source
        $ds = $catalog->getDataSource($v['data_source']);
        if (!$ds) {
            return response()->json(['message' => 'Unknown data source.', 'error' => 'validation_error'], 422);
        }

        // Validate columns
        $allowedCols = $catalog->allowedColumns($v['data_source']);
        $invalidCols = array_diff($v['columns'], $allowedCols);
        if (!empty($invalidCols)) {
            return response()->json([
                'message' => 'Invalid columns: ' . implode(', ', $invalidCols),
                'error'   => 'validation_error',
            ], 422);
        }

        // Validate filters
        if (!empty($v['filters'])) {
            foreach ($v['filters'] as $filter) {
                if (!in_array($filter['field'], $allowedCols, true)) {
                    return response()->json([
                        'message' => "Invalid filter field: {$filter['field']}",
                        'error'   => 'validation_error',
                    ], 422);
                }
            }
        }

        $user = $request->user();
        $membership = WorkspaceMembership::where('workspace_id', $ctx->workspaceId())
            ->where('user_id', $user->id)->first();

        $executor = new ReportExecutionService($catalog);

        try {
            $result = $executor->executeAdHoc(
                $ctx->workspaceId(),
                $v['data_source'],
                $v['columns'],
                $v['filters'] ?? [],
                $v['sort_by'] ?? [],
                $membership?->id,
                ['limit' => $v['limit'] ?? 100],
            );

            return response()->json(['data' => $result]);
        } catch (\InvalidArgumentException $e) {
            return response()->json([
                'message' => $e->getMessage(),
                'error'   => 'validation_error',
            ], 422);
        }
    }

    private function fmt(ReportRun $r): array
    {
        return [
            'id'                 => $r->id,
            'report_template_id' => $r->report_template_id,
            'template'           => $r->relationLoaded('template') && $r->template
                ? ['id' => $r->template->id, 'name' => $r->template->name, 'data_source' => $r->template->data_source]
                : null,
            'data_source'        => $r->data_source,
            'status'             => $r->status,
            'row_count'          => $r->row_count,
            'result_summary'     => $r->result_summary,
            'error_message'      => $r->error_message,
            'started_at'         => $r->started_at?->toIso8601String(),
            'finished_at'        => $r->finished_at?->toIso8601String(),
            'created_at'         => $r->created_at?->toIso8601String(),
        ];
    }

    private function isAdmin(string $wsId, Request $request): bool
    {
        $user = $request->user();
        if ($user->is_super_admin) {
            return true;
        }
        $m = WorkspaceMembership::where('workspace_id', $wsId)
            ->where('user_id', $user->id)->where('status', 'active')->first();
        if (!$m) {
            return false;
        }
        $keys = $m->membershipRoles()
            ->join('roles', 'roles.id', '=', 'membership_roles.role_id')
            ->pluck('roles.role_key')->toArray();
        return !empty(array_intersect($keys, self::ADMIN_ROLE_KEYS));
    }
}
