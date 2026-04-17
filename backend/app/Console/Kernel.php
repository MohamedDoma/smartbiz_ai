<?php

namespace App\Console;

use Illuminate\Console\Scheduling\Schedule;
use Illuminate\Foundation\Console\Kernel as ConsoleKernel;

class Kernel extends ConsoleKernel
{
    /**
     * Define the application's command schedule.
     */
    protected function schedule(Schedule $schedule): void
    {
        // Billing automation — production schedule
        $schedule->command('billing:expire-trials')
            ->dailyAt('02:00')
            ->withoutOverlapping()
            ->appendOutputTo(storage_path('logs/billing-expire-trials.log'));

        $schedule->command('billing:generate-snapshots')
            ->dailyAt('03:00')
            ->withoutOverlapping()
            ->appendOutputTo(storage_path('logs/billing-snapshots.log'));

        $schedule->command('billing:sync-employees')
            ->hourly()
            ->withoutOverlapping()
            ->appendOutputTo(storage_path('logs/billing-sync-employees.log'));

        $schedule->command('billing:reset-credits')
            ->dailyAt('01:00')
            ->withoutOverlapping()
            ->appendOutputTo(storage_path('logs/billing-reset-credits.log'));

        $schedule->command('billing:send-notifications')
            ->dailyAt('09:00')
            ->withoutOverlapping()
            ->appendOutputTo(storage_path('logs/billing-notifications.log'));
    }

    /**
     * Register the commands for the application.
     */
    protected function commands(): void
    {
        $this->load(__DIR__.'/Commands');
    }
}
