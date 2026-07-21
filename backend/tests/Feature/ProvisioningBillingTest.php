<?php

namespace Tests\Feature;

use App\Models\AiCreditBalance;
use App\Models\DiscoveryBlueprint;
use App\Models\DiscoverySession;
use App\Models\ManualPayment;
use App\Models\Notification;
use App\Models\PaymentTransaction;
use App\Models\ProvisioningRun;
use App\Models\WebhookEvent;
use App\Models\WorkspaceConfiguration;
use App\Models\WorkspaceSubscription;
use App\Services\Blueprint\BlueprintGenerator;
use App\Services\Blueprint\BlueprintSchema;
use App\Services\StripeService;
use Database\Seeders\FoundationSeeder;
use Database\Seeders\PlatformSeeder;
use Tests\Support\FakeStripeService;

/**
 * ERP Provisioning + Billing Hardening Tests (EP01–EP06, BH01–BH06).
 */
class ProvisioningBillingTest extends SmartBizTestCase
{
    private const ADMIN_URI = '/api/admin';
    private string $blueprintId;

    protected function setUp(): void
    {
        parent::setUp();

        // Super-admin flag
        \DB::table('users')
            ->where('id', FoundationSeeder::USER_ID)
            ->update(['is_super_admin' => true]);

        // Replace Stripe
        $this->app->instance(StripeService::class, new FakeStripeService());

        // Clean slate
        \App\Models\WorkspaceFeatureFlag::where('workspace_id', FoundationSeeder::WORKSPACE_ID)->delete();
        AiCreditBalance::where('workspace_id', FoundationSeeder::WORKSPACE_ID)->delete();
        PaymentTransaction::where('workspace_id', FoundationSeeder::WORKSPACE_ID)->delete();
        WebhookEvent::query()->delete();
        WorkspaceSubscription::where('workspace_id', FoundationSeeder::WORKSPACE_ID)->delete();
        ProvisioningRun::where('workspace_id', FoundationSeeder::WORKSPACE_ID)->delete();
        WorkspaceConfiguration::where('workspace_id', FoundationSeeder::WORKSPACE_ID)->delete();
        ManualPayment::where('workspace_id', FoundationSeeder::WORKSPACE_ID)->delete();
        Notification::where('workspace_id', FoundationSeeder::WORKSPACE_ID)->delete();

        // Create a discovery session + blueprint for provisioning tests
        $session = DiscoverySession::firstOrCreate(
            ['workspace_id' => FoundationSeeder::WORKSPACE_ID, 'status' => 'completed'],
            [
                'created_by'       => FoundationSeeder::USER_ID,
                'business_description' => 'A retail electronics shop with 5 staff',
            ],
        );

        $canonicalBlueprint = app(BlueprintGenerator::class)->generate('retail', [
            'business_name'        => 'Test Electronics',
            'business_description' => 'A retail electronics shop with 5 staff',
            'employee_count'       => 5,
            'branch_count'         => 1,
            'sells_products'       => true,
            'sells_services'       => false,
            'country'              => 'MY',
            'currency'             => 'MYR',
            'primary_language'     => 'en',
            // Keep the fixture focused on the canonical owner role so it does
            // not collide with FoundationSeeder's pre-existing admin role.
            'role_details'         => [[
                'name'             => 'Owner',
                'responsibilities' => ['Full system access and ownership'],
                'headcount'        => 1,
            ]],
        ]);

        $blueprint = DiscoveryBlueprint::updateOrCreate(
            ['session_id' => $session->id, 'workspace_id' => FoundationSeeder::WORKSPACE_ID],
            [
                'business_type'     => 'retail',
                'blueprint'         => $canonicalBlueprint,
                'version'           => 1,
                'generator_method'  => 'canonical_v1',
                'generator_version' => BlueprintSchema::VERSION,
            ],
        );
        $this->blueprintId = $blueprint->id;
    }

    // ── Helpers ───────────────────────────────────────────────

