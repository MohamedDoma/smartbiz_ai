<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * @mixin \App\Models\User
 */
class UserResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'id'               => $this->id,
            'full_name'        => $this->full_name,
            'email'            => $this->email,
            'phone_number'     => $this->phone_number,
            'is_active'        => $this->is_active,
            'preferred_locale' => $this->preferred_locale,
            'created_at'       => $this->created_at?->toIso8601String(),
        ];
    }
}
