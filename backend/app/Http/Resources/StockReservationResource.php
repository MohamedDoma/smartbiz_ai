<?php
namespace App\Http\Resources;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class StockReservationResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id'                 => $this->id,
            'order_id'           => $this->order_id,
            'order_item_id'      => $this->order_item_id,
            'warehouse_id'       => $this->warehouse_id,
            'product_id'         => $this->product_id,
            'reserved_quantity'  => $this->reserved_quantity,
            'fulfilled_quantity' => $this->fulfilled_quantity,
            'released_quantity'  => $this->released_quantity,
            'status'             => $this->status,
            'reserved_at'        => $this->reserved_at?->toIso8601String(),
            'fulfilled_at'       => $this->fulfilled_at?->toIso8601String(),
            'released_at'        => $this->released_at?->toIso8601String(),
            'created_at'         => $this->created_at?->toIso8601String(),
        ];
    }
}
