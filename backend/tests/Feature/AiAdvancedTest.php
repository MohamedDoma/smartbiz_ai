<?php

namespace Tests\Feature;

use App\Models\AiCreditBalance;
use App\Services\Ai\AiInsightService;
use App\Services\Ai\AiMemoryService;
use App\Services\Ai\AiStepPlanner;
use App\Services\Ai\LlmProviderInterface;
use App\Services\Ai\LlmResponse;
use App\Services\Ai\ProviderRouter;
use Database\Seeders\FoundationSeeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\Support\FakeLlmProvider;

/**
 * AI Phase 3 Advanced Tests (ADV01–ADV15).
 */
class AiAdvancedTest extends SmartBizTestCase
{
    private FakeLlmProvider $fakeLlm;
    private AiMemoryService $memory;

    protected function setUp(): void
    {
        parent::setUp();

        $this->fakeLlm = new FakeLlmProvider();
        $this->app->instance(LlmProviderInterface::class, $this->fakeLlm);
        $this->memory = new AiMemoryService();

        DB::table('ai_conversation_messages')->delete();
        DB::table('ai_conversations')->where('workspace_id', FoundationSeeder::WORKSPACE_ID)->delete();
        DB::table('ai_change_requests')->where('workspace_id', FoundationSeeder::WORKSPACE_ID)->delete();
        DB::table('ai_memory')->where('workspace_id', FoundationSeeder::WORKSPACE_ID)->delete();
        DB::table('ai_execution_plans')->where('workspace_id', FoundationSeeder::WORKSPACE_ID)->delete();
        DB::table('ai_insights')->where('workspace_id', FoundationSeeder::WORKSPACE_ID)->delete();

        AiCreditBalance::updateOrCreate(
            ['workspace_id' => FoundationSeeder::WORKSPACE_ID],
            [
                'included_credits'  => 1000,
                'purchased_credits' => 0,
                'bonus_credits'     => 0,
                'trial_credits'     => 0,
                'used_credits'      => 0,
                'hard_limit'        => false,
                'period_start'      => now(),
                'period_end'        => now()->addMonth(),
            ],
        );
    }

    // ═══════════════════════════════════════════════════════════
    // ADV01 — Provider fallback succeeds
    // ═══════════════════════════════════════════════════════════

    public function test_adv01_provider_fallback_succeeds(): void
    {
        $primary = new class implements LlmProviderInterface {
            public function providerName(): string { return 'failing'; }
            public function defaultModel(): string { return 'fail'; }
            public function chat(array $messages, array $options = []): LlmResponse {
                throw new \RuntimeException('Primary failed');
            }
            public function chatWithTools(array $messages, array $tools, array $options = []): LlmResponse {
                throw new \RuntimeException('Primary failed');
            }
        };

        $fallback = new FakeLlmProvider();
        $fallback->queueTextResponse('Fallback response');

        $router = new ProviderRouter();
        $ref = new \ReflectionClass($router);
        $prop = $ref->getProperty('primary');
        $prop->setValue($router, $primary);
        $prop2 = $ref->getProperty('fallback');
        $prop2->setValue($router, $fallback);

        $result = $router->withFallback(fn ($provider) => $provider->chat([['role' => 'user', 'content' => 'test']]));

        $this->assertEquals('Fallback response', $result->content);
        $this->assertEquals('fake', $result->provider);
    }

    // ═══════════════════════════════════════════════════════════
    // ADV02 — Anthropic provider routing via resolveProvider
    // ═══════════════════════════════════════════════════════════

    public function test_adv02_anthropic_provider_routing(): void
    {
        $provider = new \App\Services\Ai\AnthropicProvider();
        $this->assertEquals('anthropic', $provider->providerName());
        $this->assertNotEmpty($provider->defaultModel());
    }

    // ═══════════════════════════════════════════════════════════
    // ADV03 — Memory: entity frequency tracking
    // ═══════════════════════════════════════════════════════════

