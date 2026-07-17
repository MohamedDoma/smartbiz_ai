<?php
/**
 * Task 1.6C — 10 Operational Provisioning Integration Scenarios
 *
 *  1. Full operational apply: warehouses, pipelines, approvals, commissions
 *  2. Pipeline stages created in correct order with bindings
 *  3. Warehouse linked to provisioned branch via location_key binding
 *  4. Commission rule resolves role_key via binding
 *  5. Approval workflow steps created with correct workflow_id
 *  6. Workspace settings applied (currency, timezone, locale)
 *  7. Idempotent applyOperational (same version)
 *  8. applyOperational without foundation_applied → 409
 *  9. Mid-run failure → atomic rollback (no partial operational entities)
 * 10. Rollback of applied run deletes operational + core entities
 */

require __DIR__ . '/../vendor/autoload.php';
$app = require __DIR__ . '/../bootstrap/app.php';
$app->make(\Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Exceptions\ProvisioningException;
use App\Models\ApprovalWorkflow;
use App\Models\ApprovalWorkflowStep;
use App\Models\Branch;
use App\Models\CommissionPlan;
use App\Models\CommissionRule;
use App\Models\Department;
use App\Models\DiscoveryBlueprint;
use App\Models\Pipeline;
use App\Models\PipelineStage;
use App\Models\ProvisioningEntityBinding;
use App\Models\ProvisioningRun;
use App\Models\Role;
use App\Models\Team;
use App\Models\Warehouse;
use App\Models\Workspace;
use App\Models\WorkspaceConfiguration;
use App\Models\WorkspaceFeatureFlag;
use App\Services\Provisioning\OperationalEntityProvisioner;
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
$wsOp = 'bbbb0000-bbbb-4000-8000-bbbbbbbb0001';
$systemUserId = DB::table('users')->value('id');
if (!$systemUserId) { echo "FATAL: No users.\n"; exit(1); }

// ─── Cleanup helper ───
function cleanWsOp(string $wsId): void {
    foreach ([
        'commission_rules','commission_plans','approval_workflow_steps','approval_workflows',
        'pipeline_stages','pipelines','warehouses','provisioning_entity_bindings',
        'roles','departments','teams','workspace_feature_flags','workspace_configurations',
        'provisioning_runs','discovery_blueprints','discovery_sessions',
    ] as $t) {
        DB::table($t)->where('workspace_id', $wsId)->delete();
    }
    DB::table('workspaces')->where('id', $wsId)->delete();
}
cleanWsOp($wsOp);

// ─── Seed helper: workspace + operational blueprint ───
function seedWsOp(string $wsId, string $userId): array {
    DB::table('workspaces')->insert([
        'id' => $wsId, 'name' => "__test_op_{$wsId}__", 'industry_type' => 'retail',
        'business_size' => 'medium', 'default_locale' => 'en', 'default_currency' => 'USD',
        'timezone' => 'UTC', 'status' => 'active', 'is_active' => true, 'max_users' => 10,
        'created_at' => now(), 'updated_at' => now(),
    ]);
    $sessId = Str::uuid()->toString();
    DB::table('discovery_sessions')->insert([
        'id' => $sessId, 'workspace_id' => $wsId, 'created_by' => $userId,
        'status' => 'completed', 'business_description' => 'Test Operational',
        'created_at' => now(), 'updated_at' => now(),
    ]);
    $bpId = Str::uuid()->toString();
    $bp = [
        'schema_version' => '1.0.0',
        'business_profile' => ['business_type' => 'retail', 'business_name' => 'Test Op Store'],
        'modules' => [
            ['key' => 'customers', 'enabled' => true, 'status' => 'required'],
            ['key' => 'products',  'enabled' => true, 'status' => 'required'],
            ['key' => 'inventory', 'enabled' => true, 'status' => 'required'],
            ['key' => 'invoices',  'enabled' => true, 'status' => 'required'],
            ['key' => 'payments',  'enabled' => true, 'status' => 'required'],
            ['key' => 'commissions','enabled' => true, 'status' => 'recommended'],
            ['key' => 'employees', 'enabled' => true, 'status' => 'required'],
            ['key' => 'leads',     'enabled' => true, 'status' => 'recommended'],
        ],
        'departments' => [
            ['key' => 'sales_dept', 'name' => 'Sales'],
            ['key' => 'ops_dept',   'name' => 'Operations'],
        ],
        'teams' => [
            ['key' => 'sales_team', 'name' => 'Sales Team', 'department_key' => 'sales_dept'],
        ],
        'roles' => [
            [
                'key' => 'sales_rep', 'name' => 'Sales Representative',
                'permissions' => ['contacts.list','contacts.show','products.list'],
                'description' => 'Front-line sales',
            ],
            [
                'key' => 'ops_mgr', 'name' => 'Operations Manager',
                'permissions' => ['contacts.list','products.list','products.show'],
                'description' => 'Manages operations',
            ],
        ],
        'locations' => [
            ['key' => 'main_branch', 'name' => 'Main Branch', 'type' => 'store', 'country' => 'US'],
            ['key' => 'warehouse_loc', 'name' => 'Warehouse Site', 'type' => 'warehouse_site', 'country' => 'US'],
        ],
        // ── Operational entities ──
        'warehouses' => [
            ['key' => 'main_wh', 'name' => 'Main Warehouse', 'location_key' => 'warehouse_loc'],
            ['key' => 'secondary_wh', 'name' => 'Secondary Warehouse', 'location_key' => 'main_branch'],
        ],
        'pipelines' => [
            [
                'key' => 'sales_pipeline', 'name' => 'Sales Pipeline', 'entity_type' => 'deal',
                'description' => 'Main sales funnel',
                'stages' => [
                    ['key' => 'prospect',     'name' => 'Prospect',      'status_type' => 'open'],
                    ['key' => 'qualification','name' => 'Qualification', 'status_type' => 'open'],
                    ['key' => 'proposal',     'name' => 'Proposal',      'status_type' => 'open'],
                    ['key' => 'won',          'name' => 'Won',           'status_type' => 'completed'],
                    ['key' => 'lost',         'name' => 'Lost',          'status_type' => 'lost'],
                ],
            ],
            [
                'key' => 'lead_pipeline', 'name' => 'Lead Pipeline', 'entity_type' => 'lead',
                'stages' => [
                    ['key' => 'new_lead',   'name' => 'New Lead',   'status_type' => 'open'],
                    ['key' => 'contacted',  'name' => 'Contacted',  'status_type' => 'open'],
                    ['key' => 'converted',  'name' => 'Converted',  'status_type' => 'completed'],
                ],
            ],
        ],
        'approval_workflows' => [
            [
                'key' => 'invoice_approval', 'name' => 'Invoice Approval',
                'entity_type' => 'invoice', 'description' => 'Approves invoices > 5000',
                'conditions' => ['min_amount' => 5000],
                'steps' => [
                    ['key' => 'mgr_review', 'name' => 'Manager Review', 'approver_type' => 'permission',
                     'approver_permission_key' => 'approvals.decide'],
                    ['key' => 'finance_review', 'name' => 'Finance Review', 'approver_type' => 'permission',
                     'approver_permission_key' => 'commissions.approve'],
                ],
            ],
        ],
        'commission_rules' => [
            [
                'key' => 'sales_commission', 'name' => 'Sales Commission Plan',
                'description' => 'Standard sales commissions', 'applies_to' => 'deal',
                'rules' => [
                    [
                        'key' => 'base_pct', 'role_key' => 'sales_rep',
                        'target_type' => 'deal', 'calculation_type' => 'percentage',
                        'percentage_rate' => 5.0, 'trigger_status' => 'won',
                    ],
                ],
            ],
        ],
        'workspace_settings' => [
            'currency' => 'SAR',
            'timezone' => 'Asia/Riyadh',
            'primary_language' => 'ar',
        ],
        'metadata' => ['generated_at' => now()->toIso8601String()],
        'payment_methods' => [], 'tax_settings' => [], 'invoice_settings' => [],
        'pos_settings' => [], 'accounting_settings' => [], 'localization' => [],
        'ai_settings' => [], 'assumptions' => [], 'missing_optional_information' => [],
    ];
    DB::table('discovery_blueprints')->insert([
        'id' => $bpId, 'session_id' => $sessId, 'workspace_id' => $wsId,
        'business_type' => 'retail', 'blueprint' => json_encode($bp), 'version' => 1,
        'generator_method' => 'test', 'generator_version' => '1.0',
        'created_at' => now(), 'updated_at' => now(),
    ]);
    return ['bp_id' => $bpId, 'sess_id' => $sessId];
}

$seedOp = seedWsOp($wsOp, $systemUserId);
$bpIdOp = $seedOp['bp_id'];

echo "═══════════════════════════════════════════\n";
echo "  Task 1.6C — 10 Operational Scenarios\n";
echo "═══════════════════════════════════════════\n\n";

$svc = new ProvisioningService();

// ─── Step 0: Apply core foundation first ───
$foundationResult = $svc->apply($wsOp, $bpIdOp, $systemUserId);
if ($foundationResult['status'] !== 'foundation_applied') {
    echo "FATAL: Foundation apply failed: " . json_encode($foundationResult) . "\n";
    cleanWsOp($wsOp);
    exit(1);
}
echo "Foundation applied OK (run: {$foundationResult['run_id']})\n\n";

// ═══════════════════════════════════════════
//  1. Full operational apply
// ═══════════════════════════════════════════
test('1. Full operational apply creates warehouses, pipelines, approvals, commissions', function () use ($svc, $wsOp, $bpIdOp, $systemUserId) {
    $result = $svc->applyOperational($wsOp, $bpIdOp, $systemUserId);
    assert_true($result['status'] === 'applied', "Expected applied, got {$result['status']}");

    // Warehouses
    $whCount = Warehouse::where('workspace_id', $wsOp)->count();
    assert_true($whCount === 2, "Expected 2 warehouses, got {$whCount}");

    // Pipelines
    $plCount = Pipeline::where('workspace_id', $wsOp)->count();
    assert_true($plCount === 2, "Expected 2 pipelines, got {$plCount}");

    // Approval workflows
    $awCount = ApprovalWorkflow::where('workspace_id', $wsOp)->count();
    assert_true($awCount === 1, "Expected 1 approval workflow, got {$awCount}");

    // Commission plans
    $cpCount = CommissionPlan::where('workspace_id', $wsOp)->count();
    assert_true($cpCount === 1, "Expected 1 commission plan, got {$cpCount}");

    // Run status
    $run = ProvisioningRun::where('workspace_id', $wsOp)->where('status', 'applied')->first();
    assert_true($run !== null, 'Run should be in applied status');
}, $results, $passed, $failed);

// ═══════════════════════════════════════════
//  2. Pipeline stages created in correct order
// ═══════════════════════════════════════════
test('2. Pipeline stages created in correct order with bindings', function () use ($wsOp) {
    $pipeline = Pipeline::where('workspace_id', $wsOp)->where('pipeline_key', 'sales_pipeline')->first();
    assert_true($pipeline !== null, 'Sales pipeline should exist');

    $stages = PipelineStage::where('workspace_id', $wsOp)
        ->where('pipeline_id', $pipeline->id)
        ->orderBy('sort_order')
        ->get();

    assert_true($stages->count() === 5, "Expected 5 stages, got {$stages->count()}");
    assert_true($stages[0]->name === 'Prospect', "First stage should be Prospect, got {$stages[0]->name}");
    assert_true($stages[3]->name === 'Won', "4th stage should be Won, got {$stages[3]->name}");
    assert_true($stages[4]->status_type === 'lost', "Last stage status_type should be lost, got {$stages[4]->status_type}");

    // Verify bindings exist
    $binding = ProvisioningEntityBinding::where('workspace_id', $wsOp)
        ->where('entity_type', 'pipeline_stage')
        ->where('local_key', 'sales_pipeline.prospect')
        ->first();
    assert_true($binding !== null, 'Stage binding should exist');
    assert_true($binding->entity_id === $stages[0]->id, 'Stage binding entity_id should match');
}, $results, $passed, $failed);

// ═══════════════════════════════════════════
//  3. Warehouse linked to provisioned branch
// ═══════════════════════════════════════════
test('3. Warehouse linked to provisioned branch via location_key binding', function () use ($wsOp) {
    $wh = Warehouse::where('workspace_id', $wsOp)->where('name', 'Main Warehouse')->first();
    assert_true($wh !== null, 'Main Warehouse should exist');
    assert_true($wh->branch_id !== null, 'Warehouse should have branch_id');

    // Branch should be the one created from 'warehouse_loc' location
    $branch = Branch::find($wh->branch_id);
    assert_true($branch !== null, 'Linked branch should exist');
    assert_true($branch->name === 'Warehouse Site', "Branch name should be 'Warehouse Site', got '{$branch->name}'");

    // Verify binding
    $binding = ProvisioningEntityBinding::where('workspace_id', $wsOp)
        ->where('entity_type', 'warehouse')
        ->where('local_key', 'main_wh')
        ->first();
    assert_true($binding !== null, 'Warehouse binding should exist');
    assert_true($binding->entity_id === $wh->id, 'Warehouse binding entity_id should match');
}, $results, $passed, $failed);

// ═══════════════════════════════════════════
//  4. Commission rule resolves role_key
// ═══════════════════════════════════════════
test('4. Commission rule resolves role_key via binding', function () use ($wsOp) {
    $plan = CommissionPlan::where('workspace_id', $wsOp)->where('plan_key', 'sales_commission')->first();
    assert_true($plan !== null, 'Commission plan should exist');

    $rule = CommissionRule::where('workspace_id', $wsOp)
        ->where('commission_plan_id', $plan->id)
        ->first();
    assert_true($rule !== null, 'Commission rule should exist');
    assert_true($rule->role_id !== null, 'Commission rule should have role_id');
    assert_true($rule->calculation_type === 'percentage', "Expected percentage, got {$rule->calculation_type}");
    assert_true((float)$rule->percentage_rate === 5.0, "Expected rate 5.0, got {$rule->percentage_rate}");

    // Verify role_id points to the provisioned sales_rep role
    $role = Role::find($rule->role_id);
    assert_true($role !== null, 'Referenced role should exist');
    assert_true($role->role_key === 'sales_rep', "Role key should be sales_rep, got {$role->role_key}");
}, $results, $passed, $failed);

// ═══════════════════════════════════════════
//  5. Approval workflow steps correct
// ═══════════════════════════════════════════
test('5. Approval workflow steps created with correct workflow_id', function () use ($wsOp) {
    $wf = ApprovalWorkflow::where('workspace_id', $wsOp)->where('workflow_key', 'invoice_approval')->first();
    assert_true($wf !== null, 'Invoice approval workflow should exist');
    assert_true($wf->entity_type === 'invoice', "Entity type should be invoice, got {$wf->entity_type}");

    $steps = ApprovalWorkflowStep::where('workspace_id', $wsOp)
        ->where('workflow_id', $wf->id)
        ->orderBy('step_order')
        ->get();
    assert_true($steps->count() === 2, "Expected 2 steps, got {$steps->count()}");
    assert_true($steps[0]->name === 'Manager Review', "First step should be Manager Review, got {$steps[0]->name}");
    assert_true($steps[1]->name === 'Finance Review', "Second step should be Finance Review");
    assert_true($steps[0]->approver_permission_key === 'approvals.decide', "Step 1 perm key mismatch");

    // Verify step bindings
    $binding = ProvisioningEntityBinding::where('workspace_id', $wsOp)
        ->where('entity_type', 'approval_workflow_step')
        ->where('local_key', 'invoice_approval.mgr_review')
        ->first();
    assert_true($binding !== null, 'Workflow step binding should exist');
}, $results, $passed, $failed);

// ═══════════════════════════════════════════
//  6. Workspace settings applied
// ═══════════════════════════════════════════
test('6. Workspace settings applied (currency, timezone, locale)', function () use ($wsOp) {
    $ws = Workspace::find($wsOp);
    assert_true($ws !== null, 'Workspace should exist');
    assert_true($ws->default_currency === 'SAR', "Currency should be SAR, got {$ws->default_currency}");
    assert_true($ws->timezone === 'Asia/Riyadh', "Timezone should be Asia/Riyadh, got {$ws->timezone}");
    assert_true($ws->default_locale === 'ar', "Locale should be ar, got {$ws->default_locale}");
}, $results, $passed, $failed);

// ═══════════════════════════════════════════
//  7. Idempotent applyOperational
// ═══════════════════════════════════════════
test('7. Idempotent applyOperational (same version)', function () use ($svc, $wsOp, $bpIdOp, $systemUserId) {
    $result = $svc->applyOperational($wsOp, $bpIdOp, $systemUserId);
    assert_true(($result['already_applied'] ?? false) === true, 'Should be idempotent: ' . json_encode($result));
    assert_true($result['status'] === 'applied', "Status should still be applied");

    // No duplicates
    $whCount = Warehouse::where('workspace_id', $wsOp)->count();
    assert_true($whCount === 2, "Expected 2 warehouses after idempotent call, got {$whCount}");
    $plCount = Pipeline::where('workspace_id', $wsOp)->count();
    assert_true($plCount === 2, "Expected 2 pipelines after idempotent call, got {$plCount}");
}, $results, $passed, $failed);

// ═══════════════════════════════════════════
//  8. applyOperational without foundation → 409
// ═══════════════════════════════════════════
test('8. applyOperational without foundation_applied returns 409', function () use ($systemUserId) {
    $ws = 'bbbb0000-bbbb-4000-8000-bbbbbbbb0008';
    cleanWsOp($ws);
    $seed = seedWsOp($ws, $systemUserId);

    // Do NOT call apply() first — go straight to applyOperational
    $caught = false; $code = 0; $errCode = '';
    try {
        (new ProvisioningService())->applyOperational($ws, $seed['bp_id'], $systemUserId);
    } catch (ProvisioningException $e) {
        $caught = true;
        $code = $e->getCode();
        $errCode = $e->getErrorCode();
    }

    assert_true($caught, 'Should throw ProvisioningException');
    assert_true($code === 409, "Expected 409, got {$code}");
    assert_true($errCode === 'invalid_status_transition', "Expected invalid_status_transition, got {$errCode}");

    // No operational entities should exist
    assert_true(Warehouse::where('workspace_id', $ws)->count() === 0, 'No warehouses');
    assert_true(Pipeline::where('workspace_id', $ws)->count() === 0, 'No pipelines');

    cleanWsOp($ws);
}, $results, $passed, $failed);

// ═══════════════════════════════════════════
//  9. Mid-run failure → atomic rollback
// ═══════════════════════════════════════════
test('9. Mid-run failure rolls back all operational entities', function () use ($systemUserId) {
    $ws = 'bbbb0000-bbbb-4000-8000-bbbbbbbb0009';
    cleanWsOp($ws);
    $seed = seedWsOp($ws, $systemUserId);

    // First apply core foundation
    $svc = new ProvisioningService();
    $foundResult = $svc->apply($ws, $seed['bp_id'], $systemUserId);
    assert_true($foundResult['status'] === 'foundation_applied', 'Foundation should apply');

    // Inject failure hook via reflection
    $ref = new ReflectionProperty(OperationalEntityProvisioner::class, 'testFailureHook');
    $ref->setAccessible(true);
    $ref->setValue(null, function () { throw new \RuntimeException('Injected operational failure'); });

    $caught = false;
    try { $svc->applyOperational($ws, $seed['bp_id'], $systemUserId); }
    catch (\Throwable $e) { $caught = true; }

    $ref->setValue(null, null); // Reset hook

    assert_true($caught, 'Should throw');
    // Transaction rolled back — no operational entities
    assert_true(Warehouse::where('workspace_id', $ws)->count() === 0, 'No warehouses after failure');
    assert_true(Pipeline::where('workspace_id', $ws)->count() === 0, 'No pipelines after failure');
    assert_true(PipelineStage::where('workspace_id', $ws)->count() === 0, 'No stages after failure');
    assert_true(ApprovalWorkflow::where('workspace_id', $ws)->count() === 0, 'No workflows after failure');
    assert_true(CommissionPlan::where('workspace_id', $ws)->count() === 0, 'No commission plans after failure');

    // Run should still be foundation_applied (not applied)
    $run = ProvisioningRun::where('workspace_id', $ws)->whereIn('status', ['foundation_applied','applied'])->first();
    assert_true($run !== null && $run->status === 'foundation_applied', 'Run should remain foundation_applied');

    cleanWsOp($ws);
}, $results, $passed, $failed);

// ═══════════════════════════════════════════
// 10. Rollback of applied run deletes operational + core entities
// ═══════════════════════════════════════════
test('10. Rollback of applied run deletes operational and core entities', function () use ($wsOp, $bpIdOp, $systemUserId) {
    $svc = new ProvisioningService();
    $run = ProvisioningRun::where('workspace_id', $wsOp)->where('status', 'applied')->first();
    assert_true($run !== null, 'Should have an applied run');

    $result = $svc->rollback($wsOp, $run->id, $systemUserId);
    assert_true($result['status'] === 'rolled_back', "Expected rolled_back, got {$result['status']}");

    // Operational entities deleted
    assert_true(Warehouse::where('workspace_id', $wsOp)->count() === 0, 'Warehouses deleted');
    assert_true(Pipeline::where('workspace_id', $wsOp)->count() === 0, 'Pipelines deleted');
    assert_true(PipelineStage::where('workspace_id', $wsOp)->count() === 0, 'Pipeline stages deleted');
    assert_true(ApprovalWorkflow::where('workspace_id', $wsOp)->count() === 0, 'Approval workflows deleted');
    assert_true(ApprovalWorkflowStep::where('workspace_id', $wsOp)->count() === 0, 'Approval workflow steps deleted');
    assert_true(CommissionPlan::where('workspace_id', $wsOp)->count() === 0, 'Commission plans deleted');
    assert_true(CommissionRule::where('workspace_id', $wsOp)->count() === 0, 'Commission rules deleted');

    // Core entities also deleted
    assert_true(Role::where('workspace_id', $wsOp)->where('role_key', 'sales_rep')->first() === null, 'Role deleted');
    assert_true(Department::where('workspace_id', $wsOp)->where('department_key', 'sales_dept')->first() === null, 'Dept deleted');

    // All bindings removed
    assert_true(ProvisioningEntityBinding::where('workspace_id', $wsOp)->count() === 0, 'All bindings removed');
}, $results, $passed, $failed);

// ─── Print results ───
echo "\nResults:\n";
foreach ($results as $r) echo "{$r}\n";
echo "\n";

// ─── Final cleanup ───
echo "Cleaning test data...\n";
foreach ([
    $wsOp,
    'bbbb0000-bbbb-4000-8000-bbbbbbbb0008',
    'bbbb0000-bbbb-4000-8000-bbbbbbbb0009',
] as $w) cleanWsOp($w);
echo "Test data cleaned.\n\n";

echo "═══════════════════════════════════════════\n";
if ($failed === 0) { echo "  All {$passed}/10 scenarios PASSED ✅\n"; }
else { echo "  {$failed}/{$passed} scenarios FAILED ❌\n"; }
echo "═══════════════════════════════════════════\n";

exit($failed > 0 ? 1 : 0);
