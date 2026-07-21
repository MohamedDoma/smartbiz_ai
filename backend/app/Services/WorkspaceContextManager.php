<?php

namespace App\Services;

use App\Exceptions\WorkspaceAccessDeniedException;
use App\Exceptions\WorkspaceRequiredException;
use App\Models\User;
use App\Models\Workspace;
use App\Models\WorkspaceMembership;
use Closure;
use Illuminate\Support\Facades\DB;
use LogicException;

/**
 * Manages the current workspace context and the tenant database connection.
 *
 * Production uses two non-owner PostgreSQL identities:
 * - the default/control connection for authentication and platform metadata;
 * - the tenant connection for workspace data protected by PostgreSQL RLS.
 */
class WorkspaceContextManager
{
    private ?Workspace $workspace = null;
    private ?WorkspaceMembership $membership = null;
    private bool $isResolved = false;
    private ?string $previousConnection = null;
    private ?string $tenantConnection = null;
    private ?string $activeWorkspaceId = null;

    /**
     * Resolve and activate the workspace context for an authenticated user.
     *
     * Membership validation deliberately happens before switching to the tenant
     * connection because identity/control-plane tables are read through the
     * limited control role.
     *
     * @throws WorkspaceRequiredException
     * @throws WorkspaceAccessDeniedException
     */
    public function resolve(User $user, ?string $workspaceId): void
    {
        if ($workspaceId === null || $workspaceId === '') {
            throw new WorkspaceRequiredException();
        }

        $this->workspace = Workspace::find($workspaceId);

        if ($this->workspace === null) {
            $this->membership = null;
            throw new WorkspaceAccessDeniedException('Workspace not found.');
        }

        $this->membership = WorkspaceMembership::where('workspace_id', $workspaceId)
            ->where('user_id', $user->id)
            ->where('status', 'active')
            ->first();

        if ($this->membership === null) {
            $this->workspace = null;
            throw new WorkspaceAccessDeniedException(
                'No active membership in this workspace.'
            );
        }

        try {
            $this->activateTenantConnection($workspaceId);
        } catch (\Throwable $exception) {
            $this->workspace = null;
            $this->membership = null;
            throw $exception;
        }

        // Ensure relations loaded from the authenticated user, workspace, or
        // membership after this point use the tenant runtime connection too.
        $tenant = $this->tenantConnection;
        if ($tenant !== null) {
            $user->setConnection($tenant);
            $this->workspace?->setConnection($tenant);
            $this->membership?->setConnection($tenant);
        }
    }

    /**
     * Execute an internal/scheduled operation inside a strict tenant context.
     * This does not perform membership validation and must only be used by
     * trusted system code that already owns the workspace identifier.
     */
    public function runSystemInWorkspace(string $workspaceId, Closure $callback): mixed
    {
        if ($this->isResolved) {
            if ($this->workspaceId() !== null && $this->workspaceId() !== $workspaceId) {
                throw new LogicException('A different workspace context is already active.');
            }

            return $callback();
        }

        $this->activateTenantConnection($workspaceId);

        try {
            return $callback();
        } finally {
            $this->clear();
        }
    }

    /**
     * Clear RLS state and restore the connection that was active before the
     * request/job entered tenant mode.
     */
    public function clear(): void
    {
        $tenantConnection = $this->tenantConnection;

        try {
            if ($this->isResolved && $tenantConnection !== null) {
                DB::connection($tenantConnection)->selectOne(
                    "SELECT set_config('app.workspace_id', '', false) AS workspace_id",
                );
            }
        } catch (\Throwable $exception) {
            // A failed RESET must never leave a pooled/long-running connection
            // carrying the previous tenant identifier.
            if ($tenantConnection !== null) {
                DB::purge($tenantConnection);
            }

            throw $exception;
        } finally {
            if ($this->previousConnection !== null) {
                DB::setDefaultConnection($this->previousConnection);
            }

            $this->workspace = null;
            $this->membership = null;
            $this->isResolved = false;
            $this->previousConnection = null;
            $this->tenantConnection = null;
            $this->activeWorkspaceId = null;
        }
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
        return $this->workspace?->id ?? $this->activeWorkspaceId;
    }

    public function membershipId(): ?string
    {
        return $this->membership?->id;
    }

    private function activateTenantConnection(string $workspaceId): void
    {
        if ($this->isResolved) {
            throw new LogicException('Workspace context is already active.');
        }

        $previous = DB::getDefaultConnection();
        $tenant = (string) config('database.tenant_connection', 'pgsql_tenant');

        if ($tenant === '' || config("database.connections.{$tenant}") === null) {
            throw new LogicException('Tenant database connection is not configured.');
        }

        $this->previousConnection = $previous;
        $this->tenantConnection = $tenant;

        try {
            DB::setDefaultConnection($tenant);
            DB::connection($tenant)->selectOne(
                "SELECT set_config('app.workspace_id', ?, false) AS workspace_id",
                [$workspaceId],
            );
            $this->activeWorkspaceId = $workspaceId;
            $this->isResolved = true;
        } catch (\Throwable $exception) {
            DB::setDefaultConnection($previous);
            $this->previousConnection = null;
            $this->tenantConnection = null;
            $this->activeWorkspaceId = null;

            throw $exception;
        }
    }
}
