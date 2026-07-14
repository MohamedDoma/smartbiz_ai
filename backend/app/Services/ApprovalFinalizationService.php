<?php

namespace App\Services;

use App\Models\ApprovalRequest;
use App\Models\AuditLog;
use App\Models\CommissionEntry;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * ApprovalFinalizationService — Domain-specific final-action executor.
 *
 * When the ApprovalEngine resolves a request to 'approved' or 'rejected',
 * this service applies the domain-specific side effects:
 *
 *  - commission_entry → update CommissionEntry status + timestamps
 *  - (extensible for invoice, expense, etc.)
 *
 * Design:
 *  - Called by ApprovalEngine::decide() after terminal state is reached
 *  - Each entity type has a registered handler method
 *  - Handlers run inside the engine's existing DB transaction
 *  - All actions are audited
 *  - Unknown entity types are gracefully skipped (no crash)
 */
class ApprovalFinalizationService
{
    /**
     * Registry of entity_type → handler method name.
     *
     * To add a new domain, add an entry here and implement the method.
     */
    private const HANDLERS = [
        'commission_entry' => 'finalizeCommissionEntry',
    ];

    /**
     * Execute the final action for a resolved approval request.
     *
     * @param ApprovalRequest $request  The resolved request (status = approved|rejected)
     * @return void
     */
    public function finalize(ApprovalRequest $request): void
    {
        if (!in_array($request->status, ['approved', 'rejected'], true)) {
            return; // Only handle terminal approval states
        }

        $handler = self::HANDLERS[$request->entity_type] ?? null;

        if ($handler === null) {
            Log::info("ApprovalFinalizationService: No handler registered for entity_type '{$request->entity_type}'. Skipping.");
            return;
        }

        if (!method_exists($this, $handler)) {
            Log::warning("ApprovalFinalizationService: Handler method '{$handler}' not found.");
            return;
        }

        $this->$handler($request);
    }

    // ═══════════════════════════════════════════════════════════
    //  Commission Entry Handler
    // ═══════════════════════════════════════════════════════════

    /**
     * Handle commission_entry approval/rejection.
     *
     * On approved:  CommissionEntry.status → 'approved', set approved_at
     * On rejected:  CommissionEntry.status → 'cancelled', append rejection note
     */
    private function finalizeCommissionEntry(ApprovalRequest $request): void
    {
        $entry = CommissionEntry::where('workspace_id', $request->workspace_id)
            ->where('id', $request->entity_id)
            ->lockForUpdate()
            ->first();

        if (!$entry) {
            Log::warning("ApprovalFinalizationService: CommissionEntry '{$request->entity_id}' not found in workspace '{$request->workspace_id}'.");
            return;
        }

        // Guard: only act on entries that are still pending
        if ($entry->status !== 'pending') {
            Log::info("ApprovalFinalizationService: CommissionEntry '{$entry->id}' status is '{$entry->status}', not 'pending'. Skipping finalization.");
            return;
        }

        $oldValues = ['status' => $entry->status];

        if ($request->status === 'approved') {
            $entry->update([
                'status'      => 'approved',
                'approved_at' => now(),
            ]);

            $this->audit(
                $request->workspace_id,
                null, // system action
                'commission_entry.approved_via_workflow',
                'commission_entry',
                $entry->id,
                $oldValues,
                [
                    'status'              => 'approved',
                    'approval_request_id' => $request->id,
                    'workflow_id'         => $request->workflow_id,
                ],
            );
        } elseif ($request->status === 'rejected') {
            $rejectionNote = $request->final_notes
                ? "Rejected via approval workflow: {$request->final_notes}"
                : 'Rejected via approval workflow';

            $entry->update([
                'status' => 'cancelled',
                'notes'  => $entry->notes
                    ? "{$entry->notes}\n{$rejectionNote}"
                    : $rejectionNote,
            ]);

            $this->audit(
                $request->workspace_id,
                null,
                'commission_entry.rejected_via_workflow',
                'commission_entry',
                $entry->id,
                $oldValues,
                [
                    'status'              => 'cancelled',
                    'approval_request_id' => $request->id,
                    'workflow_id'         => $request->workflow_id,
                    'rejection_notes'     => $request->final_notes,
                ],
            );
        }
    }

    // ═══════════════════════════════════════════════════════════
    //  Audit Helper
    // ═══════════════════════════════════════════════════════════

    private function audit(
        string $workspaceId,
        ?string $userId,
        string $action,
        string $entityType,
        string $entityId,
        ?array $oldValues,
        ?array $newValues,
    ): void {
        AuditLog::create([
            'workspace_id' => $workspaceId,
            'user_id'      => $userId,
            'action'       => $action,
            'entity_type'  => $entityType,
            'entity_id'    => $entityId,
            'old_values'   => $oldValues,
            'new_values'   => $newValues,
        ]);
    }
}
