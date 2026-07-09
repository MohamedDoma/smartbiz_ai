<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class FinanceExpense extends Model
{
    use HasUuids;
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'workspace_id', 'expense_date', 'category', 'description',
        'amount', 'currency', 'payment_method', 'paid_by_membership_id',
        'finance_transaction_id', 'status',
    ];

    protected function casts(): array
    {
        return [
            'amount'       => 'decimal:2',
            'expense_date' => 'date',
        ];
    }

    public function transaction(): BelongsTo
    {
        return $this->belongsTo(FinanceTransaction::class, 'finance_transaction_id');
    }

    public function paidByMembership(): BelongsTo
    {
        return $this->belongsTo(WorkspaceMembership::class, 'paid_by_membership_id');
    }
}
