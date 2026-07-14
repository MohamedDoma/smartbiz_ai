<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\DocumentChecklist;
use App\Models\DocumentChecklistItem;
use App\Models\PipelineRecord;
use App\Models\RecordDocument;
use App\Models\WorkspaceMembership;
use App\Services\PipelineAuditService;
use App\Services\PipelineRecordScope;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;

class RecordDocumentController extends Controller
{
    public function index(string $recordId): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $wsId = $ctx->workspaceId();
        $membership = $ctx->membership();

        $query = PipelineRecord::where('workspace_id', $wsId);
        if ($membership) {
            PipelineRecordScope::apply($query, $membership);
        }
        $query->findOrFail($recordId);

        $docs = RecordDocument::where('pipeline_record_id', $recordId)
            ->where('workspace_id', $wsId)
            ->with(['checklistItem:id,title,is_required', 'uploadedByMembership.user:id,full_name'])
            ->orderByDesc('uploaded_at')
            ->get();

        return response()->json(['data' => $docs->map(fn ($d) => $this->fmt($d))]);
    }

    public function store(Request $request, string $recordId): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $wsId = $ctx->workspaceId();
        $membership = $ctx->membership();

        $query = PipelineRecord::where('workspace_id', $wsId);
        if ($membership) {
            PipelineRecordScope::apply($query, $membership);
        }
        $record = $query->findOrFail($recordId);

        // Resolve membership for uploader
        $user = $request->user();
        $membership = WorkspaceMembership::where('workspace_id', $wsId)
            ->where('user_id', $user->id)->where('status', 'active')->first();

        $validated = $request->validate([
            'document_checklist_item_id' => 'nullable|uuid',
            'title'                      => 'nullable|string|max:255',
            'status'                     => 'nullable|string|in:uploaded,provided,waived',
            'external_reference'         => 'nullable|string|max:500',
            'notes'                      => 'nullable|string|max:2000',
            'file'                       => 'nullable|file|max:51200', // 50MB max
        ]);

        // Validate checklist item
        $checklistItem = null;
        if (!empty($validated['document_checklist_item_id'])) {
            $checklistItem = DocumentChecklistItem::where('workspace_id', $wsId)
                ->where('id', $validated['document_checklist_item_id'])->first();
            if (!$checklistItem) {
                return response()->json(['message' => 'Checklist item not found.'], 422);
            }
        }

        // Resolve title
        $title = $validated['title'] ?? $checklistItem?->title ?? 'Document';

        // Handle file upload
        $filePath = null;
        $originalName = null;
        $mimeType = null;
        $fileSize = null;
        $status = $validated['status'] ?? 'provided';

        if ($request->hasFile('file')) {
            $file = $request->file('file');

            // Validate file type against checklist item constraints
            if ($checklistItem && !empty($checklistItem->accepted_file_types)) {
                $ext = strtolower($file->getClientOriginalExtension());
                if (!in_array($ext, $checklistItem->accepted_file_types, true)) {
                    return response()->json([
                        'message' => "File type '{$ext}' not accepted. Allowed: " . implode(', ', $checklistItem->accepted_file_types),
                    ], 422);
                }
            }

            // Validate file size against checklist item constraints
            $maxMb = $checklistItem?->max_file_size_mb ?? 10;
            if ($file->getSize() > $maxMb * 1024 * 1024) {
                return response()->json(['message' => "File size exceeds {$maxMb}MB limit."], 422);
            }

            $storagePath = "workspace-documents/{$wsId}/pipeline-records/{$recordId}";
            $filePath = $file->store($storagePath, 'local');
            $originalName = $file->getClientOriginalName();
            $mimeType = $file->getMimeType();
            $fileSize = $file->getSize();
            $status = 'uploaded';
        }

        if (!$title || $title === '') {
            return response()->json(['message' => 'Title is required.'], 422);
        }

        $doc = RecordDocument::create([
            'workspace_id'                => $wsId,
            'pipeline_record_id'          => $recordId,
            'document_checklist_item_id'  => $checklistItem?->id,
            'title'                       => $title,
            'status'                      => $status,
            'file_path'                   => $filePath,
            'original_filename'           => $originalName,
            'mime_type'                   => $mimeType,
            'file_size'                   => $fileSize,
            'external_reference'          => $validated['external_reference'] ?? null,
            'notes'                       => $validated['notes'] ?? null,
            'uploaded_by_membership_id'   => $membership?->id,
            'uploaded_at'                 => now(),
        ]);

        $doc->load(['checklistItem:id,title,is_required', 'uploadedByMembership.user:id,full_name']);

        PipelineAuditService::log($wsId, 'created', 'record_document', $doc->id, null, [
            'title' => $doc->title, 'pipeline_record_id' => $recordId,
            'original_filename' => $doc->original_filename, 'status' => $doc->status,
        ]);

        return response()->json(['data' => $this->fmt($doc)], 201);
    }

    public function documentStatus(string $recordId): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $wsId = $ctx->workspaceId();
        $membership = $ctx->membership();

        $query = PipelineRecord::where('workspace_id', $wsId);
        if ($membership) {
            PipelineRecordScope::apply($query, $membership);
        }
        $record = $query->findOrFail($recordId);

        // Get applicable checklists (pipeline-level, stage-level, or global)
        $checklists = DocumentChecklist::where('workspace_id', $wsId)
            ->where('is_active', true)
            ->where(function ($q) use ($record) {
                $q->where(function ($q2) use ($record) {
                    $q2->where('pipeline_id', $record->pipeline_id)
                       ->where(function ($q3) use ($record) {
                           $q3->where('stage_id', $record->stage_id)->orWhereNull('stage_id');
                       });
                })->orWhere(function ($q2) {
                    $q2->whereNull('pipeline_id')->whereNull('stage_id');
                });
            })
            ->with(['items' => fn ($q) => $q->where('is_active', true)->orderBy('sort_order')])
            ->get();

        // Get uploaded docs for this record
        $uploadedDocs = RecordDocument::where('pipeline_record_id', $recordId)
            ->where('workspace_id', $wsId)
            ->get()
            ->keyBy('document_checklist_item_id');

        $items = [];
        $requiredCount = 0;
        $completedCount = 0;
        $missingCount = 0;
        $optionalCount = 0;

        foreach ($checklists as $checklist) {
            foreach ($checklist->items as $item) {
                $doc = $uploadedDocs->get($item->id);
                $itemStatus = $doc ? $doc->status : 'missing';

                if ($item->is_required) {
                    $requiredCount++;
                    if ($doc && in_array($doc->status, ['uploaded', 'provided', 'waived'], true)) {
                        $completedCount++;
                    } else {
                        $missingCount++;
                    }
                } else {
                    $optionalCount++;
                }

                $items[] = [
                    'item_id'     => $item->id,
                    'title'       => $item->title,
                    'description' => $item->description,
                    'is_required' => $item->is_required,
                    'checklist'   => $checklist->name,
                    'status'      => $itemStatus,
                    'document'    => $doc ? $this->fmt($doc) : null,
                ];
            }
        }

        return response()->json([
            'data' => [
                'record_id'       => $record->id,
                'record_title'    => $record->title,
                'required_count'  => $requiredCount,
                'completed_count' => $completedCount,
                'missing_count'   => $missingCount,
                'optional_count'  => $optionalCount,
                'items'           => $items,
            ],
        ]);
    }

    public function destroy(Request $request, string $id): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);

        $doc = RecordDocument::where('workspace_id', $ctx->workspaceId())->findOrFail($id);

        PipelineAuditService::log($ctx->workspaceId(), 'deleted', 'record_document', $doc->id, [
            'title' => $doc->title, 'pipeline_record_id' => $doc->pipeline_record_id,
            'original_filename' => $doc->original_filename,
        ]);

        // Delete file if exists
        if ($doc->file_path && Storage::disk('local')->exists($doc->file_path)) {
            Storage::disk('local')->delete($doc->file_path);
        }

        $doc->delete();

        return response()->json(['message' => 'Document deleted.']);
    }

    private function fmt(RecordDocument $d): array
    {
        return [
            'id'                          => $d->id,
            'pipeline_record_id'          => $d->pipeline_record_id,
            'document_checklist_item_id'  => $d->document_checklist_item_id,
            'checklist_item'              => $d->relationLoaded('checklistItem') && $d->checklistItem
                ? ['id' => $d->checklistItem->id, 'title' => $d->checklistItem->title, 'is_required' => $d->checklistItem->is_required]
                : null,
            'title'                       => $d->title,
            'status'                      => $d->status,
            'original_filename'           => $d->original_filename,
            'mime_type'                   => $d->mime_type,
            'file_size'                   => $d->file_size,
            'external_reference'          => $d->external_reference,
            'notes'                       => $d->notes,
            'uploaded_by'                 => $d->relationLoaded('uploadedByMembership') && $d->uploadedByMembership
                ? ['membership_id' => $d->uploaded_by_membership_id, 'full_name' => $d->uploadedByMembership->user?->full_name]
                : null,
            'uploaded_at'                 => $d->uploaded_at?->toIso8601String(),
            'created_at'                  => $d->created_at?->toIso8601String(),
        ];
    }
}
