<?php

namespace Tests\Feature;

use App\Models\AiCreditBalance;
use App\Models\PlatformSetting;
use App\Models\WorkspaceSubscription;
use App\Models\WorkspaceFeatureFlag;
use Database\Seeders\CertificationSeeder;
use Database\Seeders\FoundationSeeder;
use Database\Seeders\PlatformSeeder;

/**
 * Platform Control + AI Billing + Super Admin Tests (PC01–PC15).
 */
class PlatformControlTest extends SmartBizTestCase
{
    private const ADMIN_URI = '/api/admin';

    // ── Setup ─────────────────────────────────────────────────

    protected function setUp(): void
    {
        parent::setUp();

        // Ensure FS admin is super-admin
        \DB::table('users')
            ->where('id', FoundationSeeder::USER_ID)
            ->update(['is_super_admin' => true]);

        // Clean slate — remove leftover data from previous tests
        WorkspaceFeatureFlag::where('workspace_id', FoundationSeeder::WORKSPACE_ID)->delete();
        AiCreditBalance::where('workspace_id', FoundationSeeder::WORKSPACE_ID)->delete();
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
     * Helper: assign plan and return the subscription.
     */
    private function assignPlan(string $planId, string $priceId, string $cycle = 'monthly', bool $trial = false): \Illuminate\Testing\TestResponse
    {
        return $this->adminPut('/workspaces/' . FoundationSeeder::WORKSPACE_ID . '/subscription', [
            'plan_id'       => $planId,
            'plan_price_id' => $priceId,
            'billing_cycle' => $cycle,
            'is_trial'      => $trial,
        ]);
    }

    // Non-super-admin helper
    private function loginAs(string $email): string
    {
        $resp = $this->postJson('/api/auth/login', [
            'email'    => $email,
            'password' => CertificationSeeder::PASSWORD,
        ]);
        $resp->assertOk();
        return $resp->json('token');
    }

    // ── PC01: Create platform plan ──────────────────────────

    public function test_pc01_create_platform_plan(): void
    {
        $response = $this->adminPost('/plans', [
            'name'          => 'Test Plan',
            'slug'          => 'test-plan-' . uniqid(),
            'description'   => 'A test plan',
            'max_employees' => 20,
        ]);

        $response->assertCreated();
        $response->assertJsonStructure(['data' => ['id', 'name', 'slug', 'max_employees']]);
        $this->assertEquals(20, $response->json('data.max_employees'));
    }

    // ── PC02: Assign plan to workspace ──────────────────────

    public function test_pc02_assign_plan_to_workspace(): void
    {
        $response = $this->assignPlan(PlatformSeeder::PLAN_STARTER, PlatformSeeder::PRICE_STARTER_M, 'monthly', true);

        $response->assertOk();
        $data = $response->json('data');
        $this->assertEquals('trial', $data['status']);
        $this->assertEquals(5, $data['included_employees']);
        $this->assertNotNull($data['trial_ends_at']);
    }

    // ── PC03: Employee limit enforcement ────────────────────

    public function test_pc03_employee_limit_check(): void
    {
        $this->assignPlan(PlatformSeeder::PLAN_STARTER, PlatformSeeder::PRICE_STARTER_M);

        $sub = app(\App\Services\SubscriptionService::class);
        $result = $sub->syncEmployeeCount(FoundationSeeder::WORKSPACE_ID);
        $this->assertNotNull($result);

        $check = $sub->canAddEmployee(FoundationSeeder::WORKSPACE_ID);
        $this->assertArrayHasKey('allowed', $check);
    }

    // ── PC04: AI credit deduction ───────────────────────────

    public function test_pc04_ai_credit_deduction(): void
    {
        $this->assignPlan(PlatformSeeder::PLAN_PRO, PlatformSeeder::PRICE_PRO_M);

        $creditService = app(\App\Services\AiCreditService::class);
        $result = $creditService->chargeCredits(
            FoundationSeeder::WORKSPACE_ID,
            FoundationSeeder::USER_ID,
            'discovery_classify',
            2,
        );

        $this->assertTrue($result['success']);
        $this->assertEquals(2, $result['charged']);
        $this->assertGreaterThan(0, $result['available']);
    }

    // ── PC05: AI credit exhaustion → block with hard limit ──

    public function test_pc05_ai_credit_exhaustion_hard_limit(): void
    {
        // Assign free plan (20 credits)
        $this->assignPlan(PlatformSeeder::PLAN_FREE, PlatformSeeder::PRICE_FREE_M);

        // Set hard limit and reduce credits to 5
        $bal = AiCreditBalance::where('workspace_id', FoundationSeeder::WORKSPACE_ID)->first();
        $this->assertNotNull($bal, 'AI credit balance should exist after plan assignment');
        $bal->update([
            'hard_limit' => true,
            'included_credits' => 5,
            'purchased_credits' => 0,
            'bonus_credits' => 0,
            'trial_credits' => 0,
            'used_credits' => 0,
        ]);

        $creditService = app(\App\Services\AiCreditService::class);

        // Use all 5 credits
        $result1 = $creditService->chargeCredits(FoundationSeeder::WORKSPACE_ID, FoundationSeeder::USER_ID, 'test', 5);
        $this->assertTrue($result1['success']);

        // Try to use 1 more → should fail
        $result2 = $creditService->chargeCredits(FoundationSeeder::WORKSPACE_ID, FoundationSeeder::USER_ID, 'test', 1);
        $this->assertFalse($result2['success']);
        $this->assertEquals('Insufficient credits.', $result2['reason']);
    }

    // ── PC06: Soft limit warning ────────────────────────────

    public function test_pc06_soft_limit_warning(): void
    {
        $this->assignPlan(PlatformSeeder::PLAN_STARTER, PlatformSeeder::PRICE_STARTER_M);

        $bal = AiCreditBalance::where('workspace_id', FoundationSeeder::WORKSPACE_ID)->first();
        $bal->update([
            'soft_limit_threshold' => 5,
            'included_credits' => 100,
            'used_credits' => 0,
            'purchased_credits' => 0,
            'bonus_credits' => 0,
            'trial_credits' => 0,
        ]);

        $creditService = app(\App\Services\AiCreditService::class);
        $result = $creditService->chargeCredits(FoundationSeeder::WORKSPACE_ID, FoundationSeeder::USER_ID, 'test', 6);
        $this->assertTrue($result['success']);
        $this->assertEquals('Soft limit reached.', $result['warning']);
    }

    // ── PC07: Credit purchase ───────────────────────────────

    public function test_pc07_credit_purchase(): void
    {
        $this->assignPlan(PlatformSeeder::PLAN_STARTER, PlatformSeeder::PRICE_STARTER_M);

        $response = $this->adminPost('/workspaces/' . FoundationSeeder::WORKSPACE_ID . '/credits', [
            'type'    => 'purchase',
            'credits' => 200,
        ]);

        $response->assertOk();
        $this->assertEquals(200, $response->json('data.purchased_credits'));
    }

    // ── PC08: Monthly credit reset ──────────────────────────

    public function test_pc08_monthly_credit_reset(): void
    {
        $this->assignPlan(PlatformSeeder::PLAN_PRO, PlatformSeeder::PRICE_PRO_M);

        // Simulate usage
        $bal = AiCreditBalance::where('workspace_id', FoundationSeeder::WORKSPACE_ID)->first();
        $bal->update(['used_credits' => 450]);

        // Reset
        $creditService = app(\App\Services\AiCreditService::class);
        $newBal = $creditService->monthlyReset(FoundationSeeder::WORKSPACE_ID, 500);

        $this->assertEquals(500, $newBal->included_credits);
        $this->assertEquals(0, $newBal->used_credits);
        $this->assertEquals(0, $newBal->trial_credits);
    }

    // ── PC09: Feature flag enforcement ──────────────────────

    public function test_pc09_feature_flag_enforcement(): void
    {
        // Assign free plan (ai.chat should be disabled)
        $this->assignPlan(PlatformSeeder::PLAN_FREE, PlatformSeeder::PRICE_FREE_M);

        $ffService = app(\App\Services\FeatureFlagService::class);

        // Free plan: ai.chat = false
        $this->assertFalse($ffService->isEnabled(FoundationSeeder::WORKSPACE_ID, 'ai.chat'));
        // Free plan: module.contacts = true
        $this->assertTrue($ffService->isEnabled(FoundationSeeder::WORKSPACE_ID, 'module.contacts'));
    }

    // ── PC10: Workspace feature override ────────────────────

    public function test_pc10_workspace_feature_override(): void
    {
        $this->assignPlan(PlatformSeeder::PLAN_FREE, PlatformSeeder::PRICE_FREE_M);

        $ffService = app(\App\Services\FeatureFlagService::class);

        // ai.chat is disabled on free plan
        $this->assertFalse($ffService->isEnabled(FoundationSeeder::WORKSPACE_ID, 'ai.chat'));

        // Override: enable ai.chat for this workspace
        $this->adminPut('/workspaces/' . FoundationSeeder::WORKSPACE_ID . '/features', [
            'features' => [
                ['key' => 'ai.chat', 'enabled' => true, 'reason' => 'VIP customer'],
            ],
        ])->assertOk();

        // Now it should be enabled
        $this->assertTrue($ffService->isEnabled(FoundationSeeder::WORKSPACE_ID, 'ai.chat'));
    }

    // ── PC11: Super-admin can list workspaces ───────────────

    public function test_pc11_super_admin_list_workspaces(): void
    {
        $response = $this->adminGet('/workspaces');
        $response->assertOk();
        $response->assertJsonStructure(['data']);
        $this->assertGreaterThanOrEqual(1, count($response->json('data')));
    }

    // ── PC12: Super-admin can view dashboard ────────────────

    public function test_pc12_super_admin_dashboard(): void
    {
        $response = $this->adminGet('/dashboard');
        $response->assertOk();
        $response->assertJsonStructure([
            'data' => [
                'mrr', 'arr', 'total_workspaces', 'active_workspaces',
                'active_trials', 'expiring_trials_7d',
                'ai_requests_mtd', 'ai_credits_used_mtd',
            ],
        ]);
    }

    // ── PC13: Non-super-admin denied admin endpoints ────────

    public function test_pc13_non_super_admin_denied(): void
    {
        $token = $this->loginAs('readonly@cert.test');
        $response = $this->withHeaders([
            'Authorization' => "Bearer {$token}",
            'Accept'        => 'application/json',
        ])->getJson(self::ADMIN_URI . '/workspaces');

        $response->assertForbidden();
    }

    // ── PC14: Super-admin adjust bonus credits ──────────────

    public function test_pc14_super_admin_adjust_bonus_credits(): void
    {
        $this->assignPlan(PlatformSeeder::PLAN_STARTER, PlatformSeeder::PRICE_STARTER_M);

        $response = $this->adminPost('/workspaces/' . FoundationSeeder::WORKSPACE_ID . '/credits', [
            'type'    => 'bonus',
            'credits' => 100,
            'reason'  => 'Launch bonus for early adopter',
        ]);

        $response->assertOk();
        $this->assertEquals(100, $response->json('data.bonus_credits'));
    }

    // ── PC15: High-usage detection ──────────────────────────

    public function test_pc15_high_usage_detection(): void
    {
        $response = $this->adminGet('/high-usage?threshold=80');
        $response->assertOk();
        $response->assertJsonStructure(['data']);
    }
}
