<?php
namespace App\Http\Resources;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class InventoryMovementResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id'              => $this->id,
            'warehouse_id'    => $this->warehouse_id,
            'warehouse'       => new WarehouseResource($this->whenLoaded('warehouse')),
            'product_id'      => $this->product_id,
            'product'         => new ProductResource($this->whenLoaded('product')),
            'movement_type'   => $this->movement_type,
            'quantity_change'  => $this->quantity_change,
            'quantity_before'  => $this->quantity_before,
            'quantity_after'   => $this->quantity_after,
            'unit_cost'        => $this->unit_cost,
            'total_cost'       => $this->total_cost,
            'reference_type'   => $this->reference_type,
            'reference_id'     => $this->reference_id,
            'reason_code'      => $this->reason_code,
            'notes'            => $this->notes,
            'created_at'       => $this->created_at?->toIso8601String(),
        ];
    }
}
