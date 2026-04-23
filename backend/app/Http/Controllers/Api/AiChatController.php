<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\Ai\AiActionService;
use App\Services\Ai\AiGateway;
use App\Services\Ai\AiInsightService;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class AiChatController extends Controller
{
    public function __construct(
        private readonly AiGateway               $gateway,
        private readonly AiActionService          $actions,
        private readonly AiInsightService         $insights,
        private readonly WorkspaceContextManager  $context,
    ) {}

    /**
     * POST /api/ai/chat — Send a message to the AI assistant.
     */
    public function chat(Request $request): JsonResponse
    {
        $request->validate([
            'message'         => 'required|string|max:4000',
            'conversation_id' => 'nullable|uuid',
        ]);

        $user        = $request->user();
        $workspaceId = $this->context->workspaceId();
        $permissions = $this->getUserPermissions($workspaceId, $user->id);

        $result = $this->gateway->chat(
            workspaceId:    $workspaceId,
            userId:         $user->id,
            message:        $request->input('message'),
            conversationId: $request->input('conversation_id'),
            permissions:    $permissions,
        );

        return response()->json(['data' => $result]);
    }

    /**
     * GET /api/ai/history — List conversations and their messages.
     */
    public function history(Request $request): JsonResponse
    {
        $workspaceId = $this->context->workspaceId();
        $userId      = $request->user()->id;

        $conversations = DB::table('ai_conversations')
            ->where('workspace_id', $workspaceId)
            ->where('user_id', $userId)
            ->where('mode', 'chat')
            ->orderByDesc('last_message_at')
            ->limit($request->input('limit', 20))
            ->get();

        $data = $conversations->map(function ($convo) {
            $messages = DB::table('ai_conversation_messages')
                ->where('conversation_id', $convo->id)
                ->orderBy('created_at')
                ->limit(50)
                ->get();

            return [
                'id'              => $convo->id,
                'title'           => $convo->title,
                'mode'            => $convo->mode,
                'message_count'   => $convo->message_count,
                'last_message_at' => $convo->last_message_at,
                'messages'        => $messages,
            ];
        });

        return response()->json(['data' => $data]);
    }

    /**
     * POST /api/ai/confirm-action — Confirm a pending AI action.
     */
    public function confirmAction(Request $request): JsonResponse
    {
        $request->validate([
            'action_id' => 'required|uuid',
        ]);

        $result = $this->actions->confirm(
            $request->input('action_id'),
            $this->context->workspaceId(),
            $request->user()->id,
        );

        return response()->json(['data' => $result]);
    }

    /**
     * POST /api/ai/reject-action — Reject a pending AI action.
     */
    public function rejectAction(Request $request): JsonResponse
    {
        $request->validate([
            'action_id' => 'required|uuid',
            'reason'    => 'nullable|string|max:500',
        ]);

        $result = $this->actions->reject(
            $request->input('action_id'),
            $this->context->workspaceId(),
            $request->user()->id,
            $request->input('reason', 'Rejected by user'),
        );

        return response()->json(['data' => $result]);
    }

    /**
     * GET /api/ai/insights — Get proactive business insights.
     */
    public function insights(Request $request): JsonResponse
    {
        $wsId   = $this->context->workspaceId();
        $status = $request->input('status', 'new');
        $data   = $this->insights->getInsights($wsId, $status);

        return response()->json(['data' => $data]);
    }

    /**
     * POST /api/ai/insights/generate — Generate insights on demand.
     */
    public function generateInsights(): JsonResponse
    {
        $wsId    = $this->context->workspaceId();
        $results = $this->insights->generateInsights($wsId);

        return response()->json(['data' => $results, 'count' => count($results)]);
    }

    /**
     * POST /api/ai/insights/{id}/dismiss — Dismiss an insight.
     */
    public function dismissInsight(string $id): JsonResponse
    {
        $wsId = $this->context->workspaceId();
        $this->insights->dismiss($id, $wsId);

        return response()->json(['data' => ['status' => 'dismissed']]);
    }

    // ── Helpers ─────────────────────────────────────────

    private function getUserPermissions(string $workspaceId, string $userId): array
    {
        $membership = \App\Models\WorkspaceMembership::where('workspace_id', $workspaceId)
            ->where('user_id', $userId)
            ->first();

        if (! $membership) {
            return [];
        }

        return app(\App\Services\PermissionResolver::class)->resolveAll($membership);
    }
}
