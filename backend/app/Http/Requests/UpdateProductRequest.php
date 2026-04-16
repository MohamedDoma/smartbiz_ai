<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

class UpdateProductRequest extends FormRequest
{
    public function authorize(): bool { return true; }

    public function rules(): array
    {
        return [
            'category_id'        => ['nullable', 'uuid'],
            'type'               => ['sometimes', 'string', 'in:physical,service,digital,subscription'],
            'name'               => ['sometimes', 'string', 'max:255'],
            'sku'                => ['nullable', 'string', 'max:100'],
            'base_price'         => ['sometimes', 'numeric', 'min:0'],
            'cost_price'         => ['sometimes', 'numeric', 'min:0'],
            'min_stock_alert'    => ['nullable', 'integer', 'min:0'],
            'dynamic_attributes' => ['nullable', 'array'],
        ];
    }
}
