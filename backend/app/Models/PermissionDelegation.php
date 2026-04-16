<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Temporary delegation of permissions from one membership to another.
 *
 * @property string $id
 * @property string $workspace_id
 * @property string $delegator_membership_id
 * @property string $delegate_membership_id
 * @property \Carbon\Carbon $start_at
 * @property \Carbon\Carbon $end_at
 * @property string $reason
 * @property string $status  (active|revoked|expired)
 */
class PermissionDelegation extends Model
{
    use HasUuids;

    protected $table = 'permission_delegations';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'workspace_id',
        'delegator_membership_id',
        'delegate_membership_id',
        'start_at',
        'end_at',
        'reason',
        'status',
    ];

    protected function casts(): array
    {
        return [
            'start_at' => 'datetime',
            'end_at' => 'datetime',
            'revoked_at' => 'datetime',
        ];
    }

    // ── Relationships ──────────────────────────────────────────

    public function delegator(): BelongsTo
    {
        return $this->belongsTo(WorkspaceMembership::class, 'delegator_membership_id');
    }

    public function delegate(): BelongsTo
    {
        return $this->belongsTo(WorkspaceMembership::class, 'delegate_membership_id');
    }

    public function items(): HasMany
    {
        return $this->hasMany(PermissionDelegationItem::class, 'delegation_id');
    }

    // ── Scopes ─────────────────────────────────────────────────

    /**
     * Only delegations that are currently active and within their time window.
     */
    public function scopeCurrentlyActive($query)
    {
        $now = now();
        return $query->where('status', 'active')
                     ->where('start_at', '<=', $now)
                     ->where('end_at', '>=', $now);
    }
}
