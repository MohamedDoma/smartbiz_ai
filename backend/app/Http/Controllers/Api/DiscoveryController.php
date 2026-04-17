<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\AnswerDiscoveryRequest;
use App\Http\Requests\StartDiscoveryRequest;
use App\Http\Resources\DiscoveryBlueprintResource;
use App\Http\Resources\DiscoverySessionResource;
use App\Services\DiscoverySessionService;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;

class DiscoveryController extends Controller
{
    public function __construct(
        private readonly DiscoverySessionService $sessions,
        private readonly WorkspaceContextManager $context,
    ) {}

    /**
     * List all discovery sessions for the current workspace.
     */
    public function index(): JsonResponse
    {
        $list = $this->sessions->list($this->context->workspaceId());
        return response()->json(['data' => DiscoverySessionResource::collection($list)]);
    }

    /**
     * Show a single session with messages and blueprint.
     */
    public function show(string $id): JsonResponse
    {
        $session = $this->sessions->find($this->context->workspaceId(), $id);
        if (! $session) return response()->json(['message' => 'Discovery session not found.'], 404);

        return response()->json(['data' => new DiscoverySessionResource($session)]);
    }

    /**
     * Start a new discovery session.
     */
    public function start(StartDiscoveryRequest $request): JsonResponse
    {
        $session = $this->sessions->startSession(
            $this->context->workspaceId(),
            $request->user()->id,
            $request->validated('business_description'),
        );

        return response()->json(['data' => new DiscoverySessionResource($session)], 201);
    }

    /**
     * Submit answers to follow-up questions.
     */
    public function answer(AnswerDiscoveryRequest $request, string $id): JsonResponse
    {
        $session = $this->sessions->find($this->context->workspaceId(), $id);
        if (! $session) return response()->json(['message' => 'Discovery session not found.'], 404);

        try {
            $session = $this->sessions->submitAnswers(
                $session,
                $request->validated('message_id'),
                $request->validated('answers'),
            );
            return response()->json(['data' => new DiscoverySessionResource($session)]);
        } catch (\InvalidArgumentException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }
    }

    /**
     * Classify the business type.
     */
    public function classify(string $id): JsonResponse
    {
        $session = $this->sessions->find($this->context->workspaceId(), $id);
        if (! $session) return response()->json(['message' => 'Discovery session not found.'], 404);

        $session = $this->sessions->classify($session);
        return response()->json(['data' => new DiscoverySessionResource($session)]);
    }

    /**
     * Generate the ERP blueprint.
     */
    public function generateBlueprint(string $id): JsonResponse
    {
        $session = $this->sessions->find($this->context->workspaceId(), $id);
        if (! $session) return response()->json(['message' => 'Discovery session not found.'], 404);

        try {
            $blueprint = $this->sessions->generateBlueprint($session);
            return response()->json(['data' => new DiscoveryBlueprintResource($blueprint)], 201);
        } catch (\InvalidArgumentException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }
    }

    /**
     * Show the generated blueprint.
     */
    public function showBlueprint(string $id): JsonResponse
    {
        $session = $this->sessions->find($this->context->workspaceId(), $id);
        if (! $session) return response()->json(['message' => 'Discovery session not found.'], 404);

        if (! $session->blueprint) {
            return response()->json(['message' => 'No blueprint has been generated yet for this session.'], 404);
        }

        return response()->json(['data' => new DiscoveryBlueprintResource($session->blueprint)]);
    }
}
