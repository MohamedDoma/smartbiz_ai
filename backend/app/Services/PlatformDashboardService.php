<?php

namespace App\Services;

use App\Models\PlatformActivationCampaign;
use App\Models\PlatformActivationCode;
use App\Models\User;
use App\Models\Workspace;
use Illuminate\Support\Facades\DB;

/**
 * Returns platform-level statistics for the Super Admin dashboard.
 */
class PlatformDashboardService
{
    public function getStats(): array
    {
        $totalWorkspaces = Workspace::count();
        $activeWorkspaces = Workspace::where('status', 'active')->count();
        $trialWorkspaces = Workspace::where('subscription_status', 'trial')->count();
        $suspendedWorkspaces = Workspace::where('status', 'suspended')->count();
        $totalUsers = User::count();
        $platformAdmins = User::where('is_super_admin', true)->count();

        $totalCampaigns = PlatformActivationCampaign::count();
        $activeCampaigns = PlatformActivationCampaign::where('status', 'active')->count();

        $totalCodes = PlatformActivationCode::count();
        $unusedCodes = PlatformActivationCode::where('status', 'unused')->count();
        $usedCodes = PlatformActivationCode::where('status', 'used')->count();
        $expiredCodes = PlatformActivationCode::where('status', 'expired')->count();
        $disabledCodes = PlatformActivationCode::where('status', 'disabled')->count();

        $recentWorkspaces = Workspace::orderByDesc('created_at')
            ->limit(5)
            ->get(['id', 'name', 'status', 'subscription_status', 'created_at']);

        $recentCodeUsage = PlatformActivationCode::whereNotNull('used_at')
            ->orderByDesc('used_at')
            ->limit(5)
            ->with('campaign:id,name')
            ->get(['id', 'code', 'campaign_id', 'used_by_user_id', 'used_workspace_id', 'used_at', 'status']);

        $topCampaigns = PlatformActivationCampaign::withCount(['codes as total_codes', 'codes as used_codes' => function ($q) {
                $q->where('status', 'used');
            }])
            ->orderByDesc('used_codes')
            ->limit(5)
            ->get(['id', 'name', 'target_market', 'status']);

        return [
            'workspaces' => [
                'total'     => $totalWorkspaces,
                'active'    => $activeWorkspaces,
                'trial'     => $trialWorkspaces,
                'suspended' => $suspendedWorkspaces,
            ],
            'users' => [
                'total'           => $totalUsers,
                'platform_admins' => $platformAdmins,
            ],
            'campaigns' => [
                'total'  => $totalCampaigns,
                'active' => $activeCampaigns,
            ],
            'codes' => [
                'total'    => $totalCodes,
                'unused'   => $unusedCodes,
                'used'     => $usedCodes,
                'expired'  => $expiredCodes,
                'disabled' => $disabledCodes,
            ],
            'recent_workspaces' => $recentWorkspaces,
            'recent_code_usage' => $recentCodeUsage,
            'top_campaigns'     => $topCampaigns,
        ];
    }
}
