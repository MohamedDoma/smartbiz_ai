<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * @property string $id
 * @property string|null $campaign_key
 * @property string $name
 * @property string|null $description
 * @property string|null $target_market
 * @property string|null $default_plan_key
 * @property int|null $trial_days
 * @property \Carbon\Carbon|null $starts_at
 * @property \Carbon\Carbon|null $expires_at
 * @property string $status
 * @property string|null $created_by_user_id
 */
class PlatformActivationCampaign extends Model
{
    use HasUuids;

    protected $table = 'platform_activation_campaigns';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'campaign_key', 'name', 'description', 'target_market',
        'default_plan_key', 'trial_days', 'starts_at', 'expires_at',
        'status', 'created_by_user_id',
    ];

    protected function casts(): array
    {
        return [
            'trial_days' => 'integer',
            'starts_at'  => 'datetime',
            'expires_at' => 'datetime',
        ];
    }

    public function codes(): HasMany
    {
        return $this->hasMany(PlatformActivationCode::class, 'campaign_id');
    }

    public function createdBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by_user_id');
    }
}
