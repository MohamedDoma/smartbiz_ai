<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class FinanceSetting extends Model
{
    use HasUuids;
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'workspace_id',
        'default_cash_account_id',
        'default_bank_account_id',
        'default_revenue_account_id',
        'default_accounts_receivable_account_id',
        'default_commission_expense_account_id',
        'default_commission_payable_account_id',
        'default_general_expense_account_id',
    ];

    public function workspace(): BelongsTo
    {
        return $this->belongsTo(Workspace::class);
    }
}
