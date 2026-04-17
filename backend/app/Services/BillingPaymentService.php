<?php

namespace App\Services;

use App\Models\AiCreditBalance;
use App\Models\PaymentTransaction;
use App\Models\PlatformPlanPrice;
use App\Models\Workspace;
use App\Models\WorkspaceSubscription;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * Orchestrates payment flows: billing setup, subscription management,
 * credit purchases, payment success/failure handling.
 */
class BillingPaymentService
{
    public function __construct(
        private readonly StripeService   $stripe,
        private readonly AiCreditService $credits,
    ) {}

    /**
     * Set up Stripe customer for a workspace.
     */
    public function setupBilling(string $workspaceId): WorkspaceSubscription
    {
        $ws = Workspace::findOrFail($workspaceId);
        $sub = WorkspaceSubscription::where('workspace_id', $workspaceId)->first();

        if ($sub && $sub->stripe_customer_id) {
            return $sub; // Already set up
        }

        // Get the owner's email
        $owner = DB::table('workspace_memberships')
            ->join('users', 'users.id', '=', 'workspace_memberships.user_id')
            ->where('workspace_memberships.workspace_id', $workspaceId)
            ->where('workspace_memberships.status', 'active')
            ->orderBy('workspace_memberships.created_at')
            ->select('users.email', 'users.full_name')
            ->first();

        $email = $owner?->email ?? 'billing@smartbiz.ai';

        $customer = $this->stripe->createCustomer(
            $ws->name,
            $email,
            ['workspace_id' => $workspaceId],
        );

        if ($sub) {
            $sub->update(['stripe_customer_id' => $customer['id']]);
        } else {
            $sub = WorkspaceSubscription::create([
                'workspace_id'         => $workspaceId,
                'plan_id'              => PlatformPlanPrice::first()?->plan_id,
                'plan_price_id'        => PlatformPlanPrice::first()?->id,
                'billing_cycle'        => 'monthly',
                'status'               => 'trial',
                'current_period_start' => now(),
                'current_period_end'   => now()->addDays(14),
                'stripe_customer_id'   => $customer['id'],
            ]);
        }

        return $sub;
    }

    /**
     * Create a Stripe subscription for a workspace.
     */
    public function createStripeSubscription(string $workspaceId, string $stripePriceId, int $trialDays = 0): WorkspaceSubscription
    {
        $sub = WorkspaceSubscription::where('workspace_id', $workspaceId)->firstOrFail();

        if (! $sub->stripe_customer_id) {
            $this->setupBilling($workspaceId);
            $sub->refresh();
        }

        $stripeSub = $this->stripe->createSubscription(
            $sub->stripe_customer_id,
            $stripePriceId,
            $trialDays,
        );

        $sub->update([
            'stripe_subscription_id' => $stripeSub['id'],
            'stripe_price_id'        => $stripePriceId,
            'status'                 => $trialDays > 0 ? 'trial' : 'active',
        ]);

        return $sub->fresh();
    }

    /**
     * Cancel the Stripe subscription.
     */
    public function cancelStripeSubscription(string $workspaceId, bool $immediately = false): WorkspaceSubscription
    {
        $sub = WorkspaceSubscription::where('workspace_id', $workspaceId)->firstOrFail();

        if ($sub->stripe_subscription_id) {
            $this->stripe->cancelSubscription($sub->stripe_subscription_id, $immediately);
        }

        $sub->update([
            'status'       => $immediately ? 'cancelled' : $sub->status,
            'cancelled_at' => now(),
        ]);

        return $sub->fresh();
    }

    /**
     * Upgrade or downgrade the subscription.
     */
    public function changeSubscription(string $workspaceId, string $newPlanPriceId, string $newStripePriceId): WorkspaceSubscription
    {
        $sub = WorkspaceSubscription::where('workspace_id', $workspaceId)->firstOrFail();
        $newPricing = PlatformPlanPrice::findOrFail($newPlanPriceId);

        if ($sub->stripe_subscription_id) {
            $this->stripe->updateSubscription($sub->stripe_subscription_id, $newStripePriceId);
        }

        $sub->update([
            'plan_id'              => $newPricing->plan_id,
            'plan_price_id'        => $newPlanPriceId,
            'stripe_price_id'      => $newStripePriceId,
            'billing_cycle'        => $newPricing->billing_cycle,
            'included_employees'   => $newPricing->included_employees,
            'price_per_extra_employee' => $newPricing->price_per_employee,
        ]);

        // Update AI credit balance
        $bal = AiCreditBalance::where('workspace_id', $workspaceId)->first();
        if ($bal) {
            $bal->update(['included_credits' => $newPricing->included_ai_credits]);
        }

        return $sub->fresh();
    }

