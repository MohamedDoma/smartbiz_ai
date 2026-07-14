<?php

namespace App\Services;

use App\Models\WorkspaceMembership;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Query\Builder as QueryBuilder;

/**
 * Centralized contact visibility scope.
 *
 * Resolves which contacts a membership can see/modify
 * based purely on permissions — never on role names.
 *
 * Rules (in priority order):
 * 1. contacts.manage_all → all contacts in the workspace
 * 2. contacts.manage_team → contacts assigned to active members
 *    sharing the same non-null team_id as the current membership,
 *    plus the membership's own assigned contacts
 * 3. Otherwise → only contacts where assigned_membership_id = current membership ID
 *
 * Unassigned (null) contacts are only visible to contacts.manage_all.
 */
class ContactScope
{
    /**
     * Apply visibility scope to an Eloquent query on Contact.
     *
     * The query must already be filtered by workspace_id.
     */
    public static function apply(Builder $query, WorkspaceMembership $membership): Builder
    {
        $resolver = app(PermissionResolver::class);

        // Level 1: manage_all sees everything
        if ($resolver->can($membership, 'contacts.manage_all')) {
            return $query;
        }

        // Level 2: manage_team sees own team's contacts
        if ($resolver->can($membership, 'contacts.manage_team')
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

        // Level 3: own contacts only
        return $query->where('assigned_membership_id', $membership->id);
    }

    /**
     * Apply visibility scope to a raw DB query builder on the contacts table.
     */
    public static function applyRaw(QueryBuilder $query, WorkspaceMembership $membership): QueryBuilder
    {
        $resolver = app(PermissionResolver::class);

        if ($resolver->can($membership, 'contacts.manage_all')) {
            return $query;
        }

        if ($resolver->can($membership, 'contacts.manage_team')
            && $membership->team_id !== null) {
            $teamId = $membership->team_id;
            $wsId = $membership->workspace_id;

            return $query->where(function ($q) use ($membership, $teamId, $wsId) {
                $q->where('contacts.assigned_membership_id', $membership->id)
                  ->orWhereIn('contacts.assigned_membership_id', function ($sub) use ($teamId, $wsId) {
                      $sub->select('id')
                          ->from('workspace_memberships')
                          ->where('workspace_id', $wsId)
                          ->where('team_id', $teamId)
                          ->where('status', 'active');
                  });
            });
        }

        return $query->where('contacts.assigned_membership_id', $membership->id);
    }

    /**
     * Check if a membership can access a specific contact.
     */
    public static function canAccess(WorkspaceMembership $membership, ?string $assignedMembershipId): bool
    {
        if ($assignedMembershipId === null) {
            return app(PermissionResolver::class)->can($membership, 'contacts.manage_all');
        }

        $resolver = app(PermissionResolver::class);

        if ($resolver->can($membership, 'contacts.manage_all')) {
            return true;
        }

        if ($assignedMembershipId === $membership->id) {
            return true;
        }

        if ($resolver->can($membership, 'contacts.manage_team')
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
