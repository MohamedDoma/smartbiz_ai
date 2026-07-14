<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class AiMessage extends Model
{
    use HasUuids;

    protected $table = 'ai_messages';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'conversation_id', 'workspace_id', 'user_id', 'role',
        'content', 'structured_payload', 'model',
        'input_tokens', 'output_tokens', 'total_tokens',
        'estimated_cost_usd', 'metadata',
    ];

    protected function casts(): array
    {
        return [
            'structured_payload' => 'array',
            'metadata'           => 'array',
            'input_tokens'       => 'integer',
            'output_tokens'      => 'integer',
            'total_tokens'       => 'integer',
            'estimated_cost_usd' => 'decimal:6',
        ];
    }

    public function conversation(): BelongsTo
    {
        return $this->belongsTo(AiConversation::class, 'conversation_id');
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
