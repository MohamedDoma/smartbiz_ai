<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

/**
 * Adds a unique X-Correlation-ID to every request/response.
 * Injects it into the log context for full request tracing.
 */
class CorrelationIdMiddleware
{
    public function handle(Request $request, Closure $next)
    {
        $correlationId = $request->header('X-Correlation-ID') ?: Str::uuid()->toString();

        // Share with log context
        Log::shareContext(['correlation_id' => $correlationId]);

        $response = $next($request);

        $response->headers->set('X-Correlation-ID', $correlationId);

        return $response;
    }
}
