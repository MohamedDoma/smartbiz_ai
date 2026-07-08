<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * WorkspaceInvitation — employee invite link.
 *
 * Token is stored as SHA-256 hash. Raw token is only returned once at creation.
 *
 * @property string $id
 * @property string $workspace_id
 * @property string $email
 * @property string|null $full_name
 * @property string|null $role_id
 * @property string $invited_by_user_id
 * @property string|null $accepted_user_id
 * @property string $token_hash
 * @property string $status  (pending|accepted|revoked|expired)
 * @property \Carbon\Carbon $expires_at
 * @property \Carbon\Carbon|null $accepted_at
 * @property \Carbon\Carbon|null $revoked_at
 * @property array|null $metadata
 */
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
        'invited_by_user_id',
        'accepted_user_id',
        'token_hash',
        'status',
        'expires_at',
        'accepted_at',
        'revoked_at',
        'metadata',
    ];

    protected function casts(): array
    {
        return [
            'expires_at'  => 'datetime',
            'accepted_at' => 'datetime',
            'revoked_at'  => 'datetime',
            'metadata'    => 'array',
        ];
    }

    // ── Relationships ──────────────────────────────────────────

    public function workspace(): BelongsTo
    {
        return $this->belongsTo(Workspace::class, 'workspace_id');
    }

    public function role(): BelongsTo
    {
        return $this->belongsTo(Role::class, 'role_id');
    }

    public function invitedByUser(): BelongsTo
    {
        return $this->belongsTo(User::class, 'invited_by_user_id');
    }

    public function acceptedUser(): BelongsTo
    {
        return $this->belongsTo(User::class, 'accepted_user_id');
    }

    /**
     * Multi-role pivot rows for this invitation.
     */
    public function invitationRoles(): HasMany
    {
        return $this->hasMany(WorkspaceInvitationRole::class, 'workspace_invitation_id');
    }

    /**
     * Get the primary invitation role (new pivot-based or old role_id fallback).
     */
    public function primaryInvitationRole(): ?Role
    {
        $primary = $this->invitationRoles()
            ->with('role')
            ->where('is_primary', true)
            ->first();

        if ($primary?->role) {
            return $primary->role;
        }

        // Fallback to legacy role_id
        return $this->role;
    }

    // ── Scopes ─────────────────────────────────────────────────

    public function scopePending($query)
    {
        return $query->where('status', 'pending');
    }

    public function scopeNotExpired($query)
    {
        return $query->where('expires_at', '>', now());
    }

    // ── Helpers ────────────────────────────────────────────────

    public function isPending(): bool
    {
        return $this->status === 'pending';
    }

    public function isExpired(): bool
    {
        return $this->expires_at->isPast();
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
