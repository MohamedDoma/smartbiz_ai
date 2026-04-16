<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin \App\Models\Order */
class OrderResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id'            => $this->id,
            'contact_id'    => $this->contact_id,
            'contact'       => new ContactResource($this->whenLoaded('contact')),
            'order_type'    => $this->order_type,
            'order_number'  => $this->order_number,
            'status'        => $this->status,
            'currency'      => $this->currency,
            'exchange_rate' => $this->exchange_rate,
            'total_amount'  => $this->total_amount,
            'valid_until'   => $this->valid_until?->toDateString(),
            'notes'         => $this->notes,
            'items'         => OrderItemResource::collection($this->whenLoaded('items')),
            'created_at'    => $this->created_at?->toIso8601String(),
            'updated_at'    => $this->updated_at?->toIso8601String(),
        ];
    }
}
