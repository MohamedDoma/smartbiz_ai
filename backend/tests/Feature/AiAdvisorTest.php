<?php

namespace Tests\Feature;

use App\Services\Ai\AiAdvisorService;
use App\Services\Ai\Analyzers\CashFlowRiskAnalyzer;
use App\Services\Ai\Analyzers\InventoryShortageAnalyzer;
use App\Services\Ai\Analyzers\ModuleSuggestionAnalyzer;
use App\Services\Ai\Analyzers\OverdueInvoiceAnalyzer;
use App\Services\Ai\Analyzers\RevenueGrowthAnalyzer;
use Database\Seeders\FoundationSeeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * AI Advisor Tests (ADV01–ADV10).
 */
class AiAdvisorTest extends SmartBizTestCase
{
    protected function setUp(): void
    {
        parent::setUp();

        // Clean recommendations
        DB::table('ai_recommendations')->where('workspace_id', FoundationSeeder::WORKSPACE_ID)->delete();

        // Set RLS context for direct DB queries in tests
        DB::statement("SET LOCAL app.workspace_id = '" . FoundationSeeder::WORKSPACE_ID . "'");
    }

    // ═══════════════════════════════════════════════════════════
    // ADV01 — Run analysis generates recommendations
    // ═══════════════════════════════════════════════════════════

    public function test_adv01_run_analysis_generates_recommendations(): void
    {
        // Seed data that will trigger analyzers
        $this->seedOverdueInvoice();
        $this->seedLowStockProduct();

        $advisor = $this->app->make(AiAdvisorService::class);
        $recs    = $advisor->runAnalysis(FoundationSeeder::WORKSPACE_ID);

        $this->assertNotEmpty($recs);

        // Verify stored in DB
        $dbCount = DB::table('ai_recommendations')
            ->where('workspace_id', FoundationSeeder::WORKSPACE_ID)
            ->count();

        $this->assertEquals(count($recs), $dbCount);

        // Each recommendation must have explainability
        foreach ($recs as $rec) {
            $this->assertNotEmpty($rec['reasoning']);
            $this->assertNotEmpty($rec['data_triggers']);
            $this->assertNotEmpty($rec['analyzer']);
        }
    }

    // ═══════════════════════════════════════════════════════════
    // ADV02 — Overdue invoice analyzer
    // ═══════════════════════════════════════════════════════════

    public function test_adv02_overdue_invoice_analyzer(): void
    {
        $this->seedOverdueInvoice();

        $analyzer = new OverdueInvoiceAnalyzer();
        $recs     = $analyzer->analyze(FoundationSeeder::WORKSPACE_ID);

        $this->assertNotEmpty($recs);
        $this->assertEquals('operational', $recs[0]['category']);
        $this->assertStringContainsString('overdue', $recs[0]['title']);
        $this->assertNotEmpty($recs[0]['reasoning']);
        $this->assertEquals('send_reminders', $recs[0]['action_type']);
    }

    // ═══════════════════════════════════════════════════════════
    // ADV03 — Inventory shortage analyzer
    // ═══════════════════════════════════════════════════════════

    public function test_adv03_inventory_shortage_analyzer(): void
    {
        $this->seedLowStockProduct();

        $analyzer = new InventoryShortageAnalyzer();
        $recs     = $analyzer->analyze(FoundationSeeder::WORKSPACE_ID);

        $this->assertNotEmpty($recs);
        $this->assertEquals('operational', $recs[0]['category']);
        $this->assertStringContainsString('stock', $recs[0]['title']);
        $this->assertNotEmpty($recs[0]['expected_impact']);
    }

    // ═══════════════════════════════════════════════════════════
    // ADV04 — Revenue growth analyzer
    // ═══════════════════════════════════════════════════════════

