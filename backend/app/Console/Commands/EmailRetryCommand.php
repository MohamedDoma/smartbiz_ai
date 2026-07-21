<?php

namespace App\Console\Commands;

use App\Services\Email\EmailService;
use App\Services\WorkspaceContextManager;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

class EmailRetryCommand extends Command
{
    protected $signature = 'email:retry-failed';
    protected $description = 'Retry failed email deliveries that have not exceeded max retries';

    public function handle(EmailService $emailService, WorkspaceContextManager $workspaceContext): int
    {
        $workspaceIds = DB::table('workspaces')->pluck('id');
        $retried = 0;

        foreach ($workspaceIds as $workspaceId) {
            $retried += $workspaceContext->runSystemInWorkspace(
                (string) $workspaceId,
                fn (): int => $emailService->retryAllFailedForWorkspace((string) $workspaceId),
            );
        }

        $this->info("Retried failed emails: {$retried}");

        return self::SUCCESS;
    }
}
