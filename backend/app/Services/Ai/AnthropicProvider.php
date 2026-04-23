<?php

namespace App\Services\Ai;

use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * Anthropic/Claude provider implementation.
 *
 * Uses the Messages API (https://docs.anthropic.com/en/api/messages).
 *
 * Env:
 *   ANTHROPIC_API_KEY   — required
 *   ANTHROPIC_MODEL     — default: claude-sonnet-4-20250514
 *   ANTHROPIC_TIMEOUT   — default: 60 (seconds)
 */
class AnthropicProvider implements LlmProviderInterface
{
    private string $apiKey;
    private string $model;
    private int    $timeout;

    public function __construct()
    {
        $this->apiKey  = config('services.anthropic.api_key', env('ANTHROPIC_API_KEY', ''));
        $this->model   = config('services.anthropic.model', env('ANTHROPIC_MODEL', 'claude-sonnet-4-20250514'));
        $this->timeout = (int) config('services.anthropic.timeout', env('ANTHROPIC_TIMEOUT', 60));
    }

    public function providerName(): string
    {
        return 'anthropic';
    }

    public function defaultModel(): string
    {
        return $this->model;
    }

    public function chat(array $messages, array $options = []): LlmResponse
    {
        return $this->request($messages, [], $options);
    }

    public function chatWithTools(array $messages, array $tools, array $options = []): LlmResponse
    {
        return $this->request($messages, $tools, $options);
    }

    private function request(array $messages, array $tools, array $options): LlmResponse
    {
        // Anthropic: system prompt goes in separate 'system' param
        $systemPrompt = null;
        $filteredMessages = [];
        foreach ($messages as $msg) {
            if ($msg['role'] === 'system') {
                $systemPrompt = $msg['content'];
            } elseif ($msg['role'] === 'tool') {
                // Anthropic uses 'tool_result' content blocks
                $filteredMessages[] = [
                    'role'    => 'user',
                    'content' => [[
                        'type'        => 'tool_result',
                        'tool_use_id' => $msg['tool_call_id'] ?? '',
                        'content'     => $msg['content'],
                    ]],
                ];
            } elseif (isset($msg['tool_calls'])) {
                // Convert OpenAI tool_calls format to Anthropic assistant message
                $content = [];
                foreach ($msg['tool_calls'] as $tc) {
                    $content[] = [
                        'type'  => 'tool_use',
                        'id'    => $tc['id'],
                        'name'  => $tc['function']['name'],
                        'input' => json_decode($tc['function']['arguments'] ?? '{}', true),
                    ];
                }
                $filteredMessages[] = ['role' => 'assistant', 'content' => $content];
            } else {
                $filteredMessages[] = [
                    'role'    => $msg['role'],
                    'content' => $msg['content'] ?? '',
                ];
            }
        }

        $body = [
            'model'      => $options['model'] ?? $this->model,
            'max_tokens' => $options['max_tokens'] ?? 2048,
            'messages'   => $filteredMessages,
        ];

        if ($systemPrompt) {
            $body['system'] = $systemPrompt;
        }

        if (isset($options['temperature'])) {
            $body['temperature'] = $options['temperature'];
        }

        // Convert OpenAI tool format to Anthropic format
        if (! empty($tools)) {
            $body['tools'] = array_map(function ($tool) {
                $fn = $tool['function'] ?? $tool;
                return [
                    'name'         => $fn['name'],
                    'description'  => $fn['description'] ?? '',
                    'input_schema' => $fn['parameters'] ?? ['type' => 'object', 'properties' => (object) []],
                ];
            }, $tools);
        }

        $start = hrtime(true);

        $response = Http::timeout($this->timeout)
            ->withHeaders([
                'x-api-key'         => $this->apiKey,
                'anthropic-version' => '2023-06-01',
                'Content-Type'      => 'application/json',
            ])
            ->post('https://api.anthropic.com/v1/messages', $body);

        $latencyMs = (int) ((hrtime(true) - $start) / 1_000_000);

        if ($response->failed()) {
            Log::error('Anthropic request failed', [
                'status' => $response->status(),
                'body'   => $response->body(),
            ]);
            throw new \RuntimeException('Anthropic API error: ' . $response->status() . ' — ' . $response->body());
        }

        $data  = $response->json();
        $usage = $data['usage'] ?? [];

        // Parse response content blocks
        $textContent = '';
        $toolCalls   = [];

        foreach ($data['content'] ?? [] as $block) {
            if ($block['type'] === 'text') {
                $textContent .= $block['text'];
            } elseif ($block['type'] === 'tool_use') {
                $toolCalls[] = [
                    'id'        => $block['id'],
                    'name'      => $block['name'],
                    'arguments' => $block['input'] ?? [],
                ];
            }
        }

        return new LlmResponse(
            content:          $textContent ?: null,
            toolCalls:        $toolCalls,
            promptTokens:     $usage['input_tokens'] ?? 0,
            completionTokens: $usage['output_tokens'] ?? 0,
            model:            $data['model'] ?? $this->model,
            provider:         'anthropic',
            finishReason:     $data['stop_reason'] ?? 'unknown',
            latencyMs:        $latencyMs,
        );
    }
}
