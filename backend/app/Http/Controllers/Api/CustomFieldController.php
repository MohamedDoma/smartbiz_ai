<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\CustomField;
use App\Models\Pipeline;
use App\Services\PipelineAuditService;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

class CustomFieldController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $wsId = app(WorkspaceContextManager::class)->workspaceId();

        $query = CustomField::where('workspace_id', $wsId)->orderBy('sort_order');

        if ($request->filled('pipeline_id')) {
            $query->where(function ($q) use ($request) {
                $q->where('pipeline_id', $request->input('pipeline_id'))
                  ->orWhereNull('pipeline_id');
            });
        }

        return response()->json([
            'data' => $query->get()->map(fn ($f) => $this->fmt($f)),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);

        $validated = $request->validate([
            'pipeline_id' => 'nullable|uuid',
            'label'       => 'required|string|max:255',
            'field_key'   => 'nullable|string|max:100',
            'field_type'  => 'required|string|in:' . implode(',', CustomField::ALLOWED_TYPES),
            'options'     => 'nullable|array',
            'options.*'   => 'string|max:255',
            'is_required' => 'nullable|boolean',
            'applies_to'  => 'nullable|string|max:50',
            'sort_order'  => 'nullable|integer|min:0',
        ]);

        // Validate pipeline belongs to workspace
        if (! empty($validated['pipeline_id'])) {
            if (! Pipeline::where('workspace_id', $ctx->workspaceId())->where('id', $validated['pipeline_id'])->exists()) {
                return response()->json(['message' => 'Pipeline not found in workspace.'], 422);
            }
        }

        // Options required for select types
        if (in_array($validated['field_type'], ['select', 'multi_select'], true)) {
            if (empty($validated['options']) || ! is_array($validated['options'])) {
                return response()->json([
                    'message' => 'Options are required for select/multi_select fields.',
                    'errors'  => ['options' => ['Required for this field type.']],
                ], 422);
            }
        }

        $fieldKey = $validated['field_key'] ?? Str::slug($validated['label'], '_');

        $field = CustomField::create([
            'workspace_id' => $ctx->workspaceId(),
            'pipeline_id'  => $validated['pipeline_id'] ?? null,
            'field_key'    => $fieldKey,
            'label'        => $validated['label'],
            'field_type'   => $validated['field_type'],
            'options'      => $validated['options'] ?? null,
            'is_required'  => $validated['is_required'] ?? false,
            'applies_to'   => $validated['applies_to'] ?? 'pipeline_record',
            'is_active'    => true,
            'sort_order'   => $validated['sort_order'] ?? 0,
        ]);

        PipelineAuditService::log($ctx->workspaceId(), 'created', 'custom_field', $field->id, null, [
            'label' => $field->label, 'field_type' => $field->field_type,
            'pipeline_id' => $field->pipeline_id,
        ]);

        return response()->json(['data' => $this->fmt($field)], 201);
    }

    public function show(string $id): JsonResponse
    {
        $wsId = app(WorkspaceContextManager::class)->workspaceId();
        $field = CustomField::where('workspace_id', $wsId)->findOrFail($id);
        return response()->json(['data' => $this->fmt($field)]);
    }

    public function update(Request $request, string $id): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $field = CustomField::where('workspace_id', $ctx->workspaceId())->findOrFail($id);

        $validated = $request->validate([
            'label'       => 'sometimes|required|string|max:255',
            'field_type'  => 'sometimes|required|string|in:' . implode(',', CustomField::ALLOWED_TYPES),
            'options'     => 'nullable|array',
            'is_required' => 'nullable|boolean',
            'is_active'   => 'sometimes|boolean',
            'sort_order'  => 'nullable|integer|min:0',
        ]);

        if (isset($validated['label'])) {
            $validated['field_key'] = Str::slug($validated['label'], '_');
        }

        $oldValues = $field->only(['label', 'field_type', 'options', 'is_required', 'is_active', 'sort_order']);
        $field->update($validated);
        $diff = PipelineAuditService::diff($oldValues, $field->only(array_keys($oldValues)));
        if (!empty($diff)) {
            PipelineAuditService::log($ctx->workspaceId(), 'updated', 'custom_field', $field->id, $oldValues, $diff);
        }
        return response()->json(['data' => $this->fmt($field->fresh())]);
    }

    public function destroy(Request $request, string $id): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $field = CustomField::where('workspace_id', $ctx->workspaceId())->findOrFail($id);

        $field->update(['is_active' => false]);

        PipelineAuditService::log($ctx->workspaceId(), 'deleted', 'custom_field', $field->id, [
            'label' => $field->label, 'field_type' => $field->field_type,
        ]);

        return response()->json(['message' => 'Custom field deactivated.']);
    }

    private function fmt(CustomField $f): array
    {
        return [
            'id'          => $f->id,
            'workspace_id' => $f->workspace_id,
            'pipeline_id' => $f->pipeline_id,
            'field_key'   => $f->field_key,
            'label'       => $f->label,
            'field_type'  => $f->field_type,
            'options'     => $f->options,
            'is_required' => $f->is_required,
            'applies_to'  => $f->applies_to,
            'is_active'   => $f->is_active,
            'sort_order'  => $f->sort_order,
            'created_at'  => $f->created_at?->toIso8601String(),
        ];
    }
}
