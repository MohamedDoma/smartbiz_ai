<?php
namespace App\Http\Requests;
use Illuminate\Foundation\Http\FormRequest;

class StoreInventoryMovementRequest extends FormRequest
{
    public function authorize(): bool { return true; }
    public function rules(): array
    {
        return [
            'warehouse_id'   => ['required', 'uuid'],
            'product_id'     => ['required', 'uuid'],
            'variant_id'     => ['nullable', 'uuid'],
            'batch_id'       => ['nullable', 'uuid'],
            'movement_type'  => ['required', 'string', 'in:purchase_receipt,sale_shipment,return_restock,return_dispose,supplier_return,adjustment_increase,adjustment_decrease,transfer_out,transfer_in,production_consume,production_output,opening_balance,damage,shrinkage,expired'],
            'quantity_change' => ['required', 'numeric', 'gt:0'],
            'unit_cost'       => ['nullable', 'numeric', 'min:0'],
            'reference_type'  => ['nullable', 'string', 'in:order,shipment,grn,return,transfer,production_order,adjustment,opening'],
            'reference_id'    => ['nullable', 'uuid'],
            'reason_code'     => ['nullable', 'string', 'max:50'],
            'notes'           => ['nullable', 'string'],
        ];
    }
}
