<?php

namespace Tests\Support;

use App\Services\StripeService;

/**
 * Fake Stripe service for testing.
 * Returns deterministic, predictable responses without calling Stripe API.
 */
class FakeStripeService extends StripeService
{
    private array $customers = [];
    private array $subscriptions = [];
    private int $counter = 0;

    public function __construct()
    {
        // Skip parent constructor — no real Stripe client needed
    }

    public function createCustomer(string $name, string $email, array $metadata = []): array
    {
        $id = 'cus_fake_' . ++$this->counter;
        $this->customers[$id] = compact('id', 'name', 'email', 'metadata');
        return $this->customers[$id];
    }

    public function createSubscription(string $customerId, string $priceId, int $trialDays = 0): array
    {
        $id = 'sub_fake_' . ++$this->counter;
        $this->subscriptions[$id] = [
            'id'       => $id,
            'customer' => $customerId,
            'status'   => $trialDays > 0 ? 'trialing' : 'active',
            'items'    => ['data' => [['id' => 'si_fake_' . $this->counter, 'price' => ['id' => $priceId]]]],
            'current_period_start' => time(),
            'current_period_end'   => time() + 86400 * 30,
        ];
        return $this->subscriptions[$id];
    }

    public function cancelSubscription(string $subscriptionId, bool $immediately = false): array
    {
        if (isset($this->subscriptions[$subscriptionId])) {
            $this->subscriptions[$subscriptionId]['status'] = $immediately ? 'canceled' : 'active';
            $this->subscriptions[$subscriptionId]['cancel_at_period_end'] = ! $immediately;
            return $this->subscriptions[$subscriptionId];
        }
        return ['id' => $subscriptionId, 'status' => 'canceled'];
    }

    public function updateSubscription(string $subscriptionId, string $newPriceId): array
    {
        if (isset($this->subscriptions[$subscriptionId])) {
            $this->subscriptions[$subscriptionId]['items']['data'][0]['price']['id'] = $newPriceId;
            return $this->subscriptions[$subscriptionId];
        }
        return ['id' => $subscriptionId, 'status' => 'active'];
    }

    public function createCreditPurchaseSession(string $customerId, int $amount, string $currency, string $description, string $successUrl, string $cancelUrl): array
    {
        return [
            'id'  => 'cs_fake_' . ++$this->counter,
            'url' => 'https://checkout.stripe.com/fake/' . $this->counter,
        ];
    }

    public function constructWebhookEvent(string $payload, string $signature): \Stripe\Event
    {
        // In tests, this is bypassed — WebhookService is called directly
        throw new \RuntimeException('Use WebhookService directly in tests.');
    }

    public function retrieveSubscription(string $subscriptionId): array
    {
        return $this->subscriptions[$subscriptionId] ?? ['id' => $subscriptionId, 'status' => 'active'];
    }

    // ── Test introspection ────────────────────────────────────

    public function getCreatedCustomers(): array
    {
        return $this->customers;
    }

    public function getCreatedSubscriptions(): array
    {
        return $this->subscriptions;
    }
}
