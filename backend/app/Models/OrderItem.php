<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * CHILD TABLE — no workspace_id, no RLS, no timestamps.
 * Must NEVER be queried directly. Always access via Order::items().
 *
 * @property string $id
 * @property string $order_id
 * @property string|null $product_id
 * @property string|null $variant_id
 * @property string|null $unit_id
 * @property float $quantity
 * @property float $unit_price
 * @property float $subtotal
 * @property string|null $product_name_snapshot
 * @property string|null $sku_snapshot
 */
class OrderItem extends Model
{
    use HasUuids;

    protected $table = 'order_items';
    protected $keyType = 'string';
    public $incrementing = false;
    public $timestamps = false;

    protected $fillable = [
        'order_id',
        'product_id',
        'variant_id',
        'unit_id',
        'quantity',
        'unit_price',
        'subtotal',
        'product_name_snapshot',
        'sku_snapshot',
    ];

    protected function casts(): array
    {
        return [
            'quantity'   => 'decimal:2',
            'unit_price' => 'decimal:2',
            'subtotal'   => 'decimal:2',
        ];
    }

    public function order(): BelongsTo
    {
        return $this->belongsTo(Order::class, 'order_id');
    }
}
