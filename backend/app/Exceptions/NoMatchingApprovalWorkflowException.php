<?php

namespace App\Exceptions;

/**
 * Thrown by ApprovalEngine::submit() when no active approval workflow
 * matches the given entity type in the target workspace.
 *
 * This is the ONLY exception a caller may interpret as "no workflow
 * exists, direct action is permitted". All other exceptions from the
 * engine indicate internal failures that must be propagated.
 */
class NoMatchingApprovalWorkflowException extends \RuntimeException
{
    public readonly string $entityType;
    public readonly string $workspaceId;

    public function __construct(string $entityType, string $workspaceId)
    {
        $this->entityType  = $entityType;
        $this->workspaceId = $workspaceId;

        parent::__construct(
            "No active approval workflow found for entity type '{$entityType}' in workspace '{$workspaceId}'."
        );
    }
}
