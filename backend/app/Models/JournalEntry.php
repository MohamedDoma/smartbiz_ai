<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * @property string $id
 * @property string $workspace_id
 * @property string|null $reference
 * @property string $description
 * @property string $date
 * @property string|null $created_by
 * @property string $currency
 * @property float $exchange_rate
 * @property string $status   draft|posted|reversed
 */
class JournalEntry extends Model
{
    use HasUuids;

    protected $table = 'journal_entries';
    protected $keyType = 'string';
    public $incrementing = false;

    // journal_entries has created_at but NO updated_at
    const UPDATED_AT = null;

    protected $fillable = [
        'workspace_id',
        'reference',
        'description',
        'date',
        'created_by',
        'currency',
        'exchange_rate',
        'status',
    ];

    protected function casts(): array
    {
        return [
            'date'          => 'date',
            'exchange_rate' => 'decimal:4',
        ];
    }

    /**
     * Journal lines — child table, NO workspace_id.
     * Deferred constraint trigger enforces total debit = total credit.
     */
    public function lines(): HasMany
    {
        return $this->hasMany(JournalLine::class, 'entry_id');
    }

    public function creator(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by');
    }
}
