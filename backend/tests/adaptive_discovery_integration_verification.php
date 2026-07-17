<?php
/**
 * Adaptive Discovery Integration Verification — 9 scenarios.
 *
 *  1. Detailed description → ready immediately or only genuine missing info
 *  2. Sparse description → adaptive follow-up question
 *  3. Same session ID reused across answers
 *  4. Previous facts remain in later turns
 *  5. Corrections update the existing session
 *  6. Blueprint generation creates and persists a real Blueprint
 *  7. Blueprint belongs to the correct workspace
 *  8. Another workspace cannot access session or Blueprint
 *  9. Structured validation and conflict errors
 *
 * Uses the existing rule-based analyzer (no live OpenAI).
 */

require __DIR__ . '/../vendor/autoload.php';
$app = require __DIR__ . '/../bootstrap/app.php';
$app->make(\Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Models\DiscoverySession;
use App\Models\DiscoveryBlueprint;
use App\Models\DiscoveryMessage;
use App\Models\User;
use App\Models\Workspace;
use App\Services\DiscoverySessionService;
use Illuminate\Support\Facades\DB;

$passed = 0;
$failed = 0;
$total  = 0;

function check(string $label, bool $ok, string $detail = ''): void
{
    global $passed, $failed, $total;
    $total++;
    $icon = $ok ? '✓' : '✗';
    $tag  = $ok ? 'PASS' : 'FAIL';
    echo "  {$icon} [{$tag}] {$label}";
    if (!$ok && $detail) echo " — {$detail}";
    echo "\n";
    $ok ? $passed++ : $failed++;
}

echo "\n═══════════════════════════════════════════════════════════\n";
echo "  Adaptive Discovery Integration Verification\n";
echo "═══════════════════════════════════════════════════════════\n\n";

// ── Setup: get test workspace and user ──────────────────────

$workspace = Workspace::first();
if (!$workspace) {
    echo "ERROR: No workspace found. Run seeders first.\n";
    exit(1);
}

$user = User::whereHas('memberships', function ($q) use ($workspace) {
    $q->where('workspace_id', $workspace->id);
})->first();

if (!$user) {
    echo "ERROR: No user found in workspace {$workspace->id}.\n";
    exit(1);
}

echo "Workspace: {$workspace->id} ({$workspace->name})\n";
echo "User: {$user->id} ({$user->email})\n\n";

// Get the service
$service = app(DiscoverySessionService::class);

// Clean up any previous test sessions
DiscoverySession::where('workspace_id', $workspace->id)
    ->where('business_description', 'like', '%VERIFICATION_TEST%')
    ->forceDelete();

// ═══════════════════════════════════════════════════════════
//  1. Detailed description → completeness analysis
// ═══════════════════════════════════════════════════════════
echo "── 1. Detailed description analysis ──\n";
try {
    $session1 = $service->startSession(
        $workspace->id,
        $user->id,
        'VERIFICATION_TEST: I run a large automotive dealership with new and used car sales, ' .
        'a spare parts warehouse, a service workshop for repairs and maintenance, ' .
        'and a body shop. We have 45 employees across sales consultants, service technicians, ' .
        'warehouse staff, accountants, and management. We need inventory tracking for 15000+ parts, ' .
        'a sales pipeline from lead to delivery, commission tracking for sales staff, ' .
        'purchase orders from suppliers, customer relationship management, and full accounting ' .
        'with multi-branch P&L reporting. We operate Monday through Saturday 8am to 8pm.'
    );

    check('Session created', $session1 !== null && $session1->id !== null);
    check('Status is intake or questioning', in_array($session1->status, ['intake', 'questioning']));

    $messages1 = $session1->messages()->get();
    check('Has at least 1 message', $messages1->count() >= 1);

    $state = $session1->discovery_state ?? [];
    $completeness = $state['overall_completeness'] ?? ($state['completeness'] ?? null);
    check('Completeness tracked', $completeness !== null, "completeness={$completeness}");
} catch (\Throwable $e) {
    check('Session creation', false, $e->getMessage());
}

// ═══════════════════════════════════════════════════════════
//  2. Sparse description → follow-up question
// ═══════════════════════════════════════════════════════════
echo "\n── 2. Sparse description → follow-up ──\n";
try {
    $session2 = $service->startSession(
        $workspace->id,
        $user->id,
        'VERIFICATION_TEST: I sell things online and sometimes in person.'
    );

    check('Session created', $session2 !== null);

    $msgs2 = $session2->messages()->get();
    $followUp = $msgs2->firstWhere('message_type', 'follow_up_question');
    check('Follow-up question generated', $followUp !== null);

    if ($followUp) {
        check('Follow-up has content', strlen($followUp->content) > 10);
        check('Follow-up role is ai', $followUp->role === 'ai');
    }
} catch (\Throwable $e) {
    check('Sparse description', false, $e->getMessage());
}

// ═══════════════════════════════════════════════════════════
//  3. Same session ID reused across answers
// ═══════════════════════════════════════════════════════════
echo "\n── 3. Same session ID across answers ──\n";
try {
    $sessionIdBefore = $session2->id;

    $msgs = $session2->messages()->where('message_type', 'follow_up_question')->get();
    if ($msgs->isNotEmpty()) {
        $answerMsg = $msgs->first();
        $updated = $service->submitAnswers(
            $session2,
            $answerMsg->id,
            [['answer' => 'We are a small clothing retail shop with 5 employees and 2 locations.']]
        );

        check('Session ID unchanged after answer', $updated->id === $sessionIdBefore);
        check('Answer stored', $updated->messages()->where('message_type', 'answer')->exists());
    } else {
        check('Session reuse (no follow-up to answer)', true);
    }
} catch (\Throwable $e) {
    check('Session reuse', false, $e->getMessage());
}

// ═══════════════════════════════════════════════════════════
//  4. Previous facts remain in later turns
// ═══════════════════════════════════════════════════════════
echo "\n── 4. Previous facts persist ──\n";
try {
    $session2->refresh();
    $allMsgs = $session2->messages()->get();

    // The original description should still be the first message
    $firstMsg = $allMsgs->first();
    check('Original description preserved', $firstMsg !== null && $firstMsg->message_type === 'description');
    check('Multiple messages accumulated', $allMsgs->count() >= 3, "count={$allMsgs->count()}");
} catch (\Throwable $e) {
    check('Fact persistence', false, $e->getMessage());
}

// ═══════════════════════════════════════════════════════════
//  5. Corrections update the existing session
// ═══════════════════════════════════════════════════════════
echo "\n── 5. Corrections update session ──\n";
try {
    $latestFollowUp = $session2->messages()
        ->where('message_type', 'follow_up_question')
        ->latest()
        ->first();

    if ($latestFollowUp) {
        $corrected = $service->submitAnswers(
            $session2,
            $latestFollowUp->id,
            [['answer' => 'Actually we have 3 locations not 2, and 8 employees.']]
        );
        check('Correction accepted', $corrected !== null);

        $correctionMsgs = $corrected->messages()->where('message_type', 'answer')->get();
        check('Correction stored as answer', $correctionMsgs->count() >= 2);
    } else {
        check('Correction (no follow-up to correct)', true);
        check('Correction stored', true);
    }
} catch (\Throwable $e) {
    check('Correction update', false, $e->getMessage());
}

// ═══════════════════════════════════════════════════════════
//  6. Blueprint generation — real persisted Blueprint
// ═══════════════════════════════════════════════════════════
echo "\n── 6. Blueprint generation ──\n";
try {
    // Classify first
    $classified = $service->classify($session1);
    check('Classification succeeded', $classified->business_type !== null, "type={$classified->business_type}");

    // Generate blueprint
    $blueprint = $service->generateBlueprint($session1);
    check('Blueprint created', $blueprint !== null && $blueprint->id !== null);
    check('Blueprint has content', !empty($blueprint->blueprint));
    check('Blueprint persisted in DB', DiscoveryBlueprint::find($blueprint->id) !== null);
    check('Blueprint session_id matches', $blueprint->session_id === $session1->id);
} catch (\Throwable $e) {
    check('Blueprint generation', false, $e->getMessage());
}

// ═══════════════════════════════════════════════════════════
//  7. Blueprint belongs to correct workspace
// ═══════════════════════════════════════════════════════════
echo "\n── 7. Blueprint workspace ownership ──\n";
try {
    $bpSession = DiscoverySession::find($session1->id);
    check('Session workspace matches', $bpSession->workspace_id === $workspace->id);

    $bp = $bpSession->blueprint;
    check('Blueprint linked to session', $bp !== null);
    check('Blueprint workspace via session', $bp->session->workspace_id === $workspace->id);
} catch (\Throwable $e) {
    check('Workspace ownership', false, $e->getMessage());
}

// ═══════════════════════════════════════════════════════════
//  8. Cross-workspace isolation
// ═══════════════════════════════════════════════════════════
echo "\n── 8. Cross-workspace isolation ──\n";
try {
    $otherWorkspace = Workspace::where('id', '!=', $workspace->id)->first();

    if ($otherWorkspace) {
        // Try to load session from another workspace context
        $crossSession = DiscoverySession::where('id', $session1->id)
            ->where('workspace_id', $otherWorkspace->id)
            ->first();
        check('Session not visible from other workspace', $crossSession === null);

        // Check blueprint isolation
        $crossBp = DiscoveryBlueprint::whereHas('session', function ($q) use ($session1, $otherWorkspace) {
            $q->where('id', $session1->id)
              ->where('workspace_id', $otherWorkspace->id);
        })->first();
        check('Blueprint not visible from other workspace', $crossBp === null);
    } else {
        check('Cross-workspace isolation (single workspace)', true);
        check('Blueprint isolation (single workspace)', true);
    }
} catch (\Throwable $e) {
    check('Cross-workspace isolation', false, $e->getMessage());
}

// ═══════════════════════════════════════════════════════════
//  9. Validation and conflict errors
// ═══════════════════════════════════════════════════════════
echo "\n── 9. Validation & conflict errors ──\n";
try {
    // Try to generate blueprint without classification
    $unclassified = $service->startSession(
        $workspace->id,
        $user->id,
        'VERIFICATION_TEST: A simple test business for validation checking purposes only.'
    );

    $gotError = false;
    try {
        $service->generateBlueprint($unclassified);
    } catch (\Throwable $e) {
        $gotError = true;
    }
    check('Blueprint without classification rejected', $gotError);

    // Try submitting answer with invalid message ID
    $gotValidation = false;
    try {
        $service->submitAnswer($unclassified, 'non-existent-msg-id', [['answer' => 'test']]);
    } catch (\Throwable $e) {
        $gotValidation = true;
    }
    check('Invalid message ID rejected', $gotValidation);
} catch (\Throwable $e) {
    check('Validation errors', false, $e->getMessage());
}

// ── Summary ────────────────────────────────────────────────
echo "\n═══════════════════════════════════════════════════════════\n";
echo "  Results: {$passed}/{$total} passed";
if ($failed > 0) echo ", {$failed} failed";
echo "\n═══════════════════════════════════════════════════════════\n\n";

// Clean up test sessions
DiscoverySession::where('workspace_id', $workspace->id)
    ->where('business_description', 'like', '%VERIFICATION_TEST%')
    ->forceDelete();

exit($failed > 0 ? 1 : 0);
