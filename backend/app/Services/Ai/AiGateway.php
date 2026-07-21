<?php

namespace App\Services\Ai;

use App\Services\Ai\Tools\AiToolRegistry;
use App\Services\AiCreditService;
use App\Services\WorkspaceContextManager;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

/**
 * Central AI orchestrator — receives user messages, routes through LLM and tools.
 *
 * Phase 3 enhancements:
 * - Memory integration (session context + entity frequency)
 * - Provider routing with fallback
 * - Variable credit cost by complexity
 */
class AiGateway
{
    private const MAX_TOOL_LOOPS = 5;

    public function __construct(
        private readonly LlmService              $llm,
        private readonly AiToolRegistry           $tools,
        private readonly AiPromptBuilder          $prompt,
        private readonly AiCreditService          $credits,
        private readonly AiMemoryService          $memory,
        private readonly WorkspaceContextManager  $context,
    ) {}

    /**
     * Process a user chat message.
     */
    public function chat(
        string  $workspaceId,
        string  $userId,
        string  $message,
        ?string $conversationId = null,
        array   $permissions = [],
    ): array {
        $start = hrtime(true);

        // 1. Resolve/create conversation
        $convo = $this->resolveConversation($workspaceId, $userId, $conversationId);

        // 2. Load history
        $history = $this->loadHistory($convo->id, 20);

        // 3. Build messages with memory context
        $memoryContext = $this->memory->getRelevantMemory($workspaceId, $userId);
        $systemPrompt  = $this->prompt->buildSystemPrompt($workspaceId, $userId, $permissions, $memoryContext);
        $toolDefs      = $this->tools->getToolDefinitions($permissions);

        $messages = [['role' => 'system', 'content' => $systemPrompt]];
        foreach ($history as $msg) {
            $messages[] = ['role' => $msg->role, 'content' => $msg->content];
        }
        $messages[] = ['role' => 'user', 'content' => $message];

        // 4. Store user message
        $this->storeMessage($convo->id, 'user', $message);

        // 5. Store session context (current message as last interaction)
        $this->memory->setSessionContext($workspaceId, $userId, 'last_message', $message);

        // 6. LLM loop (with tool calls and fallback)
        $totalTokens = 0;
        $toolsUsed   = [];
        $llmResponse = null;
        $loops       = 0;

        while ($loops < self::MAX_TOOL_LOOPS) {
            $loops++;

            try {
                $llmResponse = $this->llm->chatWithFallback($messages, $toolDefs);
            } catch (\Throwable $e) {
                Log::error('LLM call failed', ['error' => $e->getMessage()]);
                $this->storeMessage($convo->id, 'assistant', 'I encountered an error processing your request. Please try again.');
                return $this->buildErrorResponse($convo->id, $e->getMessage());
            }

            $totalTokens += $llmResponse->totalTokens();

            if (! $llmResponse->hasToolCalls()) {
                break;
            }

            // Execute each tool call
            foreach ($llmResponse->toolCalls as $tc) {
                $toolName = $tc['name'];
                $toolArgs = $tc['arguments'];
                $toolsUsed[] = $toolName;

                $toolResult = $this->tools->executeTool(
                    $toolName, $toolArgs, $workspaceId, $userId, $convo->id
                );

                // Track entity access for memory
                $this->trackEntityAccess($workspaceId, $toolName, $toolResult);

                // If ambiguity detected, return immediately
                if (! empty($toolResult['action']) && $toolResult['action'] === 'ambiguity_resolution') {
                    $ambiguityMsg = $toolResult['message'] ?? 'Multiple matches found.';
                    $candidates   = $toolResult['candidates'] ?? $toolResult['existing'] ?? [];

                    $responseText = $ambiguityMsg . "\n\nOptions:\n";
                    foreach ($candidates as $i => $c) {
                        $name  = is_object($c) ? $c->name : ($c['name'] ?? 'Unknown');
                        $id    = is_object($c) ? $c->id : ($c['id'] ?? '');
                        $email = is_object($c) ? ($c->email ?? '') : ($c['email'] ?? '');
                        $responseText .= ($i + 1) . ". {$name}";
                        if ($email) $responseText .= " ({$email})";
                        $responseText .= "\n";
                    }

                    $this->storeMessage($convo->id, 'assistant', $responseText);
                    return $this->buildResponse($convo->id, $responseText, $llmResponse, $totalTokens, $toolsUsed, 'ambiguity');
                }

                // If pending confirmation, format response
                if (! empty($toolResult['action']) && $toolResult['action'] === 'pending_confirmation') {
                    $confirmMsg = "I've prepared a draft for you:\n\n";
                    $confirmMsg .= "**Action**: {$toolResult['tool']}\n";
                    $confirmMsg .= "**Details**: " . json_encode($toolResult['draft'], JSON_PRETTY_PRINT) . "\n\n";
                    $confirmMsg .= "Please confirm or reject this action (Action ID: `{$toolResult['action_id']}`)";

                    $this->storeMessage($convo->id, 'assistant', $confirmMsg, [
                        'pending_action_id' => $toolResult['action_id'],
                    ]);

                    return $this->buildResponse($convo->id, $confirmMsg, $llmResponse, $totalTokens, $toolsUsed, 'pending_action', [
                        'action_id' => $toolResult['action_id'],
                    ]);
                }

                // Feed tool result back to LLM
                $messages[] = [
                    'role'       => 'assistant',
                    'content'    => null,
                    'tool_calls' => [[
                        'id'       => $tc['id'],
                        'type'     => 'function',
                        'function' => [
                            'name'      => $toolName,
                            'arguments' => json_encode($toolArgs),
                        ],
                    ]],
                ];
                $messages[] = [
                    'role'       => 'tool',
                    'tool_call_id' => $tc['id'],
                    'content'    => json_encode($toolResult),
                ];
            }
        }

        // 7. Store & return assistant response
        $responseText = $llmResponse->content ?? 'I couldn\'t generate a response.';
        $this->storeMessage($convo->id, 'assistant', $responseText);

        // 8. Store session context for last entities mentioned
        $this->memory->setSessionContext($workspaceId, $userId, 'last_tools_used', $toolsUsed);

        // 9. Track usage with complexity-based cost
        $latencyMs = (int) ((hrtime(true) - $start) / 1_000_000);
        $this->trackUsage($workspaceId, $userId, $convo->id, $llmResponse, $totalTokens, $toolsUsed, $latencyMs);

        return $this->buildResponse($convo->id, $responseText, $llmResponse, $totalTokens, $toolsUsed);
    }

