<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * @property string $id
 * @property string $workspace_id
 * @property string|null $invoice_id
 * @property string|null $account_id
 * @property float $amount
 * @property string $payment_method    cash|bank_transfer|credit_card|check|mobile_payment|other
 * @property string|null $reference_number
 * @property string|null $payment_date
 * @property string|null $created_by
 * @property string|null $payment_number
 * @property string $status            completed|reversed
 * @property bool $is_reversal
 * @property string|null $reversal_of_payment_id
 * @property string|null $reversal_reason
 * @property string|null $reversed_at
 * @property string|null $reversed_by
 */
class Payment extends Model
{
    use HasUuids;

    protected $table = 'payments';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'workspace_id',
        'invoice_id',
        'account_id',
        'amount',
        'payment_method',
        'reference_number',
        'payment_date',
        'created_by',
        'payment_number',
        'status',
        'is_reversal',
        'reversal_of_payment_id',
        'reversal_reason',
        'reversed_at',
        'reversed_by',
    ];

    protected function casts(): array
    {
        return [
            'amount'       => 'decimal:2',
            'payment_date' => 'date',
            'is_reversal'  => 'boolean',
            'reversed_at'  => 'datetime',
        ];
    }

    public function invoice(): BelongsTo
    {
        return $this->belongsTo(Invoice::class, 'invoice_id');
    }

    public function account(): BelongsTo
    {
        return $this->belongsTo(Account::class, 'account_id');
    }

    public function creator(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by');
    }

    public function originalPayment(): BelongsTo
    {
        return $this->belongsTo(self::class, 'reversal_of_payment_id');
    }
}
