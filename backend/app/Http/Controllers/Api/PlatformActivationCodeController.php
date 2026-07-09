<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\PlatformActivationCampaign;
use App\Models\PlatformActivationCode;
use App\Services\PlatformActivationCodeService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class PlatformActivationCodeController extends Controller
{
    private PlatformActivationCodeService $svc;

    public function __construct()
    {
        $this->svc = new PlatformActivationCodeService();
    }

    /**
     * List all codes (platform admin).
     */
    public function index(Request $request): JsonResponse
    {
        $q = PlatformActivationCode::with('campaign:id,name')
            ->orderByDesc('created_at');

        if ($request->filled('campaign_id')) {
            $q->where('campaign_id', $request->input('campaign_id'));
        }
        if ($request->filled('status')) {
            $q->where('status', $request->input('status'));
        }

        return response()->json([
            'data' => $q->get()->map(fn ($c) => $this->fmt($c)),
        ]);
    }

    /**
     * Generate batch of codes for a campaign (platform admin).
     */
    public function generateBatch(Request $request, string $campaignId): JsonResponse
    {
        $campaign = PlatformActivationCampaign::findOrFail($campaignId);

        if (!in_array($campaign->status, ['active', 'draft'], true)) {
            return response()->json(['message' => 'Campaign must be active or draft.'], 422);
        }

        $v = $request->validate([
            'count'             => 'required|integer|min:1|max:500',
            'assigned_to_name'  => 'nullable|string|max:255',
            'assigned_to_phone' => 'nullable|string|max:50',
            'expires_at'        => 'nullable|date|after_or_equal:now',
        ]);

        $codes = $this->svc->generateBatch(
            $campaign,
            $v['count'],
            $v['assigned_to_name'] ?? null,
            $v['assigned_to_phone'] ?? null,
            $v['expires_at'] ?? null,
        );

        return response()->json([
            'data' => [
                'generated_count' => count($codes),
                'codes'           => array_map(fn ($c) => $this->fmt($c), $codes),
            ],
        ], 201);
    }

    /**
     * Show single code (platform admin).
     */
    public function show(string $id): JsonResponse
    {
        $code = PlatformActivationCode::with(['campaign:id,name', 'usedByUser:id,full_name,email'])
            ->findOrFail($id);

        $data = $this->fmt($code);
        $data['whatsapp_text'] = $this->svc->whatsappText($code);

        return response()->json(['data' => $data]);
    }

    /**
     * Update code status (platform admin).
     */
    public function updateStatus(Request $request, string $id): JsonResponse
    {
        $v = $request->validate([
            'status' => 'required|string|in:unused,disabled,expired',
        ]);

        $code = PlatformActivationCode::findOrFail($id);

        if ($code->status === 'used') {
            return response()->json(['message' => 'Cannot change status of a used code.'], 422);
        }

        $code->update(['status' => $v['status']]);

        return response()->json(['data' => $this->fmt($code->fresh())]);
    }

    /**
     * Public: validate a code (no auth required).
     */
    public function publicValidate(string $codeStr): JsonResponse
    {
        $result = $this->svc->validate($codeStr);

        if (!$result['valid']) {
            return response()->json([
                'valid'  => false,
                'reason' => $result['reason'],
            ]);
        }

        /** @var PlatformActivationCode $code */
        $code = $result['code'];
        $campaign = $code->campaign;

        return response()->json([
            'valid'        => true,
            'plan_key'     => $code->default_plan_key ?? $campaign?->default_plan_key,
            'trial_days'   => $code->trial_days ?? $campaign?->trial_days,
            'campaign'     => $campaign?->name,
            'expires_at'   => $code->expires_at?->toIso8601String(),
        ]);
    }

    /**
     * Public: lookup code info (no auth required).
     */
    public function publicShow(string $codeStr): JsonResponse
    {
        return $this->publicValidate($codeStr);
    }

    private function fmt(PlatformActivationCode $c): array
    {
        return [
            'id'                => $c->id,
            'campaign_id'       => $c->campaign_id,
            'campaign_name'     => $c->relationLoaded('campaign') ? $c->campaign?->name : null,
            'code'              => $c->code,
            'registration_url'  => $c->registration_url,
            'default_plan_key'  => $c->default_plan_key,
            'trial_days'        => $c->trial_days,
            'max_uses'          => $c->max_uses,
            'used_count'        => $c->used_count,
            'status'            => $c->status,
            'assigned_to_name'  => $c->assigned_to_name,
            'assigned_to_phone' => $c->assigned_to_phone,
            'used_by_user_id'   => $c->used_by_user_id,
            'used_workspace_id' => $c->used_workspace_id,
            'used_at'           => $c->used_at?->toIso8601String(),
            'expires_at'        => $c->expires_at?->toIso8601String(),
            'created_at'        => $c->created_at?->toIso8601String(),
        ];
    }
}
