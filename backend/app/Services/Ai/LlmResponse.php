<?php

namespace App\Services\Ai;

/**
 * Provider-agnostic LLM response DTO.
 */
class LlmResponse
{
    public function __construct(
        public readonly ?string $content,
        public readonly array   $toolCalls,
        public readonly int     $promptTokens,
        public readonly int     $completionTokens,
        public readonly string  $model,
        public readonly string  $provider,
        public readonly string  $finishReason,
        public readonly int     $latencyMs,
    ) {}

    public function totalTokens(): int
    {
        return $this->promptTokens + $this->completionTokens;
    }

    public function hasToolCalls(): bool
    {
        return count($this->toolCalls) > 0;
    }

    public function toAuditMeta(): array
    {
        return [
            'provider'          => $this->provider,
            'model'             => $this->model,
            'prompt_tokens'     => $this->promptTokens,
            'completion_tokens' => $this->completionTokens,
            'total_tokens'      => $this->totalTokens(),
            'finish_reason'     => $this->finishReason,
            'latency_ms'        => $this->latencyMs,
        ];
    }
}
