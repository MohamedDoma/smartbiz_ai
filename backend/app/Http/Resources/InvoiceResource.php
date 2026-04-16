<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin \App\Models\Invoice */
class InvoiceResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id'              => $this->id,
            'contact_id'      => $this->contact_id,
            'contact'         => new ContactResource($this->whenLoaded('contact')),
            'invoice_type'    => $this->invoice_type,
            'invoice_number'  => $this->invoice_number,
            'currency'        => $this->currency,
            'exchange_rate'   => $this->exchange_rate,
            'total_amount'    => $this->total_amount,
            'discount_amount' => $this->discount_amount,
            'tax_amount'      => $this->tax_amount,
            'net_amount'      => $this->net_amount,
            'payment_status'  => $this->payment_status,
            'due_date'        => $this->due_date?->toDateString(),
            'items'           => InvoiceItemResource::collection($this->whenLoaded('items')),
            'created_at'      => $this->created_at?->toIso8601String(),
            'updated_at'      => $this->updated_at?->toIso8601String(),
        ];
    }
}
