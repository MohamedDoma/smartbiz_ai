<?php

namespace App\Providers;

use App\Services\PermissionResolver;
use App\Services\WorkspaceContextManager;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        // WorkspaceContextManager is a singleton so the same instance
        // is shared across middleware → controllers → services within a request.
        $this->app->singleton(WorkspaceContextManager::class);

        // PermissionResolver is stateless — singleton for performance.
        $this->app->singleton(PermissionResolver::class);
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        //
    }
}