    /**
     * Purchase AI credits (direct, no Stripe checkout).
     */
    public function purchaseCredits(string $workspaceId, int $credits, float $amount, string $currency = 'usd'): PaymentTransaction
    {
        return DB::transaction(function () use ($workspaceId, $credits, $amount, $currency) {
            $tx = PaymentTransaction::create([
                'workspace_id'             => $workspaceId,
                'stripe_payment_intent_id' => 'pi_credit_' . uniqid(),
                'type'                     => 'credit_purchase',
                'amount'                   => $amount,
                'currency'                 => $currency,
                'status'                   => 'succeeded',
                'description'              => "Purchase of {$credits} AI credits",
                'metadata'                 => ['credits' => $credits],
                'created_at'               => now(),
            ]);

            $this->credits->purchaseCredits($workspaceId, $credits);

            return $tx;
        });
    }

    /**
     * Handle a successful payment (called by WebhookService).
     */
    public function handlePaymentSuccess(string $workspaceId, string $paymentIntentId, float $amountCents, string $currency, ?string $invoiceId = null): void
    {
        DB::transaction(function () use ($workspaceId, $paymentIntentId, $amountCents, $currency, $invoiceId) {
            PaymentTransaction::updateOrCreate(
                ['stripe_payment_intent_id' => $paymentIntentId],
                [
                    'workspace_id'      => $workspaceId,
                    'stripe_invoice_id' => $invoiceId,
                    'type'              => 'subscription',
                    'amount'            => $amountCents / 100,
                    'currency'          => $currency,
                    'status'            => 'succeeded',
                    'description'       => 'Subscription payment',
                    'created_at'        => now(),
                ],
            );

            $sub = WorkspaceSubscription::where('workspace_id', $workspaceId)->first();
            if ($sub && in_array($sub->status, ['trial', 'past_due'])) {
                $sub->update(['status' => 'active']);
            }
        });
    }

    /**
     * Handle a failed payment (called by WebhookService).
     */
    public function handlePaymentFailure(string $workspaceId, string $paymentIntentId, float $amountCents, string $currency, ?string $invoiceId = null): void
    {
        DB::transaction(function () use ($workspaceId, $paymentIntentId, $amountCents, $currency, $invoiceId) {
            PaymentTransaction::updateOrCreate(
                ['stripe_payment_intent_id' => $paymentIntentId],
                [
                    'workspace_id'      => $workspaceId,
                    'stripe_invoice_id' => $invoiceId,
                    'type'              => 'subscription',
                    'amount'            => $amountCents / 100,
                    'currency'          => $currency,
                    'status'            => 'failed',
                    'description'       => 'Payment failed',
                    'created_at'        => now(),
                ],
            );

            $sub = WorkspaceSubscription::where('workspace_id', $workspaceId)->first();
            if (! $sub) return;

            $failures = PaymentTransaction::where('workspace_id', $workspaceId)
                ->where('status', 'failed')
                ->where('created_at', '>=', now()->subDays(30))
                ->count();

            if ($failures >= 2) {
                $sub->update(['status' => 'suspended']);
                Log::warning("Workspace {$workspaceId} suspended after {$failures} payment failures.");
            } else {
                $sub->update(['status' => 'past_due']);
            }
        });
    }

    /**
     * Get payment history for a workspace.
     */
    public function paymentHistory(string $workspaceId, int $limit = 20): \Illuminate\Support\Collection
    {
        return PaymentTransaction::where('workspace_id', $workspaceId)
            ->orderByDesc('created_at')
            ->limit($limit)
            ->get();
    }
}
