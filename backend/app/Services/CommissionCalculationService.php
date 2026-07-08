<?php

namespace App\Services;

use App\Models\CommissionEntry;
use App\Models\CommissionRule;
use App\Models\PipelineRecord;
use App\Models\WorkspaceMembership;

class CommissionCalculationService
{
    /**
     * Calculate commissions for a pipeline record.
     * Returns array of created CommissionEntry models (skips duplicates).
     */
    public function calculateForRecord(PipelineRecord $record): array
    {
        $wsId = $record->workspace_id;
        $baseAmount = (float) $record->value_amount;

        if ($baseAmount <= 0) {
            return [];
        }

        // Find active rules that match this record
        $rules = CommissionRule::where('workspace_id', $wsId)
            ->where('is_active', true)
            ->whereHas('plan', fn ($q) => $q->where('is_active', true))
            ->where(fn ($q) => $q->whereNull('pipeline_id')->orWhere('pipeline_id', $record->pipeline_id))
            ->where(fn ($q) => $q->whereNull('stage_id')->orWhere('stage_id', $record->stage_id))
            ->get();

        // Load assigned membership with relations for resolution
        $assignedMembership = null;
        if ($record->assigned_membership_id) {
            $assignedMembership = WorkspaceMembership::with(['membershipRoles.role', 'department', 'team'])
                ->find($record->assigned_membership_id);
        }

        $entries = [];

        foreach ($rules as $rule) {
            if (!$this->matchesTrigger($rule, $record)) {
                continue;
            }
            if (!$this->matchesValueRange($rule, $baseAmount)) {
                continue;
            }
            if (!$this->matchesFilters($rule, $assignedMembership)) {
                continue;
            }

            $recipientId = $this->resolveRecipient($rule, $record, $assignedMembership);
            if (!$recipientId) {
                continue;
            }

            // Duplicate check
            $exists = CommissionEntry::where('commission_rule_id', $rule->id)
                ->where('pipeline_record_id', $record->id)
                ->where('recipient_membership_id', $recipientId)
                ->exists();
            if ($exists) {
                continue;
            }

            $commissionAmount = $this->calculateAmount($rule, $baseAmount);
            $currency = $record->currency ?? $rule->currency ?? 'LYD';

            $entry = CommissionEntry::create([
                'workspace_id'            => $wsId,
                'commission_plan_id'      => $rule->commission_plan_id,
                'commission_rule_id'      => $rule->id,
                'pipeline_record_id'      => $record->id,
                'recipient_membership_id' => $recipientId,
                'source_membership_id'    => $record->assigned_membership_id !== $recipientId
                    ? $record->assigned_membership_id : null,
                'base_amount'             => $baseAmount,
                'commission_amount'       => $commissionAmount,
                'currency'                => $currency,
                'calculation_type'        => $rule->calculation_type,
                'percentage_rate'         => $rule->percentage_rate,
                'fixed_amount'            => $rule->calculation_type === 'fixed_amount' ? $rule->fixed_amount : null,
                'status'                  => 'pending',
                'calculated_at'           => now(),
            ]);

            $entries[] = $entry;
        }

        return $entries;
    }

    private function matchesTrigger(CommissionRule $rule, PipelineRecord $record): bool
    {
        return match ($rule->trigger_status) {
            'won'       => $record->status === 'won',
            'completed' => $record->status === 'completed',
            'open'      => true, // open allows any status
            default     => false,
        };
    }

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

    private function calculateAmount(CommissionRule $rule, float $baseAmount): float
    {
        return match ($rule->calculation_type) {
            'percentage'   => round($baseAmount * (float) $rule->percentage_rate / 100, 2),
            'fixed_amount' => (float) $rule->fixed_amount,
            default        => 0,
        };
    }
}
