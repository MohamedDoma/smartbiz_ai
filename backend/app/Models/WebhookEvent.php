<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class WebhookEvent extends Model
{
    use HasUuids;

    protected $table = 'webhook_events';
    protected $keyType = 'string';
    public $incrementing = false;
    public $timestamps = false;

    protected $fillable = [
        'stripe_event_id', 'event_type', 'payload',
        'status', 'processed_at', 'error_message', 'created_at',
    ];

    protected function casts(): array
    {
        return [
            'payload'      => 'array',
            'processed_at' => 'datetime',
            'created_at'   => 'datetime',
        ];
    }

    /**
     * Check if this event has already been processed.
     */
    public function isProcessed(): bool
    {
        return $this->status === 'processed';
    }
}
