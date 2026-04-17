<?php

namespace App\Services;

use App\Models\WebhookEvent;
use App\Models\WorkspaceSubscription;
use App\Models\AiCreditBalance;
use App\Models\PaymentTransaction;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * Processes Stripe webhook events idempotently.
 * Each event is stored in `webhook_events` and checked for duplicates.
 */
class WebhookService
{
    public function __construct(
        private readonly BillingPaymentService       $payment,
        private readonly SubscriptionService         $subscriptions,
        private readonly SuperAdminService           $admin,
        private readonly BillingNotificationService  $notifications,
    ) {}

    /**
     * Process a Stripe webhook event.
     * Returns true if processed, false if duplicate.
     */
    public function processEvent(string $stripeEventId, string $eventType, array $payload): bool
    {
        // Idempotency: skip if already processed
        $existing = WebhookEvent::where('stripe_event_id', $stripeEventId)->first();
        if ($existing && $existing->isProcessed()) {
            Log::info("Webhook event {$stripeEventId} already processed, skipping.");
            return false;
        }

        // Store the event
        $event = WebhookEvent::updateOrCreate(
            ['stripe_event_id' => $stripeEventId],
            [
                'event_type' => $eventType,
                'payload'    => $payload,
                'status'     => 'received',
                'created_at' => now(),
            ],
        );

        try {
            $this->handleEvent($eventType, $payload);
            $event->update(['status' => 'processed', 'processed_at' => now()]);
            return true;
        } catch (\Throwable $e) {
            $event->update(['status' => 'failed', 'error_message' => $e->getMessage()]);
            Log::error("Webhook event {$stripeEventId} failed: {$e->getMessage()}");
            throw $e;
        }
    }

    /**
     * Route event to appropriate handler.
     */
    private function handleEvent(string $type, array $payload): void
    {
        match ($type) {
            'invoice.payment_succeeded'          => $this->onPaymentSucceeded($payload),
            'invoice.payment_failed'             => $this->onPaymentFailed($payload),
            'customer.subscription.updated'      => $this->onSubscriptionUpdated($payload),
            'customer.subscription.deleted'       => $this->onSubscriptionDeleted($payload),
            'checkout.session.completed'         => $this->onCheckoutCompleted($payload),
            'charge.refunded'                    => $this->onRefund($payload),
            default                              => Log::info("Unhandled webhook type: {$type}"),
        };
    }

    private function onPaymentSucceeded(array $payload): void
    {
        $invoice = $payload['data']['object'] ?? [];
        $customerId = $invoice['customer'] ?? null;
        $paymentIntentId = $invoice['payment_intent'] ?? 'pi_' . uniqid();
        $amount = $invoice['amount_paid'] ?? 0;
        $currency = $invoice['currency'] ?? 'usd';

        $sub = $this->findSubscriptionByCustomer($customerId);
        if (! $sub) {
            Log::warning("No subscription found for customer {$customerId}");
            return;
        }

        $this->payment->handlePaymentSuccess(
            $sub->workspace_id,
            $paymentIntentId,
            (float) $amount,
            $currency,
            $invoice['id'] ?? null,
        );

        // Generate billing snapshot on successful payment
        $this->admin->createBillingSnapshot($sub->workspace_id);
    }

    private function onPaymentFailed(array $payload): void
    {
        $invoice = $payload['data']['object'] ?? [];
        $customerId = $invoice['customer'] ?? null;
        $paymentIntentId = $invoice['payment_intent'] ?? 'pi_failed_' . uniqid();
        $amount = $invoice['amount_due'] ?? 0;
        $currency = $invoice['currency'] ?? 'usd';

        $sub = $this->findSubscriptionByCustomer($customerId);
        if (! $sub) return;

        $this->payment->handlePaymentFailure(
            $sub->workspace_id,
            $paymentIntentId,
            (float) $amount,
            $currency,
            $invoice['id'] ?? null,
        );
    }

