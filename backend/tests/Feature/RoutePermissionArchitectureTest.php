<?php

namespace Tests\Feature;

use App\Http\Middleware\CheckPermission;
use App\Services\PermissionCatalog;
use Illuminate\Auth\Middleware\Authenticate;
use Illuminate\Routing\Route;
use Tests\TestCase;

class RoutePermissionArchitectureTest extends TestCase
{
    public function test_sensitive_workspace_routes_have_explicit_permission_middleware(): void
    {
        $expected = [
            'billing.manual-payment' => 'billing.manual_payment',

            'ai.chat' => 'ai.chat',
            'ai.history' => 'ai.chat',
            'ai.confirm' => 'ai.actions',
            'ai.reject' => 'ai.actions',
            'ai.insights' => 'ai.insights.view',
            'ai.insights.generate' => 'ai.insights.manage',
            'ai.insights.dismiss' => 'ai.insights.manage',
            'ai.advisor.recommendations' => 'ai_advisor.view',
            'ai.advisor.run' => 'ai_advisor.manage',
            'ai.advisor.accept' => 'ai_advisor.manage',
            'ai.advisor.reject' => 'ai_advisor.manage',
            'ai.advisor.apply' => 'ai_advisor.manage',
            'ai.foundation.test' => 'ai.manage',
            'ai.foundation.conversations' => 'ai.chat',
            'ai.foundation.conversation' => 'ai.chat',

            'document-checklists.index' => 'document_checklists.view',
            'document-checklists.store' => 'document_checklists.manage',
            'document-checklists.show' => 'document_checklists.view',
            'document-checklists.update' => 'document_checklists.manage',
            'document-checklists.destroy' => 'document_checklists.manage',
            'document-checklist-items.index' => 'document_checklists.view',
            'document-checklist-items.store' => 'document_checklists.manage',
            'document-checklist-items.update' => 'document_checklists.manage',
            'document-checklist-items.destroy' => 'document_checklists.manage',

            'commission-settings.options' => 'commissions.settings.view',
            'commission-plans.index' => 'commissions.settings.view',
            'commission-plans.store' => 'commissions.settings.manage',
            'commission-plans.show' => 'commissions.settings.view',
            'commission-plans.update' => 'commissions.settings.manage',
            'commission-plans.destroy' => 'commissions.settings.manage',
            'commission-rules.index' => 'commissions.settings.view',
            'commission-rules.store' => 'commissions.settings.manage',
            'commission-rules.show' => 'commissions.settings.view',
            'commission-rules.update' => 'commissions.settings.manage',
            'commission-rules.destroy' => 'commissions.settings.manage',
            'commission-entries.index' => 'commissions.list',
            'commission-entries.show' => 'commissions.list',
            'commission-entries.calculate' => 'commissions.calculate',
            'commission-entries.approve' => 'commissions.approve',
            'commission-entries.pay' => 'commissions.pay',
            'commission-entries.cancel' => 'commissions.cancel',

            'ownership.index' => 'ownership.view',
            'ownership.store' => 'ownership.manage',
            'ownership.show' => 'ownership.view',
            'ownership.transfer' => 'ownership.manage',
            'ownership.resolve' => 'ownership.view',

            'duplicate-rules.index' => 'duplicates.view',
            'duplicate-rules.store' => 'duplicates.manage',
            'duplicate-rules.show' => 'duplicates.view',
            'duplicate-rules.update' => 'duplicates.manage',
            'duplicate-rules.destroy' => 'duplicates.manage',
            'duplicates.check' => 'duplicates.check',
            'duplicate-matches.index' => 'duplicates.view',
            'duplicate-matches.resolve' => 'duplicates.resolve',

            'report-catalog.index' => 'reports.view',
            'report-catalog.show' => 'reports.view',
            'report-templates.index' => 'reports.view',
            'report-templates.store' => 'reports.run',
            'report-templates.show' => 'reports.view',
            'report-templates.update' => 'reports.manage',
            'report-templates.destroy' => 'reports.manage',
            'report-templates.run' => 'reports.run',
            'report-runs.index' => 'reports.view',
            'report-runs.show' => 'reports.view',
            'reports.run-adhoc' => 'reports.run',

            'finance.accounts.index' => 'finance.view',
            'finance.accounts.store' => 'finance.manage',
            'finance.accounts.update' => 'finance.manage',
            'finance.bootstrap' => 'finance.manage',
            'finance.transactions.index' => 'finance.view',
            'finance.transactions.show' => 'finance.view',
            'finance.transactions.store' => 'finance.manage',
            'finance.transactions.void' => 'finance.manage',
            'finance.expenses.index' => 'finance.view',
            'finance.expenses.store' => 'finance.manage',
            'finance.expenses.show' => 'finance.view',
            'finance.expenses.void' => 'finance.manage',
            'finance.summary' => 'finance.view',
            'finance.profit-loss' => 'finance.view',
            'finance.account-balances' => 'finance.view',
            'finance.post-commission' => 'finance.post',
            'finance.post-invoice' => 'finance.post',
            'finance.post-payment' => 'finance.post',

            'approvals.cancel' => 'approvals.cancel',
        ];

        $routes = app('router')->getRoutes();

        foreach ($expected as $routeName => $permission) {
            $route = $routes->getByName($routeName);
            $this->assertInstanceOf(Route::class, $route, "Missing route: {$routeName}");
            $this->assertContains(
                CheckPermission::class . ':' . $permission,
                $route->gatherMiddleware(),
                "Route {$routeName} must require {$permission}",
            );
        }
    }


