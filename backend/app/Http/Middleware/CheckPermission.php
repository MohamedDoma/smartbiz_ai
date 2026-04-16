<?php

namespace App\Http\Middleware;

use App\Exceptions\PermissionDeniedException;
use App\Services\PermissionResolver;
use App\Services\WorkspaceContextManager;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Route-level permission checking middleware.
 *
 * Usage in routes:
 *   ->middleware('permission:contacts.create')
 *   ->middleware('permission:contacts.update')
 *
 * Requires SetWorkspaceContext to have run first (so membership is resolved).
 */
class CheckPermission
{
    public function __construct(
        private readonly WorkspaceContextManager $context,
        private readonly PermissionResolver $resolver,
    ) {}

    /**
     * @param string $permission The permission key to check (e.g. 'contacts.create')
     */
    public function handle(Request $request, Closure $next, string $permission): Response
    {
        $membership = $this->context->membership();

        if ($membership === null) {
            throw new PermissionDeniedException($permission);
        }

        if (! $this->resolver->can($membership, $permission)) {
            throw new PermissionDeniedException($permission);
        }

        return $next($request);
    }
}
