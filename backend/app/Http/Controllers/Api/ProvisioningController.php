<?php

namespace App\Http\Controllers\Api;

use App\Exceptions\ProvisioningException;
use App\Http\Controllers\Controller;
use App\Services\ProvisioningService;
use App\Services\WorkspaceContextManager;
use Illuminate\Database\Eloquent\ModelNotFoundException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class ProvisioningController extends Controller
{
    public function __construct(
        private readonly ProvisioningService      $provisioning,
        private readonly WorkspaceContextManager  $context,
    ) {}

    /**
     * POST /api/provisioning/preview
     */
    public function preview(Request $request): JsonResponse
    {
        $request->validate(['blueprint_id' => ['required', 'uuid']]);

        try {
            $result = $this->provisioning->preview(
                $this->context->workspaceId(),
                $request->input('blueprint_id'),
            );

            // Validation failure returns structured 422
            if (($result['status'] ?? '') === 'validation_failed') {
                return response()->json([
                    'message' => 'Blueprint validation failed.',
                    'data'    => $result,
                ], 422);
            }

            return response()->json(['data' => $result]);

        } catch (ModelNotFoundException $e) {
            return response()->json([
                'message' => 'Blueprint not found in this workspace.',
                'error'   => 'blueprint_not_found',
            ], 404);
        } catch (ProvisioningException $e) {
            return response()->json([
                'message' => $e->getMessage(),
                'error'   => $e->getErrorCode(),
            ], $e->getCode() ?: 422);
        }
    }

    /**
     * POST /api/provisioning/apply
     */
    public function apply(Request $request): JsonResponse
    {
        $request->validate(['blueprint_id' => ['required', 'uuid']]);

        try {
            $result = $this->provisioning->apply(
                $this->context->workspaceId(),
                $request->input('blueprint_id'),
                $request->user()->id,
            );

            // Validation failure
            if (($result['status'] ?? '') === 'validation_failed') {
                return response()->json([
                    'message' => 'Blueprint validation failed.',
                    'data'    => $result,
                ], 422);
            }

            // Active run conflict
            if (!empty($result['active_run'])) {
                return response()->json([
                    'message' => $result['message'],
                    'data'    => $result,
                ], 409);
            }

            return response()->json(['data' => $result]);

        } catch (ModelNotFoundException $e) {
            return response()->json([
                'message' => 'Blueprint not found in this workspace.',
                'error'   => 'blueprint_not_found',
            ], 404);
        } catch (ProvisioningException $e) {
            return response()->json([
                'message' => $e->getMessage(),
                'error'   => $e->getErrorCode(),
            ], $e->getCode() ?: 422);
        }
    }

    /**
     * POST /api/provisioning/rollback
     */
    public function rollback(Request $request): JsonResponse
    {
        $request->validate(['run_id' => ['required', 'uuid']]);

        try {
            $result = $this->provisioning->rollback(
                $this->context->workspaceId(),
                $request->input('run_id'),
                $request->user()->id,
            );

            return response()->json(['data' => $result]);

        } catch (ModelNotFoundException $e) {
            return response()->json([
                'message' => 'Provisioning run not found or not eligible for rollback.',
                'error'   => 'run_not_found',
            ], 404);
        }
    }

    /**
     * GET /api/provisioning/config
     */
    public function config(): JsonResponse
    {
        $config = $this->provisioning->getActiveConfig($this->context->workspaceId());
        if (! $config) {
            return response()->json(['data' => null, 'message' => 'No configuration applied yet.']);
        }
        return response()->json(['data' => $config]);
    }

    /**
     * PUT /api/provisioning/modules
     */
    public function updateModules(Request $request): JsonResponse
    {
        $request->validate(['modules' => ['required', 'array']]);

        $config = $this->provisioning->updateModules(
            $this->context->workspaceId(),
            $request->input('modules'),
        );

        return response()->json(['data' => $config]);
    }

    /**
     * PUT /api/provisioning/roles/{role}
     */
    public function updateRole(Request $request, string $role): JsonResponse
    {
        $request->validate([
            'homepage'          => ['sometimes', 'string'],
            'navigation'        => ['sometimes', 'array'],
            'quick_actions'     => ['sometimes', 'array'],
            'allowed_screens'   => ['sometimes', 'array'],
            'dashboard_widgets' => ['sometimes', 'array'],
        ]);

        $config = $this->provisioning->updateRoleConfig(
            $this->context->workspaceId(),
            $role,
            $request->only(['homepage', 'navigation', 'quick_actions', 'allowed_screens', 'dashboard_widgets']),
        );

        return response()->json(['data' => $config]);
    }

    /**
     * POST /api/provisioning/{run}/apply-operational
     *
     * Apply operational entities (warehouses, pipelines, approvals, commissions, settings)
     * to a foundation_applied run. Idempotent — safe to call multiple times.
     */
    public function applyOperational(Request $request, string $run): JsonResponse
    {
        try {
            // Resolve the blueprint_id from the run's config rather than requiring
            // the client to re-send it.  The service method needs it for validation.
            $runRecord = \App\Models\ProvisioningRun::where('workspace_id', $this->context->workspaceId())
                ->where('id', $run)
                ->first();

            if (! $runRecord) {
                return response()->json([
                    'message' => 'Provisioning run not found in this workspace.',
                    'error'   => 'run_not_found',
                ], 404);
            }

            $blueprintId = $runRecord->blueprint_id;

            $result = $this->provisioning->applyOperational(
                $this->context->workspaceId(),
                $blueprintId,
                $request->user()->id,
            );

            return response()->json(['data' => $result]);

        } catch (ModelNotFoundException $e) {
            return response()->json([
                'message' => 'Blueprint not found in this workspace.',
                'error'   => 'blueprint_not_found',
            ], 404);
        } catch (ProvisioningException $e) {
            return response()->json([
                'message' => $e->getMessage(),
                'error'   => $e->getErrorCode(),
            ], $e->getCode() ?: 422);
        }
    }

    /**
     * POST /api/provisioning/{run}/finalize
     *
     * Finalize onboarding: assign primary_owner role to workspace owner,
     * mark onboarding complete, transition run to 'onboarding_complete'.
     * Idempotent — safe to call multiple times.
     */
    public function finalize(Request $request, string $run): JsonResponse
    {
        try {
            $result = $this->provisioning->finalize(
                $this->context->workspaceId(),
                $run,
                $request->user()->id,
            );

            $status = !empty($result['already_finalized']) ? 200 : 200;

            return response()->json(['data' => $result], $status);

        } catch (ProvisioningException $e) {
            return response()->json([
                'message' => $e->getMessage(),
                'error'   => $e->getErrorCode(),
            ], $e->getCode() ?: 422);
        }
    }
}
