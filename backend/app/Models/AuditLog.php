<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * @property string $id
 * @property string $workspace_id
 * @property string|null $user_id
 * @property string $action
 * @property string $entity_type
 * @property string $entity_id
 * @property array|null $old_values
 * @property array|null $new_values
 */
class AuditLog extends Model
{
    use HasUuids;

    protected $table = 'audit_logs';
    protected $keyType = 'string';
    public $incrementing = false;
    const UPDATED_AT = null;

    protected $fillable = [
        'workspace_id',
        'user_id',
        'action',
        'entity_type',
        'entity_id',
        'old_values',
        'new_values',
    ];

    protected function casts(): array
    {
        return [
            'old_values' => 'array',
            'new_values' => 'array',
        ];
    }
}
