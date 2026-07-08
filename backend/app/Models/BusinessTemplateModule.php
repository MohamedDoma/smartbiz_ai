<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * @property string $id
 * @property string $business_template_id
 * @property string $module_key
 * @property string $name
 * @property string|null $description
 * @property bool $is_enabled
 * @property bool $is_required
 * @property array|null $settings
 * @property int $sort_order
 */
class BusinessTemplateModule extends Model
{
    use HasUuids;

    protected $table = 'business_template_modules';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'business_template_id', 'module_key', 'name', 'description',
        'is_enabled', 'is_required', 'settings', 'sort_order',
    ];

    protected function casts(): array
    {
        return [
            'is_enabled'  => 'boolean',
            'is_required' => 'boolean',
            'settings'    => 'array',
            'sort_order'  => 'integer',
        ];
    }

    public function template(): BelongsTo
    {
        return $this->belongsTo(BusinessTemplate::class, 'business_template_id');
    }
}
