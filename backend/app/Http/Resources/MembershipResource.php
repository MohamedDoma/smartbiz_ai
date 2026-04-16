<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * @mixin \App\Models\WorkspaceMembership
 */
class MembershipResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'id'            => $this->id,
            'workspace_id'  => $this->workspace_id,
            'workspace'     => [
                'id'   => $this->workspace?->id,
                'name' => $this->workspace?->name,
            ],
            'status'        => $this->status,
            'department_id' => $this->department_id,
            'branch_id'     => $this->branch_id,
            'joined_at'     => $this->joined_at?->toIso8601String(),
            'roles'         => $this->whenLoaded('membershipRoles', function () {
                return $this->membershipRoles->map(fn ($mr) => [
                    'role_id'    => $mr->role_id,
                    'role_name'  => $mr->role?->name,
                    'role_key'   => $mr->role?->role_key,
                    'is_primary' => $mr->is_primary,
                ]);
            }),
        ];
    }
}
