<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Tracks the status of one workflow step within an approval request.
 *
 * @property string $id
 * @property string $workspace_id
 * @property string $approval_request_id
 * @property string $workflow_step_id
 * @property int $step_order
 * @property string $status
 * @property string|null $decided_by_membership_id
 * @property string|null $decision_notes
 * @property \Carbon\Carbon|null $decided_at
 */
class ApprovalRequestStep extends Model
{
    use HasUuids;

    protected $table = 'approval_request_steps';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'workspace_id',
        'approval_request_id',
        'workflow_step_id',
        'step_order',
        'status',
        'decided_by_membership_id',
        'decision_notes',
        'decided_at',
    ];

    protected function casts(): array
    {
        return [
            'decided_at' => 'datetime',
        ];
    }

    // ── Relationships ──────────────────────────────────────────

    public function approvalRequest(): BelongsTo
    {
        return $this->belongsTo(ApprovalRequest::class, 'approval_request_id');
    }

    public function workflowStep(): BelongsTo
    {
        return $this->belongsTo(ApprovalWorkflowStep::class, 'workflow_step_id');
    }

    public function decidedByMembership(): BelongsTo
    {
        return $this->belongsTo(WorkspaceMembership::class, 'decided_by_membership_id');
    }
}