    public function test_every_workspace_mutation_route_has_explicit_permission_middleware(): void
    {
        $safeMethods = ['GET', 'HEAD', 'OPTIONS'];

        foreach (app('router')->getRoutes() as $route) {
            $middleware = $route->gatherMiddleware();

            if (! in_array(\App\Http\Middleware\SetWorkspaceContext::class, $middleware, true)) {
                continue;
            }

            $mutationMethods = array_values(array_diff($route->methods(), $safeMethods));
            if ($mutationMethods === []) {
                continue;
            }

            $hasPermission = collect($middleware)->contains(
                fn (string $item): bool => str_starts_with($item, CheckPermission::class . ':'),
            );

            $this->assertTrue(
                $hasPermission,
                sprintf(
                    'Workspace mutation route %s %s (%s) has no explicit permission middleware.',
                    implode('|', $mutationMethods),
                    $route->uri(),
                    $route->getName() ?? 'unnamed',
                ),
            );
        }
    }

    public function test_api_routes_are_authenticated_unless_explicitly_public(): void
    {
        $publicRouteNames = [
            'health',
            'auth.login',
            'auth.register',
            'invites.preview',
            'invites.accept',
            'activation-codes.public-show',
            'activation-codes.public-validate',
            'webhooks.stripe',
        ];

        foreach (app('router')->getRoutes() as $route) {
            if (! str_starts_with($route->uri(), 'api/')) {
                continue;
            }

            if (in_array($route->getName(), $publicRouteNames, true)) {
                continue;
            }

            $authenticated = collect($route->gatherMiddleware())->contains(
                fn (string $item): bool => $item === 'auth:sanctum'
                    || str_starts_with($item, Authenticate::class . ':'),
            );

            $this->assertTrue(
                $authenticated,
                sprintf(
                    'API route %s %s (%s) is unexpectedly public.',
                    implode('|', $route->methods()),
                    $route->uri(),
                    $route->getName() ?? 'unnamed',
                ),
            );
        }
    }

    public function test_every_route_permission_exists_in_the_catalog(): void
    {
        $catalog = array_flip(PermissionCatalog::allKeys());

        foreach (app('router')->getRoutes() as $route) {
            foreach ($route->gatherMiddleware() as $middleware) {
                if (! str_starts_with($middleware, CheckPermission::class . ':')) {
                    continue;
                }

                $permission = substr($middleware, strlen(CheckPermission::class) + 1);
                $this->assertArrayHasKey(
                    $permission,
                    $catalog,
                    "Route {$route->getName()} uses an unknown permission: {$permission}",
                );
            }
        }
    }

    public function test_permission_catalog_keys_are_unique(): void
    {
        $keys = PermissionCatalog::allKeys();

        $this->assertSame(
            count($keys),
            count(array_unique($keys)),
            'PermissionCatalog contains duplicate keys.',
        );
    }
}
