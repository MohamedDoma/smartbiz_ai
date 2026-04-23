<?php

namespace App\Services\Ai;

/**
 * LLM service — routes to the configured provider with optional fallback.
 *
 * Env: AI_PROVIDER=openai (default) | anthropic | fake
 */
class LlmService
{
    private LlmProviderInterface $provider;
    private ?ProviderRouter $router = null;

    public function __construct(LlmProviderInterface $provider)
    {
        $this->provider = $provider;
    }

    public function chat(array $messages, array $options = []): LlmResponse
    {
        return $this->provider->chat($messages, $options);
    }

    public function chatWithTools(array $messages, array $tools, array $options = []): LlmResponse
    {
        return $this->provider->chatWithTools($messages, $tools, $options);
    }

    /**
     * Chat with automatic fallback if primary provider fails.
     * Uses the injected provider directly; only adds fallback if explicitly configured.
     */
    public function chatWithFallback(array $messages, array $tools = [], array $options = []): LlmResponse
    {
        $execute = function (LlmProviderInterface $p) use ($messages, $tools, $options) {
            return empty($tools)
                ? $p->chat($messages, $options)
                : $p->chatWithTools($messages, $tools, $options);
        };

        try {
            return $execute($this->provider);
        } catch (\Throwable $e) {
            // Try fallback only if a router with fallback is available
            if ($this->router && $this->router->fallback()) {
                return $execute($this->router->fallback());
            }
            throw $e;
        }
    }

    public function provider(): LlmProviderInterface
    {
        return $this->provider;
    }

    public function getRouter(): ProviderRouter
    {
        if (! $this->router) {
            $this->router = new ProviderRouter();
        }
        return $this->router;
    }

    public function setRouter(ProviderRouter $router): void
    {
        $this->router = $router;
    }

    /**
     * Resolve the current provider from env config.
     */
    public static function resolveProvider(): LlmProviderInterface
    {
        $name = strtolower(config('services.ai.provider', env('AI_PROVIDER', 'openai')));

        return match ($name) {
            'openai'    => new OpenAiProvider(),
            'anthropic' => new AnthropicProvider(),
            default     => throw new \InvalidArgumentException("Unsupported AI provider: {$name}"),
        };
    }
}
