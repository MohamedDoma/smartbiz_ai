<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Individual permission key within a delegation.
 *
 * @property string $id
 * @property string $delegation_id
 * @property string $permission_key
 * @property string $scope
 */
class PermissionDelegationItem extends Model
{
    protected $table = 'permission_delegation_items';
    protected $keyType = 'string';
    public $incrementing = false;
    public $timestamps = false;

    protected $fillable = [
        'delegation_id',
        'permission_key',
        'scope',
    ];

    // ── Relationships ──────────────────────────────────────────

    public function delegation(): BelongsTo
    {
        return $this->belongsTo(PermissionDelegation::class, 'delegation_id');
    }
}
