<?php

namespace App\Services\Ai;

/**
 * Contract for LLM providers (OpenAI, Anthropic, etc.).
 */
interface LlmProviderInterface
{
    /**
     * Send a chat completion request.
     *
     * @param  array{role: string, content: string}[]  $messages
     * @param  array  $options  Model-specific options (temperature, max_tokens, etc.)
     * @return LlmResponse
     */
    public function chat(array $messages, array $options = []): LlmResponse;

    /**
     * Send a chat completion request with function/tool calling.
     *
     * @param  array{role: string, content: string}[]  $messages
     * @param  array  $tools  OpenAI-compatible tool definitions
     * @param  array  $options
     * @return LlmResponse
     */
    public function chatWithTools(array $messages, array $tools, array $options = []): LlmResponse;

    /**
     * Return the provider name (e.g. 'openai', 'anthropic').
     */
    public function providerName(): string;

    /**
     * Return the default model for this provider.
     */
    public function defaultModel(): string;
}
