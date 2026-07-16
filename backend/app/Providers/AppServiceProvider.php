<?php

namespace App\Providers;

use App\Services\CommissionEntryConditionSchemaProvider;
use App\Services\ConditionEntityFieldCatalog;
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

        // ConditionEntityFieldCatalog — registry of entity field schemas
        // for approval workflow trigger conditions. Register all known
        // schema providers here. New entity types are added by creating
        // a ConditionEntitySchemaProvider implementation and registering it.
        $this->app->singleton(ConditionEntityFieldCatalog::class, function () {
            $catalog = new ConditionEntityFieldCatalog();
            $catalog->register(new CommissionEntryConditionSchemaProvider());
            return $catalog;
        });

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
