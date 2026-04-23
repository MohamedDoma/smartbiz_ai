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

        // Email automation
        $schedule->command('email:send-overdue-reminders')
            ->dailyAt('10:00')
            ->withoutOverlapping()
            ->appendOutputTo(storage_path('logs/email-overdue-reminders.log'));

        $schedule->command('email:send-trial-ending')
            ->dailyAt('09:30')
            ->withoutOverlapping()
            ->appendOutputTo(storage_path('logs/email-trial-ending.log'));

        $schedule->command('email:retry-failed')
            ->everyThirtyMinutes()
            ->withoutOverlapping()
            ->appendOutputTo(storage_path('logs/email-retry.log'));

        // AI Advisor
        $schedule->command('ai:run-advisor')
            ->dailyAt('06:00')
            ->withoutOverlapping()
            ->appendOutputTo(storage_path('logs/ai-advisor.log'));

        // Database backup
        $schedule->command('db:backup')
            ->dailyAt('04:00')
            ->withoutOverlapping()
            ->appendOutputTo(storage_path('logs/db-backup.log'));
    }

    /**
     * Register the commands for the application.
     */
    protected function commands(): void
    {
        $this->load(__DIR__.'/Commands');
    }
}
