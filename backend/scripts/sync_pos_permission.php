<?php
/**
 * Idempotent script: Replaces "pos.access" → "pos.view" in all role
 * permission JSON blobs for the demo workspace.
 *
 * Safe to run multiple times — only modifies roles that still contain
 * the deprecated key. Does NOT touch operational data (invoices, orders, etc.).
 *
 * Usage:
 *   cd /path/to/smartbiz_ai/backend
 *   php scripts/sync_pos_permission.php
 */

require_once __DIR__ . '/../vendor/autoload.php';

$app = require_once __DIR__ . '/../bootstrap/app.php';
$app->make(\Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use Illuminate\Support\Facades\DB;

$demoWorkspaceId = 'dd000000-0000-0000-0000-000000000001';
$oldKey = 'pos.access';
$newKey = 'pos.view';

echo "=== SmartBiz POS Permission Sync ===\n";
echo "Workspace: {$demoWorkspaceId}\n";
echo "Migration: {$oldKey} → {$newKey}\n\n";

// 1. Update roles table — JSON permission blobs
$roles = DB::table('roles')
    ->where('workspace_id', $demoWorkspaceId)
    ->get(['id', 'name', 'role_key', 'permissions']);

$updated = 0;
foreach ($roles as $role) {
    $perms = json_decode($role->permissions, true);
    if (!is_array($perms)) continue;

    $idx = array_search($oldKey, $perms);
    if ($idx === false) continue;

    // Replace the old key with the new one (if new key not already present)
    if (!in_array($newKey, $perms)) {
        $perms[$idx] = $newKey;
    } else {
        // New key already exists, just remove the old one
        unset($perms[$idx]);
        $perms = array_values($perms);
    }

    DB::table('roles')
        ->where('id', $role->id)
        ->update(['permissions' => json_encode(array_values($perms))]);

    echo "  ✓ Updated role: {$role->name} ({$role->role_key})\n";
    $updated++;
}

echo "\n--- Results ---\n";
echo "Roles scanned: " . $roles->count() . "\n";
echo "Roles updated: {$updated}\n";

// 2. Update permission_definitions table (if exists)
if (\Illuminate\Support\Facades\Schema::hasTable('permission_definitions')) {
    $pdUpdated = DB::table('permission_definitions')
        ->where('key', $oldKey)
        ->update(['key' => $newKey, 'action' => 'view']);
    echo "Permission definitions updated: {$pdUpdated}\n";
}

echo "\n✅ Done. No operational data was modified.\n";
