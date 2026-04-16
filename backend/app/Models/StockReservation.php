<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * @property string $id
 * @property string $workspace_id
 * @property string $order_id
 * @property string $order_item_id
 * @property string $warehouse_id
 * @property string $product_id
 * @property string|null $variant_id
 * @property float $reserved_quantity
 * @property float $fulfilled_quantity   default 0
 * @property float $released_quantity    default 0
 * @property string $status   active|fulfilled|partially_fulfilled|released|expired
 *
 * CHECK: fulfilled_quantity + released_quantity <= reserved_quantity
 */
class StockReservation extends Model
{
    use HasUuids;

    protected $table = 'stock_reservations';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'workspace_id',
        'order_id',
        'order_item_id',
        'warehouse_id',
        'product_id',
        'variant_id',
        'reserved_quantity',
        'fulfilled_quantity',
        'released_quantity',
        'status',
        'reserved_at',
        'fulfilled_at',
        'released_at',
    ];

    protected function casts(): array
    {
        return [
            'reserved_quantity'  => 'decimal:2',
            'fulfilled_quantity' => 'decimal:2',
            'released_quantity'  => 'decimal:2',
            'reserved_at'       => 'datetime',
            'fulfilled_at'      => 'datetime',
            'released_at'       => 'datetime',
        ];
    }

    public function order(): BelongsTo
    {
        return $this->belongsTo(Order::class, 'order_id');
    }

    public function warehouse(): BelongsTo
    {
        return $this->belongsTo(Warehouse::class, 'warehouse_id');
    }

    public function product(): BelongsTo
    {
        return $this->belongsTo(Product::class, 'product_id');
    }
}
