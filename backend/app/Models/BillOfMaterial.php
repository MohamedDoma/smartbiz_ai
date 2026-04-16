<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Flat BOM — maps final_product_id to raw_material_id with quantity_required.
 * UNIQUE(final_product_id, raw_material_id).
 */
class BillOfMaterial extends Model
{
    use HasUuids;

    protected $table = 'bill_of_materials';
    protected $keyType = 'string';
    public $incrementing = false;
    public $timestamps = false;

    protected $fillable = [
        'workspace_id',
        'final_product_id',
        'raw_material_id',
        'unit_id',
        'quantity_required',
    ];

    protected function casts(): array
    {
        return ['quantity_required' => 'decimal:4'];
    }

    public function finalProduct(): BelongsTo
    {
        return $this->belongsTo(Product::class, 'final_product_id');
    }

    public function rawMaterial(): BelongsTo
    {
        return $this->belongsTo(Product::class, 'raw_material_id');
    }
}
