<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class ProvisioningRun extends Model
{
    use HasUuids;

    protected $table = 'provisioning_runs';
    protected $keyType = 'string';
    public $incrementing = false;
    public $timestamps = false;

    protected $fillable = [
        'workspace_id', 'blueprint_id', 'status', 'config',
        'applied_by', 'applied_at', 'version',
        'rollback_config', 'error_message', 'created_at',
    ];

    protected function casts(): array
    {
        return [
            'config'          => 'array',
            'rollback_config' => 'array',
            'applied_at'      => 'datetime',
            'created_at'      => 'datetime',
        ];
    }

    public function workspace(): BelongsTo { return $this->belongsTo(Workspace::class); }
    public function blueprint(): BelongsTo { return $this->belongsTo(DiscoveryBlueprint::class, 'blueprint_id'); }
    public function appliedBy(): BelongsTo { return $this->belongsTo(User::class, 'applied_by'); }
}