    public function test_adv03_memory_entity_frequency(): void
    {
        $wsId = FoundationSeeder::WORKSPACE_ID;

        $this->memory->recordEntityAccess($wsId, 'contact', 'c-001', 'Ahmed');
        $this->memory->recordEntityAccess($wsId, 'contact', 'c-001', 'Ahmed');
        $this->memory->recordEntityAccess($wsId, 'contact', 'c-002', 'Sara');

        $frequent = $this->memory->getFrequentEntities($wsId, 'contact', 5);

        $this->assertCount(2, $frequent);
        $this->assertEquals('Ahmed', $frequent[0]['entity_name']);
        $this->assertEquals(2, $frequent[0]['score']);
    }

    // ═══════════════════════════════════════════════════════════
    // ADV04 — Memory: session context persistence
    // ═══════════════════════════════════════════════════════════

    public function test_adv04_memory_session_context(): void
    {
        $wsId   = FoundationSeeder::WORKSPACE_ID;
        $userId = FoundationSeeder::USER_ID;

        $this->memory->setSessionContext($wsId, $userId, 'last_action', 'created_invoice');
        $value = $this->memory->getSessionContext($wsId, $userId, 'last_action');

        $this->assertEquals('created_invoice', $value);

        // Overwrite
        $this->memory->setSessionContext($wsId, $userId, 'last_action', 'searched_contacts');
        $value2 = $this->memory->getSessionContext($wsId, $userId, 'last_action');
        $this->assertEquals('searched_contacts', $value2);
    }

    // ═══════════════════════════════════════════════════════════
    // ADV05 — Memory: context injected to prompt
    // ═══════════════════════════════════════════════════════════

    public function test_adv05_memory_context_in_prompt(): void
    {
        $wsId   = FoundationSeeder::WORKSPACE_ID;
        $userId = FoundationSeeder::USER_ID;

        $this->memory->recordEntityAccess($wsId, 'contact', 'c-001', 'Ahmed');
        $this->memory->setSessionContext($wsId, $userId, 'workflow', 'invoicing');

        $context = $this->memory->getRelevantMemory($wsId, $userId);

        $this->assertArrayHasKey('session', $context);
        $this->assertEquals('invoicing', $context['session']['workflow']);
        $this->assertArrayHasKey('frequent_contacts', $context);
        $this->assertContains('Ahmed', $context['frequent_contacts']);
    }

    // ═══════════════════════════════════════════════════════════
    // ADV06 — Draft order creates pending action
    // ═══════════════════════════════════════════════════════════

    public function test_adv06_draft_order_pending(): void
    {
        // Seed a contact for resolution
        DB::table('contacts')->updateOrInsert(
            ['id' => '99990000-0000-0000-0000-000000000002'],
            [
                'workspace_id' => FoundationSeeder::WORKSPACE_ID,
                'name'         => 'Order Customer',
                'email'        => 'order@test.com',
                'type'         => 'customer',
                'created_at'   => now(),
                'updated_at'   => now(),
            ],
        );

        $this->fakeLlm->queueToolCall('draft_order', [
            'customer_name' => 'Order Customer',
            'order_type'    => 'sale_order',
            'items'         => [['product_name' => 'Widget', 'quantity' => 5]],
        ]);

        $response = $this->wsPost('/api/ai/chat', ['message' => 'Create a sale order for Order Customer']);
        $response->assertOk();
        $data = $response->json('data');

        $this->assertContains($data['mode'], ['pending_action', 'ambiguity']);

        DB::table('contacts')->where('id', '99990000-0000-0000-0000-000000000002')->delete();
    }

    // ═══════════════════════════════════════════════════════════
    // ADV07 — Draft payment creates pending action
    // ═══════════════════════════════════════════════════════════

