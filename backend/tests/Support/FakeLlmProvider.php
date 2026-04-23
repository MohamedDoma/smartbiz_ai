<?php

namespace Tests\Support;

use App\Services\Ai\LlmProviderInterface;
use App\Services\Ai\LlmResponse;

/**
 * Deterministic fake LLM provider for testing.
 *
 * Returns predictable responses based on message content patterns.
 */
class FakeLlmProvider implements LlmProviderInterface
{
    private array $queuedResponses = [];
    private array $callLog = [];

    public function providerName(): string
    {
        return 'fake';
    }

    public function defaultModel(): string
    {
        return 'fake-model-v1';
    }

    /**
     * Queue a specific response for the next call.
     */
    public function queueResponse(LlmResponse $response): self
    {
        $this->queuedResponses[] = $response;
        return $this;
    }

    /**
     * Queue a tool call response.
     */
    public function queueToolCall(string $toolName, array $arguments, string $toolCallId = 'tc_001'): self
    {
        return $this->queueResponse(new LlmResponse(
            content:          null,
            toolCalls:        [['id' => $toolCallId, 'name' => $toolName, 'arguments' => $arguments]],
            promptTokens:     50,
            completionTokens: 20,
            model:            'fake-model-v1',
            provider:         'fake',
            finishReason:     'tool_calls',
            latencyMs:        10,
        ));
    }

    /**
     * Queue a text response.
     */
    public function queueTextResponse(string $text): self
    {
        return $this->queueResponse(new LlmResponse(
            content:          $text,
            toolCalls:        [],
            promptTokens:     50,
            completionTokens: 20,
            model:            'fake-model-v1',
            provider:         'fake',
            finishReason:     'stop',
            latencyMs:        10,
        ));
    }

    public function getCallLog(): array
    {
        return $this->callLog;
    }

    public function chat(array $messages, array $options = []): LlmResponse
    {
        $this->callLog[] = ['method' => 'chat', 'messages' => $messages, 'options' => $options];
        return $this->nextResponse($messages);
    }

    public function chatWithTools(array $messages, array $tools, array $options = []): LlmResponse
    {
        $this->callLog[] = ['method' => 'chatWithTools', 'messages' => $messages, 'tools' => $tools, 'options' => $options];
        return $this->nextResponse($messages);
    }

    private function nextResponse(array $messages): LlmResponse
    {
        if (! empty($this->queuedResponses)) {
            return array_shift($this->queuedResponses);
        }

        // Default: echo back a simple text response
        $lastMsg = end($messages);
        $text    = 'This is a response from the AI assistant.';
        if ($lastMsg && isset($lastMsg['content'])) {
            $text = 'I received your message: "' . substr($lastMsg['content'], 0, 100) . '"';
        }

        return new LlmResponse(
            content:          $text,
            toolCalls:        [],
            promptTokens:     50,
            completionTokens: 20,
            model:            'fake-model-v1',
            provider:         'fake',
            finishReason:     'stop',
            latencyMs:        10,
        );
    }
}
