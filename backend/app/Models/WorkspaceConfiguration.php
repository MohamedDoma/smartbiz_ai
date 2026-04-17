<?php
namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class WorkspaceConfiguration extends Model
{
    use HasUuids;

    protected $table = 'workspace_configurations';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'workspace_id', 'enabled_modules', 'role_configs',
        'pages', 'workflows', 'automations', 'provisioning_run_id',
    ];

    protected function casts(): array
    {
        return [
            'enabled_modules' => 'array',
            'role_configs'    => 'array',
            'pages'           => 'array',
            'workflows'       => 'array',
            'automations'     => 'array',
            'created_at'      => 'datetime',
            'updated_at'      => 'datetime',
        ];
    }

    public function workspace(): BelongsTo { return $this->belongsTo(Workspace::class); }
    public function provisioningRun(): BelongsTo { return $this->belongsTo(ProvisioningRun::class); }
}
