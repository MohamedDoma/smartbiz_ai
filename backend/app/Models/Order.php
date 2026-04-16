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
 * @property string|null $created_by
 * @property string|null $contact_id
 * @property string $order_type      quote|sale_order|purchase_order|dine_in|takeaway
 * @property string $status          draft|confirmed|processing|completed|cancelled
 * @property string $currency
 * @property float $exchange_rate
 * @property float $total_amount
 * @property string|null $order_number
 * @property string|null $notes
 * @property string|null $valid_until
 */
class Order extends Model
{
    use HasUuids;

    protected $table = 'orders';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'workspace_id',
        'branch_id',
        'created_by',
        'contact_id',
        'order_type',
        'status',
        'currency',
        'exchange_rate',
        'total_amount',
        'order_number',
        'notes',
        'valid_until',
    ];

    protected function casts(): array
    {
        return [
            'total_amount'  => 'decimal:2',
            'exchange_rate' => 'decimal:4',
            'valid_until'   => 'date',
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
     * Order items — child table, NO workspace_id, NO RLS.
     * This is the ONLY correct way to access order_items.
     */
    public function items(): HasMany
    {
        return $this->hasMany(OrderItem::class, 'order_id');
    }
}
