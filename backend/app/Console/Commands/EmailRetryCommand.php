<?php

namespace App\Console\Commands;

use App\Services\Email\EmailService;
use Illuminate\Console\Command;

class EmailRetryCommand extends Command
{
    protected $signature = 'email:retry-failed';
    protected $description = 'Retry failed email deliveries that have not exceeded max retries';

    public function handle(EmailService $emailService): int
    {
        $retried = $emailService->retryAllFailed();
        $this->info("Retried failed emails: {$retried}");
        return self::SUCCESS;
    }
}