    // ── Conversation ────────────────────────────────────────

    private function resolveConversation(string $wsId, string $userId, ?string $convoId): object
    {
        if ($convoId) {
            $convo = DB::table('ai_conversations')
                ->where('id', $convoId)
                ->where('workspace_id', $wsId)
                ->where('user_id', $userId)
                ->first();

            if ($convo) {
                return $convo;
            }
        }

        $id = Str::uuid()->toString();
        DB::table('ai_conversations')->insert([
            'id'              => $id,
            'workspace_id'    => $wsId,
            'user_id'         => $userId,
            'type'            => 'chat',
            'mode'            => 'chat',
            'status'          => 'active',
            'message_count'   => 0,
            'last_message_at' => now(),
            'metadata'        => '{}',
            'created_at'      => now(),
            'updated_at'      => now(),
        ]);

        return DB::table('ai_conversations')->where('id', $id)->first();
    }

    private function loadHistory(string $convoId, int $limit): array
    {
        return DB::table('ai_conversation_messages')
            ->where('conversation_id', $convoId)
            ->orderByDesc('created_at')
            ->limit($limit)
            ->get()
            ->reverse()
            ->values()
            ->toArray();
    }

    private function storeMessage(string $convoId, string $role, string $content, ?array $metadata = null): void
    {
        DB::table('ai_conversation_messages')->insert([
            'id'              => Str::uuid()->toString(),
            'conversation_id' => $convoId,
            'role'            => $role,
            'content'         => $content,
            'metadata'        => json_encode($metadata ?? []),
            'created_at'      => now(),
        ]);

        DB::table('ai_conversations')
            ->where('id', $convoId)
            ->update([
                'message_count'   => DB::raw('message_count + 1'),
                'last_message_at' => now(),
                'updated_at'      => now(),
            ]);
    }

    // ── Memory tracking ────────────────────────────────────

    private function trackEntityAccess(string $wsId, string $toolName, array $result): void
    {
        // Track contacts/products referenced in tool results
        if (str_contains($toolName, 'contact') && ! empty($result['data'])) {
            foreach (array_slice(is_array($result['data']) ? $result['data'] : [$result['data']], 0, 3) as $item) {
                $id   = is_object($item) ? $item->id : ($item['id'] ?? null);
                $name = is_object($item) ? $item->name : ($item['name'] ?? null);
                if ($id) $this->memory->recordEntityAccess($wsId, 'contact', $id, $name);
            }
        }
        if (str_contains($toolName, 'product') && ! empty($result['data'])) {
            foreach (array_slice(is_array($result['data']) ? $result['data'] : [$result['data']], 0, 3) as $item) {
                $id   = is_object($item) ? $item->id : ($item['id'] ?? null);
                $name = is_object($item) ? $item->name : ($item['name'] ?? null);
                if ($id) $this->memory->recordEntityAccess($wsId, 'product', $id, $name);
            }
        }
    }

    // ── Usage tracking ──────────────────────────────────────

    private function trackUsage(
        string $wsId, string $userId, string $convoId,
        LlmResponse $llm, int $totalTokens, array $toolsUsed, int $latencyMs,
    ): void {
        // Complexity-based credit cost
        $hasActions = collect($toolsUsed)->contains(fn ($t) => str_starts_with($t, 'draft_') || str_starts_with($t, 'update_'));
        $creditCost = match (true) {
            $hasActions            => max(2, count($toolsUsed) + 1),   // actions cost more
            ! empty($toolsUsed)   => count($toolsUsed) + 1,           // read tools
            default               => 1,                                // simple chat
        };

        // Charge credits
        $this->credits->chargeCredits($wsId, $userId, 'ai_chat', $creditCost, [
            'conversation_id' => $convoId,
            'tools_used'      => $toolsUsed,
            'tokens'          => $totalTokens,
        ], $llm->toAuditMeta(), $latencyMs);

        // AiCreditService stores the canonical usage record.
    }

    // ── Response builders ───────────────────────────────────

    private function buildResponse(
        string $convoId, string $content, ?LlmResponse $llm,
        int $totalTokens, array $toolsUsed, string $mode = 'chat', array $extra = [],
    ): array {
        return array_merge([
            'conversation_id' => $convoId,
            'response'        => $content,
            'mode'            => $mode,
            'tools_used'      => $toolsUsed,
            'tokens'          => $totalTokens,
            'provider'        => $llm?->provider,
            'model'           => $llm?->model,
        ], $extra);
    }

    private function buildErrorResponse(string $convoId, string $error): array
    {
        return [
            'conversation_id' => $convoId,
            'response'        => 'I encountered an error processing your request. Please try again.',
            'mode'            => 'error',
            'error'           => $error,
            'tools_used'      => [],
            'tokens'          => 0,
        ];
    }
}
