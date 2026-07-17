<?php

namespace App\Events;

use Illuminate\Foundation\Events\Dispatchable;

/**
 * Dispatched exactly once when onboarding finalization completes.
 *
 * Fired after the finalization transaction commits — never inside
 * the transaction boundary and never on idempotent repeat calls.
 */
class WorkspaceOnboardingCompleted
{
    use Dispatchable;

    public function __construct(
        public readonly string $workspaceId,
        public readonly string $provisioningRunId,
        public readonly string $finalizedBy,
        public readonly string $finalizedAt,
    ) {}
}
