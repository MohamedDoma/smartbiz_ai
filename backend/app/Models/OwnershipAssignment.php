<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * @property string $id
 * @property string $workspace_id
 * @property string $entity_type  contact|pipeline_record
 * @property string $entity_id
 * @property string $owner_membership_id
 * @property string|null $team_id
 * @property string|null $department_id
 * @property string $source  manual|created_by|assigned_employee|transfer|import
 * @property string $status  active|released
 * @property string|null $assigned_by_membership_id
 * @property \Carbon\Carbon|null $assigned_at
 * @property \Carbon\Carbon|null $released_at
 * @property string|null $notes
 */
class OwnershipAssignment extends Model
{
    use HasUuids;

    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'workspace_id', 'entity_type', 'entity_id',
        'owner_membership_id', 'team_id', 'department_id',
        'source', 'status', 'assigned_by_membership_id',
        'assigned_at', 'released_at', 'notes',
    ];

    protected function casts(): array
    {
        return [
            'assigned_at' => 'datetime',
            'released_at' => 'datetime',
        ];
    }

    public function ownerMembership(): BelongsTo
    {
        return $this->belongsTo(WorkspaceMembership::class, 'owner_membership_id');
    }

    public function team(): BelongsTo
    {
        return $this->belongsTo(Team::class);
    }

    public function department(): BelongsTo
    {
        return $this->belongsTo(Department::class);
    }

    public function assignedByMembership(): BelongsTo
    {
        return $this->belongsTo(WorkspaceMembership::class, 'assigned_by_membership_id');
    }
}
