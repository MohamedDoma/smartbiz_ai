<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\CustomField;
use App\Models\CustomFieldValue;
use App\Models\Pipeline;
use App\Models\PipelineRecord;
use App\Models\PipelineStage;
use App\Models\WorkspaceMembership;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class PipelineRecordController extends Controller
{
    private const ADMIN_ROLE_KEYS = ['owner', 'admin', 'general_manager', 'manager'];

    public function index(Request $request): JsonResponse
    {
        $wsId = app(WorkspaceContextManager::class)->workspaceId();

        $query = PipelineRecord::where('workspace_id', $wsId)
            ->with(['stage:id,name,status_type', 'pipeline:id,name', 'assignedMembership.user:id,full_name', 'contact:id,name']);

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

        // Validate contact
        if (! empty($validated['contact_id'])) {
            $contactExists = \App\Models\Contact::where('workspace_id', $wsId)
                ->where('id', $validated['contact_id'])->exists();
            if (! $contactExists) {
                return response()->json(['message' => 'Contact not found in workspace.'], 422);
            }
        }

        // Validate assigned membership
        if (! empty($validated['assigned_membership_id'])) {
            $memberExists = WorkspaceMembership::where('workspace_id', $wsId)
                ->where('id', $validated['assigned_membership_id'])
                ->where('status', 'active')->exists();
            if (! $memberExists) {
                return response()->json(['message' => 'Assigned member not found.'], 422);
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
            $record = DB::transaction(function () use ($validated, $wsId, $customValues, $customFields) {
                $record = PipelineRecord::create([
                    'workspace_id'            => $wsId,
                    'pipeline_id'             => $validated['pipeline_id'],
                    'stage_id'                => $validated['stage_id'],
                    'title'                   => $validated['title'],
                    'description'             => $validated['description'] ?? null,
                    'contact_id'              => $validated['contact_id'] ?? null,
                    'assigned_membership_id'  => $validated['assigned_membership_id'] ?? null,
                    'value_amount'            => $validated['value_amount'] ?? null,
                    'currency'                => $validated['currency'] ?? null,
                    'status'                  => 'open',
                    'expected_close_date'     => $validated['expected_close_date'] ?? null,
                ]);

                $this->saveCustomValues($record, $customValues, $customFields, $wsId);

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
        $wsId = app(WorkspaceContextManager::class)->workspaceId();

        $record = PipelineRecord::where('workspace_id', $wsId)
            ->with(['stage:id,name,status_type', 'pipeline:id,name', 'assignedMembership.user:id,full_name', 'contact:id,name', 'customFieldValues.customField:id,field_key,label,field_type'])
            ->findOrFail($id);

        return response()->json(['data' => $this->fmt($record)]);
    }

    public function update(Request $request, string $id): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $wsId = $ctx->workspaceId();

        $record = PipelineRecord::where('workspace_id', $wsId)->findOrFail($id);

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

        $customValues = $validated['custom_values'] ?? null;
        unset($validated['custom_values']);

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

        $record->load(['stage:id,name,status_type', 'pipeline:id,name', 'assignedMembership.user:id,full_name', 'contact:id,name', 'customFieldValues.customField:id,field_key,label,field_type']);

        return response()->json(['data' => $this->fmt($record)]);
    }

    public function move(Request $request, string $id): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $wsId = $ctx->workspaceId();

        $record = PipelineRecord::where('workspace_id', $wsId)->findOrFail($id);

        $validated = $request->validate(['stage_id' => 'required|uuid']);

        $stage = PipelineStage::where('pipeline_id', $record->pipeline_id)
            ->where('id', $validated['stage_id'])->first();

        if (! $stage) {
            return response()->json(['message' => 'Stage does not belong to this pipeline.'], 422);
        }

        $update = ['stage_id' => $stage->id];

        if (in_array($stage->status_type, ['won', 'completed', 'lost', 'cancelled'], true)) {
            $update['status'] = $stage->status_type;
            $update['closed_at'] = now();
        } else {
            $update['status'] = 'open';
            $update['closed_at'] = null;
        }

        $record->update($update);

        $record->load(['stage:id,name,status_type', 'pipeline:id,name']);

        return response()->json(['data' => $this->fmt($record)]);
    }

    public function destroy(Request $request, string $id): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $this->requireAdmin($ctx->workspaceId(), $request);

        $record = PipelineRecord::where('workspace_id', $ctx->workspaceId())->findOrFail($id);
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

    private function requireAdmin(string $wsId, Request $request): void
    {
        $user = $request->user();
        if ($user->is_super_admin) return;
        $membership = WorkspaceMembership::where('workspace_id', $wsId)
            ->where('user_id', $user->id)->where('status', 'active')->first();
        if (! $membership) abort(403, 'Not a member.');
        $roleKeys = $membership->membershipRoles()
            ->join('roles', 'roles.id', '=', 'membership_roles.role_id')
            ->pluck('roles.role_key')->toArray();
        if (empty(array_intersect($roleKeys, self::ADMIN_ROLE_KEYS))) abort(403, 'Insufficient permissions.');
    }
}
