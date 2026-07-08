<?php

namespace App\Services;

use App\Models\Contact;
use App\Models\OwnershipAssignment;
use App\Models\OwnershipTransferLog;
use App\Models\PipelineRecord;
use App\Models\WorkspaceMembership;

class OwnershipService
{
    /**
     * Assign ownership of an entity. Returns the assignment or null if already owned.
     */
    public function assign(
        string $wsId,
        string $entityType,
        string $entityId,
        string $ownerMembershipId,
        string $source = 'manual',
        ?string $assignedByMembershipId = null,
        ?string $notes = null,
    ): ?OwnershipAssignment {
        // Validate entity belongs to workspace
        $this->validateEntity($wsId, $entityType, $entityId);

        // Check existing active assignment
        $existing = OwnershipAssignment::where('workspace_id', $wsId)
            ->where('entity_type', $entityType)
            ->where('entity_id', $entityId)
            ->first();

        if ($existing) {
            return null; // already assigned — use transfer instead
        }

        // Auto-fill team/department from owner membership
        $owner = WorkspaceMembership::find($ownerMembershipId);

        return OwnershipAssignment::create([
            'workspace_id'              => $wsId,
            'entity_type'               => $entityType,
            'entity_id'                 => $entityId,
            'owner_membership_id'       => $ownerMembershipId,
            'team_id'                   => $owner?->team_id,
            'department_id'             => $owner?->department_id,
            'source'                    => $source,
            'status'                    => 'active',
            'assigned_by_membership_id' => $assignedByMembershipId,
            'assigned_at'               => now(),
            'notes'                     => $notes,
        ]);
    }

    /**
     * Transfer ownership to a new member. Creates transfer log.
     */
    public function transfer(
        string $wsId,
        string $assignmentId,
        string $toMembershipId,
        ?string $transferredByMembershipId = null,
        ?string $reason = null,
    ): OwnershipAssignment {
        $assignment = OwnershipAssignment::where('workspace_id', $wsId)->findOrFail($assignmentId);
        $fromId = $assignment->owner_membership_id;

        // Validate new owner belongs to workspace
        $newOwner = WorkspaceMembership::where('workspace_id', $wsId)
            ->where('id', $toMembershipId)->firstOrFail();

        // Create transfer log
        OwnershipTransferLog::create([
            'workspace_id'                => $wsId,
            'ownership_assignment_id'     => $assignment->id,
            'entity_type'                 => $assignment->entity_type,
            'entity_id'                   => $assignment->entity_id,
            'from_membership_id'          => $fromId,
            'to_membership_id'            => $toMembershipId,
            'transferred_by_membership_id' => $transferredByMembershipId,
            'reason'                      => $reason,
            'transferred_at'              => now(),
        ]);

        // Update assignment
        $assignment->update([
            'owner_membership_id' => $toMembershipId,
            'team_id'             => $newOwner->team_id,
            'department_id'       => $newOwner->department_id,
            'source'              => 'transfer',
        ]);

        return $assignment->fresh();
    }

    /**
     * Resolve the owner for an entity. Returns assignment or fallback from pipeline_record.
     */
    public function resolve(string $wsId, string $entityType, string $entityId): ?array
    {
        // Explicit ownership
        $assignment = OwnershipAssignment::where('workspace_id', $wsId)
            ->where('entity_type', $entityType)
            ->where('entity_id', $entityId)
            ->with(['ownerMembership.user:id,full_name'])
            ->first();

        if ($assignment) {
            return [
                'source'     => 'ownership_assignment',
                'assignment' => $assignment,
                'owner'      => [
                    'membership_id' => $assignment->owner_membership_id,
                    'full_name'     => $assignment->ownerMembership?->user?->full_name,
                    'team_id'       => $assignment->team_id,
                    'department_id' => $assignment->department_id,
                ],
            ];
        }

        // Fallback for pipeline_record
        if ($entityType === 'pipeline_record') {
            $record = PipelineRecord::where('workspace_id', $wsId)
                ->where('id', $entityId)
                ->with(['assignedMembership.user:id,full_name'])
                ->first();

            if ($record && $record->assigned_membership_id) {
                return [
                    'source'     => 'assigned_membership_fallback',
                    'assignment' => null,
                    'owner'      => [
                        'membership_id' => $record->assigned_membership_id,
                        'full_name'     => $record->assignedMembership?->user?->full_name,
                        'team_id'       => $record->assignedMembership?->team_id,
                        'department_id' => $record->assignedMembership?->department_id,
                    ],
                ];
            }
        }

        return null;
    }

    private function validateEntity(string $wsId, string $entityType, string $entityId): void
    {
        $exists = match ($entityType) {
            'contact'         => Contact::where('workspace_id', $wsId)->where('id', $entityId)->exists(),
            'pipeline_record' => PipelineRecord::where('workspace_id', $wsId)->where('id', $entityId)->exists(),
            default           => false,
        };

        if (!$exists) {
            abort(422, "Entity not found in this workspace.");
        }
    }
}