    public function test_adv07_draft_payment_pending(): void
    {
        $this->fakeLlm->queueToolCall('draft_payment', [
            'invoice_number' => 'INV-001',
            'amount'         => 500.0,
            'payment_method' => 'cash',
        ]);

        $response = $this->wsPost('/api/ai/chat', ['message' => 'Record payment for INV-001']);
        $response->assertOk();
        $data = $response->json('data');

        $this->assertEquals('pending_action', $data['mode']);
        $this->assertNotEmpty($data['action_id']);

        $action = DB::table('ai_change_requests')->where('id', $data['action_id'])->first();
        $this->assertEquals('payment', $action->change_type);
        $this->assertEquals('medium', $action->risk_level);
    }

    // ═══════════════════════════════════════════════════════════
    // ADV08 — Draft inventory adjustment
    // ═══════════════════════════════════════════════════════════

    public function test_adv08_draft_inventory_adjustment(): void
    {
        $this->fakeLlm->queueToolCall('draft_inventory_adjustment', [
            'product_name'   => 'Widget',
            'quantity_change' => 10,
            'reason'          => 'restock',
        ]);

        $response = $this->wsPost('/api/ai/chat', ['message' => 'Add 10 widgets to inventory']);
        $response->assertOk();
        $data = $response->json('data');

        $this->assertContains($data['mode'], ['pending_action', 'ambiguity']);

        if ($data['mode'] === 'pending_action') {
            $action = DB::table('ai_change_requests')->where('id', $data['action_id'])->first();
            $this->assertEquals('inventory', $action->change_type);
        }
    }

    // ═══════════════════════════════════════════════════════════
    // ADV09 — Update invoice status (draft)
    // ═══════════════════════════════════════════════════════════

    public function test_adv09_update_invoice_status(): void
    {
        $this->fakeLlm->queueToolCall('update_invoice_status', [
            'invoice_number' => 'INV-001',
            'new_status'     => 'paid',
        ]);

        $response = $this->wsPost('/api/ai/chat', ['message' => 'Mark INV-001 as paid']);
        $response->assertOk();
        $data = $response->json('data');

        $this->assertEquals('pending_action', $data['mode']);
        $action = DB::table('ai_change_requests')->where('id', $data['action_id'])->first();
        $this->assertEquals('status_update', $action->change_type);
        $this->assertEquals('medium', $action->risk_level);
    }

    // ═══════════════════════════════════════════════════════════
    // ADV10 — Update order status (draft)
    // ═══════════════════════════════════════════════════════════

    public function test_adv10_update_order_status(): void
    {
        $this->fakeLlm->queueToolCall('update_order_status', [
            'order_number' => 'ORD-001',
            'new_status'   => 'confirmed',
        ]);

        $response = $this->wsPost('/api/ai/chat', ['message' => 'Confirm order ORD-001']);
        $response->assertOk();
        $data = $response->json('data');

        $this->assertEquals('pending_action', $data['mode']);
    }

    // ═══════════════════════════════════════════════════════════
    // ADV11 — Multi-step plan creation
    // ═══════════════════════════════════════════════════════════

    public function test_adv11_multistep_plan_creation(): void
    {
        $planner = $this->app->make(AiStepPlanner::class);

        $plan = $planner->createPlan(
            FoundationSeeder::WORKSPACE_ID,
            FoundationSeeder::USER_ID,
            null,
            'Create Order + Invoice',
            [
                ['tool' => 'draft_order', 'params' => ['order_type' => 'sale_order']],
                ['tool' => 'draft_invoice', 'params' => ['invoice_type' => 'sale']],
            ],
        );

        $this->assertNotNull($plan);
        $this->assertEquals('pending', $plan->status);
        $this->assertEquals(0, $plan->current_step);

        $steps = json_decode($plan->steps, true);
        $this->assertCount(2, $steps);
        $this->assertEquals('pending', $steps[0]['status']);
    }

    // ═══════════════════════════════════════════════════════════
    // ADV12 — Multi-step plan execution (step-by-step)
    // ═══════════════════════════════════════════════════════════

