<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * @property string $id
 * @property string $workspace_id
 * @property string $pipeline_record_id
 * @property string|null $document_checklist_item_id
 * @property string $title
 * @property string $status  uploaded|provided|waived|missing
 * @property string|null $file_path
 * @property string|null $original_filename
 * @property string|null $mime_type
 * @property int|null $file_size
 * @property string|null $external_reference
 * @property string|null $notes
 * @property string|null $uploaded_by_membership_id
 * @property \Carbon\Carbon|null $uploaded_at
 */
class RecordDocument extends Model
{
    use HasUuids;

    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'workspace_id', 'pipeline_record_id', 'document_checklist_item_id',
        'title', 'status', 'file_path', 'original_filename', 'mime_type',
        'file_size', 'external_reference', 'notes',
        'uploaded_by_membership_id', 'uploaded_at',
    ];

    protected function casts(): array
    {
        return [
            'uploaded_at' => 'datetime',
            'file_size'   => 'integer',
        ];
    }

    public function pipelineRecord(): BelongsTo
    {
        return $this->belongsTo(PipelineRecord::class);
    }

    public function checklistItem(): BelongsTo
    {
        return $this->belongsTo(DocumentChecklistItem::class, 'document_checklist_item_id');
    }

    public function uploadedByMembership(): BelongsTo
    {
        return $this->belongsTo(WorkspaceMembership::class, 'uploaded_by_membership_id');
    }
}
