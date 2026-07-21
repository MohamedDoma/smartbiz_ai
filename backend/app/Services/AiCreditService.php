<?php

namespace App\Services;

use App\Models\AiCreditBalance;
use App\Models\AiCreditTransaction;
use App\Models\AiUsageLog;
use Illuminate\Support\Facades\DB;

/**
 * Manages AI credit multi-bucket operations.
 *
 * Deduction priority: trial → included → bonus → purchased
 */
class AiCreditService
{
    /**
     * Check the current credit balance for a workspace.
     */
    public function checkBalance(string $workspaceId): array
    {
        $bal = AiCreditBalance::where('workspace_id', $workspaceId)->first();
        if (! $bal) {
            return [
                'available' => 0, 'used' => 0,
                'exhausted' => true, 'hard_limit' => false,
                'soft_limit_reached' => false,
            ];
        }

        return [
            'available'           => $bal->totalAvailable(),
            'used'                => $bal->used_credits,
            'included_remaining'  => max(0, $bal->included_credits - $bal->used_credits),
            'purchased_remaining' => $bal->purchased_credits,
            'bonus_remaining'     => $bal->bonus_credits,
            'trial_remaining'     => $bal->trial_credits,
            'exhausted'           => $bal->isExhausted(),
            'hard_limit'          => $bal->hard_limit,
            'soft_limit_reached'  => $bal->isSoftLimitReached(),
        ];
    }

    /**
     * Charge credits for an AI action.
     * Returns true if successful, false if insufficient credits (and hard limit).
     */
    public function chargeCredits(
        string  $workspaceId,
        string  $userId,
        string  $actionType,
        int     $credits,
        ?array  $requestMeta = null,
        ?array  $responseMeta = null,
        ?int    $durationMs = null,
    ): array {
        return DB::transaction(function () use ($workspaceId, $userId, $actionType, $credits, $requestMeta, $responseMeta, $durationMs) {
            $bal = AiCreditBalance::where('workspace_id', $workspaceId)->lockForUpdate()->first();

            if (! $bal) {
                return ['success' => false, 'reason' => 'No credit balance initialized.'];
            }

            if ($bal->totalAvailable() < $credits && $bal->hard_limit) {
                return ['success' => false, 'reason' => 'Insufficient credits.', 'available' => $bal->totalAvailable()];
            }

            // Deduct using priority: trial → included → bonus → purchased
            $remaining = $credits;
            $buckets = [];

            // Trial
            if ($remaining > 0 && $bal->trial_credits > 0) {
                $deduct = min($remaining, $bal->trial_credits);
                $bal->trial_credits -= $deduct;
                $remaining -= $deduct;
                $buckets['trial'] = $deduct;
            }

            // Included
            $includedAvailable = max(0, $bal->included_credits - $bal->used_credits + ($credits - $remaining - ($buckets['trial'] ?? 0)));
            // Simpler: calculate how much included is available
            $includedRemaining = max(0, $bal->included_credits - $bal->used_credits);
            if ($remaining > 0 && $includedRemaining > 0) {
                $deduct = min($remaining, $includedRemaining);
                $remaining -= $deduct;
                $buckets['included'] = $deduct;
            }

            // Bonus
            if ($remaining > 0 && $bal->bonus_credits > 0) {
                $deduct = min($remaining, $bal->bonus_credits);
                $bal->bonus_credits -= $deduct;
                $remaining -= $deduct;
                $buckets['bonus'] = $deduct;
            }

            // Purchased
            if ($remaining > 0 && $bal->purchased_credits > 0) {
                $deduct = min($remaining, $bal->purchased_credits);
                $bal->purchased_credits -= $deduct;
                $remaining -= $deduct;
                $buckets['purchased'] = $deduct;
            }

            // Update used total
            $bal->used_credits += ($credits - $remaining);
            $bal->save();

            // Log transaction per bucket
            foreach ($buckets as $bucket => $amount) {
                AiCreditTransaction::create([
                    'workspace_id'     => $workspaceId,
                    'transaction_type' => 'usage',
                    'bucket'           => $bucket,
                    'credits'          => -$amount,
                    'balance_after'    => $bal->totalAvailable(),
                    'description'      => "AI action: {$actionType}",
                    'actor_id'         => $userId,
                    'created_at'       => now(),
                ]);
            }

            // Log usage using the canonical ai_usage_logs schema.
            $promptTokens = (int) ($responseMeta['prompt_tokens'] ?? 0);
            $completionTokens = (int) ($responseMeta['completion_tokens'] ?? 0);
            $totalTokens = (int) (
                $responseMeta['total_tokens']
                ?? $requestMeta['tokens']
                ?? ($promptTokens + $completionTokens)
            );

            $provider = trim((string) ($responseMeta['provider'] ?? 'unknown'));
            $model = trim((string) ($responseMeta['model'] ?? 'unknown'));

            AiUsageLog::create([
                'workspace_id'      => $workspaceId,
                'user_id'           => $userId,
                'conversation_id'   => $requestMeta['conversation_id'] ?? null,
                'provider'          => $provider !== '' ? $provider : 'unknown',
                'model'             => $model !== '' ? $model : 'unknown',
                'operation'         => $actionType,
                'input_tokens'      => $promptTokens,
                'output_tokens'     => $completionTokens,
                'total_tokens'      => $totalTokens,
                'estimated_cost_usd'=> (float) ($responseMeta['estimated_cost_usd'] ?? 0),
                'success'           => true,
                'duration_ms'       => $durationMs ?? 0,
                'metadata'          => [
                    'credits_charged' => $credits - $remaining,
                    'buckets'         => $buckets,
                    'request'         => $requestMeta ?? [],
                    'response'        => $responseMeta ?? [],
                ],
            ]);

            return [
                'success'   => true,
                'charged'   => $credits - $remaining,
                'available' => $bal->totalAvailable(),
                'warning'   => $bal->isSoftLimitReached() ? 'Soft limit reached.' : null,
            ];
        });
    }

