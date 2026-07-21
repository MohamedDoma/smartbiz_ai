<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\Operations\OperationalHealthService;
use Illuminate\Http\JsonResponse;

/**
 * Minimal unauthenticated readiness summary.
 * Detailed infrastructure diagnostics are available only through `php artisan ops:check`.
 */
class HealthController extends Controller
{
    public function __invoke(OperationalHealthService $health): JsonResponse
    {
        $summary = $health->publicSummary();

        return response()->json(
            $summary,
            $summary['status'] === 'healthy' ? 200 : 503,
        );
    }
}
