<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/**
 * Step 59.3 Part 4 — Non-destructive commission permission sync.
 *
 * Upserts the 9 commissions.* permission definitions into the
 * permission_definitions table and syncs exactly the intended
 * commission permissions for each role_key in a given workspace.
 *
 * - Preserves all non-commission permissions on every role
 * - Never deletes roles, users, memberships, contacts, deals, etc.
 * - Runs inside a DB transaction
 * - Idempotent — safe to run more than once
 *
 * Usage:
 *   php artisan smartbiz:sync-commission-permissions --workspace=<uuid>
 *   php artisan smartbiz:sync-commission-permissions --workspace=<uuid> --dry-run
 */
class SyncCommissionPermissionsCommand extends Command
{
    protected $signature = 'smartbiz:sync-commission-permissions
        {--workspace= : Required. Workspace UUID to sync permissions for}
        {--dry-run : Preview changes without writing to the database}';

    protected $description = 'Non-destructive sync of commissions.* permissions for workspace roles.';

    /**
     * The 7 canonical commission permission keys.
     */
    private const COMMISSION_KEYS = [
        'commissions.list',
        'commissions.view_all',
        'commissions.view_team',
        'commissions.calculate',
        'commissions.approve',
        'commissions.pay',
        'commissions.cancel',
        'commissions.settings.view',
        'commissions.settings.manage',
    ];

    /**
     * Permission definitions to upsert (module/entity/action metadata).
     */
    private const PERMISSION_DEFINITIONS = [
        ['key' => 'commissions.list',            'module' => 'crm', 'entity' => 'commission_entries',  'action' => 'list',      'scope_type' => 'workspace'],
        ['key' => 'commissions.view_all',        'module' => 'crm', 'entity' => 'commission_entries',  'action' => 'view_all',  'scope_type' => 'workspace'],
        ['key' => 'commissions.view_team',       'module' => 'crm', 'entity' => 'commission_entries',  'action' => 'view_team', 'scope_type' => 'workspace'],
        ['key' => 'commissions.calculate',       'module' => 'crm', 'entity' => 'commission_entries',  'action' => 'calculate', 'scope_type' => 'workspace'],
        ['key' => 'commissions.approve',         'module' => 'crm', 'entity' => 'commission_entries',  'action' => 'approve',   'scope_type' => 'workspace'],
        ['key' => 'commissions.pay',             'module' => 'crm', 'entity' => 'commission_entries',  'action' => 'pay',       'scope_type' => 'workspace'],
        ['key' => 'commissions.cancel',          'module' => 'crm', 'entity' => 'commission_entries',  'action' => 'cancel',    'scope_type' => 'workspace'],
        ['key' => 'commissions.settings.view',   'module' => 'crm', 'entity' => 'commission_settings', 'action' => 'view',      'scope_type' => 'workspace'],
        ['key' => 'commissions.settings.manage', 'module' => 'crm', 'entity' => 'commission_settings', 'action' => 'manage',    'scope_type' => 'workspace'],
    ];

    /**
     * Authoritative commission permission mapping by role_key.
     *
     * Roles NOT listed here receive zero commission permissions.
     * Any existing commissions.* keys on unlisted roles are removed.
     */
    private const ROLE_COMMISSION_MAP = [
        // Full access — Owner / Admin / General Manager
        'owner'           => ['commissions.list', 'commissions.view_team', 'commissions.view_all', 'commissions.calculate', 'commissions.approve', 'commissions.pay', 'commissions.cancel', 'commissions.settings.view', 'commissions.settings.manage'],
        'admin'           => ['commissions.list', 'commissions.view_team', 'commissions.view_all', 'commissions.calculate', 'commissions.approve', 'commissions.pay', 'commissions.cancel', 'commissions.settings.view', 'commissions.settings.manage'],
        'general_manager' => ['commissions.list', 'commissions.view_team', 'commissions.view_all', 'commissions.calculate', 'commissions.approve', 'commissions.pay', 'commissions.cancel', 'commissions.settings.view', 'commissions.settings.manage'],

        // Accountant — financial lifecycle + settings access
        'accountant'      => ['commissions.list', 'commissions.view_all', 'commissions.calculate', 'commissions.approve', 'commissions.pay', 'commissions.cancel', 'commissions.settings.view', 'commissions.settings.manage'],

        // Sales Manager — oversight only (no calculate/approve/pay/cancel, no settings)
        'sales_manager'   => ['commissions.list', 'commissions.view_team'],

        // Sales Agents — own commissions only (no settings)
        'sales_agent'              => ['commissions.list'],
        'vehicle_sales_agent'      => ['commissions.list'],
        'spare_parts_sales_agent'  => ['commissions.list'],
    ];

