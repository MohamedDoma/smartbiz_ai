<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasOne;

class DiscoverySession extends Model
{
    use HasUuids;

    protected $table = 'discovery_sessions';

    protected $fillable = [
        'workspace_id',
        'created_by',
        'status',
        'business_description',
        'business_type',
        'classification_confidence',
        'classification_method',
        'classification_version',
        'discovery_state',
    ];

    protected $casts = [
        'classification_confidence' => 'float',
        'discovery_state'           => 'array',
        'created_at' => 'datetime',
        'updated_at' => 'datetime',
    ];

    // ── Relationships ─────────────────────────────────────────────

    public function workspace(): BelongsTo
    {
        return $this->belongsTo(Workspace::class);
    }

    public function creator(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by');
    }

    public function messages(): HasMany
    {
        return $this->hasMany(DiscoveryMessage::class, 'session_id')->orderBy('created_at');
    }

    public function blueprint(): HasOne
    {
        return $this->hasOne(DiscoveryBlueprint::class, 'session_id');
    }
}
