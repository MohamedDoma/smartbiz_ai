<?php

namespace App\Services;

use App\Models\CommissionEntry;
use App\Models\CommissionRule;
use App\Models\Pipeline;
use App\Models\PipelineRecord;
use App\Models\WorkspaceMembership;
use Illuminate\Support\Facades\DB;

class CommissionCalculationService
{
    /**
     * Calculate commissions for a pipeline record.
     *
     * Enforces canonical eligibility centrally so every caller (auto-trigger
     * from PipelineRecordController::move() and the manual calculation
     * endpoint) receives the same protection:
     *
     *  - Pipeline entity_type = 'deal'
     *  - Assigned membership exists and is active
     *  - Deal value > 0
     *  - Active commission rules with exact pipeline_id + stage_id match
     *
     * Wrapped in a DB transaction with row-level locking to guarantee
     * idempotency. The DB unique constraint
     * `comm_entry_rule_record_recipient_unique` acts as a final safety net
     * via firstOrCreate; no QueryException is caught inside the transaction.
     *
     * @return CommissionEntry[] Created entries (empty when ineligible or already calculated)
     */
    public function calculateForRecord(PipelineRecord $record): array
    {
        return DB::transaction(function () use ($record) {
            // ── Row lock — serialise concurrent commission attempts ───
            $locked = PipelineRecord::where('id', $record->id)
                ->lockForUpdate()
                ->first();

            if (!$locked) {
                return [];
            }

            // Use the locked (freshest) values for all subsequent checks
            $wsId       = $locked->workspace_id;
            $baseAmount = (float) $locked->value_amount;

            // ── Canonical eligibility checks ─────────────────────────

            // 1. Pipeline must belong to this workspace, be active, and entity_type = 'deal'
            $pipeline = Pipeline::where('id', $locked->pipeline_id)
                ->where('workspace_id', $wsId)
                ->where('is_active', true)
                ->where('entity_type', 'deal')
                ->first();
            if (!$pipeline) {
                return [];
            }

            // 2. Deal value must be greater than zero
            if ($baseAmount <= 0) {
                return [];
            }

            // 3. Assigned membership must exist and be active
            if (!$locked->assigned_membership_id) {
                return [];
            }

            $assignedMembership = WorkspaceMembership::with(['membershipRoles.role', 'department', 'team'])
                ->where('id', $locked->assigned_membership_id)
                ->where('workspace_id', $wsId)
                ->where('status', 'active')
                ->first();

            if (!$assignedMembership) {
                return [];
            }

            // ── Find matching active rules by exact pipeline_id + stage_id ──
            // The configured stage_id is the source of truth for triggering.
            // Legacy rules with NULL stage_id are skipped until explicitly
            // saved with a stage by the user.
            $rules = CommissionRule::where('workspace_id', $wsId)
                ->where('is_active', true)
                ->whereNotNull('stage_id')
                ->where('pipeline_id', $locked->pipeline_id)
                ->where('stage_id', $locked->stage_id)
                ->whereHas('plan', fn ($q) => $q->where('is_active', true))
                ->get();

            $entries = [];

            foreach ($rules as $rule) {
                if (!$this->matchesValueRange($rule, $baseAmount)) {
                    continue;
                }
                if (!$this->matchesFilters($rule, $assignedMembership)) {
                    continue;
                }

                $recipientId = $this->resolveRecipient($rule, $locked, $assignedMembership);
                if (!$recipientId) {
                    continue;
                }

                // Validate recipient is an active member in the same workspace
                if (!$this->validateRecipient($recipientId, $wsId)) {
                    continue;
                }

                $commissionAmount = $this->calculateAmount($rule, $baseAmount);
                $currency = $locked->currency ?? $rule->currency ?? 'LYD';

                // Idempotent insert — the unique constraint
                // (commission_rule_id, pipeline_record_id, recipient_membership_id)
                // prevents duplicates. firstOrCreate is safe in PostgreSQL —
                // it does not abort the transaction on conflict.
                $entry = CommissionEntry::firstOrCreate(
                    [
                        'commission_rule_id'      => $rule->id,
                        'pipeline_record_id'      => $locked->id,
                        'recipient_membership_id' => $recipientId,
                    ],
                    [
                        'workspace_id'            => $wsId,
                        'commission_plan_id'      => $rule->commission_plan_id,
                        'source_membership_id'    => $locked->assigned_membership_id !== $recipientId
                            ? $locked->assigned_membership_id : null,
                        'base_amount'             => $baseAmount,
                        'commission_amount'       => $commissionAmount,
                        'currency'                => $currency,
                        'calculation_type'        => $rule->calculation_type,
                        'percentage_rate'         => $rule->percentage_rate,
                        'fixed_amount'            => $rule->calculation_type === 'fixed_amount' ? $rule->fixed_amount : null,
                        'status'                  => 'pending',
                        'calculated_at'           => now(),
                    ]
                );

                // Only report entries that were actually created (not pre-existing)
                if ($entry->wasRecentlyCreated) {
                    $entries[] = $entry;
                }
            }

            return $entries;
        });
    }

    // ── Private helpers ───────────────────────────────────────

    private function matchesValueRange(CommissionRule $rule, float $baseAmount): bool
    {
        if ($rule->min_record_value !== null && $baseAmount < (float) $rule->min_record_value) {
            return false;
        }
        if ($rule->max_record_value !== null && $baseAmount > (float) $rule->max_record_value) {
            return false;
        }
        return true;
    }

    private function matchesFilters(CommissionRule $rule, ?WorkspaceMembership $member): bool
    {
        if (!$member) return false;

        if ($rule->role_id) {
            $memberRoleIds = $member->membershipRoles->pluck('role_id')->toArray();
            if (!in_array($rule->role_id, $memberRoleIds, true)) {
                return false;
            }
        }
        if ($rule->department_id && $member->department_id !== $rule->department_id) {
            return false;
        }
        if ($rule->team_id && $member->team_id !== $rule->team_id) {
            return false;
        }
        return true;
    }

    private function resolveRecipient(CommissionRule $rule, PipelineRecord $record, ?WorkspaceMembership $assigned): ?string
    {
        return match ($rule->target_type) {
            'assigned_employee'  => $record->assigned_membership_id,
            'direct_manager'     => $assigned?->manager_membership_id,
            'team_manager'       => $this->resolveTeamManager($assigned),
            'department_manager' => $this->resolveDepartmentManager($assigned),
            default              => null,
        };
    }

    private function resolveTeamManager(?WorkspaceMembership $member): ?string
    {
        if (!$member || !$member->team_id) return null;
        $team = $member->team;
        return $team?->manager_membership_id ?? null;
    }

    private function resolveDepartmentManager(?WorkspaceMembership $member): ?string
    {
        if (!$member || !$member->department_id) return null;
        $dept = $member->department;
        return $dept?->manager_membership_id ?? null;
    }

    /**
     * Validate that a resolved recipient membership belongs to the given
     * workspace and is active. Prevents cross-workspace commission entries
     * when a manager reference points outside the workspace.
     */
    private function validateRecipient(string $recipientId, string $wsId): bool
    {
        return WorkspaceMembership::where('id', $recipientId)
            ->where('workspace_id', $wsId)
            ->where('status', 'active')
            ->exists();
    }

    private function calculateAmount(CommissionRule $rule, float $baseAmount): float
    {
        return match ($rule->calculation_type) {
            'percentage'   => round($baseAmount * (float) $rule->percentage_rate / 100, 2),
            'fixed_amount' => (float) $rule->fixed_amount,
            default        => 0,
        };
    }
}
