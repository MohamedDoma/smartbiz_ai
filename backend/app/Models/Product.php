<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * @property string $id
 * @property string $workspace_id
 * @property string|null $category_id
 * @property string $type          physical|service|digital|subscription
 * @property string $name
 * @property string|null $sku
 * @property string|null $unit_id
 * @property float $base_price
 * @property float $cost_price
 * @property string|null $tax_id
 * @property int|null $min_stock_alert
 * @property array|null $dynamic_attributes
 * @property bool $is_deleted
 */
class Product extends Model
{
    use HasUuids;

    protected $table = 'products';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = [
        'workspace_id',
        'category_id',
        'type',
        'name',
        'sku',
        'unit_id',
        'base_price',
        'cost_price',
        'tax_id',
        'min_stock_alert',
        'dynamic_attributes',
        'is_deleted',
    ];

    protected function casts(): array
    {
        return [
            'base_price' => 'decimal:2',
            'cost_price' => 'decimal:2',
            'min_stock_alert' => 'integer',
            'dynamic_attributes' => 'array',
            'is_deleted' => 'boolean',
        ];
    }

    // ── Relationships ──────────────────────────────────────────

    public function category(): BelongsTo
    {
        return $this->belongsTo(ProductCategory::class, 'category_id');
    }

    // ── Scopes ─────────────────────────────────────────────────

    public function scopeActive($query)
    {
        return $query->where('is_deleted', false);
    }
}
