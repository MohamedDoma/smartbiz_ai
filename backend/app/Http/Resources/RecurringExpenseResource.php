<?php
namespace App\Http\Resources;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class RecurringExpenseResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id'            => $this->id,
            'category'      => $this->category,
            'amount'        => $this->amount,
            'frequency'     => $this->frequency,
            'next_due_date' => $this->next_due_date?->toDateString(),
            'is_active'     => $this->is_active,
            'created_at'    => $this->created_at?->toIso8601String(),
        ];
    }
}
