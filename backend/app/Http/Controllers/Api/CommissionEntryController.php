<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\CommissionEntry;
use App\Models\PipelineRecord;
use App\Models\WorkspaceMembership;
use App\Services\CommissionCalculationService;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class CommissionEntryController extends Controller
{
    private const ADMIN_ROLE_KEYS = ['owner', 'admin', 'general_manager', 'manager'];

    public function index(Request $request): JsonResponse
    {
        $wsId = app(WorkspaceContextManager::class)->workspaceId();
        $q = CommissionEntry::where('workspace_id', $wsId)
            ->with([
                'plan:id,name',
                'pipelineRecord:id,title,value_amount,currency',
                'recipientMembership.user:id,full_name',
                'sourceMembership.user:id,full_name',
            ])
            ->orderByDesc('calculated_at');

        if ($request->filled('status')) {
            $q->where('status', $request->input('status'));
        }
        if ($request->filled('recipient_membership_id')) {
            $q->where('recipient_membership_id', $request->input('recipient_membership_id'));
        }
        if ($request->filled('pipeline_record_id')) {
            $q->where('pipeline_record_id', $request->input('pipeline_record_id'));
        }

        return response()->json(['data' => $q->get()->map(fn ($e) => $this->fmt($e))]);
    }

    public function show(string $id): JsonResponse
    {
        $wsId = app(WorkspaceContextManager::class)->workspaceId();
        $entry = CommissionEntry::where('workspace_id', $wsId)
            ->with([
                'plan:id,name', 'rule',
                'pipelineRecord:id,title,value_amount,currency',
                'recipientMembership.user:id,full_name',
                'sourceMembership.user:id,full_name',
            ])
            ->findOrFail($id);

        return response()->json(['data' => $this->fmt($entry)]);
    }

    public function calculateForRecord(Request $request, string $recordId): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $this->requireAdmin($ctx->workspaceId(), $request);

        $record = PipelineRecord::where('workspace_id', $ctx->workspaceId())->findOrFail($recordId);

        $service = new CommissionCalculationService();
        $entries = $service->calculateForRecord($record);

        foreach ($entries as $e) {
            $e->load([
                'plan:id,name',
                'pipelineRecord:id,title,value_amount,currency',
                'recipientMembership.user:id,full_name',
            ]);
        }

        return response()->json([
            'data' => [
                'created_count' => count($entries),
                'entries'       => array_map(fn ($e) => $this->fmt($e), $entries),
            ],
        ], 201);
    }

    public function markApproved(Request $request, string $id): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $this->requireAdmin($ctx->workspaceId(), $request);

        $entry = CommissionEntry::where('workspace_id', $ctx->workspaceId())->findOrFail($id);

        if ($entry->status !== 'pending') {
            return response()->json(['message' => "Cannot approve entry with status '{$entry->status}'."], 409);
        }

        $entry->update(['status' => 'approved', 'approved_at' => now()]);
        return response()->json(['data' => $this->fmt($entry->fresh())]);
    }

    public function markPaid(Request $request, string $id): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $this->requireAdmin($ctx->workspaceId(), $request);

        $entry = CommissionEntry::where('workspace_id', $ctx->workspaceId())->findOrFail($id);

        if (!in_array($entry->status, ['pending', 'approved'], true)) {
            return response()->json(['message' => "Cannot mark paid entry with status '{$entry->status}'."], 409);
        }

        $entry->update(['status' => 'paid', 'paid_at' => now()]);
        return response()->json(['data' => $this->fmt($entry->fresh())]);
    }

    public function cancel(Request $request, string $id): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $this->requireAdmin($ctx->workspaceId(), $request);

        $entry = CommissionEntry::where('workspace_id', $ctx->workspaceId())->findOrFail($id);

        if ($entry->status === 'paid') {
            return response()->json(['message' => 'Cannot cancel a paid commission entry.'], 409);
        }

        $entry->update(['status' => 'cancelled']);
        return response()->json(['data' => $this->fmt($entry->fresh())]);
    }

    private function fmt(CommissionEntry $e): array
    {
        return [
            'id'                      => $e->id,
            'commission_plan_id'      => $e->commission_plan_id,
            'plan'                    => $e->relationLoaded('plan') && $e->plan
                ? ['id' => $e->plan->id, 'name' => $e->plan->name] : null,
            'commission_rule_id'      => $e->commission_rule_id,
            'pipeline_record_id'      => $e->pipeline_record_id,
            'record'                  => $e->relationLoaded('pipelineRecord') && $e->pipelineRecord
                ? ['id' => $e->pipelineRecord->id, 'title' => $e->pipelineRecord->title,
                   'value_amount' => $e->pipelineRecord->value_amount, 'currency' => $e->pipelineRecord->currency]
                : null,
            'recipient_membership_id' => $e->recipient_membership_id,
            'recipient'               => $e->relationLoaded('recipientMembership') && $e->recipientMembership
                ? ['membership_id' => $e->recipient_membership_id,
                   'full_name' => $e->recipientMembership->user?->full_name]
                : null,
            'source_membership_id'    => $e->source_membership_id,
            'source'                  => $e->relationLoaded('sourceMembership') && $e->sourceMembership
                ? ['membership_id' => $e->source_membership_id,
                   'full_name' => $e->sourceMembership->user?->full_name]
                : null,
            'base_amount'             => $e->base_amount,
            'commission_amount'       => $e->commission_amount,
            'currency'                => $e->currency,
            'calculation_type'        => $e->calculation_type,
            'percentage_rate'         => $e->percentage_rate,
            'fixed_amount'            => $e->fixed_amount,
            'status'                  => $e->status,
            'calculated_at'           => $e->calculated_at?->toIso8601String(),
            'approved_at'             => $e->approved_at?->toIso8601String(),
            'paid_at'                 => $e->paid_at?->toIso8601String(),
            'notes'                   => $e->notes,
            'created_at'              => $e->created_at?->toIso8601String(),
        ];
    }

    private function requireAdmin(string $wsId, Request $request): void
    {
        $user = $request->user();
        if ($user->is_super_admin) return;
        $m = WorkspaceMembership::where('workspace_id', $wsId)
            ->where('user_id', $user->id)->where('status', 'active')->first();
        if (!$m) abort(403, 'Not a member.');
        $keys = $m->membershipRoles()
            ->join('roles', 'roles.id', '=', 'membership_roles.role_id')
            ->pluck('roles.role_key')->toArray();
        if (empty(array_intersect($keys, self::ADMIN_ROLE_KEYS))) abort(403, 'Insufficient permissions.');
    }
}
