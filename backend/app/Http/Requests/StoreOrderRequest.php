<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

class StoreOrderRequest extends FormRequest
{
    public function authorize(): bool { return true; }

    public function rules(): array
    {
        return [
            'contact_id'                   => ['nullable', 'uuid'],
            'order_type'                   => ['required', 'string', 'in:quote,sale_order,purchase_order,dine_in,takeaway'],
            'status'                       => ['sometimes', 'string', 'in:draft,confirmed,processing,completed,cancelled'],
            'currency'                     => ['sometimes', 'string', 'max:10'],
            'exchange_rate'                => ['sometimes', 'numeric', 'min:0'],
            'order_number'                 => ['nullable', 'string', 'max:100'],
            'notes'                        => ['nullable', 'string'],
            'valid_until'                  => ['nullable', 'date'],
            'items'                        => ['required', 'array', 'min:1'],
            'items.*.product_id'           => ['nullable', 'uuid'],
            'items.*.variant_id'           => ['nullable', 'uuid'],
            'items.*.unit_id'              => ['nullable', 'uuid'],
            'items.*.quantity'             => ['required', 'numeric', 'gt:0'],
            'items.*.unit_price'           => ['required', 'numeric', 'min:0'],
            'items.*.product_name_snapshot'=> ['nullable', 'string', 'max:255'],
            'items.*.sku_snapshot'          => ['nullable', 'string', 'max:100'],
        ];
    }
}
