<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class WorkspaceInvitation extends Model
{
    use HasUuids;

    protected $table = 'workspace_invitations';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'workspace_id',
        'email',
        'full_name',
        'role_id',
        'department_id',
        'team_id',
        'job_title',
        'preferred_locale',
        'invited_by_user_id',
        'accepted_user_id',
        'token_hash',
        'token_encrypted',
        'status',
        'expires_at',
        'last_sent_at',
        'send_count',
        'delivery_status',
        'delivery_error',
        'accepted_at',
        'revoked_at',
        'metadata',
    ];

    protected function casts(): array
    {
        return [
            'token_encrypted' => 'encrypted',
            'expires_at'      => 'datetime',
            'last_sent_at'    => 'datetime',
            'accepted_at'     => 'datetime',
            'revoked_at'      => 'datetime',
            'send_count'      => 'integer',
            'metadata'        => 'array',
        ];
    }

    public function workspace(): BelongsTo
    {
        return $this->belongsTo(Workspace::class, 'workspace_id');
    }

    public function role(): BelongsTo
    {
        return $this->belongsTo(Role::class, 'role_id');
    }

    public function department(): BelongsTo
    {
        return $this->belongsTo(Department::class, 'department_id');
    }

    public function team(): BelongsTo
    {
        return $this->belongsTo(Team::class, 'team_id');
    }

    public function invitedByUser(): BelongsTo
    {
        return $this->belongsTo(User::class, 'invited_by_user_id');
    }

    public function acceptedUser(): BelongsTo
    {
        return $this->belongsTo(User::class, 'accepted_user_id');
    }

    public function invitationRoles(): HasMany
    {
        return $this->hasMany(WorkspaceInvitationRole::class, 'workspace_invitation_id');
    }

    public function primaryInvitationRole(): ?Role
    {
        if ($this->relationLoaded('invitationRoles')) {
            $primary = $this->invitationRoles->firstWhere('is_primary', true)
                ?? $this->invitationRoles->first();

            if ($primary?->role) {
                return $primary->role;
            }
        }

        $primary = $this->invitationRoles()
            ->with('role')
            ->where('is_primary', true)
            ->first();

        return $primary?->role ?? $this->role;
    }

    public function scopePending($query)
    {
        return $query->where('status', 'pending');
    }

    public function scopeNotExpired($query)
    {
        return $query->where('expires_at', '>', now());
    }

    public function isPending(): bool
    {
        return $this->status === 'pending';
    }

    public function isExpired(): bool
    {
        return $this->expires_at?->isPast() ?? true;
    }

    public function isAccepted(): bool
    {
        return $this->status === 'accepted';
    }

    public function isRevoked(): bool
    {
        return $this->status === 'revoked';
    }
}
