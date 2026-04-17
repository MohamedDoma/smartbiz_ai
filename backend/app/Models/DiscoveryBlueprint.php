<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class DiscoveryBlueprint extends Model
{
    use HasUuids;

    protected $table = 'discovery_blueprints';

    protected $fillable = [
        'session_id',
        'workspace_id',
        'business_type',
        'blueprint',
        'version',
        'generator_method',
        'generator_version',
    ];

    protected $casts = [
        'blueprint'  => 'array',
        'version'    => 'integer',
        'created_at' => 'datetime',
        'updated_at' => 'datetime',
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
