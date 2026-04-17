<?php
namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class DiscoveryMessageResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id'           => $this->id,
            'session_id'   => $this->session_id,
            'role'         => $this->role,
            'content'      => $this->content,
            'message_type' => $this->message_type,
            'metadata'     => $this->metadata,
            'created_at'   => $this->created_at?->toISOString(),
        ];
    }
}
