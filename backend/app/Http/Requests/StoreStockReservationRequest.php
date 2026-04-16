<?php
namespace App\Http\Requests;
use Illuminate\Foundation\Http\FormRequest;

class StoreStockReservationRequest extends FormRequest
{
    public function authorize(): bool { return true; }
    public function rules(): array
    {
        return [
            'order_id'          => ['required', 'uuid'],
            'order_item_id'     => ['required', 'uuid'],
            'warehouse_id'      => ['required', 'uuid'],
            'product_id'        => ['required', 'uuid'],
            'variant_id'        => ['nullable', 'uuid'],
            'reserved_quantity' => ['required', 'numeric', 'gt:0'],
        ];
    }
}
