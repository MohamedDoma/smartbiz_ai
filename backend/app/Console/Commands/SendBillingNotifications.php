<?php

namespace App\Console\Commands;

use App\Services\BillingNotificationService;
use Illuminate\Console\Command;

class SendBillingNotifications extends Command
{
    protected $signature = 'billing:send-notifications';
    protected $description = 'Send billing-related notifications (trial expiring, credits low)';

    public function handle(BillingNotificationService $notifications): int
    {
        $trialExpiring = $notifications->processTrialExpiring();
        $this->info('Trial expiring notifications sent: ' . count($trialExpiring));

        $creditsLow = $notifications->processCreditsLow();
        $this->info('Credits low notifications sent: ' . count($creditsLow));

        return self::SUCCESS;
    }
}
