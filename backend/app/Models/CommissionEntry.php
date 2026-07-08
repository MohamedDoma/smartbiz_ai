<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * @property string $id
 * @property string $workspace_id
 * @property string|null $commission_plan_id
 * @property string|null $commission_rule_id
 * @property string $pipeline_record_id
 * @property string $recipient_membership_id
 * @property string|null $source_membership_id
 * @property float $base_amount
 * @property float $commission_amount
 * @property string $currency
 * @property string $calculation_type
 * @property float|null $percentage_rate
 * @property float|null $fixed_amount
 * @property string $status  pending|approved|paid|cancelled
 * @property \Carbon\Carbon|null $calculated_at
 * @property \Carbon\Carbon|null $approved_at
 * @property \Carbon\Carbon|null $paid_at
 * @property string|null $notes
 */
class CommissionEntry extends Model
{
    use HasUuids;

    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'workspace_id', 'commission_plan_id', 'commission_rule_id',
        'pipeline_record_id', 'recipient_membership_id', 'source_membership_id',
        'base_amount', 'commission_amount', 'currency',
        'calculation_type', 'percentage_rate', 'fixed_amount',
        'status', 'calculated_at', 'approved_at', 'paid_at', 'notes',
    ];

    protected function casts(): array
    {
        return [
            'base_amount'       => 'decimal:2',
            'commission_amount' => 'decimal:2',
            'percentage_rate'   => 'decimal:4',
            'fixed_amount'      => 'decimal:2',
            'calculated_at'     => 'datetime',
            'approved_at'       => 'datetime',
            'paid_at'           => 'datetime',
        ];
    }

    public function plan(): BelongsTo
    {
        return $this->belongsTo(CommissionPlan::class, 'commission_plan_id');
    }

    public function rule(): BelongsTo
    {
        return $this->belongsTo(CommissionRule::class, 'commission_rule_id');
    }

    public function pipelineRecord(): BelongsTo
    {
        return $this->belongsTo(PipelineRecord::class);
    }

    public function recipientMembership(): BelongsTo
    {
        return $this->belongsTo(WorkspaceMembership::class, 'recipient_membership_id');
    }

    public function sourceMembership(): BelongsTo
    {
        return $this->belongsTo(WorkspaceMembership::class, 'source_membership_id');
    }
}
