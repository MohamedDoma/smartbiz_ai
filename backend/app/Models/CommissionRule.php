<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * @property string $id
 * @property string $workspace_id
 * @property string $commission_plan_id
 * @property string|null $pipeline_id
 * @property string|null $stage_id
 * @property string|null $role_id
 * @property string|null $department_id
 * @property string|null $team_id
 * @property string $target_type
 * @property string $calculation_type
 * @property float|null $percentage_rate
 * @property float|null $fixed_amount
 * @property string|null $currency
 * @property float|null $min_record_value
 * @property float|null $max_record_value
 * @property string $trigger_status
 * @property bool $is_active
 * @property int $sort_order
 */
class CommissionRule extends Model
{
    use HasUuids;

    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'workspace_id', 'commission_plan_id', 'pipeline_id', 'stage_id',
        'role_id', 'department_id', 'team_id',
        'target_type', 'calculation_type', 'percentage_rate', 'fixed_amount',
        'currency', 'min_record_value', 'max_record_value',
        'trigger_status', 'is_active', 'sort_order',
    ];

    protected function casts(): array
    {
        return [
            'percentage_rate'  => 'decimal:4',
            'fixed_amount'     => 'decimal:2',
            'min_record_value' => 'decimal:2',
            'max_record_value' => 'decimal:2',
            'is_active'        => 'boolean',
            'sort_order'       => 'integer',
        ];
    }

    public function plan(): BelongsTo
    {
        return $this->belongsTo(CommissionPlan::class, 'commission_plan_id');
    }

    public function pipeline(): BelongsTo
    {
        return $this->belongsTo(Pipeline::class);
    }

    public function stage(): BelongsTo
    {
        return $this->belongsTo(PipelineStage::class, 'stage_id');
    }

    public function role(): BelongsTo
    {
        return $this->belongsTo(Role::class);
    }

    public function department(): BelongsTo
    {
        return $this->belongsTo(Department::class);
    }

    public function team(): BelongsTo
    {
        return $this->belongsTo(Team::class);
    }
}
