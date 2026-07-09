<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\PlatformActivationCampaign;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

class PlatformActivationCampaignController extends Controller
{
    public function index(): JsonResponse
    {
        $campaigns = PlatformActivationCampaign::withCount(['codes as total_codes', 'codes as used_codes' => function ($q) {
                $q->where('status', 'used');
            }])
            ->orderByDesc('created_at')
            ->get()
            ->map(fn ($c) => $this->fmt($c));

        return response()->json(['data' => $campaigns]);
    }

    public function store(Request $request): JsonResponse
    {
        $v = $request->validate([
            'name'             => 'required|string|max:255',
            'description'      => 'nullable|string|max:2000',
            'target_market'    => 'nullable|string|max:255',
            'default_plan_key' => 'nullable|string|max:50',
            'trial_days'       => 'nullable|integer|min:0|max:365',
            'starts_at'        => 'nullable|date',
            'expires_at'       => 'nullable|date|after_or_equal:now',
            'status'           => 'nullable|string|in:draft,active,paused',
        ]);

        $campaign = PlatformActivationCampaign::create([
            'campaign_key'      => Str::slug($v['name'], '_'),
            'name'              => $v['name'],
            'description'       => $v['description'] ?? null,
            'target_market'     => $v['target_market'] ?? null,
            'default_plan_key'  => $v['default_plan_key'] ?? 'starter',
            'trial_days'        => $v['trial_days'] ?? 14,
            'starts_at'         => $v['starts_at'] ?? null,
            'expires_at'        => $v['expires_at'] ?? null,
            'status'            => $v['status'] ?? 'active',
            'created_by_user_id' => $request->user()->id,
        ]);

        return response()->json(['data' => $this->fmt($campaign)], 201);
    }

    public function show(string $id): JsonResponse
    {
        $campaign = PlatformActivationCampaign::withCount(['codes as total_codes', 'codes as used_codes' => function ($q) {
                $q->where('status', 'used');
            }])
            ->findOrFail($id);

        return response()->json(['data' => $this->fmt($campaign)]);
    }

    public function update(Request $request, string $id): JsonResponse
    {
        $campaign = PlatformActivationCampaign::findOrFail($id);

        $v = $request->validate([
            'name'             => 'sometimes|required|string|max:255',
            'description'      => 'nullable|string|max:2000',
            'target_market'    => 'nullable|string|max:255',
            'default_plan_key' => 'nullable|string|max:50',
            'trial_days'       => 'nullable|integer|min:0|max:365',
            'starts_at'        => 'nullable|date',
            'expires_at'       => 'nullable|date',
            'status'           => 'nullable|string|in:draft,active,paused,expired,archived',
        ]);

        if (isset($v['name'])) {
            $v['campaign_key'] = Str::slug($v['name'], '_');
        }

        $campaign->update($v);

        return response()->json(['data' => $this->fmt($campaign->fresh())]);
    }

    public function destroy(string $id): JsonResponse
    {
        $campaign = PlatformActivationCampaign::findOrFail($id);
        $campaign->update(['status' => 'archived']);
        return response()->json(['message' => 'Campaign archived.']);
    }

    private function fmt(PlatformActivationCampaign $c): array
    {
        return [
            'id'               => $c->id,
            'campaign_key'     => $c->campaign_key,
            'name'             => $c->name,
            'description'      => $c->description,
            'target_market'    => $c->target_market,
            'default_plan_key' => $c->default_plan_key,
            'trial_days'       => $c->trial_days,
            'starts_at'        => $c->starts_at?->toIso8601String(),
            'expires_at'       => $c->expires_at?->toIso8601String(),
            'status'           => $c->status,
            'total_codes'      => $c->total_codes ?? 0,
            'used_codes'       => $c->used_codes ?? 0,
            'created_at'       => $c->created_at?->toIso8601String(),
        ];
    }
}
