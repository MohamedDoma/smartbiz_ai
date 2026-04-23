<?php

namespace App\Services\Ai;

use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * OpenAI provider implementation.
 *
 * Env:
 *   OPENAI_API_KEY      — required
 *   OPENAI_MODEL        — default: gpt-4o-mini
 *   OPENAI_TIMEOUT      — default: 30 (seconds)
 *   OPENAI_MAX_RETRIES  — default: 2
 */
class OpenAiProvider implements LlmProviderInterface
{
    private string $apiKey;
    private string $model;
    private int    $timeout;
    private int    $maxRetries;

    public function __construct()
    {
        $this->apiKey     = config('services.openai.api_key', env('OPENAI_API_KEY', ''));
        $this->model      = config('services.openai.model', env('OPENAI_MODEL', 'gpt-4o-mini'));
        $this->timeout    = (int) config('services.openai.timeout', env('OPENAI_TIMEOUT', 30));
        $this->maxRetries = (int) config('services.openai.max_retries', env('OPENAI_MAX_RETRIES', 2));
    }

    public function providerName(): string
    {
        return 'openai';
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
        $body = [
            'model'       => $options['model'] ?? $this->model,
            'messages'    => $messages,
            'temperature' => $options['temperature'] ?? 0.3,
            'max_tokens'  => $options['max_tokens'] ?? 2048,
        ];

        if (! empty($tools)) {
            $body['tools']       = $tools;
            $body['tool_choice'] = $options['tool_choice'] ?? 'auto';
        }

        $start = hrtime(true);

        $response = Http::retry($this->maxRetries, 500)
            ->timeout($this->timeout)
            ->withHeaders([
                'Authorization' => "Bearer {$this->apiKey}",
                'Content-Type'  => 'application/json',
            ])
            ->post('https://api.openai.com/v1/chat/completions', $body);

        $latencyMs = (int) ((hrtime(true) - $start) / 1_000_000);

        if ($response->failed()) {
            Log::error('OpenAI request failed', [
                'status' => $response->status(),
                'body'   => $response->body(),
            ]);
            throw new \RuntimeException('OpenAI API error: ' . $response->status() . ' — ' . $response->body());
        }

        $data    = $response->json();
        $choice  = $data['choices'][0] ?? [];
        $message = $choice['message'] ?? [];
        $usage   = $data['usage'] ?? [];

        $toolCalls = [];
        foreach ($message['tool_calls'] ?? [] as $tc) {
            $toolCalls[] = [
                'id'        => $tc['id'],
                'name'      => $tc['function']['name'],
                'arguments' => json_decode($tc['function']['arguments'] ?? '{}', true),
            ];
        }

        return new LlmResponse(
            content:          $message['content'] ?? null,
            toolCalls:        $toolCalls,
            promptTokens:     $usage['prompt_tokens'] ?? 0,
            completionTokens: $usage['completion_tokens'] ?? 0,
            model:            $data['model'] ?? $this->model,
            provider:         'openai',
            finishReason:     $choice['finish_reason'] ?? 'unknown',
            latencyMs:        $latencyMs,
        );
    }
}
