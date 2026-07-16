<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\WorkspaceConfiguration;
use App\Models\WorkspaceMembership;
use App\Services\ConditionEntityFieldCatalog;
use App\Services\PermissionResolver;
use App\Services\TriggerConditionValidator;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * ApprovalEntityFieldCatalogController — API for the condition builder field catalog.
 *
 * Exposes the entity field schema registry to the frontend condition builder,
 * enabling dynamic, type-safe construction of workflow trigger conditions.
 *
 * Endpoints:
 *  GET /api/approval-entity-field-catalog?entity_type=commission_entry
 *      → Full field schema for a specific entity type.
 *        Missing entity_type → HTTP 422.
 *  GET /api/approval-entity-types
 *      → List registered entity types with localized labels and module_key.
 *
 * Security:
 *  - Requires auth:sanctum + SetWorkspaceContext middleware (applied via route)
 *  - Requires 'approvals.manage' permission
 *  - Workspace-isolated via enabled_modules filtering
 */
class ApprovalEntityFieldCatalogController extends Controller
{
    public function __construct(
        private readonly WorkspaceContextManager $ctx,
        private readonly PermissionResolver $resolver,
        private readonly ConditionEntityFieldCatalog $catalog,
    ) {}

    /**
     * Resolve the field schema for a specific entity type.
     *
     * Query parameters:
     *  - entity_type (required): The entity type to resolve.
     *
     * Response 200:
     *  {
     *    "data": {
     *      "entity_type": "commission_entry",
     *      "label_en": "Commission entry",
     *      "label_ar": "سجل عمولة",
     *      "module_key": "commissions",
     *      "fields": [{"key": "amount", "type": "number", ...}]
     *    },
     *    "supported_operators": ["equals", "not_equals", ...]
     *  }
     *
     * Error responses:
     *  - 422: Missing entity_type parameter.
     *  - 404: Entity type not registered or module disabled.
     */
    public function index(Request $request): JsonResponse
    {
        $membership = $this->ctx->membership();
        $this->requirePermission($membership, 'approvals.manage');

        // entity_type is required — use the dedicated entity-types endpoint for listing.
        if (! $request->filled('entity_type')) {
            return response()->json([
                'message' => 'The entity_type parameter is required.',
                'errors'  => ['entity_type' => ['The entity_type parameter is required.']],
            ], 422);
        }

        $enabledModules = $this->resolveEnabledModules($this->ctx->workspaceId());
        $operators      = TriggerConditionValidator::SUPPORTED_OPERATORS;

        $entityType = $request->input('entity_type');
        $schema     = $this->catalog->resolve($entityType, $enabledModules);

        if (! $schema) {
            return response()->json([
                'message' => "Entity type '{$entityType}' is not available for trigger conditions in this workspace.",
            ], 404);
        }

        return response()->json([
            'data'                => $schema,
            'supported_operators' => $operators,
        ]);
    }

    // ── Entity Types Discovery ──────────────────────────────────

    /**
     * List registered entity types with localized labels.
     *
     * GET /api/approval-entity-types
     *
     * Response:
     *  {
     *    "data": [
     *      {
     *        "entity_type": "commission_entry",
     *        "label_en": "Commission entry",
     *        "label_ar": "سجل عمولة",
     *        "module_key": "commissions"
     *      }
     *    ]
     *  }
     *
     * Only entity types whose required module is enabled in the
     * active workspace are returned. Empty "data" array when none qualify.
     */
    public function entityTypes(): JsonResponse
    {
        $membership = $this->ctx->membership();
        $this->requirePermission($membership, 'approvals.manage');

        $enabledModules = $this->resolveEnabledModules($this->ctx->workspaceId());
        $entityTypes = $this->catalog->listEntityTypes($enabledModules);

        return response()->json([
            'data' => $entityTypes,
        ]);
    }

    // ── Helpers ─────────────────────────────────────────────────

    /**
     * Resolve the workspace's enabled_modules list from WorkspaceConfiguration.
     *
     * Returns an array of module key strings (e.g. ['crm', 'commissions', 'inventory']).
     * Returns an empty array if no configuration exists, which will hide
     * all module-gated entity types.
     */
    private function resolveEnabledModules(string $workspaceId): array
    {
        $config = WorkspaceConfiguration::where('workspace_id', $workspaceId)->first();

        if (! $config || ! is_array($config->enabled_modules)) {
            return [];
        }

        return $config->enabled_modules;
    }

    /**
     * Require a permission via PermissionResolver.
     * Super-admins bypass all checks.
     */
    private function requirePermission(?WorkspaceMembership $membership, string $permissionKey): void
    {
        $user = request()->user();
        if ($user && $user->is_super_admin) {
            return;
        }

        if (! $membership) {
            abort(403, 'Not a workspace member.');
        }

        if (! $this->resolver->can($membership, $permissionKey)) {
            abort(403, 'Insufficient permissions.');
        }
    }
}
