<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Branch / Location entity.
 *
 * Uses the existing `branches` table which serves as the workspace location model.
 *
 * @property string $id
 * @property string $workspace_id
 * @property string $name
 * @property string|null $location
 * @property bool $is_active
 * @property string|null $phone
 * @property array|null $metadata  Provenance: provisioning_run_id, blueprint_id, template_key, etc.
 */
class Branch extends Model
{
    use HasUuids;

    protected $table = 'branches';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'workspace_id',
        'name',
        'location',
        'is_active',
        'phone',
        'metadata',
    ];

    protected function casts(): array
    {
        return [
            'is_active' => 'boolean',
            'metadata'  => 'array',
        ];
    }

    public function workspace(): BelongsTo
    {
        return $this->belongsTo(Workspace::class);
    }
}
