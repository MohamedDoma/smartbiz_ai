<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * @property string $id
 * @property string $workspace_id
 * @property string|null $rule_key
 * @property string $name
 * @property string $entity_type  contact|pipeline_record
 * @property array $match_fields
 * @property string $match_strategy  exact|normalized_exact
 * @property string $action  warn|block
 * @property bool $is_active
 * @property int $sort_order
 */
class DuplicateRule extends Model
{
    use HasUuids;

    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'workspace_id', 'rule_key', 'name', 'entity_type',
        'match_fields', 'match_strategy', 'action',
        'is_active', 'sort_order',
    ];

    protected function casts(): array
    {
        return [
            'match_fields' => 'array',
            'is_active'    => 'boolean',
            'sort_order'   => 'integer',
        ];
    }

    public function matches(): HasMany
    {
        return $this->hasMany(DuplicateMatch::class, 'duplicate_rule_id');
    }
}
