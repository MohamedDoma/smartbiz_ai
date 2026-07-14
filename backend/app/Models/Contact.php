<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * @property string $id
 * @property string $workspace_id
 * @property string $type          customer|supplier|both
 * @property string $name
 * @property string|null $phone
 * @property string|null $email
 * @property string|null $address
 * @property string|null $tax_number
 * @property string|null $assigned_membership_id
 * @property float $balance        >= 0, default 0.00
 * @property \Carbon\Carbon $created_at
 * @property \Carbon\Carbon $updated_at
 */
class Contact extends Model
{
    use HasUuids;

    protected $table = 'contacts';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'workspace_id',
        'type',
        'name',
        'phone',
        'email',
        'address',
        'tax_number',
        'assigned_membership_id',
    ];

    protected function casts(): array
    {
        return [
            'balance' => 'decimal:2',
        ];
    }

    // ── Relationships ──────────────────────────────────────────

    public function workspace(): BelongsTo
    {
        return $this->belongsTo(Workspace::class, 'workspace_id');
    }

    public function assignedMembership(): BelongsTo
    {
        return $this->belongsTo(WorkspaceMembership::class, 'assigned_membership_id');
    }
}