    private function onSubscriptionUpdated(array $payload): void
    {
        $stripeSub = $payload['data']['object'] ?? [];
        $stripeSubId = $stripeSub['id'] ?? null;
        $status = $stripeSub['status'] ?? null;

        $sub = WorkspaceSubscription::where('stripe_subscription_id', $stripeSubId)->first();
        if (! $sub) return;

        // Map Stripe status -> internal status
        $internalStatus = match ($status) {
            'active'   => 'active',
            'trialing' => 'trial',
            'past_due' => 'past_due',
            'canceled', 'cancelled' => 'cancelled',
            'unpaid'   => 'suspended',
            default    => $sub->status,
        };

        $sub->update([
            'status' => $internalStatus,
            'current_period_start' => isset($stripeSub['current_period_start'])
                ? \Carbon\Carbon::createFromTimestamp($stripeSub['current_period_start'])
                : $sub->current_period_start,
            'current_period_end' => isset($stripeSub['current_period_end'])
                ? \Carbon\Carbon::createFromTimestamp($stripeSub['current_period_end'])
                : $sub->current_period_end,
        ]);
    }

    private function onSubscriptionDeleted(array $payload): void
    {
        $stripeSub = $payload['data']['object'] ?? [];
        $stripeSubId = $stripeSub['id'] ?? null;

        $sub = WorkspaceSubscription::where('stripe_subscription_id', $stripeSubId)->first();
        if (! $sub) return;

        $sub->update([
            'status'       => 'cancelled',
            'cancelled_at' => now(),
        ]);
    }

    private function onCheckoutCompleted(array $payload): void
    {
        $session = $payload['data']['object'] ?? [];
        $customerId = $session['customer'] ?? null;
        $mode = $session['mode'] ?? '';

        if ($mode !== 'payment') return;

        $sub = $this->findSubscriptionByCustomer($customerId);
        if (! $sub) return;

        // Credit purchase via checkout — metadata should contain credits
        $meta = $session['metadata'] ?? [];
        $credits = (int) ($meta['credits'] ?? 0);
        if ($credits > 0) {
            $amount = ($session['amount_total'] ?? 0) / 100;
            $this->payment->purchaseCredits($sub->workspace_id, $credits, $amount);
        }
    }

    private function findSubscriptionByCustomer(?string $customerId): ?WorkspaceSubscription
    {
        if (! $customerId) return null;
        return WorkspaceSubscription::where('stripe_customer_id', $customerId)->first();
    }

    /**
     * Handle charge.refunded — update payment transaction and deduct credits if applicable.
     */
    private function onRefund(array $payload): void
    {
        $charge = $payload['data']['object'] ?? [];
        $paymentIntentId = $charge['payment_intent'] ?? null;
        $refundedAmount  = ($charge['amount_refunded'] ?? 0) / 100;
        $customerId      = $charge['customer'] ?? null;

        if (! $paymentIntentId) return;

        // Update payment transaction status
        $tx = PaymentTransaction::where('stripe_payment_intent_id', $paymentIntentId)->first();
        if ($tx) {
            $tx->update([
                'status'   => 'refunded',
                'metadata' => array_merge($tx->metadata ?? [], [
                    'refunded_amount' => $refundedAmount,
                    'refunded_at'     => now()->toISOString(),
                ]),
            ]);

            // If this was a credit purchase, deduct purchased credits
            if ($tx->type === 'credit_purchase' && $tx->workspace_id) {
                $meta = $tx->metadata ?? [];
                $credits = (int) ($meta['credits'] ?? 0);
                if ($credits > 0) {
                    AiCreditBalance::where('workspace_id', $tx->workspace_id)
                        ->decrement('purchased_credits', $credits);
                    Log::info("Refund: deducted {$credits} purchased credits for workspace {$tx->workspace_id}");
                }
            }
        }

        // Notify workspace
        $sub = $this->findSubscriptionByCustomer($customerId);
        if ($sub) {
            $this->notifications->notifyPaymentFailed($sub->workspace_id, $refundedAmount, 'usd');
        }
    }
}
