<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * CHILD TABLE — no workspace_id, no timestamps.
 * Must NEVER be queried directly. Always access via JournalEntry::lines().
 *
 * CHECK constraint: each line must be EITHER debit>0 with credit=0, OR credit>0 with debit=0.
 * Deferred trigger: total debit must equal total credit per entry_id.
 *
 * @property string $id
 * @property string $entry_id
 * @property string $account_id
 * @property float $debit
 * @property float $credit
 * @property string|null $description
 * @property float|null $reporting_amount
 */
class JournalLine extends Model
{
    use HasUuids;

    protected $table = 'journal_lines';
    protected $keyType = 'string';
    public $incrementing = false;
    public $timestamps = false;

    protected $fillable = [
        'entry_id',
        'account_id',
        'debit',
        'credit',
        'description',
        'reporting_amount',
    ];

    protected function casts(): array
    {
        return [
            'debit'            => 'decimal:2',
            'credit'           => 'decimal:2',
            'reporting_amount' => 'decimal:2',
        ];
    }

    public function entry(): BelongsTo
    {
        return $this->belongsTo(JournalEntry::class, 'entry_id');
    }

    public function account(): BelongsTo
    {
        return $this->belongsTo(Account::class, 'account_id');
    }
}
