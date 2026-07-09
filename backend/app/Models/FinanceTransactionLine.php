<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class FinanceTransactionLine extends Model
{
    use HasUuids;
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'workspace_id', 'finance_transaction_id', 'finance_account_id',
        'description', 'debit_amount', 'credit_amount', 'currency', 'line_order',
    ];

    protected function casts(): array
    {
        return [
            'debit_amount'  => 'decimal:2',
            'credit_amount' => 'decimal:2',
            'line_order'    => 'integer',
        ];
    }

    public function transaction(): BelongsTo
    {
        return $this->belongsTo(FinanceTransaction::class, 'finance_transaction_id');
    }

    public function account(): BelongsTo
    {
        return $this->belongsTo(FinanceAccount::class, 'finance_account_id');
    }
}
