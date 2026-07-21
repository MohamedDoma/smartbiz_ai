<?php

return [
    'backup' => [
        'path' => env('BACKUP_PATH', storage_path('backups')),
        'retention_days' => (int) env('BACKUP_RETENTION_DAYS', 30),
        'max_age_hours' => (int) env('BACKUP_MAX_AGE_HOURS', 26),
        'minimum_free_mb' => (int) env('BACKUP_MIN_FREE_MB', 1024),
        'timeout_seconds' => (int) env('BACKUP_TIMEOUT_SECONDS', 1800),
        'verify_archive' => filter_var(env('BACKUP_VERIFY_ARCHIVE', true), FILTER_VALIDATE_BOOL),
        'mirror_disk' => env('BACKUP_MIRROR_DISK'),
        'mirror_prefix' => trim((string) env('BACKUP_MIRROR_PREFIX', 'smartbiz'), '/'),
        'mirror_required' => filter_var(env('BACKUP_MIRROR_REQUIRED', false), FILTER_VALIDATE_BOOL),
    ],

    'queue' => [
        'pending_warning' => (int) env('OPS_QUEUE_PENDING_WARNING', 100),
        'pending_critical' => (int) env('OPS_QUEUE_PENDING_CRITICAL', 500),
        'failed_warning' => (int) env('OPS_QUEUE_FAILED_WARNING', 1),
        'failed_critical' => (int) env('OPS_QUEUE_FAILED_CRITICAL', 10),
        'heartbeat_max_age_seconds' => (int) env('OPS_QUEUE_HEARTBEAT_MAX_AGE', 180),
    ],

    'scheduler' => [
        'heartbeat_max_age_seconds' => (int) env('OPS_SCHEDULER_HEARTBEAT_MAX_AGE', 180),
    ],

    'disk' => [
        'path' => env('OPS_DISK_PATH', storage_path()),
        'warning_free_mb' => (int) env('OPS_DISK_WARNING_FREE_MB', 1024),
        'critical_free_mb' => (int) env('OPS_DISK_CRITICAL_FREE_MB', 256),
    ],

    'alerts' => [
        'webhook_url' => env('OPS_ALERT_WEBHOOK_URL'),
        'timeout_seconds' => (int) env('OPS_ALERT_TIMEOUT_SECONDS', 10),
        'cooldown_minutes' => (int) env('OPS_ALERT_COOLDOWN_MINUTES', 30),
    ],
];