    public function handle(): int
    {
        $wsId = $this->option('workspace');
        $dryRun = $this->option('dry-run');

        // ── Validate workspace ───────────────────────────────────
        if (!$wsId) {
            $this->error('❌ --workspace is required. Usage: php artisan smartbiz:sync-commission-permissions --workspace=<uuid>');
            return self::FAILURE;
        }

        if (!preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i', $wsId)) {
            $this->error("❌ Invalid workspace UUID: {$wsId}");
            return self::FAILURE;
        }

        $workspace = DB::table('workspaces')->where('id', $wsId)->first();
        if (!$workspace) {
            $this->error("❌ Workspace not found: {$wsId}");
            return self::FAILURE;
        }

        $mode = $dryRun ? '🔍 DRY RUN' : '🔧 LIVE';
        $this->info('');
        $this->info("╔══════════════════════════════════════════════════╗");
        $this->info("║  {$mode} — Commission Permission Sync");
        $this->info("║  Workspace: {$workspace->name}");
        $this->info("║  ID: {$wsId}");
        $this->info("╚══════════════════════════════════════════════════╝");
        $this->info('');

        // ── Load all workspace roles ─────────────────────────────
        $roles = DB::table('roles')
            ->where('workspace_id', $wsId)
            ->where('is_active', true)
            ->orderBy('hierarchy_level')
            ->get();

        if ($roles->isEmpty()) {
            $this->warn('No active roles found in this workspace.');
            return self::SUCCESS;
        }

        // ── Execute ──────────────────────────────────────────────
        $changes = [];

        $execute = function () use ($roles, $wsId, &$changes) {
            // Phase 1: Upsert permission definitions
            $this->upsertPermissionDefinitions();

            // Phase 2: Sync role permissions
            foreach ($roles as $role) {
                $change = $this->syncRole($role);
                if ($change) {
                    $changes[] = $change;
                }
            }
        };

        if ($dryRun) {
            // Dry run: compute changes but don't write
            $this->upsertPermissionDefinitions(true);
            foreach ($roles as $role) {
                $change = $this->computeRoleChanges($role);
                if ($change) {
                    $changes[] = $change;
                }
            }
        } else {
            DB::transaction($execute);
        }

        // ── Print summary ────────────────────────────────────────
        $this->info('');
        $this->info('═══ Per-Role Summary ═══');
        $this->info('');

        $tableRows = [];
        foreach ($roles as $role) {
            $currentPerms = $this->extractCommissionKeys(json_decode($role->permissions, true) ?? []);
            $intended = self::ROLE_COMMISSION_MAP[$role->role_key] ?? [];

            $change = collect($changes)->firstWhere('role_key', $role->role_key);

            $tableRows[] = [
                $role->role_key,
                implode(', ', $currentPerms) ?: '(none)',
                implode(', ', $intended) ?: '(none)',
                $change ? $change['status'] : ($currentPerms === $intended ? '✅ OK' : '—'),
            ];
        }

        $this->table(['Role Key', 'Before (commissions.*)', 'After (commissions.*)', 'Status'], $tableRows);

        if ($dryRun) {
            $this->warn('');
            $this->warn('DRY RUN — no changes were written. Remove --dry-run to apply.');
        } else {
            $rolesChanged = count(array_filter($changes, fn ($c) => $c['status'] !== '✅ OK'));
            $this->info('');
            $this->info("✅ Sync complete. {$rolesChanged} role(s) updated.");
        }

        return self::SUCCESS;
    }

    /**
     * Upsert the 7 commission permission definitions.
     */
    private function upsertPermissionDefinitions(bool $dryRun = false): void
    {
        $inserted = 0;
        $existed  = 0;

        foreach (self::PERMISSION_DEFINITIONS as $def) {
            $exists = DB::table('permission_definitions')->where('key', $def['key'])->exists();

            if ($exists) {
                $existed++;
            } else {
                $inserted++;
                if (!$dryRun) {
                    DB::table('permission_definitions')->insert(array_merge($def, [
                        'applicable_scopes' => '{"workspace"}',
                        'created_at' => now(),
                    ]));
                }
            }
        }

        $label = $dryRun ? '[DRY RUN] ' : '';
        $this->line("{$label}Permission definitions: {$existed} existing, {$inserted} " . ($dryRun ? 'would be inserted' : 'inserted') . '.');
    }

    /**
     * Sync a single role's commission permissions (live write).
     */
    private function syncRole(object $role): ?array
    {
        $currentPerms = json_decode($role->permissions, true) ?? [];
        $currentCommission = $this->extractCommissionKeys($currentPerms);
        $intended = self::ROLE_COMMISSION_MAP[$role->role_key] ?? [];

        sort($currentCommission);
        $sortedIntended = $intended;
        sort($sortedIntended);

        if ($currentCommission === $sortedIntended) {
            return ['role_key' => $role->role_key, 'status' => '✅ OK'];
        }

        // Strip all commissions.* and re-add the intended set
        $nonCommission = array_values(array_filter($currentPerms, fn ($p) => !str_starts_with($p, 'commissions.')));
        $newPerms = array_values(array_unique(array_merge($nonCommission, $intended)));

        DB::table('roles')
            ->where('id', $role->id)
            ->update([
                'permissions' => json_encode($newPerms),
                'updated_at'  => now(),
            ]);

        $removed = array_values(array_diff($currentCommission, $intended));
        $added   = array_values(array_diff($intended, $currentCommission));

        return [
            'role_key' => $role->role_key,
            'status'   => '🔄 Updated',
            'removed'  => $removed,
            'added'    => $added,
        ];
    }

    /**
     * Compute what changes would be made (dry-run mode).
     */
    private function computeRoleChanges(object $role): ?array
    {
        $currentPerms = json_decode($role->permissions, true) ?? [];
        $currentCommission = $this->extractCommissionKeys($currentPerms);
        $intended = self::ROLE_COMMISSION_MAP[$role->role_key] ?? [];

        sort($currentCommission);
        $sortedIntended = $intended;
        sort($sortedIntended);

        if ($currentCommission === $sortedIntended) {
            return ['role_key' => $role->role_key, 'status' => '✅ OK'];
        }

        $removed = array_values(array_diff($currentCommission, $intended));
        $added   = array_values(array_diff($intended, $currentCommission));

        return [
            'role_key' => $role->role_key,
            'status'   => '🔄 Would update',
            'removed'  => $removed,
            'added'    => $added,
        ];
    }

    /**
     * Extract only commissions.* keys from a permission array.
     */
    private function extractCommissionKeys(array $perms): array
    {
        return array_values(array_filter($perms, fn ($p) => str_starts_with($p, 'commissions.')));
    }
}
