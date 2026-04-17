<?php

namespace App\Console\Commands;

use App\Services\BillingAutomationService;
use Illuminate\Console\Command;

class GenerateBillingSnapshots extends Command
{
    protected $signature = 'billing:generate-snapshots';
    protected $description = 'Generate billing snapshots for period-ending subscriptions';

    public function handle(BillingAutomationService $billing): int
    {
        $generated = $billing->generatePeriodSnapshots();
        $this->info('Billing snapshots generated: ' . count($generated));
        return self::SUCCESS;
    }
}
