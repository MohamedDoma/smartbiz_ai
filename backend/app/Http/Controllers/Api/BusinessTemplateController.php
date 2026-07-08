<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\BusinessTemplate;
use App\Models\WorkspaceMembership;
use App\Services\BusinessTemplateApplicationService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class BusinessTemplateController extends Controller
{
    /**
     * GET /api/business-templates
     *
     * List all active business templates with module counts.
     */
    public function index(): JsonResponse
    {
        $templates = BusinessTemplate::where('is_active', true)
            ->orderBy('sort_order')
            ->get()
            ->map(fn (BusinessTemplate $t) => [
                'id'            => $t->id,
                'template_key'  => $t->template_key,
                'name'          => $t->name,
                'description'   => $t->description,
                'industry_type' => $t->industry_type,
                'business_size' => $t->business_size,
                'version'       => $t->version,
                'is_default'    => $t->is_default,
                'module_count'  => $t->modules()->count(),
            ]);

        return response()->json([
            'data' => $templates,
        ]);
    }

    /**
     * GET /api/business-templates/{template_key}
     *
     * Show a single template with all children.
     */
    public function show(string $templateKey): JsonResponse
    {
        $template = BusinessTemplate::where('template_key', $templateKey)
            ->where('is_active', true)
            ->first();

        if (! $template) {
            return response()->json([
                'message' => 'Template not found.',
            ], 404);
        }

        return response()->json([
            'data' => [
                'id'            => $template->id,
                'template_key'  => $template->template_key,
                'name'          => $template->name,
                'description'   => $template->description,
                'industry_type' => $template->industry_type,
                'business_size' => $template->business_size,
                'version'       => $template->version,
                'is_default'    => $template->is_default,
                'modules'       => $template->modules->map(fn ($m) => [
                    'module_key'  => $m->module_key,
                    'name'        => $m->name,
                    'description' => $m->description,
                    'is_enabled'  => $m->is_enabled,
                    'is_required' => $m->is_required,
                    'settings'    => $m->settings,
                    'sort_order'  => $m->sort_order,
                ]),
                'roles'         => $template->roles->map(fn ($r) => [
                    'role_key'              => $r->role_key,
                    'name'                  => $r->name,
                    'description'           => $r->description,
                    'hierarchy_level'       => $r->hierarchy_level,
                    'permissions'           => $r->permissions,
                    'is_primary_owner_role' => $r->is_primary_owner_role,
                    'sort_order'            => $r->sort_order,
                ]),
                'workflows'     => $template->workflows->map(fn ($w) => [
                    'workflow_type' => $w->workflow_type,
                    'workflow_key'  => $w->workflow_key,
                    'name'          => $w->name,
                    'description'   => $w->description,
                    'config'        => $w->config,
                    'is_active'     => $w->is_active,
                    'sort_order'    => $w->sort_order,
                ]),
                'custom_fields' => $template->customFields->map(fn ($f) => [
                    'entity_type'      => $f->entity_type,
                    'field_key'        => $f->field_key,
                    'label'            => $f->label,
                    'field_type'       => $f->field_type,
                    'is_required'      => $f->is_required,
                    'options'          => $f->options,
                    'validation_rules' => $f->validation_rules,
                    'sort_order'       => $f->sort_order,
                ]),
            ],
        ]);
    }

    /**
     * POST /api/business-templates/{template_key}/apply
     *
     * Apply a template to the current workspace.
     * Requires X-Workspace-Id header + active membership.
     */
    public function apply(Request $request, string $templateKey, BusinessTemplateApplicationService $service): JsonResponse
    {
        $workspaceId = $request->header('X-Workspace-Id');
        if (! $workspaceId) {
            return response()->json([
                'message' => 'X-Workspace-Id header is required.',
            ], 400);
        }

        $user = $request->user();

        $membership = WorkspaceMembership::where('workspace_id', $workspaceId)
            ->where('user_id', $user->id)
            ->where('status', 'active')
            ->first();

        if (! $membership) {
            return response()->json([
                'message' => 'You are not a member of this workspace.',
            ], 403);
        }

        $template = BusinessTemplate::where('template_key', $templateKey)
            ->where('is_active', true)
            ->first();

        if (! $template) {
            return response()->json([
                'message' => 'Template not found.',
            ], 404);
        }

        if ($service->hasConflictingTemplate($membership->workspace, $template)) {
            return response()->json([
                'message' => 'A different business template is already applied to this workspace.',
            ], 409);
        }

        try {
            $application = $service->apply($template, $membership->workspace, $user);

            return response()->json([
                'message'     => 'Business template applied successfully.',
                'application' => [
                    'id'               => $application->id,
                    'template_key'     => $application->template_key,
                    'template_version' => $application->template_version,
                    'status'           => $application->status,
                    'applied_at'       => $application->applied_at?->toIso8601String(),
                ],
            ]);
        } catch (\Throwable $e) {
            report($e);
            return response()->json([
                'message' => 'Failed to apply template. Please try again.',
            ], 500);
        }
    }
}
