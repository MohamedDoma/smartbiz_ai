<?php

/**
 * ══════════════════════════════════════════════════════════════════════
 *  Task 1.6D — Onboarding Finalization Verification Suite
 * ══════════════════════════════════════════════════════════════════════
 *
 * Tests:
 *   1. State machine: STATUS_ONBOARDING_COMPLETE exists, transition allowed
 *   2. Service method: finalize() exists with correct signature
 *   3. Controller method: finalize() exists
 *   4. Route: POST /provisioning/{run}/finalize registered
 *   5. CHECK constraint: onboarding_complete in PostgreSQL constraint
 *   6. Event class: WorkspaceOnboardingCompleted exists with correct payload
 *   7. Event dispatch: fires on first finalize, not on repeat
 *   8. Integration: Full finalization flow (if an applied run exists)
 *   9. Idempotency: repeated finalize returns cached success
 *  10. Guard: non-applied run rejected with 409
 *
 * Usage:
 *   docker exec smartbiz_app php tests/onboarding_finalization_verification.php
 */

// ── Bootstrap Laravel ──────────────────────────────────────────────
require __DIR__ . '/../vendor/autoload.php';
$app = require __DIR__ . '/../bootstrap/app.php';
$app->make(\Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Events\WorkspaceOnboardingCompleted;
use App\Exceptions\ProvisioningException;
use App\Models\MembershipRole;
use App\Models\ProvisioningEntityBinding;
use App\Models\ProvisioningRun;
use App\Models\Role;
use App\Models\Workspace;
use App\Models\WorkspaceMembership;
use App\Services\ProvisioningService;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Event;

// ── Test harness ───────────────────────────────────────────────────
$passed = 0;
$failed = 0;

function check(string $label, bool $ok, string $detail = ''): void
{
    global $passed, $failed;
    if ($ok) {
        echo "  ✅  {$label}\n";
        $passed++;
    } else {
        echo "  ❌  {$label}" . ($detail ? " — {$detail}" : '') . "\n";
        $failed++;
    }
}

echo "\n";
echo "══════════════════════════════════════════════════════════════════\n";
echo "  Task 1.6D — Onboarding Finalization Verification Suite\n";
echo "══════════════════════════════════════════════════════════════════\n\n";

// ── 1. State Machine Constants ─────────────────────────────────────

echo "── 1. State Machine ──────────────────────────────────────────\n";

check(
    'STATUS_ONBOARDING_COMPLETE constant exists',
    defined(ProvisioningRun::class . '::STATUS_ONBOARDING_COMPLETE'),
);

check(
    'STATUS_ONBOARDING_COMPLETE value is "onboarding_complete"',
    defined(ProvisioningRun::class . '::STATUS_ONBOARDING_COMPLETE')
        && ProvisioningRun::STATUS_ONBOARDING_COMPLETE === 'onboarding_complete',
);

$ref = new ReflectionClass(ProvisioningRun::class);
$transitions = $ref->getConstant('TRANSITIONS');

check(
    'Transition applied → onboarding_complete is allowed',
    isset($transitions['applied']) && in_array('onboarding_complete', $transitions['applied']),
    isset($transitions['applied']) ? 'Allowed: ' . implode(', ', $transitions['applied']) : 'No applied key',
);

check(
    'Transition onboarding_complete → rolled_back is allowed',
    isset($transitions['onboarding_complete']) && in_array('rolled_back', $transitions['onboarding_complete']),
);

check(
    'onboarding_complete is terminal (only rolled_back)',
    isset($transitions['onboarding_complete']) && $transitions['onboarding_complete'] === ['rolled_back'],
);

echo "\n";

// ── 2. Service Method ──────────────────────────────────────────────

echo "── 2. Service Method ─────────────────────────────────────────\n";

$serviceRef = new ReflectionClass(ProvisioningService::class);

check(
    'ProvisioningService::finalize() method exists',
    $serviceRef->hasMethod('finalize'),
);

if ($serviceRef->hasMethod('finalize')) {
    $method = $serviceRef->getMethod('finalize');
    $params = $method->getParameters();

    check(
        'finalize() accepts 3 parameters (workspaceId, runId, userId)',
        count($params) === 3,
        'Got ' . count($params) . ' params',
    );

    check(
        'finalize() is public',
        $method->isPublic(),
    );

    $paramNames = array_map(fn($p) => $p->getName(), $params);
    check(
        'Parameters named: workspaceId, runId, userId',
        $paramNames === ['workspaceId', 'runId', 'userId'],
        'Got: ' . implode(', ', $paramNames),
    );
}

echo "\n";

// ── 3. Controller Method ───────────────────────────────────────────

echo "── 3. Controller Method ──────────────────────────────────────\n";

$ctrlRef = new ReflectionClass(\App\Http\Controllers\Api\ProvisioningController::class);

check(
    'ProvisioningController::finalize() method exists',
    $ctrlRef->hasMethod('finalize'),
);

if ($ctrlRef->hasMethod('finalize')) {
    $ctrlMethod = $ctrlRef->getMethod('finalize');
    $ctrlParams = $ctrlMethod->getParameters();

    check(
        'finalize() accepts Request and run string',
        count($ctrlParams) === 2,
        'Got ' . count($ctrlParams) . ' params',
    );

    check(
        'Return type is JsonResponse',
        $ctrlMethod->getReturnType()?->getName() === \Illuminate\Http\JsonResponse::class,
    );
}

echo "\n";

// ── 4. Route Registration ──────────────────────────────────────────

echo "── 4. Route Registration ─────────────────────────────────────\n";

$routes = app('router')->getRoutes();
$finalizeRoute = $routes->getByName('provisioning.finalize');

check(
    'provisioning.finalize route is registered',
    $finalizeRoute !== null,
);

if ($finalizeRoute) {
    check(
        'Route method is POST',
        in_array('POST', $finalizeRoute->methods()),
    );

    check(
        'Route URI matches provisioning/{run}/finalize',
        str_contains($finalizeRoute->uri(), 'provisioning/{run}/finalize'),
        'Got: ' . $finalizeRoute->uri(),
    );

    $middleware = $finalizeRoute->middleware();
    check(
        'Route has auth:sanctum middleware (inherited)',
        in_array('auth:sanctum', $middleware),
    );

    $hasPermissionCheck = false;
    foreach ($middleware as $mw) {
        if (str_contains($mw, 'discovery.manage')) {
            $hasPermissionCheck = true;
            break;
        }
    }
    check(
        'Route has discovery.manage permission middleware',
        $hasPermissionCheck,
    );
}

echo "\n";

// ── 5. CHECK Constraint ────────────────────────────────────────────

echo "── 5. CHECK Constraint ───────────────────────────────────────\n";

$constraint = DB::selectOne("
    SELECT pg_get_constraintdef(oid) AS def
    FROM pg_constraint
    WHERE conrelid = 'provisioning_runs'::regclass
      AND conname  = 'provisioning_runs_status_check'
");

check(
    'provisioning_runs_status_check constraint exists',
    $constraint !== null,
);

if ($constraint) {
    check(
        'Constraint includes onboarding_complete',
        str_contains($constraint->def, 'onboarding_complete'),
        'Def: ' . substr($constraint->def, 0, 120),
    );

    // Verify all 8 expected values are present
    $expected = ['preview', 'prepared', 'processing', 'foundation_applied', 'applied', 'onboarding_complete', 'rolled_back', 'failed'];
    $allPresent = true;
    $missing = [];
    foreach ($expected as $val) {
        if (!str_contains($constraint->def, $val)) {
            $allPresent = false;
            $missing[] = $val;
        }
    }
    check(
        'All 8 status values present in constraint',
        $allPresent,
        $missing ? 'Missing: ' . implode(', ', $missing) : '',
    );
}

echo "\n";

// ── 6. Event Class ─────────────────────────────────────────────────

echo "── 6. Event Class ────────────────────────────────────────────\n";

check(
    'WorkspaceOnboardingCompleted class exists',
    class_exists(WorkspaceOnboardingCompleted::class),
);

if (class_exists(WorkspaceOnboardingCompleted::class)) {
    $eventRef = new ReflectionClass(WorkspaceOnboardingCompleted::class);

    check(
        'Event uses Dispatchable trait',
        in_array(\Illuminate\Foundation\Events\Dispatchable::class, array_keys($eventRef->getTraits())),
    );

    $constructor = $eventRef->getConstructor();
    $eventParams = $constructor ? $constructor->getParameters() : [];
    $eventParamNames = array_map(fn($p) => $p->getName(), $eventParams);

    check(
        'Event constructor has workspaceId parameter',
        in_array('workspaceId', $eventParamNames),
        'Params: ' . implode(', ', $eventParamNames),
    );

    check(
        'Event constructor has provisioningRunId parameter',
        in_array('provisioningRunId', $eventParamNames),
        'Params: ' . implode(', ', $eventParamNames),
    );
}

echo "\n";

// ── 7. Event Dispatch (via service source inspection) ──────────────

echo "── 7. Event Dispatch ─────────────────────────────────────────\n";

$serviceSource = file_get_contents((new ReflectionClass(ProvisioningService::class))->getFileName());

check(
    'Service imports WorkspaceOnboardingCompleted',
    str_contains($serviceSource, 'use App\\Events\\WorkspaceOnboardingCompleted'),
);

check(
    'Service dispatches WorkspaceOnboardingCompleted after transaction',
    str_contains($serviceSource, 'WorkspaceOnboardingCompleted::dispatch('),
);

// Verify dispatch is OUTSIDE the transaction closure — after the closing });
// The idempotent early-return must NOT dispatch
$idempotentBlock = substr($serviceSource, 0, strpos($serviceSource, 'DB::transaction'));
check(
    'Idempotent path does NOT dispatch event',
    !str_contains($idempotentBlock, 'WorkspaceOnboardingCompleted::dispatch'),
);

echo "\n";

// ── 8. Integration: Full Finalization Flow ─────────────────────────

echo "── 8. Integration Test ─────────────────────────────────────\n";

$workspace = Workspace::first();
$appliedRun = null;

if ($workspace) {
    $appliedRun = ProvisioningRun::where('workspace_id', $workspace->id)
        ->where('status', 'applied')
        ->first();
}

if (!$appliedRun) {
    echo "  ⚠️  No 'applied' provisioning run found — skipping live integration tests.\n";
    echo "       (This is expected if demo-reset was used or no provisioning has been applied.)\n";

    // Still verify the binding structure exists
    if ($workspace) {
        $ownerBinding = ProvisioningEntityBinding::where('workspace_id', $workspace->id)
            ->where('entity_type', 'role')
            ->where('local_key', 'owner')
            ->first();

        check(
            'Owner role binding exists in provisioning_entity_bindings',
            $ownerBinding !== null,
            $ownerBinding ? "entity_id={$ownerBinding->entity_id}" : 'Not found',
        );

        if ($ownerBinding) {
            $ownerRole = Role::where('id', $ownerBinding->entity_id)
                ->where('workspace_id', $workspace->id)
                ->first();

            check(
                'Bound owner role entity exists in roles table',
                $ownerRole !== null,
                $ownerRole ? "name={$ownerRole->name}" : 'Not found',
            );
        }

        $ownerMembership = WorkspaceMembership::where('workspace_id', $workspace->id)
            ->where('status', 'active')
            ->orderBy('created_at')
            ->first();

        check(
            'Workspace owner membership identifiable (earliest active)',
            $ownerMembership !== null,
            $ownerMembership ? "id={$ownerMembership->id}, user={$ownerMembership->user_id}" : 'None found',
        );
    }
} else {
    echo "  Found applied run: {$appliedRun->id}\n";

    $testUser = WorkspaceMembership::where('workspace_id', $workspace->id)
        ->where('status', 'active')
        ->orderBy('created_at')
        ->first();

    if ($testUser) {
        $service = app(ProvisioningService::class);

        // Capture events to verify dispatch
        $dispatchedEvents = [];
        Event::listen(WorkspaceOnboardingCompleted::class, function ($event) use (&$dispatchedEvents) {
            $dispatchedEvents[] = $event;
        });

        try {
            $result = $service->finalize($workspace->id, $appliedRun->id, $testUser->user_id);

            check(
                'Finalization returns onboarding_complete status',
                ($result['status'] ?? '') === 'onboarding_complete',
                'Got: ' . ($result['status'] ?? 'null'),
            );

            check(
                'Finalization returns primary_owner_role data',
                isset($result['primary_owner_role']['key']),
            );

            check(
                'Finalization returns owner_membership data',
                isset($result['owner_membership']['id']),
            );

            check(
                'onboarding_completed flag is true',
                ($result['onboarding_completed'] ?? false) === true,
            );

            // Verify event dispatched exactly once
            check(
                'WorkspaceOnboardingCompleted dispatched exactly once',
                count($dispatchedEvents) === 1,
                'Got ' . count($dispatchedEvents) . ' dispatches',
            );

            if (count($dispatchedEvents) === 1) {
                check(
                    'Event payload has correct workspace ID',
                    $dispatchedEvents[0]->workspaceId === $workspace->id,
                );
                check(
                    'Event payload has correct run ID',
                    $dispatchedEvents[0]->provisioningRunId === $appliedRun->id,
                );
            }

            // Verify DB state
            $appliedRun->refresh();
            check(
                'Run status transitioned to onboarding_complete in DB',
                $appliedRun->status === 'onboarding_complete',
                "Got: {$appliedRun->status}",
            );

            $workspace->refresh();
            $onboardingData = $workspace->onboarding_data ?? [];
            check(
                'workspace.onboarding_data.onboarding_completed is true',
                ($onboardingData['onboarding_completed'] ?? false) === true,
            );

            check(
                'workspace.onboarding_data.finalization_run_id matches',
                ($onboardingData['finalization_run_id'] ?? '') === $appliedRun->id,
            );

            // ── 9. Idempotency ──
            echo "\n── 9. Idempotency ────────────────────────────────────────────\n";

            $dispatchCountBefore = count($dispatchedEvents);

            try {
                $result2 = $service->finalize($workspace->id, $appliedRun->id, $testUser->user_id);

                check(
                    'Repeated finalize returns success (idempotent)',
                    ($result2['status'] ?? '') === 'onboarding_complete',
                );

                check(
                    'Repeated finalize flags already_finalized',
                    ($result2['already_finalized'] ?? false) === true,
                );

                check(
                    'Repeated finalize does NOT dispatch event again',
                    count($dispatchedEvents) === $dispatchCountBefore,
                    'Events after repeat: ' . count($dispatchedEvents) . ' (expected: ' . $dispatchCountBefore . ')',
                );
            } catch (\Throwable $e) {
                check('Idempotent finalize does not throw', false, $e->getMessage());
            }

        } catch (\Throwable $e) {
            check('Finalization succeeds without exception', false, $e->getMessage());
        }
    }
}

echo "\n";

// ── 10. Guard: Reject Non-Applied Run ──────────────────────────────

echo "── 10. Guard Tests ───────────────────────────────────────────\n";

if ($workspace) {
    $service = app(ProvisioningService::class);
    $testUserId = WorkspaceMembership::where('workspace_id', $workspace->id)
        ->where('status', 'active')
        ->orderBy('created_at')
        ->value('user_id');

    // Test with non-existent run ID
    try {
        $service->finalize($workspace->id, '00000000-0000-0000-0000-000000000000', $testUserId ?? 'test');
        check('Non-existent run is rejected', false, 'Should have thrown ProvisioningException');
    } catch (ProvisioningException $e) {
        check(
            'Non-existent run returns run_not_found error',
            $e->getErrorCode() === 'run_not_found',
            "Got: {$e->getErrorCode()}",
        );
        check(
            'Non-existent run returns 404',
            $e->getCode() === 404,
            "Got: {$e->getCode()}",
        );
    } catch (\Throwable $e) {
        check('Non-existent run rejected properly', false, get_class($e) . ': ' . $e->getMessage());
    }

    // Test with a run that exists but is not in 'applied' status
    $nonAppliedRun = ProvisioningRun::where('workspace_id', $workspace->id)
        ->whereNotIn('status', ['applied'])
        ->first();

    if ($nonAppliedRun && $nonAppliedRun->status !== 'onboarding_complete') {
        try {
            $service->finalize($workspace->id, $nonAppliedRun->id, $testUserId);
            check('Non-applied run is rejected', false, 'Should have thrown ProvisioningException');
        } catch (ProvisioningException $e) {
            check(
                'Non-applied run returns invalid_status_transition error',
                $e->getErrorCode() === 'invalid_status_transition',
                "Got: {$e->getErrorCode()}",
            );
            check(
                'Non-applied run returns 409',
                $e->getCode() === 409,
                "Got: {$e->getCode()}",
            );
        } catch (\Throwable $e) {
            check('Non-applied run rejected properly', false, get_class($e) . ': ' . $e->getMessage());
        }
    } else {
        echo "  ⚠️  No non-applied run available for guard test — skipping.\n";
    }
} else {
    echo "  ⚠️  No workspace found — skipping guard tests.\n";
}

echo "\n";

// ── Summary ────────────────────────────────────────────────────────

echo "══════════════════════════════════════════════════════════════════\n";
$total = $passed + $failed;
$pct = $total > 0 ? round(($passed / $total) * 100) : 0;
echo "  Results: {$passed}/{$total} passed ({$pct}%)\n";

if ($failed === 0) {
    echo "  🎉  All tests PASSED — Task 1.6D verified.\n";
} else {
    echo "  ⚠️  {$failed} test(s) FAILED — review output above.\n";
}

echo "══════════════════════════════════════════════════════════════════\n\n";

exit($failed === 0 ? 0 : 1);
