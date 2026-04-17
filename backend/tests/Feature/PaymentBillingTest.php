<?php

namespace Tests\Feature;

use App\Models\AiCreditBalance;
use App\Models\PaymentTransaction;
use App\Models\WebhookEvent;
use App\Models\WorkspaceSubscription;
use App\Services\StripeService;
use Database\Seeders\CertificationSeeder;
use Database\Seeders\FoundationSeeder;
use Database\Seeders\PlatformSeeder;
use Tests\Support\FakeStripeService;

/**
 * Payment + Billing Automation Tests (PB01–PB12).
 *
 * Uses FakeStripeService — no real Stripe calls.
 */
class PaymentBillingTest extends SmartBizTestCase
{
    private const ADMIN_URI = '/api/admin';
    private FakeStripeService $fakeStripe;

    protected function setUp(): void
    {
        parent::setUp();

        // Super-admin flag
        \DB::table('users')
            ->where('id', FoundationSeeder::USER_ID)
            ->update(['is_super_admin' => true]);

        // Replace StripeService with fake
        $this->fakeStripe = new FakeStripeService();
        $this->app->instance(StripeService::class, $this->fakeStripe);

        // Clean slate
        \App\Models\WorkspaceFeatureFlag::where('workspace_id', FoundationSeeder::WORKSPACE_ID)->delete();
        AiCreditBalance::where('workspace_id', FoundationSeeder::WORKSPACE_ID)->delete();
        PaymentTransaction::where('workspace_id', FoundationSeeder::WORKSPACE_ID)->delete();
        WebhookEvent::query()->delete();
        WorkspaceSubscription::where('workspace_id', FoundationSeeder::WORKSPACE_ID)->delete();
    }

    // ── Helpers ───────────────────────────────────────────────

    private function adminGet(string $uri): \Illuminate\Testing\TestResponse
    {
        return $this->withHeaders([
            'Authorization' => "Bearer {$this->token}",
            'Accept'        => 'application/json',
        ])->getJson(self::ADMIN_URI . $uri);
    }

    private function adminPost(string $uri, array $data = []): \Illuminate\Testing\TestResponse
    {
        return $this->withHeaders([
            'Authorization' => "Bearer {$this->token}",
            'Accept'        => 'application/json',
        ])->postJson(self::ADMIN_URI . $uri, $data);
    }

    private function adminPut(string $uri, array $data = []): \Illuminate\Testing\TestResponse
    {
        return $this->withHeaders([
            'Authorization' => "Bearer {$this->token}",
            'Accept'        => 'application/json',
        ])->putJson(self::ADMIN_URI . $uri, $data);
    }

    /**
     * Assign a plan (internal, for setup).
     */
    private function assignPlan(): void
    {
        $this->adminPut('/workspaces/' . FoundationSeeder::WORKSPACE_ID . '/subscription', [
            'plan_id'       => PlatformSeeder::PLAN_STARTER,
            'plan_price_id' => PlatformSeeder::PRICE_STARTER_M,
            'billing_cycle' => 'monthly',
        ])->assertOk();
    }

    // ── PB01: Stripe customer creation ──────────────────────

    public function test_pb01_stripe_customer_creation(): void
    {
        $this->assignPlan();

        $response = $this->adminPost('/workspaces/' . FoundationSeeder::WORKSPACE_ID . '/setup-billing');
        $response->assertOk();

        $sub = WorkspaceSubscription::where('workspace_id', FoundationSeeder::WORKSPACE_ID)->first();
        $this->assertNotNull($sub->stripe_customer_id);
        $this->assertStringStartsWith('cus_fake_', $sub->stripe_customer_id);

        // FakeStripeService should have created a customer
        $this->assertCount(1, $this->fakeStripe->getCreatedCustomers());
    }

    // ── PB02: Subscription creation maps to Stripe ──────────

    public function test_pb02_subscription_creation_stripe(): void
    {
        $this->assignPlan();

        $paymentService = app(\App\Services\BillingPaymentService::class);
        $sub = $paymentService->createStripeSubscription(
            FoundationSeeder::WORKSPACE_ID,
            'price_starter_monthly',
        );

        $this->assertNotNull($sub->stripe_subscription_id);
        $this->assertStringStartsWith('sub_fake_', $sub->stripe_subscription_id);
        $this->assertEquals('price_starter_monthly', $sub->stripe_price_id);

        $this->assertCount(1, $this->fakeStripe->getCreatedSubscriptions());
    }

    // ── PB03: Subscription cancellation ─────────────────────

