<?php
namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class DiscoverySessionResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $state = $this->discovery_state ?? [];

        return [
            'id'                        => $this->id,
            'workspace_id'              => $this->workspace_id,
            'created_by'                => $this->created_by,
            'status'                    => $this->status,
            'business_description'      => $this->business_description,
            'business_type'             => $this->business_type,
            'classification_confidence' => $this->classification_confidence,
            'classification_method'     => $this->classification_method,
            'classification_version'    => $this->classification_version,
            'completeness'              => $state['overall_completeness'] ?? ($state['completeness'] ?? null),
            'ready_for_blueprint'       => $state['ready_for_blueprint'] ?? false,
            'critical_missing'          => $state['critical_missing'] ?? [],
            'has_blocking_contradictions' => !empty(array_filter(
                $state['contradictions'] ?? [],
                fn($c) => ($c['status'] ?? '') === 'needs_clarification'
            )),
            'messages'                  => DiscoveryMessageResource::collection($this->whenLoaded('messages')),
            'blueprint'                 => new DiscoveryBlueprintResource($this->whenLoaded('blueprint')),
            'created_at'                => $this->created_at?->toISOString(),
            'updated_at'                => $this->updated_at?->toISOString(),
        ];
    }
}
