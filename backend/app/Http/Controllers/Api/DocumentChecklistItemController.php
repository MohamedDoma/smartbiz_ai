<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\DocumentChecklist;
use App\Models\DocumentChecklistItem;
use App\Models\WorkspaceMembership;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

class DocumentChecklistItemController extends Controller
{
    private const ADMIN_ROLE_KEYS = ['owner', 'admin', 'general_manager', 'manager'];

    public function index(string $checklistId): JsonResponse
    {
        $wsId = app(WorkspaceContextManager::class)->workspaceId();
        DocumentChecklist::where('workspace_id', $wsId)->findOrFail($checklistId);

        $items = DocumentChecklistItem::where('document_checklist_id', $checklistId)
            ->where('workspace_id', $wsId)
            ->orderBy('sort_order')
            ->get();

        return response()->json(['data' => $items->map(fn ($i) => $this->fmt($i))]);
    }

    public function store(Request $request, string $checklistId): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $this->requireAdmin($ctx->workspaceId(), $request);
        DocumentChecklist::where('workspace_id', $ctx->workspaceId())->findOrFail($checklistId);

        $validated = $request->validate([
            'title'               => 'required|string|max:255',
            'description'         => 'nullable|string|max:1000',
            'is_required'         => 'nullable|boolean',
            'accepted_file_types' => 'nullable|array',
            'accepted_file_types.*' => 'string|max:20',
            'max_file_size_mb'    => 'nullable|integer|min:1|max:50',
            'sort_order'          => 'nullable|integer|min:0',
        ]);

        $item = DocumentChecklistItem::create([
            'workspace_id'          => $ctx->workspaceId(),
            'document_checklist_id' => $checklistId,
            'item_key'              => Str::slug($validated['title'], '_'),
            'title'                 => $validated['title'],
            'description'           => $validated['description'] ?? null,
            'is_required'           => $validated['is_required'] ?? true,
            'accepted_file_types'   => $validated['accepted_file_types'] ?? null,
            'max_file_size_mb'      => $validated['max_file_size_mb'] ?? 10,
            'sort_order'            => $validated['sort_order'] ?? 0,
            'is_active'             => true,
        ]);

        return response()->json(['data' => $this->fmt($item)], 201);
    }

    public function update(Request $request, string $id): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $this->requireAdmin($ctx->workspaceId(), $request);
        $item = DocumentChecklistItem::where('workspace_id', $ctx->workspaceId())->findOrFail($id);

        $validated = $request->validate([
            'title'               => 'sometimes|required|string|max:255',
            'description'         => 'nullable|string|max:1000',
            'is_required'         => 'nullable|boolean',
            'accepted_file_types' => 'nullable|array',
            'accepted_file_types.*' => 'string|max:20',
            'max_file_size_mb'    => 'nullable|integer|min:1|max:50',
            'is_active'           => 'sometimes|boolean',
            'sort_order'          => 'nullable|integer|min:0',
        ]);

        if (isset($validated['title'])) {
            $validated['item_key'] = Str::slug($validated['title'], '_');
        }

        $item->update($validated);
        return response()->json(['data' => $this->fmt($item->fresh())]);
    }

    public function destroy(Request $request, string $id): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $this->requireAdmin($ctx->workspaceId(), $request);
        $item = DocumentChecklistItem::where('workspace_id', $ctx->workspaceId())->findOrFail($id);

        $item->update(['is_active' => false]);
        return response()->json(['message' => 'Item deactivated.']);
    }

    private function fmt(DocumentChecklistItem $i): array
    {
        return [
            'id'                      => $i->id,
            'document_checklist_id'   => $i->document_checklist_id,
            'item_key'                => $i->item_key,
            'title'                   => $i->title,
            'description'             => $i->description,
            'is_required'             => $i->is_required,
            'accepted_file_types'     => $i->accepted_file_types,
            'max_file_size_mb'        => $i->max_file_size_mb,
            'sort_order'              => $i->sort_order,
            'is_active'               => $i->is_active,
            'created_at'              => $i->created_at?->toIso8601String(),
        ];
    }

    private function requireAdmin(string $wsId, Request $request): void
    {
        $user = $request->user();
        if ($user->is_super_admin) return;
        $membership = WorkspaceMembership::where('workspace_id', $wsId)
            ->where('user_id', $user->id)->where('status', 'active')->first();
        if (!$membership) abort(403, 'Not a member.');
        $roleKeys = $membership->membershipRoles()
            ->join('roles', 'roles.id', '=', 'membership_roles.role_id')
            ->pluck('roles.role_key')->toArray();
        if (empty(array_intersect($roleKeys, self::ADMIN_ROLE_KEYS))) abort(403, 'Insufficient permissions.');
    }
}
