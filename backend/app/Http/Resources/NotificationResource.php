<?php
namespace App\Http\Resources;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class NotificationResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id'         => $this->id,
            'title'      => $this->title,
            'message'    => $this->message,
            'type'       => $this->type,
            'is_read'    => $this->is_read,
            'link_url'   => $this->link_url,
            'created_at' => $this->created_at?->toIso8601String(),
        ];
    }
}
