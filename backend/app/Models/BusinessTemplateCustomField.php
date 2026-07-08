<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * @property string $id
 * @property string $business_template_id
 * @property string $entity_type
 * @property string $field_key
 * @property string $label
 * @property string $field_type
 * @property bool $is_required
 * @property array|null $options
 * @property array|null $validation_rules
 * @property int $sort_order
 */
class BusinessTemplateCustomField extends Model
{
    use HasUuids;

    protected $table = 'business_template_custom_fields';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'business_template_id', 'entity_type', 'field_key', 'label',
        'field_type', 'is_required', 'options', 'validation_rules', 'sort_order',
    ];

    protected function casts(): array
    {
        return [
            'is_required'      => 'boolean',
            'options'          => 'array',
            'validation_rules' => 'array',
            'sort_order'       => 'integer',
        ];
    }

    public function template(): BelongsTo
    {
        return $this->belongsTo(BusinessTemplate::class, 'business_template_id');
    }
}
