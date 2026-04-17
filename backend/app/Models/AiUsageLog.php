<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class AiUsageLog extends Model
{
    use HasUuids;

    protected $table = 'ai_usage_logs';
    protected $keyType = 'string';
    public $incrementing = false;
    public $timestamps = false;

    protected $fillable = [
        'workspace_id', 'user_id', 'action_type',
        'credits_charged', 'request_metadata',
        'response_metadata', 'duration_ms', 'created_at',
    ];

    protected function casts(): array
    {
        return [
            'credits_charged' => 'integer',
            'request_metadata' => 'array',
            'response_metadata' => 'array',
            'duration_ms' => 'integer',
            'created_at' => 'datetime',
        ];
    }
}
