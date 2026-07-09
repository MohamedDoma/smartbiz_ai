<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class FinanceTransaction extends Model
{
    use HasUuids;
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'workspace_id', 'transaction_number', 'transaction_date', 'description',
        'source_type', 'source_id', 'status', 'currency',
        'total_debit', 'total_credit', 'posted_by_membership_id',
        'posted_at', 'voided_at', 'metadata',
    ];

    protected function casts(): array
    {
        return [
            'total_debit'      => 'decimal:2',
            'total_credit'     => 'decimal:2',
            'posted_at'        => 'datetime',
            'voided_at'        => 'datetime',
            'metadata'         => 'array',
            'transaction_date' => 'date',
        ];
    }

    public function lines(): HasMany
    {
        return $this->hasMany(FinanceTransactionLine::class)->orderBy('line_order');
    }

    public function postedByMembership(): BelongsTo
    {
        return $this->belongsTo(WorkspaceMembership::class, 'posted_by_membership_id');
    }
}
