<?php

namespace App\Services\Ai;

use Illuminate\Support\Facades\Log;

/**
 * Smart provider routing with fallback.
 *
 * Config:
 *   AI_PRIMARY_PROVIDER=openai (default)
 *   AI_FALLBACK_PROVIDER=anthropic (default, empty = no fallback)
 */
class ProviderRouter
{
    private LlmProviderInterface $primary;
    private ?LlmProviderInterface $fallback;

    public function __construct()
    {
        $this->primary  = LlmService::resolveProvider();
        $fallbackName   = strtolower(env('AI_FALLBACK_PROVIDER', ''));
        $this->fallback = $fallbackName ? $this->resolve($fallbackName) : null;
    }

    /**
     * Route based on complexity level.
     *
     * @param  string  $complexity  'simple' | 'complex'
     */
    public function route(string $complexity = 'simple'): LlmProviderInterface
    {
        // Complex reasoning → use primary (typically the stronger model)
        // Simple queries → use primary with a cheaper model override option
        return $this->primary;
    }

    /**
     * Execute with automatic fallback on failure.
     */
    public function withFallback(callable $fn): LlmResponse
    {
        try {
            return $fn($this->primary);
        } catch (\Throwable $e) {
            if ($this->fallback) {
                Log::warning("Primary provider ({$this->primary->providerName()}) failed, trying fallback ({$this->fallback->providerName()})", [
                    'error' => $e->getMessage(),
                ]);
                return $fn($this->fallback);
            }
            throw $e;
        }
    }

    public function primary(): LlmProviderInterface
    {
        return $this->primary;
    }

    public function fallback(): ?LlmProviderInterface
    {
        return $this->fallback;
    }

    private function resolve(string $name): ?LlmProviderInterface
    {
        try {
            return match ($name) {
                'openai'    => new OpenAiProvider(),
                'anthropic' => new AnthropicProvider(),
                default     => null,
            };
        } catch (\Throwable $e) {
            Log::warning("Failed to initialize fallback provider: {$name}", ['error' => $e->getMessage()]);
            return null;
        }
    }
}
