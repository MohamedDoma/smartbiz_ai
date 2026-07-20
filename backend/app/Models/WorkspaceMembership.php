<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * WorkspaceMembership — the pivot between users and workspaces.
 *
 * This is the core of the membership model introduced in migration 006.
 * Each row represents a user's membership in a specific workspace with
 * department, branch, shift, status, and HR fields.
 *
 * @property string $id
 * @property string $workspace_id
 * @property string $user_id
 * @property string|null $department_id
 * @property string|null $team_id
 * @property string|null $job_title
 * @property string|null $branch_id
 * @property string|null $shift_id
 * @property string|null $manager_membership_id
 * @property string $status  (pending|active|suspended|removed)
 * @property string|null $hire_date
 * @property float|null $base_salary
 * @property int|null $annual_leave_balance
 * @property array $assigned_warehouses
 */
class WorkspaceMembership extends Model
{
    use HasUuids;

    protected $table = 'workspace_memberships';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'workspace_id',
        'user_id',
        'department_id',
        'team_id',
        'job_title',
        'branch_id',
        'shift_id',
        'manager_membership_id',
        'status',
        'joined_at',
        'suspended_at',
        'removed_at',
        'hire_date',
        'base_salary',
        'annual_leave_balance',
        'assigned_warehouses',
    ];

    protected function casts(): array
    {
        return [
            'assigned_warehouses' => 'array',
            'base_salary' => 'decimal:2',
            'annual_leave_balance' => 'integer',
            'hire_date' => 'date',
            'joined_at' => 'datetime',
            'suspended_at' => 'datetime',
            'removed_at' => 'datetime',
        ];
    }

    // ── Relationships ──────────────────────────────────────────

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class, 'user_id');
    }

    public function workspace(): BelongsTo
    {
        return $this->belongsTo(Workspace::class, 'workspace_id');
    }

    public function membershipRoles(): HasMany
    {
        return $this->hasMany(MembershipRole::class, 'membership_id');
    }

    public function permissionOverrides(): HasMany
    {
        return $this->hasMany(UserPermissionOverride::class, 'membership_id');
    }

    /**
     * Delegations where this membership is the delegate (receiver of permissions).
     */
    public function receivedDelegations(): HasMany
    {
        return $this->hasMany(PermissionDelegation::class, 'delegate_membership_id');
    }

    public function department(): BelongsTo
    {
        return $this->belongsTo(Department::class, 'department_id');
    }

    public function team(): BelongsTo
    {
        return $this->belongsTo(Team::class, 'team_id');
    }

    public function managerMembership(): BelongsTo
    {
        return $this->belongsTo(self::class, 'manager_membership_id');
    }

    public function directReports(): HasMany
    {
        return $this->hasMany(self::class, 'manager_membership_id');
    }

    // ── Scopes ─────────────────────────────────────────────────

    public function scopeActive($query)
    {
        return $query->where('status', 'active');
    }
}