    private function adminPost(string $uri, array $data = []): \Illuminate\Testing\TestResponse
    {
        return $this->withHeaders([
            'Authorization' => "Bearer {$this->token}",
            'Accept'        => 'application/json',
        ])->postJson(self::ADMIN_URI . $uri, $data);
    }

    private function adminGet(string $uri): \Illuminate\Testing\TestResponse
    {
        return $this->withHeaders([
            'Authorization' => "Bearer {$this->token}",
            'Accept'        => 'application/json',
        ])->getJson(self::ADMIN_URI . $uri);
    }

    private function adminPut(string $uri, array $data = []): \Illuminate\Testing\TestResponse
    {
        return $this->withHeaders([
            'Authorization' => "Bearer {$this->token}",
            'Accept'        => 'application/json',
        ])->putJson(self::ADMIN_URI . $uri, $data);
    }

    private function assignPlan(): void
    {
        $this->adminPut('/workspaces/' . FoundationSeeder::WORKSPACE_ID . '/subscription', [
            'plan_id'       => PlatformSeeder::PLAN_STARTER,
            'plan_price_id' => PlatformSeeder::PRICE_STARTER_M,
            'billing_cycle' => 'monthly',
        ])->assertOk();
    }

    // ═══════════════════════════════════════════════════════════
    // Part A — ERP Provisioning Tests (EP01–EP06)
    // ═══════════════════════════════════════════════════════════

    public function test_ep01_preview_provisioning(): void
    {
        $response = $this->wsPost('/api/provisioning/preview', [
            'blueprint_id' => $this->blueprintId,
        ]);

        $response->assertOk();
        $data = $response->json('data');
        $this->assertEquals('preview', $data['status']);
        $this->assertArrayHasKey('config_mapping', $data);
        $this->assertArrayHasKey('enabled_modules', $data['config_mapping']);
        $this->assertArrayHasKey('role_configs', $data['config_mapping']);
        $this->assertContains('customers', $data['config_mapping']['enabled_modules']);

        // Run should be in preview status
        $run = ProvisioningRun::find($data['run_id']);
        $this->assertEquals('preview', $run->status);
    }

    public function test_ep02_apply_provisioning(): void
    {
        // Phase 1: apply the foundational entities and workspace config.
        $foundation = $this->wsPost('/api/provisioning/apply', [
            'blueprint_id' => $this->blueprintId,
        ]);

        $foundation->assertOk();
        $foundationData = $foundation->json('data');
        $this->assertEquals('foundation_applied', $foundationData['status']);
        $this->assertNotNull($foundationData['blueprint_version']);
        $this->assertNotEmpty($foundationData['run_id']);

        // Phase 2: apply operational entities using the run-specific endpoint.
        $operational = $this->wsPost(
            '/api/provisioning/' . $foundationData['run_id'] . '/apply-operational'
        );
        $operational->assertOk();
        $this->assertEquals('applied', $operational->json('data.status'));

        // Workspace config should exist and use the canonical module vocabulary.
        $config = WorkspaceConfiguration::where('workspace_id', FoundationSeeder::WORKSPACE_ID)->first();
        $this->assertNotNull($config);
        $this->assertContains('customers', $config->enabled_modules);
        $this->assertArrayHasKey('owner', $config->role_configs);

        // Canonical provisioning stores role identity and permission summary.
        $ownerConfig = $config->role_configs['owner'];
        $this->assertArrayHasKey('name', $ownerConfig);
        $this->assertArrayHasKey('description', $ownerConfig);
        $this->assertArrayHasKey('department_key', $ownerConfig);
        $this->assertArrayHasKey('permission_count', $ownerConfig);
    }

    public function test_ep03_rollback_provisioning(): void
    {
        // Apply first
        $applyResponse = $this->wsPost('/api/provisioning/apply', [
            'blueprint_id' => $this->blueprintId,
        ]);
        $runId = $applyResponse->json('data.run_id');

        // Rollback
        $response = $this->wsPost('/api/provisioning/rollback', ['run_id' => $runId]);
        $response->assertOk();
        $this->assertEquals('rolled_back', $response->json('data.status'));

        // Run should be rolled_back
        $run = ProvisioningRun::find($runId);
        $this->assertEquals('rolled_back', $run->status);
    }