    public function test_pb03_subscription_cancellation(): void
    {
        $this->assignPlan();
        $paymentService = app(\App\Services\BillingPaymentService::class);
        $paymentService->createStripeSubscription(FoundationSeeder::WORKSPACE_ID, 'price_starter_monthly');

        $cancelled = $paymentService->cancelStripeSubscription(FoundationSeeder::WORKSPACE_ID);
        $this->assertNotNull($cancelled->cancelled_at);
    }

    // ── PB04: Upgrade/downgrade ─────────────────────────────

    public function test_pb04_upgrade_downgrade(): void
    {
        $this->assignPlan();
        $paymentService = app(\App\Services\BillingPaymentService::class);
        $paymentService->createStripeSubscription(FoundationSeeder::WORKSPACE_ID, 'price_starter_monthly');

        $upgraded = $paymentService->changeSubscription(
            FoundationSeeder::WORKSPACE_ID,
            PlatformSeeder::PRICE_PRO_M,
            'price_pro_monthly',
        );

        $this->assertEquals(PlatformSeeder::PLAN_PRO, $upgraded->plan_id);
        $this->assertEquals('price_pro_monthly', $upgraded->stripe_price_id);
        $this->assertEquals(15, $upgraded->included_employees); // Pro = 15
    }

    // ── PB05: AI credit purchase ────────────────────────────

    public function test_pb05_ai_credit_purchase(): void
    {
        $this->assignPlan();

        $paymentService = app(\App\Services\BillingPaymentService::class);
        $tx = $paymentService->purchaseCredits(
            FoundationSeeder::WORKSPACE_ID,
            100,
            9.99,
        );

        $this->assertEquals('credit_purchase', $tx->type);
        $this->assertEquals('succeeded', $tx->status);
        $this->assertEquals(9.99, $tx->amount);

        // Verify credits added
        $bal = AiCreditBalance::where('workspace_id', FoundationSeeder::WORKSPACE_ID)->first();
        $this->assertEquals(100, $bal->purchased_credits);
    }

    // ── PB06: Webhook payment success ───────────────────────

    public function test_pb06_webhook_payment_success(): void
    {
        $this->assignPlan();

        // Set status to trial
        WorkspaceSubscription::where('workspace_id', FoundationSeeder::WORKSPACE_ID)
            ->update([
                'status' => 'trial',
                'stripe_customer_id' => 'cus_test_123',
            ]);

        $webhookService = app(\App\Services\WebhookService::class);
        $processed = $webhookService->processEvent(
            'evt_payment_success_001',
            'invoice.payment_succeeded',
            [
                'data' => [
                    'object' => [
                        'id'             => 'in_test_001',
                        'customer'       => 'cus_test_123',
                        'payment_intent' => 'pi_test_001',
                        'amount_paid'    => 2900,
                        'currency'       => 'usd',
                    ],
                ],
            ],
        );

        $this->assertTrue($processed);

        // Subscription should be activated
        $sub = WorkspaceSubscription::where('workspace_id', FoundationSeeder::WORKSPACE_ID)->first();
        $this->assertEquals('active', $sub->status);

        // Payment transaction recorded
        $tx = PaymentTransaction::where('stripe_payment_intent_id', 'pi_test_001')->first();
        $this->assertNotNull($tx);
        $this->assertEquals('succeeded', $tx->status);
        $this->assertEquals(29.00, (float) $tx->amount);
    }

    // ── PB07: Webhook payment failure → suspend ─────────────

    public function test_pb07_webhook_payment_failure(): void
    {
        $this->assignPlan();
        WorkspaceSubscription::where('workspace_id', FoundationSeeder::WORKSPACE_ID)
            ->update(['status' => 'active', 'stripe_customer_id' => 'cus_fail_123']);

        $webhookService = app(\App\Services\WebhookService::class);

        // First failure → past_due
        $webhookService->processEvent('evt_fail_001', 'invoice.payment_failed', [
            'data' => ['object' => [
                'customer' => 'cus_fail_123', 'payment_intent' => 'pi_fail_001',
                'amount_due' => 2900, 'currency' => 'usd',
            ]],
        ]);
        $sub = WorkspaceSubscription::where('workspace_id', FoundationSeeder::WORKSPACE_ID)->first();
        $this->assertEquals('past_due', $sub->status);

        // Second failure → suspended
        $webhookService->processEvent('evt_fail_002', 'invoice.payment_failed', [
            'data' => ['object' => [
                'customer' => 'cus_fail_123', 'payment_intent' => 'pi_fail_002',
                'amount_due' => 2900, 'currency' => 'usd',
            ]],
        ]);
        $sub->refresh();
        $this->assertEquals('suspended', $sub->status);
    }

