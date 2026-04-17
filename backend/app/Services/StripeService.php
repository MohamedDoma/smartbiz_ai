<?php

namespace App\Services;

use Stripe\StripeClient;
use Stripe\Exception\ApiErrorException;

/**
 * Low-level Stripe API wrapper.
 * All Stripe interactions go through this service.
 *
 * In test mode, this class is replaced with FakeStripeService.
 */
class StripeService
{
    private ?StripeClient $client = null;

    /**
     * Lazy-load the Stripe client — only when actually needed.
     */
    private function client(): StripeClient
    {
        if (! $this->client) {
            $key = config('stripe.secret_key');
            if (empty($key)) {
                throw new \RuntimeException('Stripe secret key is not configured. Set STRIPE_SECRET_KEY in .env');
            }
            $this->client = new StripeClient($key);
        }
        return $this->client;
    }

    /**
     * Create a Stripe customer for a workspace.
     */
    public function createCustomer(string $name, string $email, array $metadata = []): array
    {
        $customer = $this->client()->customers->create([
            'name'     => $name,
            'email'    => $email,
            'metadata' => $metadata,
        ]);
        return $customer->toArray();
    }

    /**
     * Create a subscription for an existing customer.
     */
    public function createSubscription(string $customerId, string $priceId, int $trialDays = 0): array
    {
        $params = [
            'customer' => $customerId,
            'items'    => [['price' => $priceId]],
        ];

        if ($trialDays > 0) {
            $params['trial_period_days'] = $trialDays;
        }

        $subscription = $this->client()->subscriptions->create($params);
        return $subscription->toArray();
    }

    /**
     * Cancel a subscription (at period end).
     */
    public function cancelSubscription(string $subscriptionId, bool $immediately = false): array
    {
        if ($immediately) {
            $sub = $this->client()->subscriptions->cancel($subscriptionId);
        } else {
            $sub = $this->client()->subscriptions->update($subscriptionId, [
                'cancel_at_period_end' => true,
            ]);
        }
        return $sub->toArray();
    }

    /**
     * Update a subscription (upgrade/downgrade).
     */
    public function updateSubscription(string $subscriptionId, string $newPriceId): array
    {
        $sub = $this->client()->subscriptions->retrieve($subscriptionId);
        $updated = $this->client()->subscriptions->update($subscriptionId, [
            'items' => [[
                'id'    => $sub->items->data[0]->id,
                'price' => $newPriceId,
            ]],
            'proration_behavior' => 'create_prorations',
        ]);
        return $updated->toArray();
    }

    /**
     * Create a checkout session for credit purchase (one-time).
     */
    public function createCreditPurchaseSession(string $customerId, int $amount, string $currency, string $description, string $successUrl, string $cancelUrl): array
    {
        $session = $this->client()->checkout->sessions->create([
            'customer'   => $customerId,
            'mode'       => 'payment',
            'line_items' => [[
                'price_data' => [
                    'currency'     => $currency,
                    'product_data' => ['name' => $description],
                    'unit_amount'  => $amount, // cents
                ],
                'quantity' => 1,
            ]],
            'success_url' => $successUrl,
            'cancel_url'  => $cancelUrl,
        ]);
        return $session->toArray();
    }

    /**
     * Construct and verify a webhook event from payload + signature.
     */
    public function constructWebhookEvent(string $payload, string $signature): \Stripe\Event
    {
        return \Stripe\Webhook::constructEvent(
            $payload,
            $signature,
            config('stripe.webhook_secret'),
        );
    }

    /**
     * Retrieve a subscription.
     */
    public function retrieveSubscription(string $subscriptionId): array
    {
        return $this->client()->subscriptions->retrieve($subscriptionId)->toArray();
    }
}
