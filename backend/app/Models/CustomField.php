<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * @property string $id
 * @property string $workspace_id
 * @property string|null $pipeline_id
 * @property string|null $field_key
 * @property string $label
 * @property string $field_type  text|textarea|number|date|boolean|select|multi_select|currency
 * @property array|null $options
 * @property bool $is_required
 * @property string $applies_to
 * @property bool $is_active
 * @property int $sort_order
 */
class CustomField extends Model
{
    use HasUuids;

    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'workspace_id', 'pipeline_id', 'field_key', 'label', 'field_type',
        'options', 'is_required', 'applies_to', 'is_active', 'sort_order',
    ];

    protected function casts(): array
    {
        return [
            'options'     => 'array',
            'is_required' => 'boolean',
            'is_active'   => 'boolean',
            'sort_order'  => 'integer',
        ];
    }

    public const ALLOWED_TYPES = [
        'text', 'textarea', 'number', 'date', 'boolean',
        'select', 'multi_select', 'currency',
    ];

    public function pipeline(): BelongsTo
    {
        return $this->belongsTo(Pipeline::class);
    }

    public function values(): HasMany
    {
        return $this->hasMany(CustomFieldValue::class);
    }
}
