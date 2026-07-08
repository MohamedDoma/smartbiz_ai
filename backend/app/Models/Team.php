<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * @property string $id
 * @property string $workspace_id
 * @property string|null $department_id
 * @property string|null $team_key
 * @property string $name
 * @property string|null $description
 * @property string|null $manager_membership_id
 * @property bool $is_active
 * @property int $sort_order
 */
class Team extends Model
{
    use HasFactory, HasUuids;

    protected $fillable = [
        'workspace_id',
        'department_id',
        'team_key',
        'name',
        'description',
        'manager_membership_id',
        'is_active',
        'sort_order',
    ];

    protected $casts = [
        'is_active'  => 'boolean',
        'sort_order' => 'integer',
    ];

    public function workspace(): BelongsTo
    {
        return $this->belongsTo(Workspace::class);
    }

    public function department(): BelongsTo
    {
        return $this->belongsTo(Department::class);
    }

    public function managerMembership(): BelongsTo
    {
        return $this->belongsTo(WorkspaceMembership::class, 'manager_membership_id');
    }

    public function members(): HasMany
    {
        return $this->hasMany(WorkspaceMembership::class, 'team_id');
    }
}
