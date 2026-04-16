<?php

namespace App\Http\Middleware;

use App\Services\WorkspaceContextManager;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Resolves workspace context from the X-Workspace-Id header and
 * activates PostgreSQL RLS for the duration of the request.
 *
 * Usage: Apply to any route group that requires workspace scope.
 */
class SetWorkspaceContext
{
    public function __construct(
        private readonly WorkspaceContextManager $context,
    ) {}

    public function handle(Request $request, Closure $next): Response
    {
        $workspaceId = $request->header('X-Workspace-Id');

        $this->context->resolve($request->user(), $workspaceId);

        try {
            return $next($request);
        } finally {
            // Always clear context, even if the request threw an exception.
            // This resets SET app.workspace_id so pooled connections don't leak.
            $this->context->clear();
        }
    }
}
