<?php

namespace App\Console\Commands;

use App\Services\BillingAutomationService;
use Illuminate\Console\Command;

class SyncEmployeeCounts extends Command
{
    protected $signature = 'billing:sync-employees';
    protected $description = 'Sync employee counts and overage for all active subscriptions';

    public function handle(BillingAutomationService $billing): int
    {
        $synced = $billing->syncAllEmployeeCounts();
        $this->info('Employee counts synced: ' . count($synced));
        return self::SUCCESS;
    }
}
