<?php

namespace App\Services\Operations;

use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Redis;
use Throwable;

class OperationalHealthService
{
    public function __construct(private readonly BackupArchiveManager $archives)
    {
    }

    /**
     * @return array{status: string, version: string, checked_at: string}
     */
    public function publicSummary(): array
    {
        $checks = $this->coreChecks();
        $healthy = collect($checks)->every(fn (array $check): bool => $check['status'] === 'ok');

        return [
            'status' => $healthy ? 'healthy' : 'degraded',
            'version' => (string) config('app.version', '1.0.0'),
            'checked_at' => now()->utc()->toIso8601String(),
        ];
    }

    /**
     * @return array<string, mixed>
     */
    public function diagnostics(): array
    {
        $checks = array_merge($this->coreChecks(), [
            'queue' => $this->queueCheck(),
            'queue_worker' => $this->heartbeatCheck(
                'ops:queue:last_processed_at',
                (int) config('operations.queue.heartbeat_max_age_seconds', 180),
            ),
            'scheduler' => $this->heartbeatCheck(
                'ops:scheduler:last_seen_at',
                (int) config('operations.scheduler.heartbeat_max_age_seconds', 180),
            ),
            'database_backup' => $this->backupCheck('database'),
            'files_backup' => $this->backupCheck('files'),
            'disk' => $this->diskCheck(),
        ]);

        $statuses = collect($checks)->pluck('status');
        $status = $statuses->contains('error')
            ? 'unhealthy'
            : ($statuses->contains('warning') ? 'degraded' : 'healthy');

        return [
            'status' => $status,
            'version' => (string) config('app.version', '1.0.0'),
            'checked_at' => now()->utc()->toIso8601String(),
            'checks' => $checks,
        ];
    }

    /**
     * @return array<string, array<string, mixed>>
     */
    private function coreChecks(): array
    {
        return [
            'database' => $this->timedCheck(fn () => DB::select('SELECT 1')),
            'redis' => $this->timedCheck(fn () => Redis::ping()),
            'cache' => $this->timedCheck(function (): void {
                $key = 'ops:health:'.bin2hex(random_bytes(8));
                Cache::put($key, 'ok', 10);

                if (Cache::pull($key) !== 'ok') {
                    throw new \RuntimeException('Cache read/write verification failed.');
                }
            }),
        ];
    }

    /**
     * @return array<string, mixed>
     */
    private function timedCheck(callable $callback): array
    {
        $startedAt = microtime(true);

        try {
            $callback();

            return [
                'status' => 'ok',
                'latency_ms' => round((microtime(true) - $startedAt) * 1000, 2),
            ];
        } catch (Throwable) {
            return [
                'status' => 'error',
                'message' => 'Connectivity check failed.',
            ];
        }
    }

    /**
     * @return array<string, mixed>
     */
    private function queueCheck(): array
    {
        try {
            $connection = (string) config('queue.connections.redis.connection', 'default');
            $queue = (string) config('queue.connections.redis.queue', 'default');
            $pending = (int) Redis::connection($connection)->llen('queues:'.$queue);
            $failed = (int) DB::table('failed_jobs')->count();

            $status = 'ok';
            if ($pending >= (int) config('operations.queue.pending_critical', 500)
                || $failed >= (int) config('operations.queue.failed_critical', 10)) {
                $status = 'error';
            } elseif ($pending >= (int) config('operations.queue.pending_warning', 100)
                || $failed >= (int) config('operations.queue.failed_warning', 1)) {
                $status = 'warning';
            }

            return [
                'status' => $status,
                'pending_jobs' => $pending,
                'failed_jobs' => $failed,
            ];
        } catch (Throwable) {
            return [
                'status' => 'error',
                'message' => 'Queue diagnostics failed.',
            ];
        }
    }

    /**
     * @return array<string, mixed>
     */
    private function heartbeatCheck(string $cacheKey, int $maxAgeSeconds): array
    {
        $value = Cache::get($cacheKey);
        if (! is_string($value) || $value === '') {
            return [
                'status' => 'warning',
                'message' => 'Heartbeat has not been recorded yet.',
            ];
        }

        try {
            $ageSeconds = CarbonImmutable::parse($value)->diffInSeconds(now()->utc());
        } catch (Throwable) {
            return [
                'status' => 'error',
                'message' => 'Heartbeat value is invalid.',
            ];
        }

        return [
            'status' => $ageSeconds > $maxAgeSeconds ? 'error' : 'ok',
            'age_seconds' => $ageSeconds,
            'last_seen_at' => $value,
        ];
    }

    /**
     * @return array<string, mixed>
     */
    private function backupCheck(string $type): array
    {
        try {
            $latest = $this->archives->latest($type);
            if ($latest === null) {
                return [
                    'status' => 'warning',
                    'message' => 'No verified backup has been recorded yet.',
                ];
            }

            $createdAt = CarbonImmutable::createFromTimestampUTC((int) $latest['_timestamp']);
            $ageHours = round($createdAt->diffInMinutes(now()->utc()) / 60, 2);
            $maxAgeHours = (int) config('operations.backup.max_age_hours', 26);
            $archivePath = (string) $latest['_path'];
            $cacheKey = 'ops:backup:verified:'.sha1($archivePath.'|'.filemtime($archivePath));
            $checksumValid = Cache::remember(
                $cacheKey,
                now()->addHour(),
                fn (): bool => (bool) $this->archives->verify($archivePath),
            );

            return [
                'status' => $checksumValid && $ageHours <= $maxAgeHours ? 'ok' : 'error',
                'filename' => basename($archivePath),
                'age_hours' => $ageHours,
                'bytes' => (int) ($latest['bytes'] ?? 0),
                'checksum' => $checksumValid ? 'valid' : 'invalid',
            ];
        } catch (Throwable) {
            return [
                'status' => 'error',
                'message' => 'Backup verification failed.',
            ];
        }
    }

    /**
     * @return array<string, mixed>
     */
    private function diskCheck(): array
    {
        $path = (string) config('operations.disk.path', storage_path());
        $freeBytes = @disk_free_space($path);

        if ($freeBytes === false) {
            return [
                'status' => 'error',
                'message' => 'Disk free space cannot be read.',
            ];
        }

        $freeMb = round($freeBytes / 1024 / 1024, 1);
        $status = 'ok';

        if ($freeMb <= (int) config('operations.disk.critical_free_mb', 256)) {
            $status = 'error';
        } elseif ($freeMb <= (int) config('operations.disk.warning_free_mb', 1024)) {
            $status = 'warning';
        }

        return [
            'status' => $status,
            'free_mb' => $freeMb,
            'path' => $path,
        ];
    }
}
