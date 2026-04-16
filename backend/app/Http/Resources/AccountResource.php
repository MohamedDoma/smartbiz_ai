<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin \App\Models\Account */
class AccountResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id'        => $this->id,
            'code'      => $this->code,
            'name'      => $this->name,
            'type'      => $this->type,
            'parent_id' => $this->parent_id,
            'balance'   => $this->balance,
            'children'  => self::collection($this->whenLoaded('children')),
            'created_at'=> $this->created_at?->toIso8601String(),
        ];
    }
}
