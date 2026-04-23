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

        // AI: LLM provider resolved from env (AI_PROVIDER=openai|anthropic|fake)
        $this->app->singleton(
            \App\Services\Ai\LlmProviderInterface::class,
            fn () => \App\Services\Ai\LlmService::resolveProvider(),
        );
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        // Register event subscribers
        \Illuminate\Support\Facades\Event::subscribe(\App\Listeners\EmailEventSubscriber::class);
    }
}
