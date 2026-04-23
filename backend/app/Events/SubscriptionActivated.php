<?php
namespace App\Events;

use Illuminate\Foundation\Events\Dispatchable;

class SubscriptionActivated
{
    use Dispatchable;

    public function __construct(
        public string $workspaceId,
        public string $workspaceName,
        public string $planName,
        public ?string $ownerEmail = null,
    ) {}
}
