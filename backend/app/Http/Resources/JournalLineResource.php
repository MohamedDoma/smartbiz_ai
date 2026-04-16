<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin \App\Models\JournalLine */
class JournalLineResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id'               => $this->id,
            'account_id'       => $this->account_id,
            'debit'            => $this->debit,
            'credit'           => $this->credit,
            'description'      => $this->description,
            'reporting_amount' => $this->reporting_amount,
        ];
    }
}
