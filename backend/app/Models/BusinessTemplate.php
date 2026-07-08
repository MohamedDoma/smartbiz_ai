<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Business template — defines a reusable industry configuration.
 *
 * @property string $id
 * @property string $template_key
 * @property string $name
 * @property string|null $description
 * @property string $industry_type
 * @property string|null $business_size
 * @property int $version
 * @property bool $is_active
 * @property bool $is_default
 * @property int $sort_order
 * @property array|null $metadata
 */
class BusinessTemplate extends Model
{
    use HasUuids;

    protected $table = 'business_templates';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'template_key', 'name', 'description', 'industry_type',
        'business_size', 'version', 'is_active', 'is_default',
        'sort_order', 'metadata',
    ];

    protected function casts(): array
    {
        return [
            'version'    => 'integer',
            'is_active'  => 'boolean',
            'is_default' => 'boolean',
            'sort_order' => 'integer',
            'metadata'   => 'array',
        ];
    }

    // ── Relationships ──────────────────────────────────────

    public function modules(): HasMany
    {
        return $this->hasMany(BusinessTemplateModule::class, 'business_template_id')
                    ->orderBy('sort_order');
    }

    public function roles(): HasMany
    {
        return $this->hasMany(BusinessTemplateRole::class, 'business_template_id')
                    ->orderBy('sort_order');
    }

    public function workflows(): HasMany
    {
        return $this->hasMany(BusinessTemplateWorkflow::class, 'business_template_id')
                    ->orderBy('sort_order');
    }

    public function customFields(): HasMany
    {
        return $this->hasMany(BusinessTemplateCustomField::class, 'business_template_id')
                    ->orderBy('sort_order');
    }

    public function applications(): HasMany
    {
        return $this->hasMany(WorkspaceTemplateApplication::class, 'business_template_id');
    }
}
