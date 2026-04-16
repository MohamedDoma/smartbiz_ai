<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin \App\Models\JournalEntry */
class JournalEntryResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id'            => $this->id,
            'reference'     => $this->reference,
            'description'   => $this->description,
            'date'          => $this->date?->toDateString(),
            'currency'      => $this->currency,
            'exchange_rate' => $this->exchange_rate,
            'status'        => $this->status,
            'lines'         => JournalLineResource::collection($this->whenLoaded('lines')),
            'created_at'    => $this->created_at?->toIso8601String(),
        ];
    }
}
