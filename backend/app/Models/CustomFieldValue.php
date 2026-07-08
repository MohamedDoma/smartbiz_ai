<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * @property string $id
 * @property string $workspace_id
 * @property string $custom_field_id
 * @property string $record_type
 * @property string $record_id
 * @property string|null $value_text
 * @property float|null $value_number
 * @property bool|null $value_boolean
 * @property \Carbon\Carbon|null $value_date
 * @property array|null $value_json
 */
class CustomFieldValue extends Model
{
    use HasUuids;

    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'workspace_id', 'custom_field_id', 'record_type', 'record_id',
        'value_text', 'value_number', 'value_boolean', 'value_date', 'value_json',
    ];

    protected function casts(): array
    {
        return [
            'value_number'  => 'decimal:4',
            'value_boolean' => 'boolean',
            'value_date'    => 'date',
            'value_json'    => 'array',
        ];
    }

    public function customField(): BelongsTo
    {
        return $this->belongsTo(CustomField::class);
    }
}
