<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class WorkspaceSubscription extends Model
{
    use HasUuids;

    protected $table = 'workspace_subscriptions';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'workspace_id', 'plan_id', 'plan_price_id',
        'status', 'billing_cycle',
        'current_period_start', 'current_period_end',
        'trial_ends_at',
        'included_employees', 'current_employee_count',
        'billable_employee_count', 'overage_employee_count',
        'price_per_extra_employee',
        'cancelled_at',
        'stripe_customer_id', 'stripe_subscription_id', 'stripe_price_id',
    ];

    protected function casts(): array
    {
        return [
            'current_period_start' => 'datetime',
            'current_period_end' => 'datetime',
            'trial_ends_at' => 'datetime',
            'included_employees' => 'integer',
            'current_employee_count' => 'integer',
            'billable_employee_count' => 'integer',
            'overage_employee_count' => 'integer',
            'price_per_extra_employee' => 'decimal:2',
            'cancelled_at' => 'datetime',
        ];
    }

    public function workspace(): BelongsTo
    {
        return $this->belongsTo(Workspace::class, 'workspace_id');
    }

    public function plan(): BelongsTo
    {
        return $this->belongsTo(PlatformPlan::class, 'plan_id');
    }

    public function planPrice(): BelongsTo
    {
        return $this->belongsTo(PlatformPlanPrice::class, 'plan_price_id');
    }

    // ── Helpers ────────────────────────────────────

    public function isActive(): bool
    {
        return $this->status === 'active';
    }

    public function isTrial(): bool
    {
        return $this->status === 'trial';
    }

    public function isTrialExpired(): bool
    {
        return $this->isTrial() && $this->trial_ends_at && $this->trial_ends_at->isPast();
    }
}
