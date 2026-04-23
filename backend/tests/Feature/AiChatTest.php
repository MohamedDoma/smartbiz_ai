<?php

namespace Tests\Feature;

use App\Models\AiCreditBalance;
use App\Services\Ai\LlmProviderInterface;
use App\Services\Ai\LlmResponse;
use Database\Seeders\FoundationSeeder;
use Database\Seeders\PlatformSeeder;
use Illuminate\Support\Facades\DB;
use Tests\Support\FakeLlmProvider;

/**
 * AI Chat Phase 2 Tests (AI01–AI12).
 */
class AiChatTest extends SmartBizTestCase
{
    private FakeLlmProvider $fakeLlm;

    protected function setUp(): void
    {
        parent::setUp();

        // Replace LLM with fake
        $this->fakeLlm = new FakeLlmProvider();
        $this->app->instance(LlmProviderInterface::class, $this->fakeLlm);

        // Clean slate
        DB::table('ai_conversation_messages')->delete();
        DB::table('ai_conversations')->where('workspace_id', FoundationSeeder::WORKSPACE_ID)->delete();
        DB::table('ai_change_requests')->where('workspace_id', FoundationSeeder::WORKSPACE_ID)->delete();

        // Ensure credits exist
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
    // AI01 — Basic chat returns response
    // ═══════════════════════════════════════════════════════════

    public function test_ai01_chat_returns_response(): void
    {
        $this->fakeLlm->queueTextResponse('Hello! How can I help you with your business today?');

        $response = $this->wsPost('/api/ai/chat', [
            'message' => 'Hello, what can you do?',
        ]);

        $response->assertOk();
        $data = $response->json('data');
        $this->assertNotEmpty($data['conversation_id']);
        $this->assertStringContainsString('Hello', $data['response']);
        $this->assertEquals('fake', $data['provider']);
        $this->assertEquals('fake-model-v1', $data['model']);
    }

    // ═══════════════════════════════════════════════════════════
    // AI02 — Read tool: get_sales_summary
    // ═══════════════════════════════════════════════════════════

    public function test_ai02_read_tool_sales_summary(): void
    {
        // Queue: tool call → then text response
        $this->fakeLlm
            ->queueToolCall('get_sales_summary', [])
            ->queueTextResponse('Your total sales are $0. You have 0 invoices.');

        $response = $this->wsPost('/api/ai/chat', ['message' => 'What are my total sales?']);

        $response->assertOk();
        $data = $response->json('data');
        $this->assertContains('get_sales_summary', $data['tools_used']);
    }

    // ═══════════════════════════════════════════════════════════
    // AI03 — Read tool: search_contacts
    // ═══════════════════════════════════════════════════════════

    public function test_ai03_read_tool_search_contacts(): void
    {
        // Seed a contact
        DB::table('contacts')->updateOrInsert(
            ['id' => '99990000-0000-0000-0000-000000000001'],
            [
                'workspace_id' => FoundationSeeder::WORKSPACE_ID,
                'name'         => 'Ahmed Hassan',
                'email'        => 'ahmed@example.com',
                'type'         => 'customer',
                'created_at'   => now(),
                'updated_at'   => now(),
            ],
        );

        $this->fakeLlm
            ->queueToolCall('search_contacts', ['query' => 'Ahmed'])
            ->queueTextResponse('I found Ahmed Hassan (ahmed@example.com).');

        $response = $this->wsPost('/api/ai/chat', ['message' => 'Find Ahmed']);

        $response->assertOk();
        $this->assertContains('search_contacts', $response->json('data.tools_used'));

        // Clean up
        DB::table('contacts')->where('id', '99990000-0000-0000-0000-000000000001')->delete();
    }

    // ═══════════════════════════════════════════════════════════
    // AI04 — Read tool: get_inventory_status
    // ═══════════════════════════════════════════════════════════

    public function test_ai04_read_tool_inventory_status(): void
    {
        $this->fakeLlm
            ->queueToolCall('get_inventory_status', [])
            ->queueTextResponse('Your inventory has 0 stock entries.');

        $response = $this->wsPost('/api/ai/chat', ['message' => 'What is my inventory status?']);

        $response->assertOk();
        $this->assertContains('get_inventory_status', $response->json('data.tools_used'));
    }

    // ═══════════════════════════════════════════════════════════
    // AI05 — Action: draft_contact creates pending action
    // ═══════════════════════════════════════════════════════════

    public function test_ai05_draft_contact_creates_pending_action(): void
    {
        $this->fakeLlm->queueToolCall('draft_contact', [
            'name'  => 'New Customer ABC',
            'type'  => 'customer',
            'email' => 'abc@example.com',
        ]);

        $response = $this->wsPost('/api/ai/chat', ['message' => 'Create a new customer called New Customer ABC']);

        $response->assertOk();
        $data = $response->json('data');

        // Should be pending_action or ambiguity
        $this->assertContains($data['mode'], ['pending_action', 'ambiguity']);

        if ($data['mode'] === 'pending_action') {
            $this->assertNotEmpty($data['action_id']);

            // Verify in db
            $action = DB::table('ai_change_requests')->where('id', $data['action_id'])->first();
            $this->assertNotNull($action);
            $this->assertEquals('proposed', $action->status);
        }
    }

    // ═══════════════════════════════════════════════════════════
    // AI06 — Confirm action executes correctly
    // ═══════════════════════════════════════════════════════════

    public function test_ai06_confirm_action(): void
    {
        // Create a pending action directly
        $actionId = \Illuminate\Support\Str::uuid()->toString();
        DB::table('ai_change_requests')->insert([
            'id'            => $actionId,
            'workspace_id'  => FoundationSeeder::WORKSPACE_ID,
            'requested_by'  => FoundationSeeder::USER_ID,
            'change_type'   => 'settings',
            'risk_level'    => 'low',
            'status'        => 'proposed',
            'proposed_diff' => json_encode([
                'tool'   => 'draft_contact',
                'params' => ['name' => 'Test Confirm Contact', 'type' => 'customer'],
            ]),
            'proposed_at'   => now(),
            'expires_at'    => now()->addHours(24),
            'created_at'    => now(),
            'updated_at'    => now(),
        ]);

        $response = $this->wsPost('/api/ai/confirm-action', ['action_id' => $actionId]);
        $response->assertOk();
        $this->assertEquals('applied', $response->json('data.status'));

        // Contact should exist
        $contact = DB::table('contacts')
            ->where('workspace_id', FoundationSeeder::WORKSPACE_ID)
            ->where('name', 'Test Confirm Contact')
            ->first();
        $this->assertNotNull($contact);

        // Clean up
        DB::table('contacts')->where('id', $contact->id)->delete();
        DB::table('ai_change_requests')->where('id', $actionId)->delete();
    }

    // ═══════════════════════════════════════════════════════════
    // AI07 — Reject action marks rejected
    // ═══════════════════════════════════════════════════════════

    public function test_ai07_reject_action(): void
    {
        $actionId = \Illuminate\Support\Str::uuid()->toString();
        DB::table('ai_change_requests')->insert([
            'id'            => $actionId,
            'workspace_id'  => FoundationSeeder::WORKSPACE_ID,
            'requested_by'  => FoundationSeeder::USER_ID,
            'change_type'   => 'settings',
            'risk_level'    => 'low',
            'status'        => 'proposed',
            'proposed_diff' => json_encode([
                'tool'   => 'draft_contact',
                'params' => ['name' => 'Reject Me', 'type' => 'customer'],
            ]),
            'proposed_at'   => now(),
            'expires_at'    => now()->addHours(24),
            'created_at'    => now(),
            'updated_at'    => now(),
        ]);

        $response = $this->wsPost('/api/ai/reject-action', [
            'action_id' => $actionId,
            'reason'    => 'Not needed',
        ]);

        $response->assertOk();
        $this->assertEquals('rejected', $response->json('data.status'));

        $action = DB::table('ai_change_requests')->where('id', $actionId)->first();
        $this->assertEquals('rejected', $action->status);
        $this->assertEquals('Not needed', $action->review_notes);

        DB::table('ai_change_requests')->where('id', $actionId)->delete();
    }

    // ═══════════════════════════════════════════════════════════
    // AI08 — Conversation continuity
    // ═══════════════════════════════════════════════════════════

    public function test_ai08_conversation_continuity(): void
    {
        $this->fakeLlm->queueTextResponse('First response');

        $r1 = $this->wsPost('/api/ai/chat', ['message' => 'First message']);
        $r1->assertOk();
        $convoId = $r1->json('data.conversation_id');

        $this->fakeLlm->queueTextResponse('Second response with context');

        $r2 = $this->wsPost('/api/ai/chat', [
            'message'         => 'Follow-up question',
            'conversation_id' => $convoId,
        ]);
        $r2->assertOk();
        $this->assertEquals($convoId, $r2->json('data.conversation_id'));
    }

    // ═══════════════════════════════════════════════════════════
    // AI09 — Chat validation
    // ═══════════════════════════════════════════════════════════

    public function test_ai09_chat_validation(): void
    {
        $response = $this->wsPost('/api/ai/chat', []);
        $response->assertStatus(422);
    }

    // ═══════════════════════════════════════════════════════════
    // AI10 — Credits deducted per request
    // ═══════════════════════════════════════════════════════════

    public function test_ai10_credits_deducted(): void
    {
        $before = AiCreditBalance::where('workspace_id', FoundationSeeder::WORKSPACE_ID)->first();
        $usedBefore = $before->used_credits;

        $this->fakeLlm->queueTextResponse('Credit tracking test');
        $this->wsPost('/api/ai/chat', ['message' => 'Test credit deduction']);

        $after = AiCreditBalance::where('workspace_id', FoundationSeeder::WORKSPACE_ID)->first();
        $this->assertGreaterThan($usedBefore, $after->used_credits);
    }

    // ═══════════════════════════════════════════════════════════
    // AI11 — Hard credit limit blocks request
    // ═══════════════════════════════════════════════════════════

    public function test_ai11_hard_limit_blocks(): void
    {
        AiCreditBalance::where('workspace_id', FoundationSeeder::WORKSPACE_ID)->update([
            'included_credits'  => 0,
            'purchased_credits' => 0,
            'bonus_credits'     => 0,
            'trial_credits'     => 0,
            'used_credits'      => 0,
            'hard_limit'        => true,
        ]);

        $response = $this->wsPost('/api/ai/chat', ['message' => 'Should be blocked']);
        $response->assertStatus(429);
        $this->assertEquals('ai_credits_exhausted', $response->json('error'));
    }

    // ═══════════════════════════════════════════════════════════
    // AI12 — History endpoint
    // ═══════════════════════════════════════════════════════════

    public function test_ai12_history_endpoint(): void
    {
        // Create a conversation
        $this->fakeLlm->queueTextResponse('Test history');
        $this->wsPost('/api/ai/chat', ['message' => 'Test history']);

        $response = $this->wsGet('/api/ai/history');
        $response->assertOk();

        $data = $response->json('data');
        $this->assertNotEmpty($data);
        $this->assertEquals('chat', $data[0]['mode']);
        $this->assertNotEmpty($data[0]['messages']);
    }
}
