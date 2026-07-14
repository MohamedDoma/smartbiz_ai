<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\CustomField;
use App\Models\CustomFieldValue;
use App\Models\Pipeline;
use App\Models\PipelineRecord;
use App\Models\PipelineStage;
use App\Models\WorkspaceMembership;
use App\Services\CommissionCalculationService;
use App\Services\OpenDealGuard;
use App\Services\PipelineAuditService;
use App\Services\PipelineRecordScope;
use App\Services\PermissionResolver;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class PipelineRecordController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $wsId = $ctx->workspaceId();
        $membership = $ctx->membership();

        $query = PipelineRecord::where('workspace_id', $wsId)
            ->with(['stage:id,name,status_type', 'pipeline:id,name', 'assignedMembership.user:id,full_name', 'contact:id,name']);

        if ($membership) {
            PipelineRecordScope::apply($query, $membership);
        }

        if ($request->filled('pipeline_id')) {
            $query->where('pipeline_id', $request->input('pipeline_id'));
        }
        if ($request->filled('stage_id')) {
            $query->where('stage_id', $request->input('stage_id'));
        }

        $records = $query->orderByDesc('created_at')->get();

        return response()->json([
            'data' => $records->map(fn ($r) => $this->fmt($r)),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $wsId = $ctx->workspaceId();

        $validated = $request->validate([
            'pipeline_id'             => 'required|uuid',
            'stage_id'                => 'required|uuid',
            'title'                   => 'required|string|max:255',
            'description'             => 'nullable|string|max:5000',
            'contact_id'              => 'nullable|uuid',
            'assigned_membership_id'  => 'nullable|uuid',
            'value_amount'            => 'nullable|numeric|min:0',
            'currency'                => 'nullable|string|max:10',
            'expected_close_date'     => 'nullable|date',
            'custom_values'           => 'nullable|array',
        ]);

        // Validate pipeline + stage belong to workspace
        $pipeline = Pipeline::where('workspace_id', $wsId)->where('id', $validated['pipeline_id'])->first();
        if (! $pipeline) {
            return response()->json(['message' => 'Pipeline not found in workspace.'], 422);
        }

        $stage = PipelineStage::where('pipeline_id', $pipeline->id)->where('id', $validated['stage_id'])->first();
        if (! $stage) {
            return response()->json(['message' => 'Stage does not belong to this pipeline.'], 422);
        }

        // Validate contact — scope to user's visible customers
        $currentMembership = $ctx->membership();
        if (! empty($validated['contact_id'])) {
            $contactQuery = \App\Models\Contact::where('workspace_id', $wsId)
                ->where('id', $validated['contact_id']);
            if ($currentMembership) {
                \App\Services\ContactScope::apply($contactQuery, $currentMembership);
            }
            if (! $contactQuery->exists()) {
                return response()->json(['message' => 'Contact not found or not accessible.'], 422);
            }
        } elseif ($pipeline->entity_type === 'deal') {
            return response()->json(['message' => 'A customer is required for deal records.'], 422);
        }

        // ── Open deal duplicate guard ────────────────────────────
        if ($pipeline->entity_type === 'deal' && ! empty($validated['contact_id'])) {
            $dealGuard = app(OpenDealGuard::class);
            $dealCheck = $dealGuard->check(
                $wsId,
                $pipeline->id,
                $validated['contact_id'],
                $currentMembership,
            );

            if ($dealCheck['blocked']) {
                $code = $dealCheck['code'];
                if ($code === 'open_deal_duplicate' && $dealCheck['record']) {
                    $r = $dealCheck['record'];
                    return response()->json([
                        'message'    => 'An open deal already exists for this customer in this pipeline.',
                        'error_code' => 'open_deal_duplicate',
                        'existing'   => [
                            'id'    => $r->id,
                            'title' => $r->title,
                            'stage' => $r->stage ? ['id' => $r->stage->id, 'name' => $r->stage->name] : null,
                        ],
                    ], 409);
                }

                return response()->json([
                    'message'    => 'This customer has an open deal managed by another employee. Contact your sales manager.',
                    'error_code' => 'open_deal_exists_outside_scope',
                ], 409);
            }
        }

        // ── Assignment logic ──────────────────────────────────────
        $resolver = app(PermissionResolver::class);
        $canAssign = $currentMembership
            ? $resolver->can($currentMembership, 'pipeline_records.assign')
            : false;
        $canOwn = $currentMembership
            ? $resolver->can($currentMembership, 'pipeline_records.own')
            : false;

        if ($canAssign && ! empty($validated['assigned_membership_id'])) {
            // Manager picked an assignee — validate them.
            $assignError = $this->validateAssignee($validated['assigned_membership_id'], $wsId);
            if ($assignError) {
                return response()->json(['message' => $assignError], 422);
            }
            $resolvedAssigneeId = $validated['assigned_membership_id'];
        } elseif ($canAssign && empty($validated['assigned_membership_id'])) {
            // Manager didn't pick anyone — auto-assign only if they can own.
            if ($canOwn) {
                $resolvedAssigneeId = $currentMembership?->id;
            } else {
                return response()->json(['message' => 'An assignee is required. You do not have pipeline_records.own to self-assign.'], 422);
            }
        } elseif (! $canAssign) {
            // No assign permission — auto-assign to creator only if they can own.
            if ($canOwn) {
                $resolvedAssigneeId = $currentMembership?->id;
            } else {
                return response()->json(['message' => 'You are not eligible to own pipeline records.'], 403);
            }
        }

        // Validate custom values
        $customValues = $validated['custom_values'] ?? [];
        $customFields = CustomField::where('workspace_id', $wsId)
            ->where(function ($q) use ($pipeline) {
                $q->where('pipeline_id', $pipeline->id)->orWhereNull('pipeline_id');
            })
            ->where('is_active', true)
            ->get()
            ->keyBy('field_key');

        // Check required fields
        foreach ($customFields as $key => $field) {
            if ($field->is_required && (! isset($customValues[$key]) || $customValues[$key] === '' || $customValues[$key] === null)) {
                return response()->json([
                    'message' => "Custom field '{$field->label}' is required.",
                    'errors' => ["custom_values.{$key}" => ['Required.']],
                ], 422);
            }
        }

        // Validate provided keys exist
        foreach ($customValues as $key => $val) {
            if (! $customFields->has($key)) {
                return response()->json(['message' => "Unknown custom field: {$key}"], 422);
            }
        }

        try {
            $record = DB::transaction(function () use ($validated, $wsId, $customValues, $customFields, $ctx, $resolvedAssigneeId) {
                $record = PipelineRecord::create([
                    'workspace_id'            => $wsId,
                    'pipeline_id'             => $validated['pipeline_id'],
                    'stage_id'                => $validated['stage_id'],
                    'title'                   => $validated['title'],
                    'description'             => $validated['description'] ?? null,
                    'contact_id'              => $validated['contact_id'] ?? null,
                    'assigned_membership_id'  => $resolvedAssigneeId,
                    'value_amount'            => $validated['value_amount'] ?? null,
                    'currency'                => $validated['currency'] ?? null,
                    'status'                  => 'open',
                    'expected_close_date'     => $validated['expected_close_date'] ?? null,
                ]);

                $this->saveCustomValues($record, $customValues, $customFields, $wsId);

                PipelineAuditService::log($wsId, 'created', 'pipeline_record', $record->id, null, [
                    'title' => $record->title, 'pipeline_id' => $record->pipeline_id,
                    'stage_id' => $record->stage_id, 'value_amount' => $record->value_amount,
                    'assigned_membership_id' => $record->assigned_membership_id,
                ]);

                return $record;
            });
        } catch (\Throwable $e) {
            report($e);
            return response()->json(['message' => 'Failed to create record.'], 500);
        }

        $record->load(['stage:id,name,status_type', 'pipeline:id,name', 'assignedMembership.user:id,full_name', 'contact:id,name', 'customFieldValues.customField:id,field_key,label,field_type']);

        return response()->json(['data' => $this->fmt($record)], 201);
    }

    public function show(string $id): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $wsId = $ctx->workspaceId();
        $membership = $ctx->membership();

        $query = PipelineRecord::where('workspace_id', $wsId)
            ->with(['stage:id,name,status_type', 'pipeline:id,name', 'assignedMembership.user:id,full_name', 'contact:id,name', 'customFieldValues.customField:id,field_key,label,field_type']);

        if ($membership) {
            PipelineRecordScope::apply($query, $membership);
        }

        $record = $query->findOrFail($id);

        return response()->json(['data' => $this->fmt($record)]);
    }

    public function update(Request $request, string $id): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $wsId = $ctx->workspaceId();

        $membership = $ctx->membership();
        $scopedQuery = PipelineRecord::where('workspace_id', $wsId);
        if ($membership) {
            PipelineRecordScope::apply($scopedQuery, $membership);
        }
        $record = $scopedQuery->findOrFail($id);

        $validated = $request->validate([
            'title'                   => 'sometimes|required|string|max:255',
            'description'             => 'nullable|string|max:5000',
            'contact_id'              => 'nullable|uuid',
            'assigned_membership_id'  => 'nullable|uuid',
            'value_amount'            => 'nullable|numeric|min:0',
            'currency'                => 'nullable|string|max:10',
            'expected_close_date'     => 'nullable|date',
            'custom_values'           => 'nullable|array',
        ]);

        // Check assignment permission if changing assigned_membership_id
        if (array_key_exists('assigned_membership_id', $validated)
            && $validated['assigned_membership_id'] !== $record->assigned_membership_id) {
            if (! $this->hasPermission($request, 'pipeline_records.assign')) {
                return response()->json(['message' => 'You do not have permission to assign records.'], 403);
            }
            // Validate the new assignee
            if (! empty($validated['assigned_membership_id'])) {
                $assignError = $this->validateAssignee($validated['assigned_membership_id'], $wsId);
                if ($assignError) {
                    return response()->json(['message' => $assignError], 422);
                }
            }
        }

        $customValues = $validated['custom_values'] ?? null;
        unset($validated['custom_values']);

        $oldValues = $record->only(['title', 'description', 'contact_id', 'assigned_membership_id', 'value_amount', 'currency', 'expected_close_date']);
        $record->update($validated);

        if ($customValues !== null) {
            $pipeline = $record->pipeline;
            $customFields = CustomField::where('workspace_id', $wsId)
                ->where(function ($q) use ($pipeline) {
                    $q->where('pipeline_id', $pipeline->id)->orWhereNull('pipeline_id');
                })
                ->where('is_active', true)
                ->get()
                ->keyBy('field_key');

            $this->saveCustomValues($record, $customValues, $customFields, $wsId);
        }

        $diff = PipelineAuditService::diff($oldValues, $record->only(array_keys($oldValues)));
        if (!empty($diff)) {
            PipelineAuditService::log($wsId, 'updated', 'pipeline_record', $record->id, $oldValues, $diff);
        }

        $record->load(['stage:id,name,status_type', 'pipeline:id,name', 'assignedMembership.user:id,full_name', 'contact:id,name', 'customFieldValues.customField:id,field_key,label,field_type']);

        return response()->json(['data' => $this->fmt($record)]);
    }

    public function move(Request $request, string $id): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $wsId = $ctx->workspaceId();

        $membership = $ctx->membership();
        $scopedQuery = PipelineRecord::where('workspace_id', $wsId);
        if ($membership) {
            PipelineRecordScope::apply($scopedQuery, $membership);
        }
        $record = $scopedQuery->findOrFail($id);

        $validated = $request->validate(['stage_id' => 'required|uuid']);

        $stage = PipelineStage::where('pipeline_id', $record->pipeline_id)
            ->where('id', $validated['stage_id'])->first();

        if (! $stage) {
            return response()->json(['message' => 'Stage does not belong to this pipeline.'], 422);
        }

        $oldStatus  = $record->status;
        $oldStageId = $record->stage_id;

        // ── Atomic transition: stage move + commission calculation ────
        // Wraps the record update and commission generation in a single
        // DB transaction so a crash between the two cannot leave an
        // inconsistent state.
        $commissionResult = DB::transaction(function () use ($record, $stage, $oldStatus, $wsId, $oldStageId) {
            $update = ['stage_id' => $stage->id];

            if (in_array($stage->status_type, ['won', 'completed', 'lost', 'cancelled'], true)) {
                $update['status'] = $stage->status_type;
                $update['closed_at'] = now();
            } else {
                $update['status'] = 'open';
                $update['closed_at'] = null;
            }

            $record->update($update);

            PipelineAuditService::log($wsId, 'moved', 'pipeline_record', $record->id, [
                'stage_id' => $oldStageId,
            ], [
                'stage_id' => $stage->id, 'status' => $record->status,
            ]);

            // ── Commission auto-trigger on any real stage transition ──
            // Commissions are calculated whenever the record moves to a
            // different stage. The CommissionCalculationService decides
            // whether any rule matches the entered stage. Same-stage
            // moves are already prevented above (422). Leaving a stage
            // does NOT auto-cancel existing entries.
            if ($oldStageId !== $stage->id) {
                $commissionService = app(CommissionCalculationService::class);
                $entries = $commissionService->calculateForRecord($record);

                if (count($entries) > 0) {
                    PipelineAuditService::log($wsId, 'commission_generated', 'pipeline_record', $record->id, null, [
                        'entries_count' => count($entries),
                        'total_amount'  => array_sum(array_map(fn ($e) => (float) $e->commission_amount, $entries)),
                    ]);
                }

                return [
                    'action'        => 'calculated',
                    'created_count' => count($entries),
                ];
            }

            return null;
        });

        $record->load(['stage:id,name,status_type', 'pipeline:id,name']);

        $response = ['data' => $this->fmt($record)];
        if ($commissionResult !== null) {
            $response['commission'] = $commissionResult;
        }

        return response()->json($response);
    }

    public function destroy(Request $request, string $id): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $wsId = $ctx->workspaceId();

        $membership = $ctx->membership();
        $scopedQuery = PipelineRecord::where('workspace_id', $wsId);
        if ($membership) {
            PipelineRecordScope::apply($scopedQuery, $membership);
        }
        $record = $scopedQuery->findOrFail($id);

        PipelineAuditService::log($wsId, 'deleted', 'pipeline_record', $record->id, [
            'title' => $record->title, 'pipeline_id' => $record->pipeline_id,
            'stage_id' => $record->stage_id, 'value_amount' => $record->value_amount,
        ]);

        $record->delete();

        return response()->json(['message' => 'Record deleted.']);
    }

    // ═══════════════════════════════════════════════════════
    //  Helpers
    // ═══════════════════════════════════════════════════════

    private function fmt(PipelineRecord $r): array
    {
        $customValues = null;
        if ($r->relationLoaded('customFieldValues')) {
            $customValues = [];
            foreach ($r->customFieldValues as $v) {
                $field = $v->customField;
                $key = $field?->field_key ?? $v->custom_field_id;
                $customValues[$key] = [
                    'field_id'   => $v->custom_field_id,
                    'field_key'  => $field?->field_key,
                    'label'      => $field?->label,
                    'field_type' => $field?->field_type,
                    'value'      => $this->extractValue($v, $field?->field_type),
                ];
            }
        }

        return [
            'id'                      => $r->id,
            'pipeline_id'             => $r->pipeline_id,
            'pipeline'                => $r->relationLoaded('pipeline') ? ['id' => $r->pipeline->id, 'name' => $r->pipeline->name] : null,
            'stage_id'                => $r->stage_id,
            'stage'                   => $r->relationLoaded('stage') ? ['id' => $r->stage->id, 'name' => $r->stage->name, 'status_type' => $r->stage->status_type] : null,
            'title'                   => $r->title,
            'description'             => $r->description,
            'contact'                 => $r->relationLoaded('contact') && $r->contact ? ['id' => $r->contact->id, 'name' => $r->contact->name] : null,
            'assigned_to'             => $r->relationLoaded('assignedMembership') && $r->assignedMembership ? [
                'membership_id' => $r->assigned_membership_id,
                'full_name'     => $r->assignedMembership->user?->full_name,
            ] : null,
            'value_amount'            => $r->value_amount,
            'currency'                => $r->currency,
            'status'                  => $r->status,
            'expected_close_date'     => $r->expected_close_date?->toDateString(),
            'closed_at'               => $r->closed_at?->toIso8601String(),
            'custom_values'           => $customValues,
            'created_at'              => $r->created_at?->toIso8601String(),
            'updated_at'              => $r->updated_at?->toIso8601String(),
        ];
    }

    private function extractValue(CustomFieldValue $v, ?string $fieldType): mixed
    {
        return match ($fieldType) {
            'number', 'currency' => $v->value_number,
            'boolean'            => $v->value_boolean,
            'date'               => $v->value_date?->toDateString(),
            'select'             => $v->value_text,
            'multi_select'       => $v->value_json,
            default              => $v->value_text,
        };
    }

    private function saveCustomValues(PipelineRecord $record, array $values, $customFields, string $wsId): void
    {
        foreach ($values as $key => $val) {
            if (! $customFields->has($key)) continue;
            $field = $customFields[$key];

            $data = [
                'workspace_id'    => $wsId,
                'custom_field_id' => $field->id,
                'record_type'     => 'pipeline_record',
                'record_id'       => $record->id,
                'value_text'      => null,
                'value_number'    => null,
                'value_boolean'   => null,
                'value_date'      => null,
                'value_json'      => null,
            ];

            match ($field->field_type) {
                'number', 'currency' => $data['value_number'] = is_numeric($val) ? $val : null,
                'boolean'            => $data['value_boolean'] = filter_var($val, FILTER_VALIDATE_BOOLEAN, FILTER_NULL_ON_FAILURE),
                'date'               => $data['value_date'] = $val,
                'multi_select'       => $data['value_json'] = is_array($val) ? $val : [$val],
                default              => $data['value_text'] = is_string($val) ? $val : json_encode($val),
            };

            CustomFieldValue::updateOrCreate(
                ['custom_field_id' => $field->id, 'record_type' => 'pipeline_record', 'record_id' => $record->id],
                $data,
            );
        }
    }


    /**
     * Check if the authenticated user has a specific permission in the current workspace.
     */
    private function hasPermission(Request $request, string $permissionKey): bool
    {
        $user = $request->user();
        if (! $user) return false;

        $wsId = app(WorkspaceContextManager::class)->workspaceId();
        $membership = WorkspaceMembership::where('workspace_id', $wsId)
            ->where('user_id', $user->id)
            ->where('status', 'active')
            ->first();

        if (! $membership) return false;

        return app(PermissionResolver::class)->can($membership, $permissionKey);
    }

    /**
     * Validate that an assignee is active and eligible to own pipeline records.
     * Requires: pipelines.list AND pipeline_records.update AND pipeline_records.own.
     * Returns an error message string on failure, null on success.
     */
    private function validateAssignee(string $membershipId, string $wsId): ?string
    {
        $member = WorkspaceMembership::where('workspace_id', $wsId)
            ->where('id', $membershipId)
            ->where('status', 'active')
            ->first();

        if (! $member) {
            return 'Assigned member not found or inactive in this workspace.';
        }

        $resolver = app(PermissionResolver::class);
        if (! $resolver->can($member, 'pipelines.list')
            || ! $resolver->can($member, 'pipeline_records.update')
            || ! $resolver->can($member, 'pipeline_records.own')) {
            return 'The selected employee is not eligible to own pipeline records.';
        }

        return null;
    }

    /**
     * GET /pipeline-records/assignable-members
     *
     * Returns active workspace members who are eligible to own pipeline records.
     * Requires: pipelines.list AND pipeline_records.update AND pipeline_records.own.
     * Gated by pipeline_records.assign permission.
     *
     * Scope:
     * - manage_all: workspace-wide eligible salespeople
     * - manage_team: same-team eligible salespeople only
     * - otherwise: no list (should not reach here due to route guard)
     */
    public function assignableMembers(): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $wsId = $ctx->workspaceId();
        $currentMembership = $ctx->membership();

        $query = WorkspaceMembership::where('workspace_id', $wsId)
            ->where('status', 'active');

        // Scope the assignable list based on caller's visibility
        $resolver = app(PermissionResolver::class);
        if ($currentMembership && ! $resolver->can($currentMembership, 'pipeline_records.manage_all')) {
            if ($resolver->can($currentMembership, 'pipeline_records.manage_team')
                && $currentMembership->team_id !== null) {
                $query->where('team_id', $currentMembership->team_id);
            } else {
                // Can only assign to self (edge case — shouldn't normally reach here)
                $query->where('id', $currentMembership->id);
            }
        }

        $memberships = $query->with([
            'user:id,full_name',
            'membershipRoles.role:id,role_key,name',
            'department:id,name',
            'team:id,name',
        ])->get();

        $assignable = [];

        foreach ($memberships as $m) {
            if (! $resolver->can($m, 'pipelines.list')
                || ! $resolver->can($m, 'pipeline_records.update')
                || ! $resolver->can($m, 'pipeline_records.own')) {
                continue;
            }

            $roles = $m->membershipRoles;
            $primaryMr = $roles->firstWhere('is_primary', true) ?? $roles->first();

            $assignable[] = [
                'membership_id' => $m->id,
                'full_name'     => $m->user?->full_name,
                'role_name'     => $primaryMr?->role?->name,
                'role_key'      => $primaryMr?->role?->role_key,
                'department'    => $m->department?->name,
                'team'          => $m->team?->name,
            ];
        }

        return response()->json(['data' => $assignable]);
    }
}
