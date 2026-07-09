<?php

namespace App\Services;

use App\Models\PlatformActivationCampaign;
use App\Models\PlatformActivationCode;
use Illuminate\Support\Str;

/**
 * Generates, validates, and redeems platform activation codes.
 */
class PlatformActivationCodeService
{
    /** Characters used for code generation (no ambiguous O/0/I/1). */
    private const CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

    /**
     * Generate a single readable activation code: SBZ-XXXX-XXXX
     */
    public function generateUniqueCode(): string
    {
        $maxAttempts = 20;
        for ($i = 0; $i < $maxAttempts; $i++) {
            $seg1 = $this->segment(3);
            $seg2 = $this->segment(4);
            $code = "SBZ-{$seg1}-{$seg2}";
            if (!PlatformActivationCode::where('code', $code)->exists()) {
                return $code;
            }
        }
        // Fallback: use UUID suffix
        return 'SBZ-' . strtoupper(Str::random(8));
    }

    /**
     * Generate a batch of codes for a campaign.
     */
    public function generateBatch(
        PlatformActivationCampaign $campaign,
        int $count,
        ?string $assignedToName = null,
        ?string $assignedToPhone = null,
        ?string $expiresAt = null,
    ): array {
        $frontendUrl = config('app.frontend_url', env('FRONTEND_URL', 'http://localhost:5173'));

        $codes = [];
        for ($i = 0; $i < $count; $i++) {
            $code = $this->generateUniqueCode();
            $regUrl = "{$frontendUrl}/#/activate?code={$code}";

            $codes[] = PlatformActivationCode::create([
                'campaign_id'      => $campaign->id,
                'code'             => $code,
                'registration_url' => $regUrl,
                'default_plan_key' => $campaign->default_plan_key,
                'trial_days'       => $campaign->trial_days,
                'max_uses'         => 1,
                'status'           => 'unused',
                'assigned_to_name' => $assignedToName,
                'assigned_to_phone' => $assignedToPhone,
                'expires_at'       => $expiresAt ?? $campaign->expires_at,
            ]);
        }
        return $codes;
    }

    /**
     * Validate an activation code. Returns [valid, code, reason].
     */
    public function validate(string $codeStr): array
    {
        $code = PlatformActivationCode::where('code', strtoupper(trim($codeStr)))->first();

        if (!$code) {
            return ['valid' => false, 'code' => null, 'reason' => 'not_found'];
        }
        if ($code->status === 'disabled') {
            return ['valid' => false, 'code' => $code, 'reason' => 'disabled'];
        }
        if ($code->status === 'expired') {
            return ['valid' => false, 'code' => $code, 'reason' => 'expired'];
        }
        if ($code->expires_at && $code->expires_at->isPast()) {
            $code->update(['status' => 'expired']);
            return ['valid' => false, 'code' => $code, 'reason' => 'expired'];
        }
        if ($code->used_count >= $code->max_uses) {
            return ['valid' => false, 'code' => $code, 'reason' => 'used'];
        }
        return ['valid' => true, 'code' => $code, 'reason' => null];
    }

    /**
     * Mark code as used during registration.
     */
    public function markUsed(PlatformActivationCode $code, string $userId, string $workspaceId): void
    {
        $code->update([
            'used_count'        => $code->used_count + 1,
            'status'            => $code->used_count + 1 >= $code->max_uses ? 'used' : 'unused',
            'used_by_user_id'   => $userId,
            'used_workspace_id' => $workspaceId,
            'used_at'           => now(),
        ]);
    }

    /**
     * Build WhatsApp share text (Arabic-first).
     */
    public function whatsappText(PlatformActivationCode $code): string
    {
        $url = $code->registration_url;
        $campaign = $code->campaign;
        $planInfo = $code->default_plan_key ? " (خطة: {$code->default_plan_key})" : '';
        $trialInfo = $code->trial_days ? " - تجربة مجانية {$code->trial_days} يوم" : '';

        return "ابدأ نظام شركتك مع SmartBiz AI 🚀\n"
            . "استخدم الكود: {$code->code}\n"
            . "الرابط: {$url}\n"
            . ($campaign ? "الحملة: {$campaign->name}\n" : '')
            . "{$planInfo}{$trialInfo}";
    }

    /**
     * Build registration URL for a code.
     */
    public function registrationUrl(string $code): string
    {
        $frontendUrl = config('app.frontend_url', env('FRONTEND_URL', 'http://localhost:5173'));
        return "{$frontendUrl}/#/activate?code={$code}";
    }

    private function segment(int $len): string
    {
        $seg = '';
        for ($i = 0; $i < $len; $i++) {
            $seg .= self::CHARS[random_int(0, strlen(self::CHARS) - 1)];
        }
        return $seg;
    }
}