    public function test_adv04_revenue_growth_analyzer(): void
    {
        // Clean existing invoices to avoid pollution from other test data
        DB::table('invoices')->where('workspace_id', FoundationSeeder::WORKSPACE_ID)->delete();

        // Seed larger contrast: 5000 previous vs 100 current = -98%
        $contactId = $this->seedContact('Revenue Test Customer');

        for ($i = 0; $i < 5; $i++) {
            $this->seedInvoice($contactId, 1000.00, now()->subDays(45), 'sale');
        }
        $this->seedInvoice($contactId, 100.00, now()->subDays(5), 'sale');

        $analyzer = new RevenueGrowthAnalyzer();
        $recs     = $analyzer->analyze(FoundationSeeder::WORKSPACE_ID);

        // Revenue dropped from 5000 to 100 = -98%, should trigger
        $this->assertNotEmpty($recs);
        $this->assertEquals('optimization', $recs[0]['category']);
        $this->assertStringContainsString('declined', $recs[0]['title']);
    }

    // ═══════════════════════════════════════════════════════════
    // ADV05 — Module suggestion analyzer
    // ═══════════════════════════════════════════════════════════

    public function test_adv05_module_suggestion_analyzer(): void
    {
        // Ensure product exists but inventory module not enabled
        $this->seedLowStockProduct();

        // Clear workspace config
        DB::table('workspace_configurations')
            ->updateOrInsert(
                ['workspace_id' => FoundationSeeder::WORKSPACE_ID],
                ['enabled_modules' => json_encode(['sales', 'contacts']), 'role_configs' => json_encode([]), 'pages' => json_encode([]), 'workflows' => json_encode([]), 'automations' => json_encode([])],
            );

        $analyzer = new ModuleSuggestionAnalyzer();
        $recs     = $analyzer->analyze(FoundationSeeder::WORKSPACE_ID);

        $this->assertNotEmpty($recs);
        $this->assertEquals('erp', $recs[0]['category']);
        $this->assertEquals('enable_module', $recs[0]['action_type']);
    }

    // ═══════════════════════════════════════════════════════════
    // ADV06 — Cash flow risk analyzer
    // ═══════════════════════════════════════════════════════════

    public function test_adv06_cash_flow_risk_analyzer(): void
    {
        // Clean any existing invoices to avoid pollution
        DB::table('invoices')->where('workspace_id', FoundationSeeder::WORKSPACE_ID)->delete();

        $contactId = $this->seedContact('Cash Flow Test');

        // High payables, low receivables
        $this->seedInvoice($contactId, 100.00, now()->subDays(5), 'sale');    // receivable
        $this->seedInvoice($contactId, 5000.00, now()->subDays(5), 'purchase'); // payable

        $analyzer = new CashFlowRiskAnalyzer();
        $recs     = $analyzer->analyze(FoundationSeeder::WORKSPACE_ID);

        $this->assertNotEmpty($recs);
        $this->assertEquals('risk', $recs[0]['category']);
        $this->assertStringContainsString('payables', $recs[0]['title']);
    }

    // ═══════════════════════════════════════════════════════════
    // ADV07 — Accept + reject lifecycle
    // ═══════════════════════════════════════════════════════════

    public function test_adv07_accept_reject_lifecycle(): void
    {
        $id1 = $this->seedRecommendation('pending');
        $id2 = $this->seedRecommendation('pending');

        $advisor = $this->app->make(AiAdvisorService::class);

        // Accept
        $this->assertTrue($advisor->accept($id1, FoundationSeeder::WORKSPACE_ID));
        $rec1 = DB::table('ai_recommendations')->where('id', $id1)->first();
        $this->assertEquals('accepted', $rec1->status);

        // Reject
        $this->assertTrue($advisor->reject($id2, FoundationSeeder::WORKSPACE_ID, 'Not relevant'));
        $rec2 = DB::table('ai_recommendations')->where('id', $id2)->first();
        $this->assertEquals('rejected', $rec2->status);
        $this->assertEquals('Not relevant', $rec2->rejected_reason);

        // Cannot accept already accepted
        $this->assertFalse($advisor->accept($id1, FoundationSeeder::WORKSPACE_ID));
    }

    // ═══════════════════════════════════════════════════════════
    // ADV08 — Apply ERP recommendation (module enablement)
    // ═══════════════════════════════════════════════════════════