    public function test_ep04_module_update(): void
    {
        // Apply first
        $this->wsPost('/api/provisioning/apply', ['blueprint_id' => $this->blueprintId]);

        // Update modules
        $response = $this->wsPut('/api/provisioning/modules', [
            'modules' => ['contacts', 'products', 'invoices'],
        ]);

        $response->assertOk();
        $config = WorkspaceConfiguration::where('workspace_id', FoundationSeeder::WORKSPACE_ID)->first();
        $this->assertCount(3, $config->enabled_modules);
        $this->assertContains('invoices', $config->enabled_modules);
    }

    public function test_ep05_role_config_update(): void
    {
        // Apply first
        $this->wsPost('/api/provisioning/apply', ['blueprint_id' => $this->blueprintId]);

        // Update cashier role
        $response = $this->wsPut('/api/provisioning/roles/cashier', [
            'homepage'          => '/custom-pos',
            'navigation'        => ['pos', 'invoices', 'payments', 'reports'],
            'dashboard_widgets' => ['todays_sales', 'recent_transactions', 'cash_drawer'],
        ]);

        $response->assertOk();
        $config = WorkspaceConfiguration::where('workspace_id', FoundationSeeder::WORKSPACE_ID)->first();
        $cashier = $config->role_configs['cashier'];
        $this->assertEquals('/custom-pos', $cashier['homepage']);
        $this->assertContains('reports', $cashier['navigation']);
        $this->assertContains('cash_drawer', $cashier['dashboard_widgets']);
    }

    public function test_ep06_get_active_config(): void
    {
        // No config yet
        $response = $this->wsGet('/api/provisioning/config');
        $response->assertOk();
        $this->assertNull($response->json('data'));

        // Apply
        $this->wsPost('/api/provisioning/apply', ['blueprint_id' => $this->blueprintId]);

        // Config should exist
        $response = $this->wsGet('/api/provisioning/config');
        $response->assertOk();
        $this->assertNotNull($response->json('data'));
        $this->assertNotEmpty($response->json('data.enabled_modules'));
    }

    // ═══════════════════════════════════════════════════════════
    // Part B — Billing Hardening Tests (BH01–BH06)
    // ═══════════════════════════════════════════════════════════

    public function test_bh01_refund_webhook(): void
    {
        $this->assignPlan();
        WorkspaceSubscription::where('workspace_id', FoundationSeeder::WORKSPACE_ID)
            ->update(['stripe_customer_id' => 'cus_refund_123']);

        // Create a credit purchase transaction
        PaymentTransaction::create([
            'workspace_id'             => FoundationSeeder::WORKSPACE_ID,
            'stripe_payment_intent_id' => 'pi_credit_001',
            'type'                     => 'credit_purchase',
            'amount'                   => 9.99,
            'currency'                 => 'usd',
            'status'                   => 'succeeded',
            'metadata'                 => ['credits' => 100],
            'created_at'               => now(),
        ]);

        // Add purchased credits
        AiCreditBalance::where('workspace_id', FoundationSeeder::WORKSPACE_ID)
            ->update(['purchased_credits' => 100]);

        $webhookService = app(\App\Services\WebhookService::class);
        $webhookService->processEvent('evt_refund_001', 'charge.refunded', [
            'data' => ['object' => [
                'payment_intent'  => 'pi_credit_001',
                'customer'        => 'cus_refund_123',
                'amount_refunded' => 999,
            ]],
        ]);

        // Transaction should be refunded
        $tx = PaymentTransaction::where('stripe_payment_intent_id', 'pi_credit_001')->first();
        $this->assertEquals('refunded', $tx->status);

        // Credits should be deducted
        $bal = AiCreditBalance::where('workspace_id', FoundationSeeder::WORKSPACE_ID)->first();
        $this->assertEquals(0, $bal->purchased_credits);
    }

