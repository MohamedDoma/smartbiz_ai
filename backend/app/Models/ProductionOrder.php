<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * @property string $id
 * @property string $workspace_id
 * @property string|null $created_by
 * @property string $product_id
 * @property string|null $work_center_id
 * @property float $target_quantity
 * @property string $status    planned|in_progress|done|cancelled
 * @property string|null $warehouse_id
 * @property string|null $production_order_number
 * @property string|null $start_date
 * @property string|null $end_date
 */
class ProductionOrder extends Model
{
    use HasUuids;

    protected $table = 'production_orders';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'workspace_id',
        'created_by',
        'product_id',
        'work_center_id',
        'target_quantity',
        'status',
        'warehouse_id',
        'production_order_number',
        'start_date',
        'end_date',
    ];

    protected function casts(): array
    {
        return [
            'target_quantity' => 'decimal:4',
            'start_date'     => 'date',
            'end_date'       => 'date',
        ];
    }

    public function product(): BelongsTo
    {
        return $this->belongsTo(Product::class, 'product_id');
    }

    public function warehouse(): BelongsTo
    {
        return $this->belongsTo(Warehouse::class, 'warehouse_id');
    }
}
