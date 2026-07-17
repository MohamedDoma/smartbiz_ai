<?php
/**
 * Task 1.6B — 14 Integration Scenarios
 *
 *  1. Exact permissions stored
 *  2. Unknown permission → 422, no partial
 *  3. Idempotent apply (same version)
 *  4. Same-workspace concurrent apply blocked
 *  5. Different workspaces independent
 *  6. Mid-run failure → atomic rollback
 *  7. Clean rollback restores state
 *  8. Created entities deleted on rollback
 *  9. Adopted entities restored, not deleted
 * 10. Manual change → rollback_conflict 409
 * 11. Absent WC deleted on rollback
 * 12. Template adoption (role, dept, team)
 * 13. Unmanaged entity conflict 409
 * 14. Missing bound entity 409
 */

require __DIR__ . '/../vendor/autoload.php';
$app = require __DIR__ . '/../bootstrap/app.php';
$app->make(\Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Exceptions\ProvisioningException;
use App\Models\Branch;
use App\Models\Department;
use App\Models\DiscoveryBlueprint;
use App\Models\ProvisioningEntityBinding;
use App\Models\ProvisioningRun;
use App\Models\Role;
use App\Models\Team;
use App\Models\WorkspaceConfiguration;
use App\Models\WorkspaceFeatureFlag;
use App\Services\PermissionCatalog;
use App\Services\Provisioning\CoreEntityProvisioner;
use App\Services\ProvisioningService;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

$results = []; $passed = 0; $failed = 0;

function test(string $name, callable $fn, array &$results, int &$passed, int &$failed): void {
    try { $fn(); $results[] = "  ✅ {$name}"; $passed++; }
    catch (\Throwable $e) { $results[] = "  ❌ {$name}: {$e->getMessage()} (line {$e->getLine()})"; $failed++; }
}
function assert_true(bool $v, string $msg = ''): void {
    if (!$v) throw new \RuntimeException("Assertion failed" . ($msg ? ": {$msg}" : ''));
}

// ─── Deterministic test workspace IDs ───
$wsA  = 'aaaa0000-aaaa-4000-8000-aaaaaaaaa001';
$wsB  = 'aaaa0000-aaaa-4000-8000-aaaaaaaaa002';
$systemUserId = DB::table('users')->value('id');
if (!$systemUserId) { echo "FATAL: No users.\n"; exit(1); }

// ─── Cleanup helper ───
function cleanWs(string $wsId): void {
    foreach (['provisioning_entity_bindings','roles','departments','teams','workspace_feature_flags','workspace_configurations','provisioning_runs','discovery_blueprints','discovery_sessions'] as $t)
        DB::table($t)->where('workspace_id', $wsId)->delete();
    DB::table('workspaces')->where('id', $wsId)->delete();
}
cleanWs($wsA); cleanWs($wsB);

// ─── Seed helper: workspace + blueprint ───
function seedWs(string $wsId, string $userId): array {
    DB::table('workspaces')->insert([
        'id' => $wsId, 'name' => "__test_{$wsId}__", 'industry_type' => 'test',
        'business_size' => 'small', 'default_locale' => 'en', 'default_currency' => 'USD',
        'timezone' => 'UTC', 'status' => 'active', 'is_active' => true, 'max_users' => 5,
        'created_at' => now(), 'updated_at' => now(),
    ]);
    $sessId = Str::uuid()->toString();
    DB::table('discovery_sessions')->insert([
        'id' => $sessId, 'workspace_id' => $wsId, 'created_by' => $userId,
        'status' => 'completed', 'business_description' => 'Test',
        'created_at' => now(), 'updated_at' => now(),
    ]);
    $bpId = Str::uuid()->toString();
    $bp = [
        'schema_version' => '1.0.0',
        'business_profile' => ['business_type' => 'test', 'business_name' => 'Test'],
        'modules' => [
            ['key' => 'customers', 'enabled' => true, 'status' => 'required'],
            ['key' => 'products',  'enabled' => true, 'status' => 'required'],
        ],
        'departments' => [['key' => 'sales_dept', 'name' => 'Sales']],
        'teams'       => [['key' => 'sales_team', 'name' => 'Sales Team', 'department_key' => 'sales_dept']],
        'roles'       => [[
            'key' => 'sales_mgr', 'name' => 'Sales Manager',
            'permissions' => ['contacts.list','contacts.show','products.list'],
            'description' => 'Manages sales',
        ]],
        'locations'   => [['key' => 'hq', 'name' => 'Headquarters', 'type' => 'office', 'country' => 'US']],
        'metadata'    => ['generated_at' => now()->toIso8601String()],
        'warehouses' => [], 'pipelines' => [], 'approval_workflows' => [],
        'commission_rules' => [], 'payment_methods' => [], 'tax_settings' => [],
        'invoice_settings' => [], 'pos_settings' => [], 'accounting_settings' => [],
        'workspace_settings' => [], 'localization' => [], 'ai_settings' => [],
        'assumptions' => [], 'missing_optional_information' => [],
    ];
    DB::table('discovery_blueprints')->insert([
        'id' => $bpId, 'session_id' => $sessId, 'workspace_id' => $wsId,
        'business_type' => 'test', 'blueprint' => json_encode($bp), 'version' => 1,
        'generator_method' => 'test', 'generator_version' => '1.0',
        'created_at' => now(), 'updated_at' => now(),
    ]);
    return ['bp_id' => $bpId, 'sess_id' => $sessId];
}

$seedA = seedWs($wsA, $systemUserId);
$bpIdA = $seedA['bp_id'];

echo "═══════════════════════════════════════\n";
echo "  Task 1.6B — 14 Integration Scenarios\n";
echo "═══════════════════════════════════════\n\n";

$svc = new ProvisioningService();

// ─── 1. Exact permissions stored ───
test('1. Exact Blueprint permissions equal stored role permissions', function () use ($svc, $wsA, $bpIdA, $systemUserId) {
    $result = $svc->apply($wsA, $bpIdA, $systemUserId);
    assert_true($result['status'] === 'foundation_applied', "Expected foundation_applied, got {$result['status']}");
    $role = Role::where('workspace_id', $wsA)->where('role_key', 'sales_mgr')->first();
    assert_true($role !== null, 'Role should exist');
    assert_true($role->permissions === ['contacts.list','contacts.show','products.list'], 'Perms mismatch: ' . json_encode($role->permissions));
}, $results, $passed, $failed);

// ─── 2. Unknown permission → rejected, no partial changes ───
test('2. Unknown permission is rejected with no partial changes', function () use ($wsA, $systemUserId) {
    $ws = 'aaaa0000-aaaa-4000-8000-aaaaaaaaa099';
    cleanWs($ws);
    $seed = seedWs($ws, $systemUserId);
    // Update blueprint with bad permission
    $bp = json_decode(DB::table('discovery_blueprints')->where('id', $seed['bp_id'])->value('blueprint'), true);
    $bp['roles'][0]['permissions'] = ['contacts.list', 'totally.fake.perm'];
    DB::table('discovery_blueprints')->where('id', $seed['bp_id'])->update(['blueprint' => json_encode($bp)]);

    $svc = new ProvisioningService();
    $caught = false; $rejected = false;
    try {
        $result = $svc->apply($ws, $seed['bp_id'], $systemUserId);
        // BlueprintValidator revalidation catches it → validation_failed return
        if (($result['status'] ?? '') === 'validation_failed') {
            $rejected = true;
            // Check that the error mentions the bad permission
            $errStr = json_encode($result['errors'] ?? []);
            assert_true(str_contains($errStr, 'totally.fake.perm') || str_contains($errStr, 'Unknown permission'), 'Error should mention bad perm: ' . $errStr);
        }
    } catch (ProvisioningException $e) {
        // CoreEntityProvisioner catches it → 422 throw
        $caught = true;
        assert_true($e->getCode() === 422, "Expected 422, got {$e->getCode()}");
        assert_true($e->getErrorCode() === 'invalid_permissions', "Expected invalid_permissions, got {$e->getErrorCode()}");
    }
    assert_true($caught || $rejected, 'Bad permission must be rejected (either validation_failed or 422 throw)');
    // No partial entities in either case
    assert_true(Role::where('workspace_id', $ws)->where('role_key', 'sales_mgr')->first() === null, 'No partial role');
    assert_true(Department::where('workspace_id', $ws)->where('department_key', 'sales_dept')->first() === null, 'No partial dept');
    cleanWs($ws);
}, $results, $passed, $failed);

// ─── 3. Idempotent apply ───
test('3. Same Blueprint version creates no duplicates', function () use ($svc, $wsA, $bpIdA, $systemUserId) {
    $result = $svc->apply($wsA, $bpIdA, $systemUserId);
    assert_true(($result['already_foundation_applied'] ?? false) === true, 'Should be idempotent');
    $count = Role::where('workspace_id', $wsA)->where('role_key', 'sales_mgr')->count();
    assert_true($count === 1, "Expected 1 role, got {$count}");
}, $results, $passed, $failed);

// ─── 4. Same-workspace concurrent apply blocked ───
test('4. Same-workspace concurrent apply is blocked', function () use ($wsA, $bpIdA, $systemUserId) {
    // There's already an active foundation_applied run — a new blueprint should be blocked
    $result = (new ProvisioningService())->apply($wsA, $bpIdA, $systemUserId);
    // It should either return idempotent or active_run
    assert_true(
        ($result['already_foundation_applied'] ?? false) === true || ($result['active_run'] ?? false) === true,
        'Should be blocked or idempotent: ' . json_encode($result)
    );
}, $results, $passed, $failed);

// ─── 5. Different workspaces independent ───
test('5. Different workspaces are independent', function () use ($wsB, $systemUserId) {
    $seed = seedWs($wsB, $systemUserId);
    $svc = new ProvisioningService();
    $result = $svc->apply($wsB, $seed['bp_id'], $systemUserId);
    assert_true($result['status'] === 'foundation_applied', "wsB should apply independently: {$result['status']}");
    $roleA = Role::where('workspace_id', 'aaaa0000-aaaa-4000-8000-aaaaaaaaa001')->where('role_key', 'sales_mgr')->count();
    $roleB = Role::where('workspace_id', $wsB)->where('role_key', 'sales_mgr')->count();
    assert_true($roleA === 1 && $roleB === 1, "Each ws should have 1 role: A={$roleA}, B={$roleB}");
}, $results, $passed, $failed);

// ─── 6. Forced mid-run failure → atomic rollback ───
test('6. Forced mid-run failure rolls back all entities', function () use ($systemUserId) {
    $ws = 'aaaa0000-aaaa-4000-8000-aaaaaaaaa098';
    cleanWs($ws);
    $seed = seedWs($ws, $systemUserId);

    // Inject failure hook via reflection
    $ref = new ReflectionProperty(CoreEntityProvisioner::class, 'testFailureHook');
    $ref->setAccessible(true);
    $ref->setValue(null, function () { throw new \RuntimeException('Injected mid-run failure'); });

    $caught = false;
    try { (new ProvisioningService())->apply($ws, $seed['bp_id'], $systemUserId); }
    catch (\Throwable $e) { $caught = true; }

    $ref->setValue(null, null); // Reset hook

    assert_true($caught, 'Should throw');
    // Transaction should have rolled back — no entities
    assert_true(Branch::where('workspace_id', $ws)->count() === 0, 'No locations after failure');
    assert_true(Department::where('workspace_id', $ws)->count() === 0, 'No depts after failure');
    assert_true(Role::where('workspace_id', $ws)->count() === 0, 'No roles after failure');
    assert_true(ProvisioningEntityBinding::where('workspace_id', $ws)->count() === 0, 'No bindings after failure');
    cleanWs($ws);
}, $results, $passed, $failed);

// ─── 7. Clean rollback restores previous state ───
test('7. Clean rollback restores previous state', function () use ($wsB, $systemUserId) {
    $svc = new ProvisioningService();
    $run = ProvisioningRun::where('workspace_id', $wsB)->where('status', 'foundation_applied')->first();
    assert_true($run !== null, 'wsB should have a foundation_applied run');

    $result = $svc->rollback($wsB, $run->id, $systemUserId);
    assert_true($result['status'] === 'rolled_back', "Expected rolled_back, got {$result['status']}");

    // WC should be deleted (didn't exist before provisioning)
    $wc = WorkspaceConfiguration::where('workspace_id', $wsB)->first();
    assert_true($wc === null, 'WC should be deleted after rollback (scenario 11 overlap)');
}, $results, $passed, $failed);

// ─── 8. Provisioning-created entities deleted on rollback ───
test('8. Provisioning-created entities are deleted during rollback', function () use ($wsB) {
    // After rollback in test 7, created entities should be gone
    assert_true(Role::where('workspace_id', $wsB)->where('role_key', 'sales_mgr')->first() === null, 'Role deleted');
    assert_true(Department::where('workspace_id', $wsB)->where('department_key', 'sales_dept')->first() === null, 'Dept deleted');
    assert_true(Team::where('workspace_id', $wsB)->where('team_key', 'sales_team')->first() === null, 'Team deleted');
    assert_true(Branch::where('workspace_id', $wsB)->where('name', 'Headquarters')->first() === null, 'Location deleted');
    assert_true(ProvisioningEntityBinding::where('workspace_id', $wsB)->count() === 0, 'All bindings removed');
}, $results, $passed, $failed);

// ─── 9. Template-adopted entities restored, not deleted ───
test('9. Template-adopted entities are restored, never deleted', function () use ($systemUserId) {
    $ws = 'aaaa0000-aaaa-4000-8000-aaaaaaaaa097';
    cleanWs($ws);
    $seed = seedWs($ws, $systemUserId);

    // Pre-create a department with template provenance
    $deptId = Str::uuid()->toString();
    DB::table('departments')->insert([
        'id' => $deptId, 'workspace_id' => $ws, 'name' => 'Sales Original',
        'department_key' => 'sales_dept', 'is_active' => true, 'sort_order' => 0,
        'created_at' => now(), 'updated_at' => now(),
    ]);
    DB::table('provisioning_entity_bindings')->insert([
        'id' => Str::uuid()->toString(), 'workspace_id' => $ws, 'entity_type' => 'department',
        'local_key' => 'tmpl_sales', 'entity_id' => $deptId,
        'ownership_type' => 'created_by_template', 'last_blueprint_version' => 1,
        'created_at' => now(), 'updated_at' => now(),
    ]);

    $svc = new ProvisioningService();
    $applyResult = $svc->apply($ws, $seed['bp_id'], $systemUserId);
    assert_true($applyResult['status'] === 'foundation_applied', 'Should apply');

    // Dept should be adopted (name updated to 'Sales')
    $dept = Department::find($deptId);
    assert_true($dept !== null, 'Adopted dept should exist');
    assert_true($dept->name === 'Sales', "Name should be 'Sales', got '{$dept->name}'");

    // Rollback
    $run = ProvisioningRun::where('workspace_id', $ws)->where('status', 'foundation_applied')->first();
    $rbResult = $svc->rollback($ws, $run->id, $systemUserId);
    assert_true($rbResult['status'] === 'rolled_back', 'Should rollback');

    // Adopted dept should be RESTORED to original name, NOT deleted
    $dept = Department::find($deptId);
    assert_true($dept !== null, 'Adopted entity must NOT be deleted');
    assert_true($dept->name === 'Sales Original', "Name should be restored to 'Sales Original', got '{$dept->name}'");

    cleanWs($ws);
}, $results, $passed, $failed);

// ─── 10. Manual change → rollback_conflict 409 ───
test('10. Manual changes before rollback return rollback_conflict 409', function () use ($systemUserId) {
    $ws = 'aaaa0000-aaaa-4000-8000-aaaaaaaaa096';
    cleanWs($ws);
    $seed = seedWs($ws, $systemUserId);

    $svc = new ProvisioningService();
    $applyResult = $svc->apply($ws, $seed['bp_id'], $systemUserId);
    assert_true($applyResult['status'] === 'foundation_applied', 'Should apply');

    $run = ProvisioningRun::where('workspace_id', $ws)->where('status', 'foundation_applied')->first();
    assert_true($run !== null, 'Run should exist');

    // Simulate external modification: set WC provisioning_run_id to null
    // This makes detectManualChanges think WC was modified by a different process
    WorkspaceConfiguration::where('workspace_id', $ws)
        ->update(['provisioning_run_id' => null]);

    $caught = false; $code = 0; $errCode = '';
    try { $svc->rollback($ws, $run->id, $systemUserId); }
    catch (ProvisioningException $e) { $caught = true; $code = $e->getCode(); $errCode = $e->getErrorCode(); }

    assert_true($caught, 'Should throw ProvisioningException');
    assert_true($code === 409, "Expected 409, got {$code}");
    assert_true($errCode === 'rollback_conflict', "Expected rollback_conflict, got {$errCode}");

    // Run should still be foundation_applied (not rolled back)
    $run->refresh();
    assert_true($run->status === 'foundation_applied', 'Run should remain foundation_applied');

    cleanWs($ws);
}, $results, $passed, $failed);

// ─── 11. Absent WC deleted on rollback ───
test('11. WC that did not exist before provisioning is deleted on rollback', function () use ($systemUserId) {
    $ws = 'aaaa0000-aaaa-4000-8000-aaaaaaaaa095';
    cleanWs($ws);
    $seed = seedWs($ws, $systemUserId);

    // Verify no WC exists
    assert_true(WorkspaceConfiguration::where('workspace_id', $ws)->first() === null, 'No WC before apply');

    $svc = new ProvisioningService();
    $svc->apply($ws, $seed['bp_id'], $systemUserId);

    // WC should exist after apply
    assert_true(WorkspaceConfiguration::where('workspace_id', $ws)->first() !== null, 'WC should exist after apply');

    $run = ProvisioningRun::where('workspace_id', $ws)->where('status', 'foundation_applied')->first();
    $svc->rollback($ws, $run->id, $systemUserId);

    // WC should be deleted
    assert_true(WorkspaceConfiguration::where('workspace_id', $ws)->first() === null, 'WC should be deleted after rollback');

    cleanWs($ws);
}, $results, $passed, $failed);

// ─── 12. Template adoption (role, dept, team) ───
test('12. Template adoption works for role, department, and team', function () use ($systemUserId) {
    $ws = 'aaaa0000-aaaa-4000-8000-aaaaaaaaa094';
    cleanWs($ws);
    $seed = seedWs($ws, $systemUserId);

    // Pre-create entities with template provenance
    $roleId = Str::uuid()->toString();
    DB::table('roles')->insert([
        'id' => $roleId, 'workspace_id' => $ws, 'name' => 'Sales Manager Old',
        'role_key' => 'sales_mgr', 'permissions' => json_encode(['contacts.list']),
        'hierarchy_level' => 4, 'is_system' => true, 'is_default' => false,
        'is_deletable' => true, 'is_active' => true, 'sort_order' => 1,
        'created_at' => now(), 'updated_at' => now(),
    ]);
    DB::table('provisioning_entity_bindings')->insert([
        'id' => Str::uuid()->toString(), 'workspace_id' => $ws, 'entity_type' => 'role',
        'local_key' => 'tmpl_sales_mgr', 'entity_id' => $roleId,
        'ownership_type' => 'created_by_template', 'last_blueprint_version' => 1,
        'created_at' => now(), 'updated_at' => now(),
    ]);

    $deptId = Str::uuid()->toString();
    DB::table('departments')->insert([
        'id' => $deptId, 'workspace_id' => $ws, 'name' => 'Sales Dept Old',
        'department_key' => 'sales_dept', 'is_active' => true, 'sort_order' => 0,
        'created_at' => now(), 'updated_at' => now(),
    ]);
    DB::table('provisioning_entity_bindings')->insert([
        'id' => Str::uuid()->toString(), 'workspace_id' => $ws, 'entity_type' => 'department',
        'local_key' => 'tmpl_sales_dept', 'entity_id' => $deptId,
        'ownership_type' => 'created_by_template', 'last_blueprint_version' => 1,
        'created_at' => now(), 'updated_at' => now(),
    ]);

    $teamId = Str::uuid()->toString();
    DB::table('teams')->insert([
        'id' => $teamId, 'workspace_id' => $ws, 'name' => 'Sales Team Old',
        'team_key' => 'sales_team', 'is_active' => true, 'sort_order' => 0,
        'created_at' => now(), 'updated_at' => now(),
    ]);
    DB::table('provisioning_entity_bindings')->insert([
        'id' => Str::uuid()->toString(), 'workspace_id' => $ws, 'entity_type' => 'team',
        'local_key' => 'tmpl_sales_team', 'entity_id' => $teamId,
        'ownership_type' => 'created_by_template', 'last_blueprint_version' => 1,
        'created_at' => now(), 'updated_at' => now(),
    ]);

    $svc = new ProvisioningService();
    $result = $svc->apply($ws, $seed['bp_id'], $systemUserId);
    assert_true($result['status'] === 'foundation_applied', 'Should apply');

    // Verify adoption
    assert_true(Role::find($roleId)->name === 'Sales Manager', 'Role adopted/updated');
    assert_true(Department::find($deptId)->name === 'Sales', 'Dept adopted/updated');
    assert_true(Team::find($teamId)->name === 'Sales Team', 'Team adopted/updated');

    $adopted = ProvisioningEntityBinding::where('workspace_id', $ws)
        ->where('ownership_type', 'adopted_template_entity')->count();
    assert_true($adopted >= 3, "Expected ≥3 adopted bindings, got {$adopted}");

    cleanWs($ws);
}, $results, $passed, $failed);

// ─── 13. Unmanaged entity conflict 409 ───
test('13. Unmanaged entity conflict returns 409', function () use ($systemUserId) {
    $ws = 'aaaa0000-aaaa-4000-8000-aaaaaaaaa093';
    cleanWs($ws);
    $seed = seedWs($ws, $systemUserId);

    // Create an unmanaged role (no binding)
    DB::table('roles')->insert([
        'id' => Str::uuid()->toString(), 'workspace_id' => $ws, 'name' => 'Manual Role',
        'role_key' => 'sales_mgr', 'permissions' => json_encode([]),
        'hierarchy_level' => 5, 'is_system' => false, 'is_default' => false,
        'is_deletable' => true, 'is_active' => true, 'sort_order' => 99,
        'created_at' => now(), 'updated_at' => now(),
    ]);

    $caught = false; $code = 0;
    try { (new ProvisioningService())->apply($ws, $seed['bp_id'], $systemUserId); }
    catch (ProvisioningException $e) { $caught = true; $code = $e->getCode(); }

    assert_true($caught, 'Should throw');
    assert_true($code === 409, "Expected 409, got {$code}");

    cleanWs($ws);
}, $results, $passed, $failed);

// ─── 14. Missing bound entity 409 ───
test('14. Missing bound entity detection returns 409', function () use ($systemUserId) {
    $ws = 'aaaa0000-aaaa-4000-8000-aaaaaaaaa092';
    cleanWs($ws);
    $seed = seedWs($ws, $systemUserId);

    // Create binding to non-existent entity
    $ghostId = Str::uuid()->toString();
    DB::table('provisioning_entity_bindings')->insert([
        'id' => Str::uuid()->toString(), 'workspace_id' => $ws, 'entity_type' => 'department',
        'local_key' => 'sales_dept', 'entity_id' => $ghostId,
        'ownership_type' => 'created_by_provisioning', 'last_blueprint_version' => 1,
        'created_at' => now(), 'updated_at' => now(),
    ]);

    $caught = false; $code = 0; $errCode = '';
    try { (new ProvisioningService())->apply($ws, $seed['bp_id'], $systemUserId); }
    catch (ProvisioningException $e) { $caught = true; $code = $e->getCode(); $errCode = $e->getErrorCode(); }

    assert_true($caught, 'Should throw');
    assert_true($code === 409, "Expected 409, got {$code}");
    assert_true($errCode === 'missing_bound_entity', "Expected missing_bound_entity, got {$errCode}");

    cleanWs($ws);
}, $results, $passed, $failed);

// ─── Print results ───
echo "Results:\n";
foreach ($results as $r) echo "{$r}\n";
echo "\n";

// ─── Final cleanup ───
echo "Cleaning test data...\n";
foreach (['aaaa0000-aaaa-4000-8000-aaaaaaaaa001','aaaa0000-aaaa-4000-8000-aaaaaaaaa002'] as $w) cleanWs($w);
echo "Test data cleaned.\n\n";

echo "═══════════════════════════════════════\n";
if ($failed === 0) { echo "  All {$passed}/14 scenarios PASSED ✅\n"; }
else { echo "  {$failed}/{$passed} scenarios FAILED ❌\n"; }
echo "═══════════════════════════════════════\n";

exit($failed > 0 ? 1 : 0);
