<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class PlatformPlanPrice extends Model
{
    use HasUuids;

    protected $table = 'platform_plan_prices';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'plan_id', 'billing_cycle', 'base_price',
        'included_employees', 'price_per_employee',
        'included_ai_credits', 'ai_overage_price_per_credit',
        'currency', 'is_active',
        'effective_from', 'effective_until',
    ];

    protected function casts(): array
    {
        return [
            'base_price' => 'decimal:2',
            'included_employees' => 'integer',
            'price_per_employee' => 'decimal:2',
            'included_ai_credits' => 'integer',
            'ai_overage_price_per_credit' => 'decimal:4',
            'is_active' => 'boolean',
            'effective_from' => 'date',
            'effective_until' => 'date',
        ];
    }

    public function plan(): BelongsTo
    {
        return $this->belongsTo(PlatformPlan::class, 'plan_id');
    }
}