    public function test_adv08_apply_erp_recommendation(): void
    {
        // Prepare workspace config without inventory
        DB::table('workspace_configurations')
            ->updateOrInsert(
                ['workspace_id' => FoundationSeeder::WORKSPACE_ID],
                ['enabled_modules' => json_encode(['sales']), 'role_configs' => json_encode([]), 'pages' => json_encode([]), 'workflows' => json_encode([]), 'automations' => json_encode([])],
            );

        $id = $this->seedRecommendation('pending', 'enable_module', ['module' => 'inventory']);

        $advisor = $this->app->make(AiAdvisorService::class);
        $result  = $advisor->apply($id, FoundationSeeder::WORKSPACE_ID, FoundationSeeder::USER_ID);

        $this->assertEquals('module_enabled', $result['applied']);
        $this->assertEquals('inventory', $result['module']);

        // Verify module now enabled
        $config = DB::table('workspace_configurations')
            ->where('workspace_id', FoundationSeeder::WORKSPACE_ID)
            ->first();

        $modules = is_string($config->enabled_modules) ? json_decode($config->enabled_modules, true) : $config->enabled_modules;
        $this->assertContains('inventory', $modules);

        // Verify recommendation status
        $rec = DB::table('ai_recommendations')->where('id', $id)->first();
        $this->assertEquals('applied', $rec->status);
        $this->assertNotNull($rec->applied_at);
    }

    // ═══════════════════════════════════════════════════════════
    // ADV09 — Scheduler command runs for all workspaces
    // ═══════════════════════════════════════════════════════════

    public function test_adv09_scheduler_command_runs(): void
    {
        $this->seedOverdueInvoice();

        // Ensure workspace has an active subscription for the scheduler
        DB::table('workspace_subscriptions')->updateOrInsert(
            ['workspace_id' => FoundationSeeder::WORKSPACE_ID],
            [
                'plan_id' => 'a0000000-0000-0000-0000-000000000001',
                'plan_price_id' => 'b0000000-0000-0000-0000-000000000001',
                'status' => 'active',
                'billing_cycle' => 'monthly',
                'current_period_start' => now(),
                'current_period_end' => now()->addMonth(),
            ],
        );

        $this->artisan('ai:run-advisor')
            ->assertExitCode(0);

        $count = DB::table('ai_recommendations')
            ->where('workspace_id', FoundationSeeder::WORKSPACE_ID)
            ->count();

        $this->assertGreaterThanOrEqual(1, $count);
    }

    // ═══════════════════════════════════════════════════════════
    // ADV10 — High impact creates notification
    // ═══════════════════════════════════════════════════════════

    public function test_adv10_high_impact_notification(): void
    {
        // Seed data triggering high-impact (many overdue invoices)
        $contactId = $this->seedContact('Notification Test');
        for ($i = 0; $i < 5; $i++) {
            $this->seedOverdueInvoice($contactId, 2000 + $i * 100);
        }

        // Clear old notifications
        DB::table('notifications')
            ->where('workspace_id', FoundationSeeder::WORKSPACE_ID)
            ->where('title', 'LIKE', '%AI Recommendation%')
            ->delete();

        $advisor = $this->app->make(AiAdvisorService::class);
        $recs    = $advisor->runAnalysis(FoundationSeeder::WORKSPACE_ID);

        $highImpact = array_filter($recs, fn ($r) => ($r['impact_level'] ?? '') === 'high');

        if (count($highImpact) > 0) {
            $notifCount = DB::table('notifications')
                ->where('workspace_id', FoundationSeeder::WORKSPACE_ID)
                ->where('title', 'LIKE', '%AI Recommendation%')
                ->count();

            $this->assertGreaterThanOrEqual(1, $notifCount);
        }

        $this->assertNotEmpty($recs);
    }

    // ── Helpers ─────────────────────────────────────────────────

    private function seedContact(string $name = 'Test Contact'): string
    {
        $id = Str::uuid()->toString();
        DB::table('contacts')->insert([
            'id'           => $id,
            'workspace_id' => FoundationSeeder::WORKSPACE_ID,
            'name'         => $name,
            'email'        => strtolower(str_replace(' ', '', $name)) . '@test.com',
            'type'         => 'customer',
            'created_at'   => now(),
            'updated_at'   => now(),
        ]);
        return $id;
    }

