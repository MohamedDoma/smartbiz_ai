<?php
/**
 * SmartBiz AI — Idempotent Demo Approval Workflow Synchronization
 *
 * Seeds the "High Commission Approval" workflow into the demo workspace,
 * and ensures all demo roles have the correct approval permissions.
 *
 * Safe to run multiple times. Does NOT modify operational data.
 *
 * Usage:
 *   php scripts/sync_demo_approval_workflows.php
 */

require_once __DIR__ . '/../vendor/autoload.php';

$app = require_once __DIR__ . '/../bootstrap/app.php';
$app->make(\Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

$workspaceId = 'dd000000-0000-0000-0000-000000000001';

echo "════════════════════════════════════════════════════\n";
echo "  SmartBiz AI — Demo Approval Workflow Sync\n";
echo "  Workspace: {$workspaceId}\n";
echo "════════════════════════════════════════════════════\n\n";

// ── 1. Verify workspace exists ──────────────────────────

$workspace = DB::table('workspaces')->where('id', $workspaceId)->first();
if (!$workspace) {
    echo "❌ ERROR: Demo workspace not found. Run the demo seeder first.\n";
    exit(1);
}
echo "✓ Workspace found: {$workspace->name}\n\n";

// ── 2. Verify approval tables exist ────────────────────

$requiredTables = ['approval_workflows', 'approval_workflow_steps', 'approval_requests', 'approval_request_steps', 'approval_decisions'];
foreach ($requiredTables as $table) {
    if (!DB::getSchemaBuilder()->hasTable($table)) {
        echo "❌ ERROR: Table '{$table}' not found. Run migration 037_approval_engine first.\n";
        exit(1);
    }
}
echo "✓ All approval tables present\n\n";

// ── 3. Seed "High Commission Approval" workflow ────────

$workflowKey = 'high_commission_approval';

$existing = DB::table('approval_workflows')
    ->where('workspace_id', $workspaceId)
    ->where('workflow_key', $workflowKey)
    ->first();

DB::beginTransaction();
try {
    if ($existing) {
        echo "ℹ Workflow '{$workflowKey}' already exists (id: {$existing->id})\n";
        echo "  Updating to canonical state...\n";

        DB::table('approval_workflows')
            ->where('id', $existing->id)
            ->update([
                'name'               => 'High Commission Approval',
                'description'        => 'Requires manager approval for commission entries exceeding the configured threshold.',
                'entity_type'        => 'commission_entry',
                'trigger_conditions' => json_encode([
                    'logic' => 'and',
                    'conditions' => [
                        ['field' => 'amount', 'operator' => 'greater_than_or_equal', 'value' => 500],
                        ['field' => 'currency', 'operator' => 'equals', 'value' => 'SAR'],
                    ],
                ]),
                'is_active'          => true,
                'sort_order'         => 0,
                'updated_at'         => now(),
            ]);

        $workflowId = $existing->id;
    } else {
        $workflowId = Str::uuid()->toString();

        // Find the Owner membership for created_by (via role assignment)
        $ownerRole = DB::table('roles')
            ->where('workspace_id', $workspaceId)
            ->where('role_key', 'owner')
            ->first();

        $ownerMembership = null;
        if ($ownerRole) {
            $ownerMr = DB::table('membership_roles')
                ->where('workspace_id', $workspaceId)
                ->where('role_id', $ownerRole->id)
                ->first();
            if ($ownerMr) {
                $ownerMembership = DB::table('workspace_memberships')
                    ->where('id', $ownerMr->membership_id)
                    ->first();
            }
        }

        DB::table('approval_workflows')->insert([
            'id'                 => $workflowId,
            'workspace_id'       => $workspaceId,
            'workflow_key'       => $workflowKey,
            'name'               => 'High Commission Approval',
            'description'        => 'Requires manager approval for commission entries exceeding the configured threshold.',
            'entity_type'        => 'commission_entry',
            'trigger_conditions' => json_encode([
                'logic' => 'and',
                'conditions' => [
                    ['field' => 'amount', 'operator' => 'greater_than_or_equal', 'value' => 500],
                    ['field' => 'currency', 'operator' => 'equals', 'value' => 'SAR'],
                ],
            ]),
            'is_active'          => true,
            'sort_order'         => 0,
            'created_by'         => $ownerMembership?->id,
            'created_at'         => now(),
            'updated_at'         => now(),
        ]);

        echo "✓ Created workflow '{$workflowKey}' (id: {$workflowId})\n";
    }

    // ── 3b. Seed workflow steps ──────────────────────────

    // Delete existing steps for idempotency
    $deletedSteps = DB::table('approval_workflow_steps')
        ->where('workflow_id', $workflowId)
        ->delete();
    if ($deletedSteps > 0) {
        echo "  Cleared {$deletedSteps} existing steps\n";
    }

    // Step 1: Manager Review (permission-based)
    $step1Id = Str::uuid()->toString();
    DB::table('approval_workflow_steps')->insert([
        'id'                      => $step1Id,
        'workspace_id'            => $workspaceId,
        'workflow_id'             => $workflowId,
        'name'                    => 'Manager Review',
        'step_order'              => 1,
        'approver_type'           => 'permission',
        'approver_permission_key' => 'commissions.approve',
        'approver_membership_id'  => null,
        'conditions'              => json_encode([]),
        'allow_self_approval'     => false,
        'is_active'               => true,
        'created_at'              => now(),
        'updated_at'              => now(),
    ]);
    echo "  ✓ Step 1: Manager Review (requires commissions.approve permission)\n";

    // Step 2: Finance Approval (permission-based)
    $step2Id = Str::uuid()->toString();
    DB::table('approval_workflow_steps')->insert([
        'id'                      => $step2Id,
        'workspace_id'            => $workspaceId,
        'workflow_id'             => $workflowId,
        'name'                    => 'Finance Approval',
        'step_order'              => 2,
        'approver_type'           => 'permission',
        'approver_permission_key' => 'approvals.decide',
        'approver_membership_id'  => null,
        'conditions'              => json_encode([]),
        'allow_self_approval'     => false,
        'is_active'               => true,
        'created_at'              => now(),
        'updated_at'              => now(),
    ]);
    echo "  ✓ Step 2: Finance Approval (requires approvals.decide permission)\n";

    echo "\n";

    // ── 4. Ensure demo roles have approval permissions ──

    echo "── ROLE PERMISSION SYNC ──────────────────────────\n\n";

    // Define which approval perms each role should have
    $rolePermAdditions = [
        'owner' => [
            'approvals.list', 'approvals.show', 'approvals.request',
            'approvals.decide', 'approvals.manage', 'approvals.cancel',
            'commissions.approve',
        ],
        'sales_manager' => [
            'approvals.list', 'approvals.show', 'approvals.request',
            'approvals.decide', 'approvals.cancel',
            'commissions.approve',
        ],
        'sales_agent' => [
            'approvals.list', 'approvals.show', 'approvals.request',
        ],
    ];

    foreach ($rolePermAdditions as $roleKey => $permsToAdd) {
        $role = DB::table('roles')
            ->where('workspace_id', $workspaceId)
            ->where('role_key', $roleKey)
            ->first();

        if (!$role) {
            echo "  SKIP: Role '{$roleKey}' not found\n";
            continue;
        }

        $currentPerms = json_decode($role->permissions, true) ?? [];
        $newPerms = array_values(array_unique(array_merge($currentPerms, $permsToAdd)));

        $added = array_diff($newPerms, $currentPerms);

        DB::table('roles')
            ->where('id', $role->id)
            ->update([
                'permissions' => json_encode($newPerms),
                'updated_at'  => now(),
            ]);

        echo "  ✓ {$roleKey}: " . count($currentPerms) . " → " . count($newPerms) . " permissions\n";
        if (!empty($added)) {
            echo "    Added: " . implode(', ', $added) . "\n";
        } else {
            echo "    No new permissions needed\n";
        }
    }

    DB::commit();
    echo "\n── TRANSACTION COMMITTED ─────────────────────────\n\n";

} catch (\Exception $e) {
    DB::rollBack();
    echo "❌ TRANSACTION ROLLED BACK: " . $e->getMessage() . "\n";
    echo $e->getTraceAsString() . "\n";
    exit(1);
}

// ── 5. Post-sync verification ───────────────────────────

echo "── VERIFICATION ─────────────────────────────────\n\n";

$wf = DB::table('approval_workflows')
    ->where('workspace_id', $workspaceId)
    ->where('workflow_key', $workflowKey)
    ->first();

if ($wf) {
    echo "  Workflow: {$wf->name}\n";
    echo "  Entity type: {$wf->entity_type}\n";
    echo "  Active: " . ($wf->is_active ? 'yes ✓' : 'no ⚠️') . "\n";
    echo "  Trigger: " . $wf->trigger_conditions . "\n";

    $steps = DB::table('approval_workflow_steps')
        ->where('workflow_id', $wf->id)
        ->orderBy('step_order')
        ->get();

    echo "  Steps (" . count($steps) . "):\n";
    foreach ($steps as $s) {
        echo "    [{$s->step_order}] {$s->name} — {$s->approver_type}";
        if ($s->approver_permission_key) {
            echo " ({$s->approver_permission_key})";
        }
        echo " — self_approval: " . ($s->allow_self_approval ? 'yes' : 'no');
        echo " — active: " . ($s->is_active ? 'yes' : 'no') . "\n";
    }
} else {
    echo "  ⚠️ Workflow not found after sync!\n";
}

// Verify role permissions
echo "\n  Role permissions:\n";
foreach (['owner', 'sales_manager', 'sales_agent'] as $rk) {
    $r = DB::table('roles')
        ->where('workspace_id', $workspaceId)
        ->where('role_key', $rk)
        ->first();
    if ($r) {
        $perms = json_decode($r->permissions, true) ?? [];
        $approvalPerms = array_filter($perms, fn($p) => str_starts_with($p, 'approvals.') || $p === 'commissions.approve');
        echo "    {$rk}: " . implode(', ', $approvalPerms) . "\n";
    }
}

echo "\n✅ Done. Approval workflow is ready for use.\n";
