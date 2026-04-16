<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin \App\Models\Product */
class ProductResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id'                 => $this->id,
            'category_id'        => $this->category_id,
            'category'           => new ProductCategoryResource($this->whenLoaded('category')),
            'type'               => $this->type,
            'name'               => $this->name,
            'sku'                => $this->sku,
            'base_price'         => $this->base_price,
            'cost_price'         => $this->cost_price,
            'min_stock_alert'    => $this->min_stock_alert,
            'dynamic_attributes' => $this->dynamic_attributes,
            'created_at'         => $this->created_at?->toIso8601String(),
            'updated_at'         => $this->updated_at?->toIso8601String(),
        ];
    }
}
