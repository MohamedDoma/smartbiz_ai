<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Reusable approval workflow definition.
 *
 * A workflow defines an ordered sequence of approval steps
 * that can be applied to any entity_type (commission_entry, invoice, etc.).
 *
 * @property string $id
 * @property string $workspace_id
 * @property string $workflow_key
 * @property string $name
 * @property string|null $description
 * @property string $entity_type
 * @property array $trigger_conditions
 * @property bool $is_active
 * @property int $sort_order
 * @property string|null $created_by
 */
class ApprovalWorkflow extends Model
{
    use HasUuids;

    protected $table = 'approval_workflows';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'workspace_id',
        'workflow_key',
        'name',
        'description',
        'entity_type',
        'trigger_conditions',
        'is_active',
        'sort_order',
        'created_by',
    ];

    protected function casts(): array
    {
        return [
            'trigger_conditions' => 'array',
            'is_active'          => 'boolean',
        ];
    }

    // ── Relationships ──────────────────────────────────────────

    public function workspace(): BelongsTo
    {
        return $this->belongsTo(Workspace::class, 'workspace_id');
    }

    public function steps(): HasMany
    {
        return $this->hasMany(ApprovalWorkflowStep::class, 'workflow_id')
                    ->orderBy('step_order');
    }

    public function activeSteps(): HasMany
    {
        return $this->hasMany(ApprovalWorkflowStep::class, 'workflow_id')
                    ->where('is_active', true)
                    ->orderBy('step_order');
    }

    public function requests(): HasMany
    {
        return $this->hasMany(ApprovalRequest::class, 'workflow_id');
    }

    // ── Scopes ─────────────────────────────────────────────────

    public function scopeActive($query)
    {
        return $query->where('is_active', true);
    }

    public function scopeForEntity($query, string $entityType)
    {
        return $query->where('entity_type', $entityType);
    }
}
