<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class AiUsageLog extends Model
{
    use HasUuids;

    protected $table = 'ai_usage_logs';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'workspace_id', 'user_id', 'conversation_id', 'message_id',
        'provider', 'model', 'operation',
        'input_tokens', 'output_tokens', 'total_tokens',
        'estimated_cost_usd', 'success', 'error_code', 'error_message',
        'request_id', 'duration_ms', 'metadata',
    ];

    protected function casts(): array
    {
        return [
            'metadata'           => 'array',
            'input_tokens'       => 'integer',
            'output_tokens'      => 'integer',
            'total_tokens'       => 'integer',
            'estimated_cost_usd' => 'decimal:6',
            'success'            => 'boolean',
            'duration_ms'        => 'integer',
        ];
    }

    public function conversation(): BelongsTo
    {
        return $this->belongsTo(AiConversation::class, 'conversation_id');
    }

    public function message(): BelongsTo
    {
        return $this->belongsTo(AiMessage::class, 'message_id');
    }

    public function workspace(): BelongsTo
    {
        return $this->belongsTo(Workspace::class);
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
