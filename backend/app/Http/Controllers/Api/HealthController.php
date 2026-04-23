<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Redis;

/**
 * Deep health check for monitoring and load balancers.
 * Checks DB, Redis, and queue connectivity.
 */
class HealthController extends Controller
{
    public function __invoke(): JsonResponse
    {
        $checks = [];
        $healthy = true;

        // Database
        $dbStart = microtime(true);
        try {
            DB::select('SELECT 1');
            $checks['database'] = [
                'status'  => 'ok',
                'latency' => round((microtime(true) - $dbStart) * 1000, 2) . 'ms',
            ];
        } catch (\Throwable $e) {
            $checks['database'] = ['status' => 'error', 'message' => 'Connection failed'];
            $healthy = false;
        }

        // Redis
        $redisStart = microtime(true);
        try {
            Redis::ping();
            $checks['redis'] = [
                'status'  => 'ok',
                'latency' => round((microtime(true) - $redisStart) * 1000, 2) . 'ms',
            ];
        } catch (\Throwable $e) {
            $checks['redis'] = ['status' => 'error', 'message' => 'Connection failed'];
            $healthy = false;
        }

        // Queue (Redis-based)
        try {
            $queueSize = Redis::llen('queues:default') ?: 0;
            $failedCount = DB::table('failed_jobs')->count();
            $checks['queue'] = [
                'status'       => 'ok',
                'pending_jobs' => $queueSize,
                'failed_jobs'  => $failedCount,
            ];
        } catch (\Throwable $e) {
            $checks['queue'] = ['status' => 'unknown'];
        }

        // Cache
        try {
            Cache::put('health_check', true, 10);
            $checks['cache'] = ['status' => Cache::get('health_check') ? 'ok' : 'error'];
        } catch (\Throwable $e) {
            $checks['cache'] = ['status' => 'error'];
            $healthy = false;
        }

        return response()->json([
            'status'  => $healthy ? 'healthy' : 'degraded',
            'checks'  => $checks,
            'version' => config('app.version', '1.0.0'),
            'env'     => config('app.env'),
        ], $healthy ? 200 : 503);
    }
}
