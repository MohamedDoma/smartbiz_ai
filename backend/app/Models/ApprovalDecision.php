<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Immutable audit record of an approval decision.
 *
 * Stores a snapshot of the actor's identity and permissions at the time
 * of the decision, ensuring full auditability even if roles change later.
 *
 * @property string $id
 * @property string $workspace_id
 * @property string $approval_request_id
 * @property string $approval_request_step_id
 * @property string $actor_membership_id
 * @property string $decision
 * @property string|null $notes
 * @property array $actor_snapshot
 * @property \Carbon\Carbon $created_at
 */
class ApprovalDecision extends Model
{
    use HasUuids;

    protected $table = 'approval_decisions';
    protected $keyType = 'string';
    public $incrementing = false;

    const UPDATED_AT = null; // Immutable — no updates

    protected $fillable = [
        'workspace_id',
        'approval_request_id',
        'approval_request_step_id',
        'actor_membership_id',
        'decision',
        'notes',
        'actor_snapshot',
    ];

    protected function casts(): array
    {
        return [
            'actor_snapshot' => 'array',
        ];
    }

    // ── Relationships ──────────────────────────────────────────

    public function approvalRequest(): BelongsTo
    {
        return $this->belongsTo(ApprovalRequest::class, 'approval_request_id');
    }

    public function requestStep(): BelongsTo
    {
        return $this->belongsTo(ApprovalRequestStep::class, 'approval_request_step_id');
    }

    public function actorMembership(): BelongsTo
    {
        return $this->belongsTo(WorkspaceMembership::class, 'actor_membership_id');
    }
}
