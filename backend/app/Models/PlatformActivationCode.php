<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * @property string $id
 * @property string|null $campaign_id
 * @property string $code
 * @property string|null $registration_url
 * @property string|null $default_plan_key
 * @property int|null $trial_days
 * @property int $max_uses
 * @property int $used_count
 * @property string $status
 * @property string|null $assigned_to_name
 * @property string|null $assigned_to_phone
 * @property string|null $used_by_user_id
 * @property string|null $used_workspace_id
 * @property \Carbon\Carbon|null $used_at
 * @property \Carbon\Carbon|null $expires_at
 * @property array|null $metadata
 */
class PlatformActivationCode extends Model
{
    use HasUuids;

    protected $table = 'platform_activation_codes';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'campaign_id', 'code', 'registration_url', 'default_plan_key',
        'trial_days', 'max_uses', 'used_count', 'status',
        'assigned_to_name', 'assigned_to_phone',
        'used_by_user_id', 'used_workspace_id', 'used_at',
        'expires_at', 'metadata',
    ];

    protected function casts(): array
    {
        return [
            'max_uses'   => 'integer',
            'used_count' => 'integer',
            'trial_days' => 'integer',
            'used_at'    => 'datetime',
            'expires_at' => 'datetime',
            'metadata'   => 'array',
        ];
    }

    public function campaign(): BelongsTo
    {
        return $this->belongsTo(PlatformActivationCampaign::class, 'campaign_id');
    }

    public function usedByUser(): BelongsTo
    {
        return $this->belongsTo(User::class, 'used_by_user_id');
    }

    public function usedWorkspace(): BelongsTo
    {
        return $this->belongsTo(Workspace::class, 'used_workspace_id');
    }

    /**
     * Whether this code can be used for registration.
     */
    public function isUsable(): bool
    {
        if ($this->status === 'disabled' || $this->status === 'expired') {
            return false;
        }
        if ($this->used_count >= $this->max_uses) {
            return false;
        }
        if ($this->expires_at && $this->expires_at->isPast()) {
            return false;
        }
        return true;
    }
}
