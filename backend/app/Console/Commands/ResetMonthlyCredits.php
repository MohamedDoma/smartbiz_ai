<?php

namespace App\Console\Commands;

use App\Services\BillingAutomationService;
use Illuminate\Console\Command;

class ResetMonthlyCredits extends Command
{
    protected $signature = 'billing:reset-credits';
    protected $description = 'Monthly reset of AI credits for eligible subscriptions';

    public function handle(BillingAutomationService $billing): int
    {
        $reset = $billing->resetMonthlyCredits();
        $this->info('Monthly credit resets: ' . count($reset));
        return self::SUCCESS;
    }
}
