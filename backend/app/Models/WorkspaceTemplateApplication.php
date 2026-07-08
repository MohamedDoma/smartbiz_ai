<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Tracks which business template has been applied to a workspace.
 *
 * @property string $id
 * @property string $workspace_id
 * @property string $business_template_id
 * @property string $template_key
 * @property int $template_version
 * @property string $status
 * @property \Carbon\Carbon|null $applied_at
 * @property string|null $applied_by_user_id
 * @property array|null $snapshot
 */
class WorkspaceTemplateApplication extends Model
{
    use HasUuids;

    protected $table = 'workspace_template_applications';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'workspace_id', 'business_template_id', 'template_key',
        'template_version', 'status', 'applied_at', 'applied_by_user_id',
        'snapshot',
    ];

    protected function casts(): array
    {
        return [
            'template_version' => 'integer',
            'applied_at'       => 'datetime',
            'snapshot'         => 'array',
        ];
    }

    public function workspace(): BelongsTo
    {
        return $this->belongsTo(Workspace::class, 'workspace_id');
    }

    public function template(): BelongsTo
    {
        return $this->belongsTo(BusinessTemplate::class, 'business_template_id');
    }
}
