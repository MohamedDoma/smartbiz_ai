<?php

use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Schedule;

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');

// Billing automation
Schedule::command('billing:expire-trials')
    ->dailyAt('02:00')
    ->withoutOverlapping()
    ->onOneServer()
    ->appendOutputTo(storage_path('logs/billing-expire-trials.log'));

Schedule::command('billing:generate-snapshots')
    ->dailyAt('03:00')
    ->withoutOverlapping()
    ->onOneServer()
    ->appendOutputTo(storage_path('logs/billing-snapshots.log'));

Schedule::command('billing:sync-employees')
    ->hourly()
    ->withoutOverlapping()
    ->onOneServer()
    ->appendOutputTo(storage_path('logs/billing-sync-employees.log'));

Schedule::command('billing:reset-credits')
    ->dailyAt('01:00')
    ->withoutOverlapping()
    ->onOneServer()
    ->appendOutputTo(storage_path('logs/billing-reset-credits.log'));

Schedule::command('billing:send-notifications')
    ->dailyAt('09:00')
    ->withoutOverlapping()
    ->onOneServer()
    ->appendOutputTo(storage_path('logs/billing-notifications.log'));

// Email automation
Schedule::command('email:send-overdue-reminders')
    ->dailyAt('10:00')
    ->withoutOverlapping()
    ->onOneServer()
    ->appendOutputTo(storage_path('logs/email-overdue-reminders.log'));

Schedule::command('email:send-trial-ending')
    ->dailyAt('09:30')
    ->withoutOverlapping()
    ->onOneServer()
    ->appendOutputTo(storage_path('logs/email-trial-ending.log'));

Schedule::command('email:retry-failed')
    ->everyThirtyMinutes()
    ->withoutOverlapping()
    ->onOneServer()
    ->appendOutputTo(storage_path('logs/email-retry.log'));

// AI Advisor
Schedule::command('ai:run-advisor')
    ->dailyAt('06:00')
    ->withoutOverlapping()
    ->onOneServer()
    ->appendOutputTo(storage_path('logs/ai-advisor.log'));

// Database backup
Schedule::command('db:backup')
    ->dailyAt('04:00')
    ->withoutOverlapping()
    ->onOneServer()
    ->appendOutputTo(storage_path('logs/db-backup.log'));
