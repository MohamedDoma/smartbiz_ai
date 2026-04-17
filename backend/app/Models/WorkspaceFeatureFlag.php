<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class WorkspaceFeatureFlag extends Model
{
    use HasUuids;

    protected $table = 'workspace_feature_flags';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'workspace_id', 'feature_key', 'is_enabled',
        'override_reason', 'set_by',
    ];

    protected function casts(): array
    {
        return ['is_enabled' => 'boolean'];
    }

    public function workspace(): BelongsTo
    {
        return $this->belongsTo(Workspace::class, 'workspace_id');
    }
}
