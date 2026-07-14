<?php

namespace App\Services\Ai;

use App\Models\AiUsageLog;
use Illuminate\Support\Facades\Log;

/**
 * Logs AI usage to the ai_usage_logs table.
 */
class AiUsageLogger
{
    public function __construct(
        private readonly AiUsageEstimator $estimator,
    ) {}

    /**
     * Log a successful AI request.
     */
    public function logSuccess(array $data): AiUsageLog
    {
        $model       = $data['model'] ?? config('ai.openai.default_model');
        $inputTokens = $data['input_tokens'] ?? 0;
        $outputTokens = $data['output_tokens'] ?? 0;
        $totalTokens  = $data['total_tokens'] ?? ($inputTokens + $outputTokens);
        $cost         = $this->estimator->estimate($model, $inputTokens, $outputTokens);

        return AiUsageLog::create([
            'workspace_id'      => $data['workspace_id'] ?? null,
            'user_id'           => $data['user_id'] ?? null,
            'conversation_id'   => $data['conversation_id'] ?? null,
            'message_id'        => $data['message_id'] ?? null,
            'provider'          => $data['provider'] ?? 'openai',
            'model'             => $model,
            'operation'         => $data['operation'] ?? 'chat',
            'input_tokens'      => $inputTokens,
            'output_tokens'     => $outputTokens,
            'total_tokens'      => $totalTokens,
            'estimated_cost_usd' => $cost,
            'success'           => true,
            'request_id'        => $data['request_id'] ?? null,
            'duration_ms'       => $data['duration_ms'] ?? 0,
            'metadata'          => $data['metadata'] ?? [],
        ]);
    }

    /**
     * Log a failed AI request.
     */
    public function logFailure(array $data): AiUsageLog
    {
        return AiUsageLog::create([
            'workspace_id'      => $data['workspace_id'] ?? null,
            'user_id'           => $data['user_id'] ?? null,
            'conversation_id'   => $data['conversation_id'] ?? null,
            'message_id'        => $data['message_id'] ?? null,
            'provider'          => $data['provider'] ?? 'openai',
            'model'             => $data['model'] ?? config('ai.openai.default_model'),
            'operation'         => $data['operation'] ?? 'chat',
            'input_tokens'      => 0,
            'output_tokens'     => 0,
            'total_tokens'      => 0,
            'estimated_cost_usd' => 0,
            'success'           => false,
            'error_code'        => $data['error_code'] ?? 'unknown',
            'error_message'     => $data['error_message'] ?? '',
            'request_id'        => $data['request_id'] ?? null,
            'duration_ms'       => $data['duration_ms'] ?? 0,
            'metadata'          => $data['metadata'] ?? [],
        ]);
    }
}
