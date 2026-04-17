<?php

namespace App\Http\Middleware;

use App\Services\AiCreditService;
use App\Services\WorkspaceContextManager;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Checks workspace AI credit balance before allowing AI actions.
 * Returns 429 with ai_credits_exhausted error if hard limit is hit.
 * Adds X-AI-Credits-Warning header when soft limit is reached.
 */
class CheckAiCredits
{
    public function __construct(
        private readonly AiCreditService $credits,
        private readonly WorkspaceContextManager $context,
    ) {}

    public function handle(Request $request, Closure $next, string $actionType = 'ai_action'): Response
    {
        $workspaceId = $this->context->workspaceId();
        if (! $workspaceId) {
            return $next($request);
        }

        $check = $this->credits->checkBalance($workspaceId);

        if ($check['exhausted'] && $check['hard_limit']) {
            return response()->json([
                'message' => 'AI credit limit reached. Please purchase additional credits or wait for monthly reset.',
                'error'   => 'ai_credits_exhausted',
                'credits' => [
                    'available' => $check['available'],
                    'used'      => $check['used'],
                ],
            ], 429);
        }

        $response = $next($request);

        // Add warning header if soft limit reached
        if ($check['soft_limit_reached']) {
            $response->headers->set('X-AI-Credits-Warning', 'Soft limit reached. ' . $check['available'] . ' credits remaining.');
        }

        return $response;
    }
}