    public function test_bh02_trial_expiring_notification(): void
    {
        $this->assignPlan();
        WorkspaceSubscription::where('workspace_id', FoundationSeeder::WORKSPACE_ID)
            ->update([
                'status'        => 'trial',
                'trial_ends_at' => now()->addDays(2),
            ]);

        $notificationService = app(\App\Services\BillingNotificationService::class);
        $sent = $notificationService->processTrialExpiring();

        $this->assertContains(FoundationSeeder::WORKSPACE_ID, $sent);

        // Notification should exist
        $notif = Notification::where('workspace_id', FoundationSeeder::WORKSPACE_ID)
            ->where('title', 'Trial Expiring Soon')
            ->first();
        $this->assertNotNull($notif);
        $this->assertEquals('warning', $notif->type);
    }

    public function test_bh03_manual_payment_submit(): void
    {
        $response = $this->wsPost('/api/billing/manual-payment', [
            'amount'        => 290.00,
            'method'        => 'bank_transfer',
            'reference'     => 'TRX-2026-001',
            'plan_id'       => PlatformSeeder::PLAN_STARTER,
            'billing_cycle' => 'annual',
            'notes'         => 'Annual payment via wire transfer',
        ]);

        $response->assertCreated();
        $data = $response->json('data');
        $this->assertEquals('pending', $data['status']);
        $this->assertEquals('bank_transfer', $data['method']);
        $this->assertEquals('290.00', $data['amount']);

        $mp = ManualPayment::find($data['id']);
        $this->assertNotNull($mp);
        $this->assertEquals(FoundationSeeder::WORKSPACE_ID, $mp->workspace_id);
    }

    public function test_bh04_manual_payment_confirm(): void
    {
        // Submit
        $mp = ManualPayment::create([
            'workspace_id'  => FoundationSeeder::WORKSPACE_ID,
            'amount'        => 290.00,
            'currency'      => 'usd',
            'method'        => 'bank_transfer',
            'reference'     => 'BANK-001',
            'status'        => 'pending',
            'plan_id'       => PlatformSeeder::PLAN_STARTER,
            'billing_cycle' => 'monthly',
            'submitted_by'  => FoundationSeeder::USER_ID,
            'created_at'    => now(),
        ]);

        // Confirm
        $response = $this->adminPost("/manual-payments/{$mp->id}/confirm");
        $response->assertOk();

        $mp->refresh();
        $this->assertEquals('confirmed', $mp->status);
        $this->assertNotNull($mp->confirmed_at);

        // Subscription should be active
        $sub = WorkspaceSubscription::where('workspace_id', FoundationSeeder::WORKSPACE_ID)->first();
        $this->assertNotNull($sub);
        $this->assertEquals('active', $sub->status);

        // Payment transaction should be recorded
        $tx = PaymentTransaction::where('workspace_id', FoundationSeeder::WORKSPACE_ID)
            ->where('description', 'LIKE', '%Manual payment%')
            ->first();
        $this->assertNotNull($tx);
        $this->assertEquals('succeeded', $tx->status);
    }

    public function test_bh05_manual_payment_reject(): void
    {
        $mp = ManualPayment::create([
            'workspace_id'  => FoundationSeeder::WORKSPACE_ID,
            'amount'        => 100.00,
            'currency'      => 'usd',
            'method'        => 'cheque',
            'reference'     => 'CHK-001',
            'status'        => 'pending',
            'submitted_by'  => FoundationSeeder::USER_ID,
            'created_at'    => now(),
        ]);

        $response = $this->adminPost("/manual-payments/{$mp->id}/reject", [
            'reason' => 'Cheque bounced',
        ]);

        $response->assertOk();
        $mp->refresh();
        $this->assertEquals('rejected', $mp->status);
        $this->assertEquals('Cheque bounced', $mp->rejected_reason);
    }

    public function test_bh06_scheduler_commands_registered(): void
    {
        $this->artisan('billing:expire-trials')->assertExitCode(0);
        $this->artisan('billing:generate-snapshots')->assertExitCode(0);
        $this->artisan('billing:sync-employees')->assertExitCode(0);
        $this->artisan('billing:reset-credits')->assertExitCode(0);
        $this->artisan('billing:send-notifications')->assertExitCode(0);
    }
}
