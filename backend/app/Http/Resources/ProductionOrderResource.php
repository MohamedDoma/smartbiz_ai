<?php
namespace App\Http\Resources;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class ProductionOrderResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id'                       => $this->id,
            'product_id'               => $this->product_id,
            'product'                  => new ProductResource($this->whenLoaded('product')),
            'warehouse_id'             => $this->warehouse_id,
            'warehouse'                => new WarehouseResource($this->whenLoaded('warehouse')),
            'target_quantity'          => $this->target_quantity,
            'status'                   => $this->status,
            'production_order_number'  => $this->production_order_number,
            'start_date'               => $this->start_date?->toDateString(),
            'end_date'                 => $this->end_date?->toDateString(),
            'created_at'               => $this->created_at?->toIso8601String(),
        ];
    }
}
