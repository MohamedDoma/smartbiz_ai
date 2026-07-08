<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * @property string $id
 * @property string $workspace_id
 * @property string $pipeline_id
 * @property string|null $stage_key
 * @property string $name
 * @property string|null $description
 * @property string $status_type  open|won|lost|completed|cancelled
 * @property int $sort_order
 * @property bool $is_active
 */
class PipelineStage extends Model
{
    use HasUuids;

    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'workspace_id', 'pipeline_id', 'stage_key', 'name',
        'description', 'status_type', 'sort_order', 'is_active',
    ];

    protected function casts(): array
    {
        return [
            'is_active'  => 'boolean',
            'sort_order' => 'integer',
        ];
    }

    public function pipeline(): BelongsTo
    {
        return $this->belongsTo(Pipeline::class);
    }

    public function records(): HasMany
    {
        return $this->hasMany(PipelineRecord::class, 'stage_id');
    }
}
