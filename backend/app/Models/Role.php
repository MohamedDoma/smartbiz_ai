<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

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
    ];

    protected function casts(): array
    {
        return [
            'permissions' => 'array',
            'hierarchy_level' => 'integer',
            'is_system' => 'boolean',
            'is_default' => 'boolean',
            'is_deletable' => 'boolean',
        ];
    }

    // ── Relationships ──────────────────────────────────────────

    public function workspace(): BelongsTo
    {
        return $this->belongsTo(Workspace::class, 'workspace_id');
    }
}
