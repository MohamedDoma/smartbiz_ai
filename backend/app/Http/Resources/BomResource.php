<?php
namespace App\Http\Resources;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class BomResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id'                => $this->id,
            'final_product_id'  => $this->final_product_id,
            'final_product'     => new ProductResource($this->whenLoaded('finalProduct')),
            'raw_material_id'   => $this->raw_material_id,
            'raw_material'      => new ProductResource($this->whenLoaded('rawMaterial')),
            'quantity_required' => $this->quantity_required,
        ];
    }
}
