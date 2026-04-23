<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\Ai\AiAdvisorService;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class AiAdvisorController extends Controller
{
    public function __construct(
        private readonly AiAdvisorService $advisor,
        private readonly WorkspaceContextManager $context,
    ) {}

    /**
     * GET /api/ai/advisor/recommendations
     */
    public function index(Request $request): JsonResponse
    {
        $recs = $this->advisor->getRecommendations(
            $this->context->workspaceId(),
            $request->input('status'),
            $request->input('category'),
            (int) $request->input('limit', 50),
        );

        return response()->json(['data' => $recs, 'count' => count($recs)]);
    }

    /**
     * POST /api/ai/advisor/run-analysis
     */
    public function runAnalysis(): JsonResponse
    {
        $recs = $this->advisor->runAnalysis($this->context->workspaceId());

        return response()->json([
            'message' => count($recs) . ' recommendation(s) generated.',
            'data'    => $recs,
        ]);
    }

    /**
     * POST /api/ai/advisor/{id}/accept
     */
    public function accept(string $id): JsonResponse
    {
        $ok = $this->advisor->accept($id, $this->context->workspaceId());
        if (! $ok) {
            return response()->json(['message' => 'Recommendation not found or not pending.'], 404);
        }
        return response()->json(['message' => 'Recommendation accepted.']);
    }

    /**
     * POST /api/ai/advisor/{id}/reject
     */
    public function reject(Request $request, string $id): JsonResponse
    {
        $ok = $this->advisor->reject($id, $this->context->workspaceId(), $request->input('reason'));
        if (! $ok) {
            return response()->json(['message' => 'Recommendation not found or not pending.'], 404);
        }
        return response()->json(['message' => 'Recommendation rejected.']);
    }

    /**
     * POST /api/ai/advisor/{id}/apply
     */
    public function apply(string $id, Request $request): JsonResponse
    {
        try {
            $result = $this->advisor->apply(
                $id,
                $this->context->workspaceId(),
                $request->user()->id,
            );
            return response()->json(['message' => 'Recommendation applied.', 'result' => $result]);
        } catch (\InvalidArgumentException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }
    }
}