    // ── PB08: Webhook idempotency ───────────────────────────

    public function test_pb08_webhook_idempotency(): void
    {
        $this->assignPlan();
        WorkspaceSubscription::where('workspace_id', FoundationSeeder::WORKSPACE_ID)
            ->update(['status' => 'trial', 'stripe_customer_id' => 'cus_idem_123']);

        $webhookService = app(\App\Services\WebhookService::class);

        // First processing
        $first = $webhookService->processEvent('evt_idem_001', 'invoice.payment_succeeded', [
            'data' => ['object' => [
                'customer' => 'cus_idem_123', 'payment_intent' => 'pi_idem_001',
                'amount_paid' => 2900, 'currency' => 'usd', 'id' => 'in_idem',
            ]],
        ]);
        $this->assertTrue($first);

        // Second processing (duplicate) — should be skipped
        $second = $webhookService->processEvent('evt_idem_001', 'invoice.payment_succeeded', [
            'data' => ['object' => [
                'customer' => 'cus_idem_123', 'payment_intent' => 'pi_idem_001',
                'amount_paid' => 2900, 'currency' => 'usd', 'id' => 'in_idem',
            ]],
        ]);
        $this->assertFalse($second);

        // Only one webhook event record
        $this->assertEquals(1, WebhookEvent::where('stripe_event_id', 'evt_idem_001')->count());
    }

    // ── PB09: Trial expiration → suspension ─────────────────

    public function test_pb09_trial_expiration(): void
    {
        $this->assignPlan();
        WorkspaceSubscription::where('workspace_id', FoundationSeeder::WORKSPACE_ID)
            ->update([
                'status'         => 'trial',
                'trial_ends_at'  => now()->subDay(),
            ]);

        $automation = app(\App\Services\BillingAutomationService::class);
        $processed = $automation->processExpiredTrials();

        $this->assertContains(FoundationSeeder::WORKSPACE_ID, $processed);

        $sub = WorkspaceSubscription::where('workspace_id', FoundationSeeder::WORKSPACE_ID)->first();
        $this->assertEquals('suspended', $sub->status);
    }

    // ── PB10: Billing snapshot generation ───────────────────

    public function test_pb10_billing_snapshot_generation(): void
    {
        $this->assignPlan();
        WorkspaceSubscription::where('workspace_id', FoundationSeeder::WORKSPACE_ID)
            ->update([
                'status'               => 'active',
                'current_period_end'   => now()->subHour(),
            ]);

        $automation = app(\App\Services\BillingAutomationService::class);
        $generated = $automation->generatePeriodSnapshots();

        $this->assertContains(FoundationSeeder::WORKSPACE_ID, $generated);

        $snapshot = \App\Models\BillingSnapshot::where('workspace_id', FoundationSeeder::WORKSPACE_ID)->first();
        $this->assertNotNull($snapshot);
        $this->assertEquals('draft', $snapshot->status);
    }

    // ── PB11: Monthly credit reset ──────────────────────────

    public function test_pb11_monthly_credit_reset(): void
    {
        $this->assignPlan();

        // Set period_end to past and add usage
        AiCreditBalance::where('workspace_id', FoundationSeeder::WORKSPACE_ID)
            ->update([
                'period_end'   => now()->subHour(),
                'used_credits' => 80,
            ]);

        $automation = app(\App\Services\BillingAutomationService::class);
        $reset = $automation->resetMonthlyCredits();

        $this->assertContains(FoundationSeeder::WORKSPACE_ID, $reset);

        $bal = AiCreditBalance::where('workspace_id', FoundationSeeder::WORKSPACE_ID)->first();
        $this->assertEquals(0, $bal->used_credits);
        $this->assertEquals(100, $bal->included_credits); // Starter plan = 100
    }

    // ── PB12: Employee count sync ───────────────────────────

    public function test_pb12_employee_count_sync(): void
    {
        $this->assignPlan();

        $automation = app(\App\Services\BillingAutomationService::class);
        $synced = $automation->syncAllEmployeeCounts();

        $this->assertNotEmpty($synced);

        $sub = WorkspaceSubscription::where('workspace_id', FoundationSeeder::WORKSPACE_ID)->first();
        $this->assertNotNull($sub->current_employee_count);
        $this->assertGreaterThanOrEqual(0, $sub->current_employee_count);
    }
}
