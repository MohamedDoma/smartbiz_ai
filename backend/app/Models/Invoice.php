<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * @property string $id
 * @property string $workspace_id
 * @property string|null $branch_id
 * @property string|null $contact_id
 * @property string|null $created_by
 * @property string $invoice_type    sale|purchase|return|refund
 * @property string $currency
 * @property float $exchange_rate
 * @property float $total_amount
 * @property float $discount_amount
 * @property float $net_amount
 * @property float $tax_amount
 * @property string $payment_status  unpaid|partial|paid|overdue|refunded
 * @property string|null $invoice_number
 * @property string|null $due_date
 */
class Invoice extends Model
{
    use HasUuids;

    protected $table = 'invoices';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'workspace_id',
        'branch_id',
        'contact_id',
        'created_by',
        'invoice_type',
        'currency',
        'exchange_rate',
        'total_amount',
        'discount_amount',
        'net_amount',
        'tax_amount',
        'payment_status',
        'invoice_number',
        'due_date',
    ];

    protected function casts(): array
    {
        return [
            'total_amount' => 'decimal:2',
            'discount_amount' => 'decimal:2',
            'net_amount' => 'decimal:2',
            'tax_amount' => 'decimal:2',
            'exchange_rate' => 'decimal:4',
            'due_date' => 'date',
        ];
    }

    // ── Relationships ──────────────────────────────────────────

    public function contact(): BelongsTo
    {
        return $this->belongsTo(Contact::class, 'contact_id');
    }

    public function creator(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by');
    }

    /**
     * Invoice items — child table, NO RLS.
     * This is the ONLY correct way to access invoice_items.
     */
    public function items(): HasMany
    {
        return $this->hasMany(InvoiceItem::class, 'invoice_id');
    }
}
