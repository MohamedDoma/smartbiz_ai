<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * @property string $id
 * @property string $workspace_id
 * @property string $user_id
 * @property string $title
 * @property string $message
 * @property string $type      info|warning|alert|success
 * @property bool $is_read
 * @property string|null $link_url
 */
class Notification extends Model
{
    use HasUuids;

    protected $table = 'notifications';
    protected $keyType = 'string';
    public $incrementing = false;
    const UPDATED_AT = null;

    protected $fillable = [
        'workspace_id',
        'user_id',
        'title',
        'message',
        'type',
        'is_read',
        'link_url',
    ];

    protected function casts(): array
    {
        return ['is_read' => 'boolean'];
    }
}
