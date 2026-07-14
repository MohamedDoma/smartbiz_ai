<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * An individual approval request for a specific entity.
 *
 * Tracks the lifecycle of the approval: pending → approved/rejected/cancelled.
 * Each request has N request_steps mirroring the workflow's active steps.
 *
 * @property string $id
 * @property string $workspace_id
 * @property string $workflow_id
 * @property string $entity_type
 * @property string $entity_id
 * @property string $requester_membership_id
 * @property string $status
 * @property int $current_step_order
 * @property array $entity_snapshot
 * @property array $metadata
 * @property string|null $final_notes
 * @property \Carbon\Carbon|null $resolved_at
 */
class ApprovalRequest extends Model
{
    use HasUuids;

    protected $table = 'approval_requests';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'workspace_id',
        'workflow_id',
        'entity_type',
        'entity_id',
        'requester_membership_id',
        'status',
        'current_step_order',
        'entity_snapshot',
        'metadata',
        'final_notes',
        'resolved_at',
    ];

    protected function casts(): array
    {
        return [
            'entity_snapshot' => 'array',
            'metadata'        => 'array',
            'resolved_at'     => 'datetime',
        ];
    }

    // ── Relationships ──────────────────────────────────────────

    public function workflow(): BelongsTo
    {
        return $this->belongsTo(ApprovalWorkflow::class, 'workflow_id');
    }

    public function requesterMembership(): BelongsTo
    {
        return $this->belongsTo(WorkspaceMembership::class, 'requester_membership_id');
    }

    public function requestSteps(): HasMany
    {
        return $this->hasMany(ApprovalRequestStep::class, 'approval_request_id')
                    ->orderBy('step_order');
    }

    public function decisions(): HasMany
    {
        return $this->hasMany(ApprovalDecision::class, 'approval_request_id')
                    ->orderBy('created_at');
    }

    // ── Scopes ─────────────────────────────────────────────────

    public function scopePending($query)
    {
        return $query->where('status', 'pending');
    }

    public function scopeResolved($query)
    {
        return $query->whereIn('status', ['approved', 'rejected', 'cancelled']);
    }

    // ── Helpers ─────────────────────────────────────────────────

    public function isPending(): bool
    {
        return $this->status === 'pending';
    }

    public function isResolved(): bool
    {
        return in_array($this->status, ['approved', 'rejected', 'cancelled'], true);
    }

    /**
     * Get the current active request step (the one awaiting decision).
     */
    public function currentRequestStep(): ?ApprovalRequestStep
    {
        return $this->requestSteps()
                    ->where('step_order', $this->current_step_order)
                    ->where('status', 'pending')
                    ->first();
    }
}
