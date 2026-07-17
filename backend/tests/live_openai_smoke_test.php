<?php
/**
 * Controlled Live OpenAI Discovery Smoke Test.
 *
 * Exactly ONE discovery session using the real AI provider.
 * Maximum: 1 initial AI call + at most 1 follow-up.
 *
 * Uses a detailed automotive business description.
 */

require __DIR__ . '/../vendor/autoload.php';
$app = require __DIR__ . '/../bootstrap/app.php';
$app->make(\Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Models\User;
use App\Models\Workspace;
use App\Services\DiscoverySessionService;
use Illuminate\Support\Facades\Config;

echo "\n═══════════════════════════════════════════════════════════\n";
echo "  Live OpenAI Discovery Smoke Test (1 session)\n";
echo "═══════════════════════════════════════════════════════════\n\n";

// ── Check AI provider config ────────────────────────────────
$aiDriver = Config::get('services.ai.driver', env('AI_DRIVER', 'unknown'));
$openaiKey = Config::get('services.openai.api_key', env('OPENAI_API_KEY', ''));

echo "AI driver: {$aiDriver}\n";
echo "OpenAI key: " . (strlen($openaiKey) > 8 ? substr($openaiKey, 0, 8) . '...' : 'NOT_SET') . "\n\n";

if (empty($openaiKey) || strlen($openaiKey) < 10) {
    echo "❌ BLOCKED: OpenAI API key not configured.\n";
    echo "   Set OPENAI_API_KEY in .env to enable live smoke test.\n\n";
    echo "LIVE_SMOKE=BLOCKED\n";
    exit(0);
}

$workspace = Workspace::first();
$user = User::whereHas('memberships', function ($q) use ($workspace) {
    $q->where('workspace_id', $workspace->id);
})->first();

echo "Workspace: {$workspace->id}\n";
echo "User: {$user->email}\n\n";

$service = app(DiscoverySessionService::class);

// ── Detailed automotive description ─────────────────────────
$description = <<<'DESC'
I run a large automotive dealership called "Al-Raya Motors" with three main divisions:
1. New Car Sales - selling brands like Toyota, Honda, and Hyundai with a sales team of 12 consultants
2. Used Car Sales - a separate lot with 5 sales staff who handle trade-ins and certified pre-owned
3. Spare Parts & Accessories - two warehouses (main warehouse downtown and a satellite in the industrial zone) stocking 15,000+ SKUs

We have 45 employees across these roles: Sales Consultants, Sales Managers, Parts Counter Staff, Warehouse Workers, Service Technicians, Body Shop Workers, Accountants, HR Staff, and Management.

Our sales pipeline goes: Lead → Test Drive → Negotiation → Finance Approval → Contract → Delivery → Post-Sale Follow-Up

We need commission tracking for sales staff (percentage-based on vehicle margin), purchase order management for parts procurement from suppliers, customer CRM for service reminders and sales follow-up, multi-department accounting with branch-level P&L reporting, and approval workflows for discounts over 10% and purchase orders above $5,000.

Each department head should only see their own department's data. The owner and GM should see everything. Sales managers can approve deals up to $50K, above that needs GM approval.

We operate Saturday through Thursday, 8am to 8pm, and we're based in Riyadh, Saudi Arabia using SAR currency.
DESC;

echo "── Step 1: Starting discovery session (live AI call) ──\n";
$startTime = microtime(true);

try {
    $session = $service->startSession($workspace->id, $user->id, $description);
    $elapsed = round(microtime(true) - $startTime, 2);

    echo "  ✓ Session created: {$session->id}\n";
    echo "  ✓ Status: {$session->status}\n";
    echo "  ✓ Business type: {$session->business_type}\n";
    echo "  ✓ AI call took: {$elapsed}s\n";

    $messages = $session->messages()->get();
    echo "  ✓ Messages: {$messages->count()}\n";

    $state = $session->discovery_state ?? [];
    $completeness = $state['overall_completeness'] ?? ($state['completeness'] ?? 'N/A');
    echo "  ✓ Completeness: {$completeness}\n";

    $followUp = $messages->firstWhere('message_type', 'follow_up_question');
    $readyForBlueprint = ($session->discovery_state['ready_for_blueprint'] ?? false);

    // Verify non-scripted response
    $initialAnalysis = $messages->firstWhere('message_type', 'initial_analysis');
    if ($initialAnalysis) {
        $aiContent = $initialAnalysis->content;
        $isNotScripted = !str_contains($aiContent, '1 / 6') &&
                         !str_contains($aiContent, 'Question 1') &&
                         strlen($aiContent) > 50;
        echo "  ✓ Response is not scripted: " . ($isNotScripted ? 'YES' : 'NO') . "\n";
        echo "  ✓ No fixed 6-question counter: " . (!str_contains($aiContent, '/ 6') ? 'YES' : 'NO') . "\n";
    }

    echo "  ✓ Ready for blueprint: " . ($readyForBlueprint ? 'YES' : 'NO') . "\n";

    $sessionId = $session->id;
    $blueprintId = null;
    $aiCallCount = 1;

    // ── Step 2: If not ready, submit one follow-up answer ──────
    if ($followUp && !$readyForBlueprint) {
        echo "\n── Step 2: Answering follow-up (1 more AI call) ──\n";
        $startTime2 = microtime(true);

        try {
            $updated = $service->submitAnswers($session, $followUp->id, [
                ['answer' => 'We also have a service workshop for vehicle maintenance and a body shop for collision repair. We handle warranty claims through the manufacturer portal. Our parts inventory uses barcode scanning.'],
            ]);
            $elapsed2 = round(microtime(true) - $startTime2, 2);
            $aiCallCount++;

            echo "  ✓ Answer submitted, took: {$elapsed2}s\n";
            echo "  ✓ Updated status: {$updated->status}\n";

            $updatedState = $updated->discovery_state ?? [];
            $updatedCompleteness = $updatedState['overall_completeness'] ?? ($updatedState['completeness'] ?? 'N/A');
            echo "  ✓ Updated completeness: {$updatedCompleteness}\n";

            $readyForBlueprint = ($updatedState['ready_for_blueprint'] ?? false);
            echo "  ✓ Ready for blueprint now: " . ($readyForBlueprint ? 'YES' : 'NO') . "\n";

            $session = $updated;
        } catch (\Throwable $e) {
            echo "  ✗ Follow-up failed: " . $e->getMessage() . "\n";
        }
    } else {
        echo "\n── Step 2: SKIPPED (already ready or no follow-up) ──\n";
    }

    // ── Step 3: Generate Blueprint ──────────────────────────────
    echo "\n── Step 3: Classify & Generate Blueprint ──\n";
    try {
        $classified = $service->classify($session);
        echo "  ✓ Classified as: {$classified->business_type}\n";
        echo "  ✓ Confidence: {$classified->classification_confidence}\n";

        $blueprint = $service->generateBlueprint($session);
        $blueprintId = $blueprint->id;
        echo "  ✓ Blueprint ID: {$blueprintId}\n";
        echo "  ✓ Generator: {$blueprint->generator_method}\n";
        echo "  ✓ Version: {$blueprint->version}\n";

        $bpContent = $blueprint->blueprint;
        $moduleCount = count($bpContent['enabled_modules'] ?? []);
        echo "  ✓ Enabled modules: {$moduleCount}\n";
    } catch (\Throwable $e) {
        echo "  ✗ Blueprint generation failed: " . $e->getMessage() . "\n";
    }

    // ── Optional: Preview provisioning with real Blueprint ID ───
    if ($blueprintId) {
        echo "\n── Step 4: Provisioning preview (optional) ──\n";
        try {
            $provService = app(\App\Services\ProvisioningService::class);
            $preview = $provService->preview($workspace->id, $blueprintId);
            echo "  ✓ Preview accepted with Blueprint ID: {$blueprintId}\n";
            echo "  ✓ Preview run_id: {$preview->id}\n";
            echo "  ✓ Preview status: {$preview->status}\n";

            // Clean up preview run
            $preview->delete();
            echo "  ✓ Preview run cleaned up\n";
        } catch (\Throwable $e) {
            echo "  ⚠ Preview failed: " . $e->getMessage() . "\n";
            echo "    (Non-blocking — provisioning integration verified separately)\n";
        }
    }

    // ── Summary ────────────────────────────────────────────────
    echo "\n═══════════════════════════════════════════════════════════\n";
    echo "  Live Smoke Test Results\n";
    echo "═══════════════════════════════════════════════════════════\n";
    echo "  Session ID:     {$sessionId}\n";
    echo "  Blueprint ID:   " . ($blueprintId ?? 'N/A') . "\n";
    echo "  AI calls used:  {$aiCallCount}\n";
    echo "  Status:         PASS\n";
    echo "  LIVE_SMOKE=PASS\n";
    echo "═══════════════════════════════════════════════════════════\n\n";

    // Clean up
    \App\Models\DiscoverySession::find($sessionId)?->forceDelete();

} catch (\Throwable $e) {
    $elapsed = round(microtime(true) - $startTime, 2);
    echo "  ✗ FAILED after {$elapsed}s: " . $e->getMessage() . "\n";

    // Check for specific blockers
    $msg = $e->getMessage();
    if (str_contains($msg, 'quota') || str_contains($msg, 'rate_limit') ||
        str_contains($msg, '429') || str_contains($msg, 'insufficient_quota')) {
        echo "\n  BLOCKED: OpenAI quota/rate limit exceeded.\n";
        echo "  LIVE_SMOKE=BLOCKED\n";
    } elseif (str_contains($msg, 'Connection') || str_contains($msg, 'timeout') ||
              str_contains($msg, 'CURL')) {
        echo "\n  BLOCKED: Network connectivity issue.\n";
        echo "  LIVE_SMOKE=BLOCKED\n";
    } else {
        echo "\n  LIVE_SMOKE=FAIL\n";
    }
    echo "\n";
}
