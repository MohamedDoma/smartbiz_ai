<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Grant/deny override for a specific permission key on a membership.
 *
 * @property string $id
 * @property string $workspace_id
 * @property string $membership_id
 * @property string $permission_key
 * @property string $scope           e.g. 'workspace', 'branch', 'own'
 * @property string $override_type   'grant' or 'deny'
 * @property string|null $reason
 * @property string $granted_by_membership_id
 * @property \Carbon\Carbon|null $expires_at
 */
class UserPermissionOverride extends Model
{
    use HasUuids;

    protected $table = 'user_permission_overrides';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'workspace_id',
        'membership_id',
        'permission_key',
        'scope',
        'override_type',
        'reason',
        'granted_by_membership_id',
        'expires_at',
    ];

    protected function casts(): array
    {
        return [
            'expires_at' => 'datetime',
        ];
    }

    // ── Relationships ──────────────────────────────────────────

    public function membership(): BelongsTo
    {
        return $this->belongsTo(WorkspaceMembership::class, 'membership_id');
    }

    // ── Scopes ─────────────────────────────────────────────────

    /**
     * Only overrides that have not expired.
     */
    public function scopeActive($query)
    {
        return $query->where(function ($q) {
            $q->whereNull('expires_at')
              ->orWhere('expires_at', '>', now());
        });
    }
}
