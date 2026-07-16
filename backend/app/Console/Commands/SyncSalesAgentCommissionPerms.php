<?php

namespace App\Console\Commands;

use App\Models\Role;
use Illuminate\Console\Command;

/**
 * Idempotent sync: add commissions.view_own to sales_agent roles.
 *
 * Safe to run multiple times — second run makes zero changes.
 */
class SyncSalesAgentCommissionPerms extends Command
{
    protected $signature = 'smartbiz:sync-sales-agent-commission-perms
                            {--workspace= : Workspace UUID (defaults to demo workspace)}';

    protected $description = 'Add commissions.view_own to sales_agent roles (idempotent)';

    private const DEMO_WS = 'dd000000-0000-0000-0000-000000000001';

    /** Permissions to add to the target roles. */
    private const PERMS_TO_ADD = ['commissions.view_own'];

    /** Role keys to update. */
    private const TARGET_ROLES = [
        'sales_agent',
        'vehicle_sales_agent',
        'spare_parts_sales_agent',
    ];

    public function handle(): int
    {
        $wsId = $this->option('workspace') ?: self::DEMO_WS;
        $this->info("Workspace: {$wsId}");
        $this->line('');

        $roles = Role::where('workspace_id', $wsId)
            ->whereIn('role_key', self::TARGET_ROLES)
            ->get();

        if ($roles->isEmpty()) {
            $this->warn('No matching roles found.');
            return 0;
        }

        $anyChanged = false;

        foreach ($roles as $role) {
            $current = $role->permissions ?? [];
            if (is_string($current)) {
                $current = json_decode($current, true) ?: [];
            }

            $this->info("── {$role->role_key} ──");
            $this->line('  BEFORE: ' . json_encode(array_values($current)));

            $added = [];
            $newPerms = $current;

            foreach (self::PERMS_TO_ADD as $perm) {
                if (!in_array($perm, $newPerms, true)) {
                    $newPerms[] = $perm;
                    $added[] = $perm;
                }
            }

            $removed = []; // We don't remove anything.

            if (empty($added)) {
                $this->line('  ADDED:   (none)');
                $this->line('  REMOVED: (none)');
                $this->line('  AFTER:  ' . json_encode(array_values($newPerms)));
                $this->line('  → No changes needed.');
            } else {
                $anyChanged = true;
                $role->permissions = array_values(array_unique($newPerms));
                $role->save();

                $this->line('  ADDED:   ' . json_encode($added));
                $this->line('  REMOVED: ' . json_encode($removed));
                $this->line('  AFTER:  ' . json_encode(array_values($role->permissions)));
                $this->line('  → Updated.');
            }

            $this->line('');
        }

        if (!$anyChanged) {
            $this->info('✓ All roles already up-to-date. No changes made.');
        } else {
            $this->info('✓ Sync complete.');
        }

        return 0;
    }
}
