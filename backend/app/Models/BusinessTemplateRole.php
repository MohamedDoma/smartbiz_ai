<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * @property string $id
 * @property string $business_template_id
 * @property string $role_key
 * @property string $name
 * @property string|null $description
 * @property int $hierarchy_level
 * @property array|null $permissions
 * @property bool $is_primary_owner_role
 * @property int $sort_order
 */
class BusinessTemplateRole extends Model
{
    use HasUuids;

    protected $table = 'business_template_roles';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'business_template_id', 'role_key', 'name', 'description',
        'hierarchy_level', 'permissions', 'is_primary_owner_role', 'sort_order',
    ];

    protected function casts(): array
    {
        return [
            'hierarchy_level'       => 'integer',
            'permissions'           => 'array',
            'is_primary_owner_role' => 'boolean',
            'sort_order'            => 'integer',
        ];
    }

    public function template(): BelongsTo
    {
        return $this->belongsTo(BusinessTemplate::class, 'business_template_id');
    }
}
