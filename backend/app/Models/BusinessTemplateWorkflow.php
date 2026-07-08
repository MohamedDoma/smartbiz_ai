<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * @property string $id
 * @property string $business_template_id
 * @property string $workflow_type
 * @property string $workflow_key
 * @property string $name
 * @property string|null $description
 * @property array|null $config
 * @property bool $is_active
 * @property int $sort_order
 */
class BusinessTemplateWorkflow extends Model
{
    use HasUuids;

    protected $table = 'business_template_workflows';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'business_template_id', 'workflow_type', 'workflow_key', 'name',
        'description', 'config', 'is_active', 'sort_order',
    ];

    protected function casts(): array
    {
        return [
            'config'     => 'array',
            'is_active'  => 'boolean',
            'sort_order' => 'integer',
        ];
    }

    public function template(): BelongsTo
    {
        return $this->belongsTo(BusinessTemplate::class, 'business_template_id');
    }
}
