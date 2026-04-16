<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Chart of Accounts — hierarchical via parent_id.
 *
 * NOTE: The accounts table has NO updated_at column.
 *
 * @property string $id
 * @property string $workspace_id
 * @property string $code
 * @property string $name
 * @property string $type   asset|liability|equity|revenue|expense
 * @property string|null $parent_id
 * @property float $balance
 */
class Account extends Model
{
    use HasUuids;

    protected $table = 'accounts';
    protected $keyType = 'string';
    public $incrementing = false;

    // accounts table has created_at but NO updated_at
    const UPDATED_AT = null;

    protected $fillable = [
        'workspace_id',
        'code',
        'name',
        'type',
        'parent_id',
    ];

    protected function casts(): array
    {
        return [
            'balance' => 'decimal:2',
        ];
    }

    // ── Relationships ──────────────────────────────────────────

    public function parent(): BelongsTo
    {
        return $this->belongsTo(self::class, 'parent_id');
    }

    public function children(): HasMany
    {
        return $this->hasMany(self::class, 'parent_id');
    }
}
