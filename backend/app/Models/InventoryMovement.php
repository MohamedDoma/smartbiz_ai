<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * IMMUTABLE — cannot be updated (DB trigger: prevent_immutable_update).
 *
 * @property string $id
 * @property string $workspace_id
 * @property string $warehouse_id
 * @property string $product_id
 * @property string|null $variant_id
 * @property string|null $batch_id
 * @property string $movement_type   15 types with sign rules
 * @property float $quantity_change  positive for IN, negative for OUT
 * @property float $quantity_before
 * @property float $quantity_after   = quantity_before + quantity_change (CHECK)
 * @property float|null $unit_cost
 * @property float|null $total_cost
 * @property string|null $reference_type
 * @property string|null $reference_id
 * @property string|null $created_by
 * @property string|null $reason_code
 * @property string|null $notes
 */
class InventoryMovement extends Model
{
    use HasUuids;

    protected $table = 'inventory_movements';
    protected $keyType = 'string';
    public $incrementing = false;

    // Only created_at, no updated_at (immutable table)
    const UPDATED_AT = null;

    protected $fillable = [
        'workspace_id',
        'warehouse_id',
        'product_id',
        'variant_id',
        'batch_id',
        'movement_type',
        'quantity_change',
        'quantity_before',
        'quantity_after',
        'unit_cost',
        'total_cost',
        'reference_type',
        'reference_id',
        'created_by',
        'reason_code',
        'notes',
    ];

    protected function casts(): array
    {
        return [
            'quantity_change' => 'decimal:2',
            'quantity_before' => 'decimal:2',
            'quantity_after'  => 'decimal:2',
            'unit_cost'       => 'decimal:2',
            'total_cost'      => 'decimal:2',
        ];
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
