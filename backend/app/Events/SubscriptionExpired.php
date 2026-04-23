<?php
namespace App\Events;

use Illuminate\Foundation\Events\Dispatchable;

class SubscriptionExpired
{
    use Dispatchable;

    public function __construct(
        public string $workspaceId,
        public string $workspaceName,
        public ?string $ownerEmail = null,
    ) {}
}
