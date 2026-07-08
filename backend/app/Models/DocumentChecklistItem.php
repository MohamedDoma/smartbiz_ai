<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * @property string $id
 * @property string $workspace_id
 * @property string $document_checklist_id
 * @property string|null $item_key
 * @property string $title
 * @property string|null $description
 * @property bool $is_required
 * @property array|null $accepted_file_types
 * @property int|null $max_file_size_mb
 * @property int $sort_order
 * @property bool $is_active
 */
class DocumentChecklistItem extends Model
{
    use HasUuids;

    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'workspace_id', 'document_checklist_id', 'item_key', 'title',
        'description', 'is_required', 'accepted_file_types',
        'max_file_size_mb', 'sort_order', 'is_active',
    ];

    protected function casts(): array
    {
        return [
            'is_required'         => 'boolean',
            'accepted_file_types' => 'array',
            'max_file_size_mb'    => 'integer',
            'is_active'           => 'boolean',
            'sort_order'          => 'integer',
        ];
    }

    public function checklist(): BelongsTo
    {
        return $this->belongsTo(DocumentChecklist::class, 'document_checklist_id');
    }

    public function recordDocuments(): HasMany
    {
        return $this->hasMany(RecordDocument::class, 'document_checklist_item_id');
    }
}
