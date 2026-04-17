<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class DiscoveryMessage extends Model
{
    use HasUuids;

    protected $table = 'discovery_messages';
    public $timestamps = false;

    protected $fillable = [
        'session_id',
        'workspace_id',
        'role',
        'content',
        'message_type',
        'metadata',
    ];

    protected $casts = [
        'metadata'   => 'array',
        'created_at' => 'datetime',
    ];

    // ── Relationships ─────────────────────────────────────────────

    public function session(): BelongsTo
    {
        return $this->belongsTo(DiscoverySession::class, 'session_id');
    }

    public function workspace(): BelongsTo
    {
        return $this->belongsTo(Workspace::class);
    }
}
