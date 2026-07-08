<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * @property string $id
 * @property string $workspace_id
 * @property string|null $duplicate_rule_id
 * @property string $entity_type
 * @property string $source_entity_id
 * @property string $matched_entity_id
 * @property array|null $match_fields
 * @property float|null $match_score
 * @property string $status  open|ignored|resolved
 * @property string|null $resolution  keep_separate|duplicate_confirmed|merged_later
 * @property string|null $resolved_by_membership_id
 * @property \Carbon\Carbon|null $resolved_at
 */
class DuplicateMatch extends Model
{
    use HasUuids;

    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'workspace_id', 'duplicate_rule_id', 'entity_type',
        'source_entity_id', 'matched_entity_id', 'match_fields',
        'match_score', 'status', 'resolution',
        'resolved_by_membership_id', 'resolved_at',
    ];

    protected function casts(): array
    {
        return [
            'match_fields' => 'array',
            'match_score'  => 'decimal:2',
            'resolved_at'  => 'datetime',
        ];
    }

    public function rule(): BelongsTo
    {
        return $this->belongsTo(DuplicateRule::class, 'duplicate_rule_id');
    }

    public function resolvedByMembership(): BelongsTo
    {
        return $this->belongsTo(WorkspaceMembership::class, 'resolved_by_membership_id');
    }
}
