<?php

namespace App\Services;

use App\Exceptions\WorkspaceAccessDeniedException;
use App\Exceptions\WorkspaceRequiredException;
use App\Models\User;
use App\Models\Workspace;
use App\Models\WorkspaceMembership;
use Illuminate\Support\Facades\DB;

/**
 * Manages the current workspace context for a request.
 *
 * Responsibilities:
 * - Resolves workspace from the request header
 * - Validates user membership in that workspace
 * - Executes SET app.workspace_id on the DB connection for RLS
 * - Provides accessors for the current workspace + membership
 */
class WorkspaceContextManager
{
    private ?Workspace $workspace = null;
    private ?WorkspaceMembership $membership = null;
    private bool $isResolved = false;

    /**
     * Resolve and activate the workspace context for a user.
     *
     * @throws WorkspaceRequiredException if workspaceId is null
     * @throws WorkspaceAccessDeniedException if workspace not found or user has no active membership
     */
    public function resolve(User $user, ?string $workspaceId): void
    {
        if ($workspaceId === null || $workspaceId === '') {
            throw new WorkspaceRequiredException();
        }

        $this->workspace = Workspace::find($workspaceId);

        if ($this->workspace === null) {
            throw new WorkspaceAccessDeniedException('Workspace not found.');
        }

        $this->membership = WorkspaceMembership::where('workspace_id', $workspaceId)
            ->where('user_id', $user->id)
            ->where('status', 'active')
            ->first();

        if ($this->membership === null) {
            throw new WorkspaceAccessDeniedException(
                'No active membership in this workspace.'
            );
        }

        // Set the PostgreSQL session variable for RLS enforcement.
        // NOTE: SET does not support parameterized queries in PostgreSQL,
        // so we use DB::unprepared with PDO::quote for safe escaping.
        $quoted = DB::getPdo()->quote($workspaceId);
        DB::unprepared("SET app.workspace_id = {$quoted}");

        $this->isResolved = true;
    }

    /**
     * Clear the workspace context (e.g. at end of request).
     */
    public function clear(): void
    {
        if ($this->isResolved) {
            // Reset the session variable so the connection can be safely returned to the pool.
            DB::unprepared("RESET app.workspace_id");
        }

        $this->workspace = null;
        $this->membership = null;
        $this->isResolved = false;
    }

    public function isResolved(): bool
    {
        return $this->isResolved;
    }

    public function workspace(): ?Workspace
    {
        return $this->workspace;
    }

    public function membership(): ?WorkspaceMembership
    {
        return $this->membership;
    }

    public function workspaceId(): ?string
    {
        return $this->workspace?->id;
    }

    public function membershipId(): ?string
    {
        return $this->membership?->id;
    }
}
