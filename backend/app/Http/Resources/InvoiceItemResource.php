<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin \App\Models\InvoiceItem */
class InvoiceItemResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id'                    => $this->id,
            'product_id'            => $this->product_id,
            'variant_id'            => $this->variant_id,
            'quantity'              => $this->quantity,
            'unit_price'            => $this->unit_price,
            'discount_amount'       => $this->discount_amount,
            'tax_amount'            => $this->tax_amount,
            'subtotal'              => $this->subtotal,
            'product_name_snapshot' => $this->product_name_snapshot,
            'sku_snapshot'          => $this->sku_snapshot,
            'tax_rate_snapshot'     => $this->tax_rate_snapshot,
        ];
    }
}
