<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * A single step within an approval workflow.
 *
 * Approver resolution is configuration-driven:
 *  - 'permission':          Any membership holding approver_permission_key
 *  - 'requester_manager':   The requester's manager_membership_id
 *  - 'specific_membership': A fixed membership (approver_membership_id)
 *
 * @property string $id
 * @property string $workspace_id
 * @property string $workflow_id
 * @property string $name
 * @property int $step_order
 * @property string $approver_type
 * @property string|null $approver_permission_key
 * @property string|null $approver_membership_id
 * @property array $conditions
 * @property bool $allow_self_approval
 * @property bool $is_active
 */
class ApprovalWorkflowStep extends Model
{
    use HasUuids;

    protected $table = 'approval_workflow_steps';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'workspace_id',
        'workflow_id',
        'name',
        'step_order',
        'approver_type',
        'approver_permission_key',
        'approver_membership_id',
        'conditions',
        'allow_self_approval',
        'is_active',
    ];

    protected function casts(): array
    {
        return [
            'conditions'          => 'array',
            'allow_self_approval' => 'boolean',
            'is_active'           => 'boolean',
        ];
    }

    // ── Relationships ──────────────────────────────────────────

    public function workflow(): BelongsTo
    {
        return $this->belongsTo(ApprovalWorkflow::class, 'workflow_id');
    }

    public function approverMembership(): BelongsTo
    {
        return $this->belongsTo(WorkspaceMembership::class, 'approver_membership_id');
    }

    // ── Scopes ─────────────────────────────────────────────────

    public function scopeActive($query)
    {
        return $query->where('is_active', true);
    }
}
