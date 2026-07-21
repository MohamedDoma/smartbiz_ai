<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\ReportTemplate;
use App\Models\WorkspaceMembership;
use App\Services\PermissionResolver;
use App\Services\ReportCatalogService;
use App\Services\ReportExecutionService;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

class ReportTemplateController extends Controller
{

    public function index(Request $request): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $wsId = $ctx->workspaceId();
        $membership = $ctx->membership();

        $q = ReportTemplate::where('workspace_id', $wsId)
            ->where('is_active', true)
            ->where(function ($q) use ($membership) {
                $q->where('visibility', 'workspace');
                if ($membership) {
                    $q->orWhere(function ($q2) use ($membership) {
                        $q2->where('visibility', 'private')
                            ->where('created_by_membership_id', $membership->id);
                    });
                }
            })
            ->orderBy('sort_order')
            ->orderByDesc('created_at');

        if ($request->filled('data_source')) {
            $q->where('data_source', $request->input('data_source'));
        }

        return response()->json(['data' => $q->get()->map(fn ($t) => $this->fmt($t))]);
    }

    public function store(Request $request): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $catalog = new ReportCatalogService();

        $v = $request->validate([
            'name'           => 'required|string|max:255',
            'description'    => 'nullable|string|max:2000',
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
            'group_by'       => 'nullable|array',
            'visibility'     => 'nullable|string|in:workspace,private',
        ]);

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

        // Validate filter fields
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

        // Private templates can be created by report runners. Workspace-wide
        // templates require the explicit reports.manage capability.
        $visibility = $v['visibility'] ?? 'workspace';
        $membership = $ctx->membership();
        if ($visibility === 'workspace' && ! $this->canManageReports($membership)) {
            abort(403, 'The reports.manage permission is required for workspace templates.');
        }

        $template = ReportTemplate::create([
            'workspace_id'             => $ctx->workspaceId(),
            'template_key'             => Str::slug($v['name'], '_'),
            'name'                     => $v['name'],
            'description'              => $v['description'] ?? null,
            'data_source'              => $v['data_source'],
            'columns'                  => $v['columns'],
            'filters'                  => $v['filters'] ?? null,
            'group_by'                 => $v['group_by'] ?? null,
            'sort_by'                  => $v['sort_by'] ?? null,
            'visibility'               => $visibility,
            'created_by_membership_id' => $membership?->id,
            'is_active'                => true,
        ]);

        return response()->json(['data' => $this->fmt($template)], 201);
    }

    public function show(string $id): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $membership = $ctx->membership();

        $query = ReportTemplate::where('workspace_id', $ctx->workspaceId());
        if (! $this->canManageReports($membership)) {
            $query->where(function ($q) use ($membership) {
                $q->where('visibility', 'workspace');
                if ($membership) {
                    $q->orWhere(function ($private) use ($membership) {
                        $private->where('visibility', 'private')
                            ->where('created_by_membership_id', $membership->id);
                    });
                }
            });
        }

        $template = $query->findOrFail($id);
        return response()->json(['data' => $this->fmt($template)]);
    }

    public function update(Request $request, string $id): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $catalog = new ReportCatalogService();

        $template = ReportTemplate::where('workspace_id', $ctx->workspaceId())->findOrFail($id);

        $v = $request->validate([
            'name'        => 'sometimes|required|string|max:255',
            'description' => 'nullable|string|max:2000',
            'columns'     => 'sometimes|array|min:1',
            'columns.*'   => 'string',
            'filters'     => 'nullable|array',
            'sort_by'     => 'nullable|array',
            'group_by'    => 'nullable|array',
            'visibility'  => 'nullable|string|in:workspace,private',
            'is_active'   => 'sometimes|boolean',
        ]);

        // Validate columns against catalog
        if (isset($v['columns'])) {
            $allowedCols = $catalog->allowedColumns($template->data_source);
            $invalidCols = array_diff($v['columns'], $allowedCols);
            if (!empty($invalidCols)) {
                return response()->json([
                    'message' => 'Invalid columns: ' . implode(', ', $invalidCols),
                    'error'   => 'validation_error',
                ], 422);
            }
        }

        if (isset($v['name'])) {
            $v['template_key'] = Str::slug($v['name'], '_');
        }

        $template->update($v);

        return response()->json(['data' => $this->fmt($template->fresh())]);
    }

    public function destroy(Request $request, string $id): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);

        $template = ReportTemplate::where('workspace_id', $ctx->workspaceId())->findOrFail($id);
        $template->update(['is_active' => false]);

        return response()->json(['message' => 'Report template deactivated.']);
    }

    public function run(Request $request, string $id): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $membership = $ctx->membership();

        $query = ReportTemplate::where('workspace_id', $ctx->workspaceId())
            ->where('is_active', true);

        if (! $this->canManageReports($membership)) {
            $query->where(function ($q) use ($membership) {
                $q->where('visibility', 'workspace');
                if ($membership) {
                    $q->orWhere(function ($private) use ($membership) {
                        $private->where('visibility', 'private')
                            ->where('created_by_membership_id', $membership->id);
                    });
                }
            });
        }

        $template = $query->findOrFail($id);

        $params = $request->validate([
            'parameters'       => 'nullable|array',
            'parameters.limit' => 'nullable|integer|min:1|max:500',
        ]);

        $catalog = new ReportCatalogService();
        $executor = new ReportExecutionService($catalog);

        try {
            $result = $executor->execute(
                $ctx->workspaceId(),
                $template,
                $membership?->id,
                $params['parameters'] ?? [],
            );

            return response()->json(['data' => $result]);
        } catch (\InvalidArgumentException $e) {
            return response()->json([
                'message' => $e->getMessage(),
                'error'   => 'validation_error',
            ], 422);
        }
    }

    private function fmt(ReportTemplate $t): array
    {
        return [
            'id'          => $t->id,
            'template_key' => $t->template_key,
            'name'        => $t->name,
            'description' => $t->description,
            'data_source' => $t->data_source,
            'columns'     => $t->columns,
            'filters'     => $t->filters,
            'group_by'    => $t->group_by,
            'sort_by'     => $t->sort_by,
            'visibility'  => $t->visibility,
            'is_active'   => $t->is_active,
            'sort_order'  => $t->sort_order,
            'created_at'  => $t->created_at?->toIso8601String(),
        ];
    }


    private function canManageReports(?WorkspaceMembership $membership): bool
    {
        return $membership !== null
            && app(PermissionResolver::class)->can($membership, 'reports.manage');
    }

}
