<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Cache;

class PlatformSystemHealthController extends Controller
{
    public function health(): JsonResponse
    {
        $checks = [];

        // API
        $checks['api'] = ['status' => 'ok', 'response_time_ms' => round(microtime(true) * 1000 - LARAVEL_START * 1000)];

        // Database
        try {
            $start = microtime(true);
            DB::select('SELECT 1');
            $checks['database'] = ['status' => 'ok', 'response_time_ms' => round((microtime(true) - $start) * 1000, 1)];
        } catch (\Throwable $e) {
            $checks['database'] = ['status' => 'error', 'message' => 'Connection failed'];
        }

        // Redis / Cache
        try {
            $start = microtime(true);
            Cache::put('_health_check', true, 5);
            $ok = Cache::get('_health_check');
            Cache::forget('_health_check');
            $checks['cache'] = ['status' => $ok ? 'ok' : 'degraded', 'response_time_ms' => round((microtime(true) - $start) * 1000, 1)];
        } catch (\Throwable $e) {
            $checks['cache'] = ['status' => 'unavailable', 'message' => 'Cache driver not configured'];
        }

        // Storage
        try {
            $path = storage_path('app/_health_check.tmp');
            file_put_contents($path, 'ok');
            $read = file_get_contents($path);
            @unlink($path);
            $checks['storage'] = ['status' => $read === 'ok' ? 'ok' : 'error'];
        } catch (\Throwable $e) {
            $checks['storage'] = ['status' => 'error', 'message' => 'Not writable'];
        }

        $allOk = collect($checks)->every(fn ($c) => $c['status'] === 'ok');

        return response()->json([
            'data' => [
                'overall' => $allOk ? 'healthy' : 'degraded',
                'checks' => $checks,
                'timestamp' => now()->toIso8601String(),
            ],
        ]);
    }
}
