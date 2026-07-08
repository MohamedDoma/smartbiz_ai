<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * @property string $id
 * @property string $workspace_id
 * @property string|null $template_key
 * @property string $name
 * @property string|null $description
 * @property string $data_source
 * @property array $columns
 * @property array|null $filters
 * @property array|null $group_by
 * @property array|null $sort_by
 * @property string $visibility  workspace|private
 * @property string|null $created_by_membership_id
 * @property bool $is_active
 * @property int $sort_order
 */
class ReportTemplate extends Model
{
    use HasUuids;

    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'workspace_id', 'template_key', 'name', 'description',
        'data_source', 'columns', 'filters', 'group_by', 'sort_by',
        'visibility', 'created_by_membership_id', 'is_active', 'sort_order',
    ];

    protected function casts(): array
    {
        return [
            'columns'    => 'array',
            'filters'    => 'array',
            'group_by'   => 'array',
            'sort_by'    => 'array',
            'is_active'  => 'boolean',
            'sort_order' => 'integer',
        ];
    }

    public function createdByMembership(): BelongsTo
    {
        return $this->belongsTo(WorkspaceMembership::class, 'created_by_membership_id');
    }

    public function runs(): HasMany
    {
        return $this->hasMany(ReportRun::class, 'report_template_id');
    }
}
