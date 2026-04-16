<?php
namespace App\Http\Resources;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class PaymentResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id'                     => $this->id,
            'invoice_id'             => $this->invoice_id,
            'account_id'             => $this->account_id,
            'amount'                 => $this->amount,
            'payment_method'         => $this->payment_method,
            'reference_number'       => $this->reference_number,
            'payment_date'           => $this->payment_date?->toDateString(),
            'payment_number'         => $this->payment_number,
            'status'                 => $this->status,
            'is_reversal'            => $this->is_reversal,
            'reversal_of_payment_id' => $this->reversal_of_payment_id,
            'reversal_reason'        => $this->reversal_reason,
            'reversed_at'            => $this->reversed_at?->toIso8601String(),
            'created_at'             => $this->created_at?->toIso8601String(),
            'updated_at'             => $this->updated_at?->toIso8601String(),
        ];
    }
}
