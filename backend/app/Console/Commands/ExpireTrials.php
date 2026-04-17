<?php

namespace App\Console\Commands;

use App\Services\BillingAutomationService;
use Illuminate\Console\Command;

class ExpireTrials extends Command
{
    protected $signature = 'billing:expire-trials';
    protected $description = 'Suspend expired trial subscriptions';

    public function handle(BillingAutomationService $billing): int
    {
        $processed = $billing->processExpiredTrials();
        $this->info('Expired trials processed: ' . count($processed));
        return self::SUCCESS;
    }
}
