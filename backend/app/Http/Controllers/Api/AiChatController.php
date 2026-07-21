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
        private readonly AiGateway                $gateway,
        private readonly AiActionService          $actions,
        private readonly AiInsightService         $insights,
        private readonly WorkspaceContextManager  $context,
    ) {}

    /**
     * POST /api/ai/chat — Send a message to the AI assistant.
     *
     * Uses the canonical AiGateway for provider abstraction, tool calls,
     * permission enforcement, memory, actions, credits, and conversation persistence.
     */
    public function chat(Request $request): JsonResponse
    {
        $request->validate([
            'message'         => 'required|string|max:8000',
            'conversation_id' => 'nullable|uuid',
        ]);

        $user        = $request->user();
        $workspaceId = $this->context->workspaceId();
        $membership  = $this->context->membership();

        $permissions = $membership
            ? app(\App\Services\PermissionResolver::class)->resolveAll($membership)
            : [];

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
                'messages'        => $messages->map(fn ($message) => [
                    'id'         => $message->id,
                    'role'       => $message->role,
                    'content'    => $message->content,
                    'metadata'   => isset($message->metadata)
                        ? json_decode($message->metadata, true)
                        : [],
                    'created_at' => $message->created_at,
                ])->values(),
            ];
        });

        return response()->json(['data' => $data]);
    }

    /**
     * GET /api/ai/conversations — List the current user's conversations.
     *
     * Scoped by authenticated user_id + current workspace_id.
     * Never returns conversations belonging to another user/workspace.
     */
    public function conversations(Request $request): JsonResponse
    {
        $workspaceId = $this->context->workspaceId();
        $userId      = $request->user()->id;

        $conversations = DB::table('ai_conversations')
            ->where('workspace_id', $workspaceId)
            ->where('user_id', $userId)
            ->orderByDesc('updated_at')
            ->limit($request->input('limit', 20))
            ->get()
            ->map(fn ($c) => [
                'id'              => $c->id,
                'title'           => $c->title,
                'type'            => $c->type,
                'mode'            => $c->mode,
                'status'          => $c->status,
                'message_count'   => $c->message_count,
                'last_message_at' => $c->last_message_at,
                'created_at'      => $c->created_at,
                'updated_at'      => $c->updated_at,
            ]);

        return response()->json(['data' => $conversations]);
    }

    /**
     * GET /api/ai/conversations/{conversation} — Load a single conversation with messages.
     *
     * Scoped by authenticated user_id + current workspace_id.
     * Returns generic 404 if conversation doesn't belong to this user/workspace.
     */
    public function showConversation(Request $request, string $conversationId): JsonResponse
    {
        $workspaceId = $this->context->workspaceId();
        $userId      = $request->user()->id;

        $convo = DB::table('ai_conversations')
            ->where('id', $conversationId)
            ->where('workspace_id', $workspaceId)
            ->where('user_id', $userId)
            ->first();

        if (!$convo) {
            return response()->json([
                'data'    => null,
                'error'   => 'conversation_not_found',
                'message' => 'المحادثة غير موجودة.',
            ], 404);
        }

        $messages = DB::table('ai_conversation_messages')
            ->where('conversation_id', $convo->id)
            ->orderBy('created_at')
            ->limit(100)
            ->get()
            ->map(fn ($m) => [
                'id'         => $m->id,
                'role'       => $m->role,
                'content'    => $m->content,
                'metadata'   => isset($m->metadata)
                    ? json_decode($m->metadata, true)
                    : [],
                'created_at' => $m->created_at,
            ]);

        return response()->json(['data' => [
            'id'              => $convo->id,
            'title'           => $convo->title,
            'type'            => $convo->type,
            'mode'            => $convo->mode,
            'status'          => $convo->status,
            'message_count'   => $convo->message_count,
            'last_message_at' => $convo->last_message_at,
            'messages'        => $messages,
        ]]);
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
