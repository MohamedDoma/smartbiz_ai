<?php

namespace App\Console\Commands;

use App\Services\Operations\OperationalHealthService;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Throwable;

class MonitorOperations extends Command
{
    protected $signature = 'ops:check
        {--json : Output the diagnostics as JSON}
        {--notify : Send a configured webhook alert when degraded or unhealthy}
        {--fail-on-warning : Return a failure exit code for warnings too}';

    protected $description = 'Check database, Redis, cache, queue, scheduler, backups, and disk capacity';

    public function handle(OperationalHealthService $health): int
    {
        $report = $health->diagnostics();

        if ($this->option('json')) {
            $this->line(json_encode($report, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR));
        } else {
            $rows = [];
            foreach ($report['checks'] as $name => $check) {
                $details = collect($check)
                    ->except('status')
                    ->map(fn (mixed $value, string $key): string => $key.'='.(is_scalar($value) ? (string) $value : json_encode($value)))
                    ->implode(', ');
                $rows[] = [$name, $check['status'], $details];
            }

            $this->table(['Check', 'Status', 'Details'], $rows);
            $this->line('Overall status: '.$report['status']);
        }

        Cache::forever('ops:monitor:last_report', $report);

        if ($report['status'] !== 'healthy') {
            Log::warning('Operational health is not healthy.', $report);

            if ($this->option('notify')) {
                $this->notify($report);
            }
        }

        if ($report['status'] === 'unhealthy') {
            return self::FAILURE;
        }

        if ($report['status'] === 'degraded' && $this->option('fail-on-warning')) {
            return self::FAILURE;
        }

        return self::SUCCESS;
    }

    /**
     * @param  array<string, mixed>  $report
     */
    private function notify(array $report): void
    {
        $url = trim((string) config('operations.alerts.webhook_url'));
        if ($url === '') {
            return;
        }

        $cooldownMinutes = max(1, (int) config('operations.alerts.cooldown_minutes', 30));
        $fingerprint = sha1(json_encode([
            $report['status'],
            collect($report['checks'])->map(fn (array $check): string => $check['status'])->all(),
        ], JSON_THROW_ON_ERROR));
        $cacheKey = 'ops:alert:'.$fingerprint;

        if (! Cache::add($cacheKey, true, now()->addMinutes($cooldownMinutes))) {
            return;
        }

        try {
            $response = Http::timeout((int) config('operations.alerts.timeout_seconds', 10))
                ->asJson()
                ->post($url, [
                    'service' => 'smartbiz',
                    'status' => $report['status'],
                    'checked_at' => $report['checked_at'],
                    'checks' => collect($report['checks'])
                        ->map(fn (array $check): string => $check['status'])
                        ->all(),
                    'text' => 'SmartBiz operational status: '.$report['status'],
                ]);

            if (! $response->successful()) {
                throw new \RuntimeException('Alert webhook returned HTTP '.$response->status());
            }
        } catch (Throwable $exception) {
            Cache::forget($cacheKey);
            Log::error('Operational alert delivery failed.', ['exception' => $exception]);
        }
    }
}
