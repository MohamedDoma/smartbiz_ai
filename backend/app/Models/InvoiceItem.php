<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * CHILD TABLE — no workspace_id, no RLS.
 * Must NEVER be queried directly. Always access via Invoice::items().
 *
 * @property string $id
 * @property string $invoice_id
 * @property string|null $product_id
 * @property string|null $variant_id
 * @property string|null $unit_id
 * @property string|null $warehouse_id
 * @property float $quantity
 * @property float $unit_price
 * @property float $discount_amount
 * @property float $tax_amount
 * @property float $subtotal
 * @property string|null $product_name_snapshot
 * @property string|null $sku_snapshot
 * @property float|null $tax_rate_snapshot
 */
class InvoiceItem extends Model
{
    use HasUuids;

    protected $table = 'invoice_items';
    protected $keyType = 'string';
    public $incrementing = false;
    public $timestamps = false;

    protected $fillable = [
        'invoice_id',
        'product_id',
        'variant_id',
        'unit_id',
        'warehouse_id',
        'quantity',
        'unit_price',
        'discount_amount',
        'tax_amount',
        'subtotal',
        'product_name_snapshot',
        'sku_snapshot',
        'tax_rate_snapshot',
    ];

    protected function casts(): array
    {
        return [
            'quantity' => 'decimal:2',
            'unit_price' => 'decimal:2',
            'discount_amount' => 'decimal:2',
            'tax_amount' => 'decimal:2',
            'subtotal' => 'decimal:2',
            'tax_rate_snapshot' => 'decimal:4',
        ];
    }

    // ── Relationships ──────────────────────────────────────────

    public function invoice(): BelongsTo
    {
        return $this->belongsTo(Invoice::class, 'invoice_id');
    }
}