    public function test_adv12_multistep_plan_execution(): void
    {
        $planner = $this->app->make(AiStepPlanner::class);

        $plan = $planner->createPlan(
            FoundationSeeder::WORKSPACE_ID,
            FoundationSeeder::USER_ID,
            null,
            'Test Execution',
            [
                ['tool' => 'draft_contact', 'params' => ['name' => 'StepTest Customer', 'type' => 'customer']],
            ],
        );

        $result = $planner->executeNextStep($plan->id, FoundationSeeder::WORKSPACE_ID, FoundationSeeder::USER_ID);

        $this->assertEquals('step_pending', $result['status']);
        $this->assertEquals(0, $result['step']);
        $this->assertNotEmpty($result['action_id']);

        // Verify action created
        $action = DB::table('ai_change_requests')->where('id', $result['action_id'])->first();
        $this->assertEquals('multi_step', $action->change_type);
        $this->assertEquals('proposed', $action->status);
    }

    // ═══════════════════════════════════════════════════════════
    // ADV13 — Proactive insights generation
    // ═══════════════════════════════════════════════════════════

    public function test_adv13_proactive_insights(): void
    {
        $service = $this->app->make(AiInsightService::class);

        $insights = $service->generateInsights(FoundationSeeder::WORKSPACE_ID);

        // Even if no data matches, the method should work without errors
        $this->assertIsArray($insights);

        // Verify stored
        $stored = $service->getInsights(FoundationSeeder::WORKSPACE_ID, 'new');
        $this->assertCount(count($insights), $stored);
    }

    // ═══════════════════════════════════════════════════════════
    // ADV14 — Insight dismissal
    // ═══════════════════════════════════════════════════════════

    public function test_adv14_insight_dismissal(): void
    {
        $insightId = Str::uuid()->toString();
        DB::table('ai_insights')->insert([
            'id'           => $insightId,
            'workspace_id' => FoundationSeeder::WORKSPACE_ID,
            'insight_type' => 'general',
            'severity'     => 'info',
            'title'        => 'Test Insight',
            'detail'       => json_encode(['message' => 'test']),
            'status'       => 'new',
            'created_at'   => now(),
            'updated_at'   => now(),
        ]);

        $response = $this->wsPost("/api/ai/insights/{$insightId}/dismiss");
        $response->assertOk();
        $this->assertEquals('dismissed', $response->json('data.status'));

        $row = DB::table('ai_insights')->where('id', $insightId)->first();
        $this->assertEquals('dismissed', $row->status);
    }

    // ═══════════════════════════════════════════════════════════
    // ADV15 — Credit cost varies by complexity
    // ═══════════════════════════════════════════════════════════

    public function test_adv15_credit_cost_varies(): void
    {
        // Simple chat = 1 credit
        $this->fakeLlm->queueTextResponse('Simple response');
        $before = (int) DB::table('ai_credit_balances')->where('workspace_id', FoundationSeeder::WORKSPACE_ID)->value('used_credits');
        $this->wsPost('/api/ai/chat', ['message' => 'Hello']);

        $after1 = (int) DB::table('ai_credit_balances')->where('workspace_id', FoundationSeeder::WORKSPACE_ID)->value('used_credits');
        $costSimple = $after1 - $before;

        // Tool use = 2 credits (1 base + 1 tool)
        $this->fakeLlm
            ->queueToolCall('get_sales_summary', [])
            ->queueTextResponse('Sales data');
        $this->wsPost('/api/ai/chat', ['message' => 'Show sales']);

        $after2 = (int) DB::table('ai_credit_balances')->where('workspace_id', FoundationSeeder::WORKSPACE_ID)->value('used_credits');
        $costWithTool = $after2 - $after1;

        $this->assertGreaterThanOrEqual(1, $costSimple, 'Simple chat should cost at least 1 credit');
        $this->assertGreaterThanOrEqual(2, $costWithTool, 'Tool use should cost at least 2 credits');
        $this->assertGreaterThanOrEqual($costSimple, $costWithTool, 'Tool use should cost more than simple chat');
    }
}
