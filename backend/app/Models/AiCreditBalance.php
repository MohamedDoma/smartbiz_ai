<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class AiCreditBalance extends Model
{
    use HasUuids;

    protected $table = 'ai_credit_balances';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'workspace_id',
        'included_credits', 'purchased_credits',
        'bonus_credits', 'trial_credits',
        'used_credits',
        'hard_limit', 'soft_limit_threshold',
        'period_start', 'period_end',
    ];

    protected function casts(): array
    {
        return [
            'included_credits' => 'integer',
            'purchased_credits' => 'integer',
            'bonus_credits' => 'integer',
            'trial_credits' => 'integer',
            'used_credits' => 'integer',
            'hard_limit' => 'boolean',
            'soft_limit_threshold' => 'integer',
            'period_start' => 'datetime',
            'period_end' => 'datetime',
        ];
    }

    public function workspace(): BelongsTo
    {
        return $this->belongsTo(Workspace::class, 'workspace_id');
    }

    /**
     * Total available credits across all buckets.
     */
    public function totalAvailable(): int
    {
        return ($this->trial_credits + $this->included_credits + $this->bonus_credits + $this->purchased_credits) - $this->used_credits;
    }

    /**
     * Check if soft limit threshold has been reached.
     */
    public function isSoftLimitReached(): bool
    {
        return $this->soft_limit_threshold > 0 && $this->used_credits >= $this->soft_limit_threshold;
    }

    /**
     * Check if all credits are exhausted.
     */
    public function isExhausted(): bool
    {
        return $this->totalAvailable() <= 0;
    }
}
