<?php

namespace App\Services;

use App\Models\WorkspaceMembership;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Query\Builder as QueryBuilder;

/**
 * Centralized pipeline record visibility scope.
 *
 * Resolves which pipeline records a membership can see/modify
 * based purely on permissions — never on role names.
 *
 * Rules (in priority order):
 * 1. pipeline_records.manage_all → all records in the workspace
 * 2. pipeline_records.manage_team → records assigned to active members
 *    sharing the same non-null team_id as the current membership,
 *    plus the membership's own records
 * 3. Otherwise → only records where assigned_membership_id = current membership ID
 *
 * Unassigned (null) records are only visible to manage_all holders.
 */
class PipelineRecordScope
{
    /**
     * Apply visibility scope to an Eloquent query on PipelineRecord.
     *
     * The query must already be filtered by workspace_id.
     */
    public static function apply(Builder $query, WorkspaceMembership $membership): Builder
    {
        $resolver = app(PermissionResolver::class);

        // Level 1: manage_all sees everything
        if ($resolver->can($membership, 'pipeline_records.manage_all')) {
            return $query;
        }

        // Level 2: manage_team sees own team's records
        if ($resolver->can($membership, 'pipeline_records.manage_team')
            && $membership->team_id !== null) {
            $teamId = $membership->team_id;
            $wsId = $membership->workspace_id;

            return $query->where(function ($q) use ($membership, $teamId, $wsId) {
                $q->where('assigned_membership_id', $membership->id)
                  ->orWhereIn('assigned_membership_id', function ($sub) use ($teamId, $wsId) {
                      $sub->select('id')
                          ->from('workspace_memberships')
                          ->where('workspace_id', $wsId)
                          ->where('team_id', $teamId)
                          ->where('status', 'active');
                  });
            });
        }

        // Level 3: own records only
        return $query->where('assigned_membership_id', $membership->id);
    }

    /**
     * Apply visibility scope to a raw DB query builder on the pipeline_records table.
     *
     * Used by services that build queries with DB::table() instead of Eloquent.
     */
    public static function applyRaw(QueryBuilder $query, WorkspaceMembership $membership): QueryBuilder
    {
        $resolver = app(PermissionResolver::class);

        if ($resolver->can($membership, 'pipeline_records.manage_all')) {
            return $query;
        }

        if ($resolver->can($membership, 'pipeline_records.manage_team')
            && $membership->team_id !== null) {
            $teamId = $membership->team_id;
            $wsId = $membership->workspace_id;

            return $query->where(function ($q) use ($membership, $teamId, $wsId) {
                $q->where('pipeline_records.assigned_membership_id', $membership->id)
                  ->orWhereIn('pipeline_records.assigned_membership_id', function ($sub) use ($teamId, $wsId) {
                      $sub->select('id')
                          ->from('workspace_memberships')
                          ->where('workspace_id', $wsId)
                          ->where('team_id', $teamId)
                          ->where('status', 'active');
                  });
            });
        }

        return $query->where('pipeline_records.assigned_membership_id', $membership->id);
    }

    /**
     * Check if a membership can access a specific record.
     */
    public static function canAccess(WorkspaceMembership $membership, ?string $assignedMembershipId): bool
    {
        if ($assignedMembershipId === null) {
            // Unassigned records: only manage_all can see them
            return app(PermissionResolver::class)->can($membership, 'pipeline_records.manage_all');
        }

        $resolver = app(PermissionResolver::class);

        if ($resolver->can($membership, 'pipeline_records.manage_all')) {
            return true;
        }

        if ($assignedMembershipId === $membership->id) {
            return true;
        }

        if ($resolver->can($membership, 'pipeline_records.manage_team')
            && $membership->team_id !== null) {
            return WorkspaceMembership::where('id', $assignedMembershipId)
                ->where('workspace_id', $membership->workspace_id)
                ->where('team_id', $membership->team_id)
                ->where('status', 'active')
                ->exists();
        }

        return false;
    }
}
