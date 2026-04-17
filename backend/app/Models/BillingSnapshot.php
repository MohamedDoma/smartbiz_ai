<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class BillingSnapshot extends Model
{
    use HasUuids;

    protected $table = 'billing_snapshots';
    protected $keyType = 'string';
    public $incrementing = false;
    public $timestamps = false;

    protected $fillable = [
        'workspace_id', 'period_start', 'period_end',
        'plan_name', 'billing_cycle', 'base_price',
        'employee_count', 'included_employees',
        'overage_employees', 'employee_overage_charge',
        'ai_credits_included', 'ai_credits_used',
        'ai_credits_overage', 'ai_overage_charge',
        'total_amount', 'status', 'created_at',
    ];

    protected function casts(): array
    {
        return [
            'period_start' => 'datetime',
            'period_end' => 'datetime',
            'base_price' => 'decimal:2',
            'employee_count' => 'integer',
            'included_employees' => 'integer',
            'overage_employees' => 'integer',
            'employee_overage_charge' => 'decimal:2',
            'ai_credits_included' => 'integer',
            'ai_credits_used' => 'integer',
            'ai_credits_overage' => 'integer',
            'ai_overage_charge' => 'decimal:2',
            'total_amount' => 'decimal:2',
            'created_at' => 'datetime',
        ];
    }

    public function workspace(): BelongsTo
    {
        return $this->belongsTo(Workspace::class, 'workspace_id');
    }
}
