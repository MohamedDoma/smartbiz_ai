<?php

namespace App\Services;

use App\Models\AiCreditBalance;
use App\Models\Notification;
use App\Models\WorkspaceSubscription;

/**
 * Billing notification service.
 *
 * Cross-workspace discovery runs on the limited control connection. Every
 * tenant write is then executed through the strict tenant runtime connection.
 */
class BillingNotificationService
{
    public function __construct(
        private readonly WorkspaceContextManager $workspaceContext,
    ) {}

    public function processTrialExpiring(): array
    {
        $expiring = WorkspaceSubscription::where('status', 'trial')
            ->whereBetween('trial_ends_at', [now(), now()->addDays(3)])
            ->get();

        $sent = [];
        foreach ($expiring as $sub) {
            $created = $this->workspaceContext->runSystemInWorkspace(
                $sub->workspace_id,
                function () use ($sub): bool {
                    $exists = Notification::where('workspace_id', $sub->workspace_id)
                        ->where('title', 'Trial Expiring Soon')
                        ->where('created_at', '>=', now()->subDay())
                        ->exists();

                    if ($exists) {
                        return false;
                    }

                    Notification::create([
                        'workspace_id' => $sub->workspace_id,
                        'type' => 'warning',
                        'title' => 'Trial Expiring Soon',
                        'message' => 'Your free trial will expire on '.$sub->trial_ends_at->format('M d, Y').'. Please add a payment method to continue using SmartBiz AI.',
                    ]);

                    return true;
                },
            );

            if ($created) {
                $sent[] = $sub->workspace_id;
            }
        }

        return $sent;
    }

    public function notifyPaymentFailed(string $workspaceId, float $amount, string $currency): void
    {
        $this->workspaceContext->runSystemInWorkspace($workspaceId, function () use ($workspaceId, $amount, $currency): void {
            Notification::create([
                'workspace_id' => $workspaceId,
                'type' => 'alert',
                'title' => 'Payment Failed',
                'message' => "Your payment of {$currency} ".number_format($amount, 2).' has failed. Please update your payment method to avoid service interruption.',
            ]);
        });
    }

    public function notifySubscriptionActivated(string $workspaceId): void
    {
        $this->workspaceContext->runSystemInWorkspace($workspaceId, function () use ($workspaceId): void {
            Notification::create([
                'workspace_id' => $workspaceId,
                'type' => 'success',
                'title' => 'Subscription Activated',
                'message' => 'Your subscription is now active. Welcome to SmartBiz AI!',
            ]);
        });
    }

    public function notifySubscriptionSuspended(string $workspaceId, string $reason = 'payment_failure'): void
    {
        $message = match ($reason) {
            'payment_failure' => 'Your subscription has been suspended due to failed payment. Please update your payment method to restore access.',
            'trial_expired' => 'Your free trial has expired. Subscribe to a plan to continue using SmartBiz AI.',
            default => 'Your subscription has been suspended. Contact support for assistance.',
        };

        $this->workspaceContext->runSystemInWorkspace($workspaceId, function () use ($workspaceId, $message): void {
            Notification::create([
                'workspace_id' => $workspaceId,
                'type' => 'alert',
                'title' => 'Subscription Suspended',
                'message' => $message,
            ]);
        });
    }

    public function processCreditsLow(): array
    {
        $balances = AiCreditBalance::all();
        $sent = [];

        foreach ($balances as $balance) {
            $total = ($balance->included_credits ?? 0)
                + ($balance->bonus_credits ?? 0)
                + ($balance->purchased_credits ?? 0);
            $remaining = $total - ($balance->used_credits ?? 0);
            $threshold = max(1, (int) ($total * 0.2));

            if ($remaining > $threshold || $remaining < 0) {
                continue;
            }

            $created = $this->workspaceContext->runSystemInWorkspace(
                $balance->workspace_id,
                function () use ($balance, $remaining): bool {
                    $exists = Notification::where('workspace_id', $balance->workspace_id)
                        ->where('title', 'LIKE', '%AI Credits%')
                        ->where('created_at', '>=', now()->subDay())
                        ->exists();

                    if ($exists) {
                        return false;
                    }

                    $title = $remaining <= 0 ? 'AI Credits Exhausted' : 'AI Credits Running Low';
                    $message = $remaining <= 0
                        ? 'You have no AI credits remaining. Purchase additional credits to continue using AI features.'
                        : "You have {$remaining} AI credits remaining. Consider purchasing more credits.";

                    Notification::create([
                        'workspace_id' => $balance->workspace_id,
                        'type' => 'warning',
                        'title' => $title,
                        'message' => $message,
                    ]);

                    return true;
                },
            );

            if ($created) {
                $sent[] = $balance->workspace_id;
            }
        }

        return $sent;
    }
}
