<?php

namespace App\Services\Ai;

/**
 * Estimate OpenAI API cost using configurable per-model rates.
 * This is for internal monitoring only — not billing-accurate.
 */
class AiUsageEstimator
{
    /**
     * Estimate cost in USD for a given model and token counts.
     */
    public function estimate(string $model, int $inputTokens, int $outputTokens): float
    {
        $rates = config('ai.cost_rates', []);
        $rate  = $rates[$model] ?? $rates['_default'] ?? ['input' => 1.0, 'output' => 3.0];

        // Rates are per 1M tokens.
        $inputCost  = ($inputTokens / 1_000_000) * $rate['input'];
        $outputCost = ($outputTokens / 1_000_000) * $rate['output'];

        return round($inputCost + $outputCost, 6);
    }
}
