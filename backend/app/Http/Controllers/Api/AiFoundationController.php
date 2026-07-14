<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AiConversation;
use App\Models\AiMessage;
use App\Services\Ai\AiGatewayService;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Step 59.1 — AI Controller.
 *
 * POST /api/ai/test           — connection test
 * POST /api/ai/chat           — basic chat (no tools, no business data)
 * GET  /api/ai/conversations   — list user conversations
 * GET  /api/ai/conversations/{id} — show conversation messages
 */
class AiFoundationController extends Controller
{
    public function __construct(
        private readonly AiGatewayService        $gateway,
        private readonly WorkspaceContextManager $context,
    ) {}

    /**
     * POST /api/ai/test
     */
    public function test(Request $request): JsonResponse
    {
        $user        = $request->user();
        $workspaceId = $this->context->workspaceId();

        $result = $this->gateway->test($workspaceId, $user->id);

        if (isset($result['status'])) {
            return response()->json(['data' => $result], $result['status']);
        }

        return response()->json(['data' => $result]);
    }

    /**
     * POST /api/ai/chat
     */
    public function chat(Request $request): JsonResponse
    {
        $request->validate([
            'message'         => 'required|string|max:8000',
            'conversation_id' => 'nullable|uuid',
        ]);

        $user        = $request->user();
        $workspaceId = $this->context->workspaceId();

        $result = $this->gateway->chat(
            message:        $request->input('message'),
            workspaceId:    $workspaceId,
            userId:         $user->id,
            conversationId: $request->input('conversation_id'),
        );

        if (isset($result['status'])) {
            return response()->json(['data' => $result], $result['status']);
        }

        return response()->json(['data' => $result]);
    }

    /**
     * GET /api/ai/conversations
     */
    public function conversations(Request $request): JsonResponse
    {
        $user        = $request->user();
        $workspaceId = $this->context->workspaceId();

        $conversations = AiConversation::where('user_id', $user->id)
            ->where('workspace_id', $workspaceId)
            ->where('type', 'chat')
            ->orderByDesc('last_message_at')
            ->limit($request->input('limit', 20))
            ->get()
            ->map(fn ($c) => [
                'id'              => $c->id,
                'title'           => $c->title,
                'type'            => $c->type,
                'status'          => $c->status,
                'message_count'   => $c->message_count,
                'last_message_at' => $c->last_message_at?->toIso8601String(),
                'created_at'      => $c->created_at->toIso8601String(),
            ]);

        return response()->json(['data' => $conversations]);
    }

    /**
     * GET /api/ai/conversations/{id}
     */
    public function showConversation(Request $request, string $id): JsonResponse
    {
        $user        = $request->user();
        $workspaceId = $this->context->workspaceId();

        $convo = AiConversation::where('id', $id)
            ->where('user_id', $user->id)
            ->where('workspace_id', $workspaceId)
            ->first();

        if (!$convo) {
            return response()->json([
                'data'    => null,
                'error'   => 'conversation_not_found',
                'message' => 'المحادثة غير موجودة.',
            ], 404);
        }

        $messages = AiMessage::where('conversation_id', $convo->id)
            ->orderBy('created_at')
            ->limit(100)
            ->get()
            ->map(fn ($m) => [
                'id'         => $m->id,
                'role'       => $m->role,
                'content'    => $m->content,
                'model'      => $m->model,
                'tokens'     => $m->total_tokens,
                'created_at' => $m->created_at->toIso8601String(),
            ]);

        return response()->json([
            'data' => [
                'id'              => $convo->id,
                'title'           => $convo->title,
                'type'            => $convo->type,
                'status'          => $convo->status,
                'message_count'   => $convo->message_count,
                'last_message_at' => $convo->last_message_at?->toIso8601String(),
                'messages'        => $messages,
            ],
        ]);
    }
}
