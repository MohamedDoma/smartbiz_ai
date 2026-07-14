<?php

namespace App\Services;

use App\Models\PipelineRecord;
use App\Models\WorkspaceMembership;

/**
 * Prevents duplicate open deals for the same contact in the same pipeline.
 *
 * Rules:
 * - Same workspace + same pipeline + same contact_id + status = 'open' → blocked
 * - Completed/won/lost/cancelled deals do NOT block new deals
 *
 * Returns:
 *   'blocked' => bool
 *   'code'    => 'open_deal_duplicate' | 'open_deal_exists_outside_scope' | null
 *   'record'  => PipelineRecord|null (only if visible)
 */
class OpenDealGuard
{
    /**
     * Check if there is an existing open deal for a contact in a pipeline.
     *
     * @param  string                   $wsId        Workspace ID
     * @param  string                   $pipelineId  Pipeline ID
     * @param  string                   $contactId   Contact ID
     * @param  WorkspaceMembership|null $membership  Caller's membership
     * @param  string|null              $excludeId   Record ID to exclude (for updates)
     * @return array{blocked: bool, code: string|null, record: PipelineRecord|null}
     */
    public function check(
        string $wsId,
        string $pipelineId,
        string $contactId,
        ?WorkspaceMembership $membership = null,
        ?string $excludeId = null,
    ): array {
        $existing = PipelineRecord::where('workspace_id', $wsId)
            ->where('pipeline_id', $pipelineId)
            ->where('contact_id', $contactId)
            ->where('status', 'open')
            ->when($excludeId, fn ($q) => $q->where('id', '!=', $excludeId))
            ->with(['stage:id,name,status_type'])
            ->first();

        if (! $existing) {
            return ['blocked' => false, 'code' => null, 'record' => null];
        }

        // Determine if the existing record is visible to the caller
        if ($membership && PipelineRecordScope::canAccess($membership, $existing->assigned_membership_id)) {
            return [
                'blocked' => true,
                'code'    => 'open_deal_duplicate',
                'record'  => $existing,
            ];
        }

        // Record exists but is outside the caller's scope
        return [
            'blocked' => true,
            'code'    => 'open_deal_exists_outside_scope',
            'record'  => null,
        ];
    }
}
