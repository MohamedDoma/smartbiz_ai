<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * WorkspaceInvitationRole — pivot model linking invitations to multiple roles.
 */
class WorkspaceInvitationRole extends Model
{
    use HasUuids;

    protected $table = 'workspace_invitation_roles';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'workspace_invitation_id',
        'role_id',
        'is_primary',
    ];

    protected function casts(): array
    {
        return [
            'is_primary' => 'boolean',
        ];
    }

    public function invitation(): BelongsTo
    {
        return $this->belongsTo(WorkspaceInvitation::class, 'workspace_invitation_id');
    }

    public function role(): BelongsTo
    {
        return $this->belongsTo(Role::class, 'role_id');
    }
}
