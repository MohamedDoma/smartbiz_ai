<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * @property string $id
 * @property string $workspace_id
 * @property string $pipeline_id
 * @property string $stage_id
 * @property string $title
 * @property string|null $description
 * @property string|null $contact_id
 * @property string|null $assigned_membership_id
 * @property float|null $value_amount
 * @property string|null $currency
 * @property string $status  open|won|lost|completed|cancelled
 * @property \Carbon\Carbon|null $expected_close_date
 * @property \Carbon\Carbon|null $closed_at
 */
class PipelineRecord extends Model
{
    use HasUuids;

    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'workspace_id', 'pipeline_id', 'stage_id', 'title', 'description',
        'contact_id', 'assigned_membership_id', 'value_amount', 'currency',
        'status', 'expected_close_date', 'closed_at',
    ];

    protected function casts(): array
    {
        return [
            'value_amount'       => 'decimal:2',
            'expected_close_date' => 'date',
            'closed_at'          => 'datetime',
        ];
    }

    public function pipeline(): BelongsTo
    {
        return $this->belongsTo(Pipeline::class);
    }

    public function stage(): BelongsTo
    {
        return $this->belongsTo(PipelineStage::class, 'stage_id');
    }

    public function assignedMembership(): BelongsTo
    {
        return $this->belongsTo(WorkspaceMembership::class, 'assigned_membership_id');
    }

    public function contact(): BelongsTo
    {
        return $this->belongsTo(Contact::class);
    }

    public function customFieldValues(): HasMany
    {
        return $this->hasMany(CustomFieldValue::class, 'record_id')
            ->where('record_type', 'pipeline_record');
    }
}
