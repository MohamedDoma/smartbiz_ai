<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * @property string $id
 * @property string $name
 * @property string|null $industry_type
 * @property string|null $business_size
 * @property array|null $onboarding_data
 * @property string|null $invite_code
 * @property string $subscription_status
 * @property string $default_locale
 * @property string $default_currency
 * @property string $timezone
 * @property string|null $status
 * @property bool $is_active
 */
class Workspace extends Model
{
    use HasUuids;

    protected $table = 'workspaces';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'name',
        'industry_type',
        'business_size',
        'onboarding_data',
        'invite_code',
        'subscription_status',
        'default_locale',
        'default_currency',
        'timezone',
        'status',
        'is_active',
    ];

    protected function casts(): array
    {
        return [
            'onboarding_data' => 'array',
            'ui_configuration' => 'array',
            'is_active' => 'boolean',
            'max_users' => 'integer',
            'subscription_end_date' => 'datetime',
        ];
    }

    // ── Relationships ──────────────────────────────────────────

    public function memberships(): HasMany
    {
        return $this->hasMany(WorkspaceMembership::class, 'workspace_id');
    }

    public function activeMemberships(): HasMany
    {
        return $this->memberships()->where('status', 'active');
    }

    public function roles(): HasMany
    {
        return $this->hasMany(Role::class, 'workspace_id');
    }
}
