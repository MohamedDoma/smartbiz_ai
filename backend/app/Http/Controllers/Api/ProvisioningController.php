<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\ProvisioningService;
use App\Services\WorkspaceContextManager;
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

        $result = $this->provisioning->preview(
            $this->context->workspaceId(),
            $request->input('blueprint_id'),
        );

        return response()->json(['data' => $result]);
    }

    /**
     * POST /api/provisioning/apply
     */
    public function apply(Request $request): JsonResponse
    {
        $request->validate(['blueprint_id' => ['required', 'uuid']]);

        $result = $this->provisioning->apply(
            $this->context->workspaceId(),
            $request->input('blueprint_id'),
            $request->user()->id,
        );

        return response()->json(['data' => $result]);
    }

    /**
     * POST /api/provisioning/rollback
     */
    public function rollback(Request $request): JsonResponse
    {
        $request->validate(['run_id' => ['required', 'uuid']]);

        $result = $this->provisioning->rollback(
            $this->context->workspaceId(),
            $request->input('run_id'),
            $request->user()->id,
        );

        return response()->json(['data' => $result]);
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
}
