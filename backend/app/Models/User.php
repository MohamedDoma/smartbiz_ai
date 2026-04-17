<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Laravel\Sanctum\HasApiTokens;

/**
 * SmartBiz AI User model.
 *
 * Maps to the live `users` table which uses the membership model (migration 006+).
 * Auth is via email + password_hash. Workspace access is via workspace_memberships.
 *
 * @property string $id
 * @property string $full_name
 * @property string $email
 * @property string $phone_number
 * @property string $password_hash
 * @property bool $is_active
 * @property bool $is_super_admin
 * @property string|null $preferred_locale
 * @property \Carbon\Carbon $created_at
 * @property \Carbon\Carbon $updated_at
 */
class User extends Authenticatable
{
    use HasApiTokens, HasUuids;

    protected $table = 'users';
    protected $keyType = 'string';
    public $incrementing = false;

    /**
     * Override Laravel's default password column name.
     * The live DB uses `password_hash`, not `password`.
     */
    public function getAuthPassword(): string
    {
        return $this->password_hash;
    }

    protected $fillable = [
        'full_name',
        'email',
        'phone_number',
        'password_hash',
        'is_active',
        'is_super_admin',
        'preferred_locale',
    ];

    protected $hidden = [
        'password_hash',
        'is_super_admin',
    ];

    protected function casts(): array
    {
        return [
            'is_active' => 'boolean',
            'is_super_admin' => 'boolean',
            'created_at' => 'datetime',
            'updated_at' => 'datetime',
        ];
    }

    // ── Relationships ──────────────────────────────────────────

    public function memberships(): HasMany
    {
        return $this->hasMany(WorkspaceMembership::class, 'user_id');
    }

    public function activeMemberships(): HasMany
    {
        return $this->memberships()->where('status', 'active');
    }
}
