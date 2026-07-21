<?php

namespace App\Providers;

use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\ServiceProvider;

/**
 * Defines rate limits for API, AI, auth, and admin endpoints.
 */
class RateLimitServiceProvider extends ServiceProvider
{
    public function boot(): void
    {
        // General API: 60 requests/minute per user
        RateLimiter::for('api', function (Request $request) {
            return Limit::perMinute(60)->by($request->user()?->id ?: $request->ip());
        });

        // AI endpoints: 20 requests/minute (expensive operations)
        RateLimiter::for('ai', function (Request $request) {
            return Limit::perMinute(20)->by($request->user()?->id ?: $request->ip());
        });

        // Auth endpoints: 5 requests/minute (brute force protection)
        RateLimiter::for('auth', function (Request $request) {
            return Limit::perMinute(5)->by($request->ip());
        });

        // Public activation-code lookups: reduce enumeration and abuse.
        RateLimiter::for('activation', function (Request $request) {
            return Limit::perMinute(20)->by($request->ip());
        });

        // Admin endpoints: 30 requests/minute
        RateLimiter::for('admin', function (Request $request) {
            return Limit::perMinute(30)->by($request->user()?->id ?: $request->ip());
        });
    }
}
