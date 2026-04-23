<?php
namespace App\Events;

use Illuminate\Foundation\Events\Dispatchable;

class TrialStarted
{
    use Dispatchable;

    public function __construct(
        public string $workspaceId,
        public string $workspaceName,
        public string $trialEndDate,
        public ?string $ownerEmail = null,
    ) {}
}
