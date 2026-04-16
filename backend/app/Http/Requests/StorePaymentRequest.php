<?php
namespace App\Http\Requests;
use Illuminate\Foundation\Http\FormRequest;

class StorePaymentRequest extends FormRequest
{
    public function authorize(): bool { return true; }
    public function rules(): array
    {
        return [
            'invoice_id'       => ['nullable', 'uuid'],
            'account_id'       => ['nullable', 'uuid'],
            'amount'           => ['required', 'numeric', 'gt:0'],
            'payment_method'   => ['required', 'string', 'in:cash,bank_transfer,credit_card,check,mobile_payment,other'],
            'reference_number' => ['nullable', 'string', 'max:100'],
            'payment_date'     => ['sometimes', 'date'],
            'payment_number'   => ['nullable', 'string', 'max:100'],
        ];
    }
}
