<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

class StoreInvoiceRequest extends FormRequest
{
    public function authorize(): bool { return true; }

    public function rules(): array
    {
        return [
            'contact_id'                  => ['nullable', 'uuid'],
            'invoice_type'                => ['sometimes', 'string', 'in:sale,purchase,return,refund'],
            'currency'                    => ['sometimes', 'string', 'max:10'],
            'exchange_rate'               => ['sometimes', 'numeric', 'min:0'],
            'invoice_number'              => ['nullable', 'string', 'max:100'],
            'due_date'                    => ['nullable', 'date'],
            'items'                       => ['required', 'array', 'min:1'],
            'items.*.product_id'          => ['nullable', 'uuid'],
            'items.*.variant_id'          => ['nullable', 'uuid'],
            'items.*.unit_id'             => ['nullable', 'uuid'],
            'items.*.warehouse_id'        => ['nullable', 'uuid'],
            'items.*.quantity'            => ['required', 'numeric', 'min:0.01'],
            'items.*.unit_price'          => ['required', 'numeric', 'min:0'],
            'items.*.discount_amount'     => ['sometimes', 'numeric', 'min:0'],
            'items.*.tax_amount'          => ['sometimes', 'numeric', 'min:0'],
            'items.*.product_name_snapshot'=> ['nullable', 'string', 'max:255'],
            'items.*.sku_snapshot'        => ['nullable', 'string', 'max:100'],
            'items.*.tax_rate_snapshot'   => ['nullable', 'numeric'],
        ];
    }
}
