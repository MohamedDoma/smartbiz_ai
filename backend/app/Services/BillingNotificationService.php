<?php

namespace App\Services;

use App\Models\AiCreditBalance;
use App\Models\Notification;
use App\Models\WorkspaceSubscription;
use Illuminate\Support\Facades\Log;

/**
 * Billing notification service.
 * Creates auditable notification records for billing events.
 *
 * Uses the existing notifications table (type: info|warning|alert|success).
 */
class BillingNotificationService
{
    /**
     * Send trial-expiring notifications (3 days before expiry).
     */
    public function processTrialExpiring(): array
    {
        $expiring = WorkspaceSubscription::where('status', 'trial')
            ->whereBetween('trial_ends_at', [now(), now()->addDays(3)])
            ->get();

        $sent = [];
        foreach ($expiring as $sub) {
            $exists = Notification::where('workspace_id', $sub->workspace_id)
                ->where('title', 'Trial Expiring Soon')
                ->where('created_at', '>=', now()->subDay())
                ->exists();

            if ($exists) continue;

            Notification::create([
                'workspace_id' => $sub->workspace_id,
                'type'         => 'warning',
                'title'        => 'Trial Expiring Soon',
                'message'      => 'Your free trial will expire on ' . $sub->trial_ends_at->format('M d, Y') . '. Please add a payment method to continue using SmartBiz AI.',
            ]);
            $sent[] = $sub->workspace_id;
        }

        return $sent;
    }

    /**
     * Create payment-failed notification.
     */
    public function notifyPaymentFailed(string $workspaceId, float $amount, string $currency): void
    {
        Notification::create([
            'workspace_id' => $workspaceId,
            'type'         => 'alert',
            'title'        => 'Payment Failed',
            'message'      => "Your payment of {$currency} " . number_format($amount, 2) . " has failed. Please update your payment method to avoid service interruption.",
        ]);
    }

    /**
     * Create subscription-activated notification.
     */
    public function notifySubscriptionActivated(string $workspaceId): void
    {
        Notification::create([
            'workspace_id' => $workspaceId,
            'type'         => 'success',
            'title'        => 'Subscription Activated',
            'message'      => 'Your subscription is now active. Welcome to SmartBiz AI!',
        ]);
    }

    /**
     * Create subscription-suspended notification.
     */
    public function notifySubscriptionSuspended(string $workspaceId, string $reason = 'payment_failure'): void
    {
        $message = match ($reason) {
            'payment_failure' => 'Your subscription has been suspended due to failed payment. Please update your payment method to restore access.',
            'trial_expired'   => 'Your free trial has expired. Subscribe to a plan to continue using SmartBiz AI.',
            default           => 'Your subscription has been suspended. Contact support for assistance.',
        };

        Notification::create([
            'workspace_id' => $workspaceId,
            'type'         => 'alert',
            'title'        => 'Subscription Suspended',
            'message'      => $message,
        ]);
    }

    /**
     * Check for low/exhausted credits.
     */
    public function processCreditsLow(): array
    {
        $balances = AiCreditBalance::all();
        $sent = [];

        foreach ($balances as $bal) {
            $total = ($bal->included_credits ?? 0) + ($bal->bonus_credits ?? 0) + ($bal->purchased_credits ?? 0);
            $remaining = $total - ($bal->used_credits ?? 0);
            $threshold = max(1, (int) ($total * 0.2));

            if ($remaining > $threshold || $remaining < 0) continue;

            $exists = Notification::where('workspace_id', $bal->workspace_id)
                ->where('title', 'LIKE', '%AI Credits%')
                ->where('created_at', '>=', now()->subDay())
                ->exists();
            if ($exists) continue;

            $title = $remaining <= 0 ? 'AI Credits Exhausted' : 'AI Credits Running Low';
            $msg   = $remaining <= 0
                ? 'You have no AI credits remaining. Purchase additional credits to continue using AI features.'
                : "You have {$remaining} AI credits remaining. Consider purchasing more credits.";

            Notification::create([
                'workspace_id' => $bal->workspace_id,
                'type'         => 'warning',
                'title'        => $title,
                'message'      => $msg,
            ]);
            $sent[] = $bal->workspace_id;
        }

        return $sent;
    }
}
