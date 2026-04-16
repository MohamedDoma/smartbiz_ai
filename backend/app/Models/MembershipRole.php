<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Junction: membership ↔ role assignment.
 *
 * @property string $id
 * @property string $workspace_id
 * @property string $membership_id
 * @property string $role_id
 * @property bool $is_primary
 * @property string|null $assigned_by
 * @property \Carbon\Carbon $assigned_at
 */
class MembershipRole extends Model
{
    use HasUuids;

    protected $table = 'membership_roles';
    protected $keyType = 'string';
    public $incrementing = false;
    public $timestamps = false;

    protected $fillable = [
        'workspace_id',
        'membership_id',
        'role_id',
        'is_primary',
        'assigned_by',
        'assigned_at',
    ];

    protected function casts(): array
    {
        return [
            'is_primary' => 'boolean',
            'assigned_at' => 'datetime',
        ];
    }

    // ── Relationships ──────────────────────────────────────────

    public function membership(): BelongsTo
    {
        return $this->belongsTo(WorkspaceMembership::class, 'membership_id');
    }

    public function role(): BelongsTo
    {
        return $this->belongsTo(Role::class, 'role_id');
    }
}
