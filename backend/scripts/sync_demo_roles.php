<?php
/**
 * SmartBiz AI — Idempotent Demo Role Synchronization
 *
 * Synchronizes the demo workspace roles (owner, sales_manager, inventory_manager)
 * to their canonical permission sets derived from PermissionCatalog and
 * SmartBizDemoSeeder.
 *
 * Also upserts missing permission_definitions from PermissionCatalog and
 * migrates the obsolete pos.access → pos.view.
 *
 * Safe to run multiple times. Does NOT modify operational data.
 *
 * Usage:
 *   php scripts/sync_demo_roles.php
 */

require_once __DIR__ . '/../vendor/autoload.php';

$app = require_once __DIR__ . '/../bootstrap/app.php';
$app->make(\Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use App\Services\PermissionCatalog;

$workspaceId = 'dd000000-0000-0000-0000-000000000001';

echo "════════════════════════════════════════════════════\n";
echo "  SmartBiz AI — Demo Role Synchronization\n";
echo "  Workspace: {$workspaceId}\n";
echo "════════════════════════════════════════════════════\n\n";

// ── 1. Build canonical permission sets ──────────────────

$allKeys = PermissionCatalog::allKeys();

// Exact Sales Manager mapping from SmartBizDemoSeeder::seedRoles() + enforceRolePermissions()
$salesMgrPerms = [
    "contacts.list","contacts.show","contacts.create","contacts.update","contacts.delete",
    "contacts.own","contacts.manage_team","contacts.assign",
    "products.list","products.show",
    "invoices.list","invoices.show","invoices.create","invoices.update",
    "orders.list","orders.show","orders.create","orders.update",
    "notifications.list","notifications.update",
    "pipelines.list","pipelines.manage",
    "pipeline_records.create","pipeline_records.update","pipeline_records.delete",
    "pipeline_records.own","pipeline_records.manage_team","pipeline_records.assign",
    "commissions.list","commissions.view_team",
];

// Exact Inventory Manager mapping from SmartBizDemoSeeder
// = $wh + ["categories.list","categories.show"]
$invMgrPerms = [
    "warehouses.list","warehouses.show","warehouses.create","warehouses.update","warehouses.delete",
    "inventory.list","inventory.show","inventory.create",
    "reservations.list","reservations.show","reservations.create","reservations.update",
    "products.list","products.show",
    "notifications.list","notifications.update",
    "categories.list","categories.show",
];

$targetRoles = [
    'owner'             => array_values(array_unique($allKeys)),
    'sales_manager'     => array_values(array_unique($salesMgrPerms)),
    'inventory_manager' => array_values(array_unique($invMgrPerms)),
];

// ── 2. Read current state ───────────────────────────────

echo "── BEFORE STATE ──────────────────────────────────\n\n";

$roles = DB::table('roles')
    ->where('workspace_id', $workspaceId)
    ->whereIn('role_key', array_keys($targetRoles))
    ->get(['id', 'name', 'role_key', 'permissions']);

if ($roles->isEmpty()) {
    echo "ERROR: No matching roles found in workspace {$workspaceId}.\n";
    echo "Are you sure the demo seeder has been run?\n";
    exit(1);
}

$beforeState = [];
foreach ($roles as $role) {
    $perms = json_decode($role->permissions, true) ?? [];
    $beforeState[$role->role_key] = [
        'id'    => $role->id,
        'name'  => $role->name,
        'count' => count($perms),
        'perms' => $perms,
    ];
    echo "  {$role->role_key} ({$role->name})\n";
    echo "    Permission count: " . count($perms) . "\n";
    echo "    Has pos.access: " . (in_array('pos.access', $perms) ? 'YES ⚠️' : 'no') . "\n";
    echo "    Has pos.view: " . (in_array('pos.view', $perms) ? 'yes' : 'NO') . "\n";
    echo "    Permissions: " . json_encode($perms) . "\n\n";
}

// ── 3. Update roles inside a transaction ────────────────

echo "── SYNCHRONIZING ─────────────────────────────────\n\n";

DB::beginTransaction();
try {
    foreach ($targetRoles as $roleKey => $newPerms) {
        if (!isset($beforeState[$roleKey])) {
            echo "  SKIP: {$roleKey} — role not found in database\n";
            continue;
        }

        $roleId = $beforeState[$roleKey]['id'];
        $oldPerms = $beforeState[$roleKey]['perms'];
        $newPermsUnique = array_values(array_unique($newPerms));

        DB::table('roles')
            ->where('id', $roleId)
            ->update([
                'permissions' => json_encode($newPermsUnique),
                'updated_at'  => now(),
            ]);

        // Calculate diffs
        $added   = array_values(array_diff($newPermsUnique, $oldPerms));
        $removed = array_values(array_diff($oldPerms, $newPermsUnique));

        echo "  ✓ {$roleKey}\n";
        echo "    Before: " . count($oldPerms) . " → After: " . count($newPermsUnique) . "\n";
        if (!empty($added)) {
            echo "    Added (" . count($added) . "): " . implode(', ', $added) . "\n";
        } else {
            echo "    Added: (none)\n";
        }
        if (!empty($removed)) {
            echo "    Removed (" . count($removed) . "): " . implode(', ', $removed) . "\n";
        } else {
            echo "    Removed: (none)\n";
        }
        echo "\n";
    }

    // ── 4. Upsert permission_definitions ────────────────

    if (Schema::hasTable('permission_definitions')) {
        echo "── PERMISSION DEFINITIONS ────────────────────────\n\n";

        // Remove obsolete pos.access if still present
        $deleted = DB::table('permission_definitions')
            ->where('key', 'pos.access')
            ->delete();
        if ($deleted > 0) {
            echo "  ✓ Removed obsolete pos.access definition\n";
        }

        // Upsert all catalog keys
        $catalogKeys = PermissionCatalog::allKeys();
        $existingKeys = DB::table('permission_definitions')
            ->pluck('key')
            ->toArray();
        $missing = array_diff($catalogKeys, $existingKeys);

        if (!empty($missing)) {
            echo "  Inserting " . count($missing) . " missing definitions:\n";
            foreach ($missing as $key) {
                // Derive module/entity/action from key
                $parts = explode('.', $key);
                $entity = $parts[0] ?? $key;
                $action = $parts[1] ?? 'view';
                // Handle nested keys like commissions.settings.view
                if (count($parts) === 3) {
                    $entity = $parts[0] . '_' . $parts[1];
                    $action = $parts[2];
                }

                DB::table('permission_definitions')->insertOrIgnore([
                    'key'              => $key,
                    'module'           => $entity,
                    'entity'           => $entity,
                    'action'           => $action,
                    'scope_type'       => 'workspace',
                    'applicable_scopes'=> '{"workspace"}',
                    'created_at'       => now(),
                ]);
                echo "    + {$key}\n";
            }
        } else {
            echo "  All " . count($catalogKeys) . " definitions present.\n";
        }
        echo "\n";
    }

    DB::commit();
    echo "── TRANSACTION COMMITTED ─────────────────────────\n\n";
} catch (\Exception $e) {
    DB::rollBack();
    echo "❌ TRANSACTION ROLLED BACK: " . $e->getMessage() . "\n";
    exit(1);
}

// ── 5. Post-sync verification ───────────────────────────

echo "── AFTER STATE (VERIFICATION) ────────────────────\n\n";

$rolesAfter = DB::table('roles')
    ->where('workspace_id', $workspaceId)
    ->whereIn('role_key', array_keys($targetRoles))
    ->get(['id', 'name', 'role_key', 'permissions']);

foreach ($rolesAfter as $role) {
    $perms = json_decode($role->permissions, true) ?? [];
    $oldCount = $beforeState[$role->role_key]['count'] ?? '?';

    echo "  {$role->role_key} ({$role->name})\n";
    echo "    Count: {$oldCount} → " . count($perms) . "\n";
    echo "    Has pos.access: " . (in_array('pos.access', $perms) ? 'YES ⚠️ PROBLEM' : 'no ✓') . "\n";
    echo "    Has pos.view: " . (in_array('pos.view', $perms) ? 'yes ✓' : 'MISSING ⚠️') . "\n";

    if ($role->role_key === 'owner') {
        $catalogKeys = PermissionCatalog::allKeys();
        $missing = array_diff($catalogKeys, $perms);
        $extra = array_diff($perms, $catalogKeys);
        echo "    Catalog match: " . (empty($missing) && empty($extra) ? 'EXACT ✓' : 'MISMATCH ⚠️') . "\n";
        if (!empty($missing)) {
            echo "    Missing from catalog: " . implode(', ', $missing) . "\n";
        }
        if (!empty($extra)) {
            echo "    Extra (not in catalog): " . implode(', ', $extra) . "\n";
        }
    }
    if ($role->role_key === 'sales_manager') {
        echo "    Has commissions.list: " . (in_array('commissions.list', $perms) ? 'yes ✓' : 'no') . "\n";
        echo "    Has commissions.view_team: " . (in_array('commissions.view_team', $perms) ? 'yes ✓' : 'no') . "\n";
        $noFinance = !in_array('accounting.view', $perms) && !in_array('payments.list', $perms);
        echo "    Finance isolation: " . ($noFinance ? 'clean ✓' : 'LEAKING ⚠️') . "\n";
    }
    if ($role->role_key === 'inventory_manager') {
        $noCommissions = !in_array('commissions.list', $perms) && !in_array('commissions.view_team', $perms);
        $noFinance = !in_array('accounting.view', $perms) && !in_array('payments.list', $perms);
        $noHr = !in_array('employees.list', $perms) && !in_array('roles.list', $perms);
        echo "    Commission isolation: " . ($noCommissions ? 'clean ✓' : 'LEAKING ⚠️') . "\n";
        echo "    Finance isolation: " . ($noFinance ? 'clean ✓' : 'LEAKING ⚠️') . "\n";
        echo "    HR isolation: " . ($noHr ? 'clean ✓' : 'LEAKING ⚠️') . "\n";
    }
    echo "    Permissions: " . json_encode($perms) . "\n\n";
}

echo "✅ Done. No operational data was modified.\n";
