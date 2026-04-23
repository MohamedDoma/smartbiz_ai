<?php
namespace App\Events;

use Illuminate\Foundation\Events\Dispatchable;

class AiActionConfirmed
{
    use Dispatchable;

    public function __construct(
        public string $workspaceId,
        public string $userId,
        public string $actionId,
        public string $changeType,
        public string $summary,
    ) {}
}
