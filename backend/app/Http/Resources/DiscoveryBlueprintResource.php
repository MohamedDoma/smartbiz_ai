<?php
namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class DiscoveryBlueprintResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id'                => $this->id,
            'session_id'        => $this->session_id,
            'business_type'     => $this->business_type,
            'blueprint'         => $this->blueprint,
            'schema_version'    => $this->blueprint['schema_version'] ?? null,
            'version'           => $this->version,
            'generator_method'  => $this->generator_method,
            'generator_version' => $this->generator_version,
            'created_at'        => $this->created_at?->toISOString(),
            'updated_at'        => $this->updated_at?->toISOString(),
        ];
    }
}
