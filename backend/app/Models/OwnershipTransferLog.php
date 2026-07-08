<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * @property string $id
 * @property string $workspace_id
 * @property string|null $ownership_assignment_id
 * @property string $entity_type
 * @property string $entity_id
 * @property string|null $from_membership_id
 * @property string $to_membership_id
 * @property string|null $transferred_by_membership_id
 * @property string|null $reason
 * @property \Carbon\Carbon|null $transferred_at
 */
class OwnershipTransferLog extends Model
{
    use HasUuids;

    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'workspace_id', 'ownership_assignment_id',
        'entity_type', 'entity_id',
        'from_membership_id', 'to_membership_id',
        'transferred_by_membership_id', 'reason', 'transferred_at',
    ];

    protected function casts(): array
    {
        return ['transferred_at' => 'datetime'];
    }

    public function ownershipAssignment(): BelongsTo
    {
        return $this->belongsTo(OwnershipAssignment::class);
    }

    public function fromMembership(): BelongsTo
    {
        return $this->belongsTo(WorkspaceMembership::class, 'from_membership_id');
    }

    public function toMembership(): BelongsTo
    {
        return $this->belongsTo(WorkspaceMembership::class, 'to_membership_id');
    }
}
