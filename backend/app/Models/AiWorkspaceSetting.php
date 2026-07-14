<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class AiWorkspaceSetting extends Model
{
    use HasUuids;

    protected $table = 'ai_workspace_settings';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'workspace_id', 'ai_enabled',
        'monthly_budget_usd', 'daily_message_limit', 'monthly_message_limit',
        'default_model', 'smart_model', 'metadata',
    ];

    protected function casts(): array
    {
        return [
            'ai_enabled'          => 'boolean',
            'monthly_budget_usd'  => 'decimal:2',
            'daily_message_limit' => 'integer',
            'monthly_message_limit' => 'integer',
            'metadata'            => 'array',
        ];
    }

    public function workspace(): BelongsTo
    {
        return $this->belongsTo(Workspace::class);
    }
}