    private function seedInvoice(string $contactId, float $amount, $date = null, string $type = 'sale'): string
    {
        $id = Str::uuid()->toString();
        DB::table('invoices')->insert([
            'id'             => $id,
            'workspace_id'   => FoundationSeeder::WORKSPACE_ID,
            'contact_id'     => $contactId,
            'invoice_type'   => $type,
            'invoice_number' => 'ADV-' . substr($id, 0, 8),
            'total_amount'   => $amount,
            'net_amount'     => $amount,
            'tax_amount'     => 0,
            'payment_status' => 'unpaid',
            'due_date'       => ($date ?? now())->subDays(5)->toDateString(),
            'created_at'     => $date ?? now(),
            'updated_at'     => now(),
        ]);
        return $id;
    }

    private function seedOverdueInvoice(?string $contactId = null, float $amount = 1500): void
    {
        $contactId = $contactId ?? $this->seedContact('Overdue Customer');
        DB::table('invoices')->insert([
            'id'             => Str::uuid()->toString(),
            'workspace_id'   => FoundationSeeder::WORKSPACE_ID,
            'contact_id'     => $contactId,
            'invoice_type'   => 'sale',
            'invoice_number' => 'ADV-OD-' . Str::random(6),
            'total_amount'   => $amount,
            'net_amount'     => $amount,
            'tax_amount'     => 0,
            'payment_status' => 'unpaid',
            'due_date'       => now()->subDays(20)->toDateString(),
            'created_at'     => now()->subDays(30),
            'updated_at'     => now(),
        ]);
    }

    private function seedLowStockProduct(): void
    {
        $productId = Str::uuid()->toString();
        DB::table('products')->insert([
            'id'             => $productId,
            'workspace_id'   => FoundationSeeder::WORKSPACE_ID,
            'name'           => 'Low Stock Widget ' . Str::random(4),
            'sku'            => 'LSW-' . Str::random(6),
            'base_price'     => 25.00,
            'type'           => 'physical',
            'is_deleted'     => false,
            'min_stock_alert' => 10,
            'created_at'     => now(),
            'updated_at'     => now(),
        ]);

        // Check if warehouse exists, create if needed
        $warehouseId = DB::table('warehouses')
            ->where('workspace_id', FoundationSeeder::WORKSPACE_ID)
            ->value('id');

        if (!$warehouseId) {
            $warehouseId = Str::uuid()->toString();
            DB::table('warehouses')->insert([
                'id'           => $warehouseId,
                'workspace_id' => FoundationSeeder::WORKSPACE_ID,
                'name'         => 'Test Warehouse',
                'created_at'   => now(),
                'updated_at'   => now(),
            ]);
        }

        DB::table('inventory_levels')->insert([
            'id'           => Str::uuid()->toString(),
            'workspace_id' => FoundationSeeder::WORKSPACE_ID,
            'product_id'   => $productId,
            'warehouse_id' => $warehouseId,
            'quantity'      => 2,
        ]);
    }

    private function seedRecommendation(string $status = 'pending', ?string $actionType = null, ?array $actionPayload = null): string
    {
        $id = Str::uuid()->toString();
        DB::table('ai_recommendations')->insert([
            'id'               => $id,
            'workspace_id'     => FoundationSeeder::WORKSPACE_ID,
            'category'         => 'erp',
            'title'            => 'Test Recommendation',
            'description'      => 'Test description',
            'impact_level'     => 'medium',
            'confidence_score' => 80,
            'status'           => $status,
            'reasoning'        => 'Test reasoning',
            'data_triggers'    => json_encode(['test' => true]),
            'action_type'      => $actionType,
            'action_payload'   => json_encode($actionPayload ?? []),
            'analyzer'         => 'TestAnalyzer',
            'created_at'       => now(),
            'updated_at'       => now(),
        ]);
        return $id;
    }
}
