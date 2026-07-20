<?php

namespace App\Services\Email;

use Illuminate\Support\Facades\DB;

/**
 * Email configuration service.
 *
 * Manages global toggle (platform_settings key/value) and per-workspace settings.
 */
class EmailConfigService
{
    /**
     * Check if email is globally enabled.
     */
    public function isGloballyEnabled(): bool
    {
        $val = DB::table('platform_settings')
            ->where('key', 'email.enabled')
            ->value('value');

        return $val === 'true' || $val === '1';
    }

    /**
     * Check if email is enabled for a specific workspace.
     */
    public function isEnabledForWorkspace(string $workspaceId): bool
    {
        if (! $this->isGloballyEnabled()) {
            return false;
        }

        $settings = $this->getWorkspaceSettings($workspaceId);

        return $settings?->enabled ?? true; // default enabled if no override
    }

    /**
     * Get workspace-level email settings.
     */
    public function getWorkspaceSettings(string $workspaceId): ?object
    {
        return DB::table('email_settings')
            ->where('workspace_id', $workspaceId)
            ->first();
    }

    /**
     * Get the sender info for a workspace (with fallback to global defaults).
     */
    public function getSenderInfo(string $workspaceId): array
    {
        $ws = $this->getWorkspaceSettings($workspaceId);

        $globalFromName = DB::table('platform_settings')
            ->where('key', 'email.default_from_name')
            ->value('value');
        $globalFromEmail = DB::table('platform_settings')
            ->where('key', 'email.default_from_email')
            ->value('value');

        $configuredFromName = (string) config('mail.from.name', 'SmartBiz AI');
        $configuredFromEmail = (string) config('mail.from.address', 'noreply@smartbiz.ai');

        // Fresh installations seed noreply@smartbiz.ai as a placeholder. When
        // MAIL_FROM_ADDRESS is configured (for example with a verified Resend
        // domain), use it automatically unless an explicit platform/workspace
        // sender override has been configured.
        if (! $globalFromEmail || $globalFromEmail === 'noreply@smartbiz.ai') {
            $globalFromEmail = $configuredFromEmail;
        }
        $globalFromName = $globalFromName ?: $configuredFromName;

        return [
            'from_name'  => $ws?->from_name_override ?: $globalFromName,
            'from_email' => $ws?->from_email_override ?: $globalFromEmail,
            'reply_to'   => $ws?->reply_to ?: null,
        ];
    }

    /**
     * Get a global platform setting.
     */
    public function getGlobalSetting(string $key, string $default = ''): string
    {
        return DB::table('platform_settings')
            ->where('key', $key)
            ->value('value') ?? $default;
    }

    /**
     * Check daily limit for workspace.
     */
    public function isWithinDailyLimit(string $workspaceId): bool
    {
        $ws           = $this->getWorkspaceSettings($workspaceId);
        $limit        = $ws?->daily_limit ?? 200;
        $globalLimit  = (int) $this->getGlobalSetting('email.global_daily_limit', '5000');

        $todayCount = DB::table('email_logs')
            ->where('workspace_id', $workspaceId)
            ->where('created_at', '>=', now()->startOfDay())
            ->count();

        return $todayCount < min($limit, $globalLimit);
    }
}
