<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * @property string $id
 * @property string $workspace_id
 * @property string $name
 * @property string|null $role_key
 * @property array $permissions  JSONB permission matrix
 * @property string|null $description
 * @property int $hierarchy_level
 * @property bool $is_system
 * @property bool $is_default
 * @property bool $is_deletable
 * @property bool $is_active
 * @property int $sort_order
 */
class Role extends Model
{
    use HasUuids;

    protected $table = 'roles';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'workspace_id',
        'name',
        'role_key',
        'permissions',
        'description',
        'hierarchy_level',
        'is_system',
        'is_default',
        'is_deletable',
        'is_active',
        'sort_order',
    ];

    protected function casts(): array
    {
        return [
            'permissions' => 'array',
            'hierarchy_level' => 'integer',
            'is_system' => 'boolean',
            'is_default' => 'boolean',
            'is_deletable' => 'boolean',
            'is_active' => 'boolean',
            'sort_order' => 'integer',
        ];
    }

    // ── Relationships ──────────────────────────────────────────

    public function workspace(): BelongsTo
    {
        return $this->belongsTo(Workspace::class, 'workspace_id');
    }

    public function membershipRoles(): HasMany
    {
        return $this->hasMany(MembershipRole::class, 'role_id');
    }

    // ── Scopes ─────────────────────────────────────────────────

    public function scopeActive($query)
    {
        return $query->where('is_active', true);
    }
}
