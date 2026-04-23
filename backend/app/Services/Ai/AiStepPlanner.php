<?php

namespace App\Services\Ai;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

/**
 * Plans and executes multi-step AI workflows.
 *
 * Example: "create order → reserve inventory → create invoice"
 * Each step is stored in ai_execution_plans as a JSONB array.
 */
class AiStepPlanner
{
    public function __construct(
        private readonly AiActionService $actions,
    ) {}

    /**
     * Create a multi-step execution plan.
     *
     * @param  array  $steps  Each step: ['tool' => string, 'params' => array, 'depends_on' => ?int]
     */
    public function createPlan(string $workspaceId, string $userId, ?string $conversationId, string $planName, array $steps): object
    {
        $stepsWithStatus = array_map(function ($step, $i) {
            return array_merge($step, [
                'index'  => $i,
                'status' => 'pending',
                'result' => null,
            ]);
        }, $steps, array_keys($steps));

        $planId = Str::uuid()->toString();
        DB::table('ai_execution_plans')->insert([
            'id'              => $planId,
            'workspace_id'    => $workspaceId,
            'conversation_id' => $conversationId,
            'user_id'         => $userId,
            'plan_name'       => $planName,
            'steps'           => json_encode($stepsWithStatus),
            'status'          => 'pending',
            'current_step'    => 0,
            'metadata'        => json_encode(['created_by' => 'ai_planner']),
            'created_at'      => now(),
            'updated_at'      => now(),
        ]);

        return DB::table('ai_execution_plans')->where('id', $planId)->first();
    }

    /**
     * Execute the next pending step in a plan.
     * Creates an ai_change_request for the step (draft-first).
     */
    public function executeNextStep(string $planId, string $workspaceId, string $userId): array
    {
        $plan = DB::table('ai_execution_plans')
            ->where('id', $planId)
            ->where('workspace_id', $workspaceId)
            ->first();

        if (! $plan || $plan->status === 'completed' || $plan->status === 'cancelled') {
            return ['error' => 'Plan not found or already completed.'];
        }

        $steps = json_decode($plan->steps, true);
        $currentIdx = $plan->current_step;

        if ($currentIdx >= count($steps)) {
            DB::table('ai_execution_plans')->where('id', $planId)->update(['status' => 'completed', 'updated_at' => now()]);
            return ['status' => 'completed', 'message' => 'All steps executed.'];
        }

        $step = $steps[$currentIdx];

        // Create a draft for this step
        $actionId = Str::uuid()->toString();
        DB::table('ai_change_requests')->insert([
            'id'              => $actionId,
            'workspace_id'    => $workspaceId,
            'requested_by'    => $userId,
            'change_type'     => 'multi_step',
            'risk_level'      => 'medium',
            'status'          => 'proposed',
            'proposed_diff'   => json_encode([
                'tool'    => $step['tool'],
                'params'  => $step['params'] ?? [],
                'plan_id' => $planId,
                'step'    => $currentIdx,
            ]),
            'proposed_at'     => now(),
            'expires_at'      => now()->addHours(24),
            'created_at'      => now(),
            'updated_at'      => now(),
        ]);

        // Update plan status
        $steps[$currentIdx]['status'] = 'awaiting_confirmation';
        $steps[$currentIdx]['action_id'] = $actionId;

        DB::table('ai_execution_plans')->where('id', $planId)->update([
            'steps'      => json_encode($steps),
            'status'     => 'in_progress',
            'updated_at' => now(),
        ]);

        return [
            'status'    => 'step_pending',
            'step'      => $currentIdx,
            'action_id' => $actionId,
            'tool'      => $step['tool'],
            'params'    => $step['params'] ?? [],
        ];
    }

    /**
     * Advance the plan after a step is confirmed.
     */
    public function advancePlan(string $planId, int $stepIndex, array $result): void
    {
        $plan  = DB::table('ai_execution_plans')->where('id', $planId)->first();
        $steps = json_decode($plan->steps, true);

        $steps[$stepIndex]['status'] = 'completed';
        $steps[$stepIndex]['result'] = $result;

        $nextStep = $stepIndex + 1;
        $isComplete = $nextStep >= count($steps);

        DB::table('ai_execution_plans')->where('id', $planId)->update([
            'steps'        => json_encode($steps),
            'current_step' => $nextStep,
            'status'       => $isComplete ? 'completed' : 'in_progress',
            'updated_at'   => now(),
        ]);
    }

    /**
     * Confirm all pending steps in batch.
     */
    public function confirmBatch(string $planId, string $workspaceId, string $userId): array
    {
        $plan  = DB::table('ai_execution_plans')
            ->where('id', $planId)
            ->where('workspace_id', $workspaceId)
            ->first();

        if (! $plan) {
            return ['error' => 'Plan not found.'];
        }

        $steps   = json_decode($plan->steps, true);
        $results = [];

        foreach ($steps as $i => &$step) {
            if ($step['status'] !== 'pending' && $step['status'] !== 'awaiting_confirmation') {
                continue;
            }

            try {
                if (! empty($step['action_id'])) {
                    $result = $this->actions->confirm($step['action_id'], $workspaceId, $userId);
                    $step['status'] = 'completed';
                    $step['result'] = $result;
                    $results[] = $result;
                }
            } catch (\Throwable $e) {
                $step['status'] = 'failed';
                $step['error']  = $e->getMessage();

                DB::table('ai_execution_plans')->where('id', $planId)->update([
                    'steps'      => json_encode($steps),
                    'status'     => 'failed',
                    'updated_at' => now(),
                ]);

                return ['status' => 'failed', 'step' => $i, 'error' => $e->getMessage(), 'completed' => $results];
            }
        }

        DB::table('ai_execution_plans')->where('id', $planId)->update([
            'steps'        => json_encode($steps),
            'status'       => 'completed',
            'current_step' => count($steps),
            'updated_at'   => now(),
        ]);

        return ['status' => 'completed', 'results' => $results];
    }

    /**
     * Cancel remaining steps.
     */
    public function cancelPlan(string $planId, string $workspaceId): array
    {
        $plan = DB::table('ai_execution_plans')
            ->where('id', $planId)
            ->where('workspace_id', $workspaceId)
            ->first();

        if (! $plan) {
            return ['error' => 'Plan not found.'];
        }

        $steps = json_decode($plan->steps, true);
        foreach ($steps as &$step) {
            if ($step['status'] === 'pending' || $step['status'] === 'awaiting_confirmation') {
                $step['status'] = 'cancelled';
            }
        }

        DB::table('ai_execution_plans')->where('id', $planId)->update([
            'steps'      => json_encode($steps),
            'status'     => 'cancelled',
            'updated_at' => now(),
        ]);

        return ['status' => 'cancelled'];
    }

    /**
     * Get a plan by ID.
     */
    public function getPlan(string $planId, string $workspaceId): ?object
    {
        return DB::table('ai_execution_plans')
            ->where('id', $planId)
            ->where('workspace_id', $workspaceId)
            ->first();
    }
}