    /**
     * Add purchased credits.
     */
    public function purchaseCredits(string $workspaceId, int $credits, ?string $actorId = null): AiCreditBalance
    {
        return DB::transaction(function () use ($workspaceId, $credits, $actorId) {
            $bal = AiCreditBalance::where('workspace_id', $workspaceId)->lockForUpdate()->firstOrFail();
            $bal->purchased_credits += $credits;
            $bal->save();

            AiCreditTransaction::create([
                'workspace_id'     => $workspaceId,
                'transaction_type' => 'purchase',
                'bucket'           => 'purchased',
                'credits'          => $credits,
                'balance_after'    => $bal->totalAvailable(),
                'description'      => "Purchased {$credits} credits",
                'actor_id'         => $actorId,
                'created_at'       => now(),
            ]);

            return $bal;
        });
    }

    /**
     * Add bonus credits (admin gifted).
     */
    public function addBonusCredits(string $workspaceId, int $credits, ?string $actorId = null, ?string $reason = null): AiCreditBalance
    {
        return DB::transaction(function () use ($workspaceId, $credits, $actorId, $reason) {
            $bal = AiCreditBalance::where('workspace_id', $workspaceId)->lockForUpdate()->firstOrFail();
            $bal->bonus_credits += $credits;
            $bal->save();

            AiCreditTransaction::create([
                'workspace_id'     => $workspaceId,
                'transaction_type' => 'bonus',
                'bucket'           => 'bonus',
                'credits'          => $credits,
                'balance_after'    => $bal->totalAvailable(),
                'description'      => $reason ?? "Bonus: {$credits} credits",
                'actor_id'         => $actorId,
                'created_at'       => now(),
            ]);

            return $bal;
        });
    }

    /**
     * Monthly credit reset — resets used, refreshes included.
     */
    public function monthlyReset(string $workspaceId, int $newIncluded): AiCreditBalance
    {
        return DB::transaction(function () use ($workspaceId, $newIncluded) {
            $bal = AiCreditBalance::where('workspace_id', $workspaceId)->lockForUpdate()->firstOrFail();

            $bal->included_credits = $newIncluded;
            $bal->trial_credits    = 0;
            $bal->used_credits     = 0;
            $bal->period_start     = now();
            $bal->period_end       = now()->addMonth();
            $bal->save();

            AiCreditTransaction::create([
                'workspace_id'     => $workspaceId,
                'transaction_type' => 'monthly_reset',
                'bucket'           => 'included',
                'credits'          => $newIncluded,
                'balance_after'    => $bal->totalAvailable(),
                'description'      => "Monthly reset: {$newIncluded} credits",
                'created_at'       => now(),
            ]);

            return $bal;
        });
    }
}
