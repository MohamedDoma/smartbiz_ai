<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Reference table — not UUID-keyed, has composite natural key (key).
 *
 * @property string $key          e.g. 'products.create'
 * @property string $module       e.g. 'inventory'
 * @property string $entity       e.g. 'products'
 * @property string $action       e.g. 'create'
 * @property string $scope_type   e.g. 'workspace'
 * @property array $applicable_scopes
 * @property string|null $description
 */
class PermissionDefinition extends Model
{
    protected $table = 'permission_definitions';
    protected $primaryKey = 'key';
    protected $keyType = 'string';
    public $incrementing = false;
    public $timestamps = false;

    protected $fillable = [
        'key',
        'module',
        'entity',
        'action',
        'scope_type',
        'applicable_scopes',
        'description',
    ];

    protected function casts(): array
    {
        return [
            'applicable_scopes' => 'array',
        ];
    }
}
