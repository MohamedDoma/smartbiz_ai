<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /** @var array<int, array<string, string>> */
    private const DEFINITIONS = [
        ['key' => 'ai.chat', 'module' => 'ai', 'entity' => 'ai_chat', 'action' => 'chat'],
        ['key' => 'ai.actions', 'module' => 'ai', 'entity' => 'ai_actions', 'action' => 'confirm'],
        ['key' => 'ai.insights.view', 'module' => 'ai', 'entity' => 'ai_insights', 'action' => 'view'],
        ['key' => 'ai.insights.manage', 'module' => 'ai', 'entity' => 'ai_insights', 'action' => 'manage'],
        ['key' => 'ai.manage', 'module' => 'ai', 'entity' => 'ai', 'action' => 'manage'],
        ['key' => 'ai_advisor.manage', 'module' => 'ai', 'entity' => 'ai_advisor', 'action' => 'manage'],
        ['key' => 'finance.view', 'module' => 'finance', 'entity' => 'finance_operations', 'action' => 'view'],
        ['key' => 'finance.manage', 'module' => 'finance', 'entity' => 'finance_operations', 'action' => 'manage'],
        ['key' => 'finance.post', 'module' => 'finance', 'entity' => 'finance_operations', 'action' => 'post'],
        ['key' => 'document_checklists.view', 'module' => 'crm', 'entity' => 'document_checklists', 'action' => 'view'],
        ['key' => 'document_checklists.manage', 'module' => 'crm', 'entity' => 'document_checklists', 'action' => 'manage'],
        ['key' => 'ownership.view', 'module' => 'crm', 'entity' => 'ownership_assignments', 'action' => 'view'],
        ['key' => 'ownership.manage', 'module' => 'crm', 'entity' => 'ownership_assignments', 'action' => 'manage'],
        ['key' => 'duplicates.view', 'module' => 'crm', 'entity' => 'duplicates', 'action' => 'view'],
        ['key' => 'duplicates.check', 'module' => 'crm', 'entity' => 'duplicates', 'action' => 'check'],
        ['key' => 'duplicates.manage', 'module' => 'crm', 'entity' => 'duplicates', 'action' => 'manage'],
        ['key' => 'duplicates.resolve', 'module' => 'crm', 'entity' => 'duplicates', 'action' => 'resolve'],
        ['key' => 'reports.run', 'module' => 'reports', 'entity' => 'reports', 'action' => 'run'],
        ['key' => 'reports.manage', 'module' => 'reports', 'entity' => 'reports', 'action' => 'manage'],
        ['key' => 'billing.manual_payment', 'module' => 'billing', 'entity' => 'manual_payments', 'action' => 'create'],
    ];

    public function up(): void
    {
        $this->seedPermissionDefinitions();
        $this->backfillRolePermissions();
    }

    public function down(): void
    {
        $keys = array_column(self::DEFINITIONS, 'key');

        if (Schema::hasTable('roles')) {
            DB::table('roles')->chunkById(100, function ($roles) use ($keys): void {
                foreach ($roles as $role) {
                    $permissions = $this->decodePermissions($role->permissions ?? null);
                    $filtered = array_values(array_diff($permissions, $keys));

                    if ($filtered !== $permissions) {
                        DB::table('roles')->where('id', $role->id)->update([
                            'permissions' => json_encode($filtered),
                            'updated_at' => now(),
                        ]);
                    }
                }
            });
        }

        if (Schema::hasTable('permission_definitions')) {
            DB::table('permission_definitions')->whereIn('key', $keys)->delete();
        }
    }

    private function seedPermissionDefinitions(): void
    {
        if (! Schema::hasTable('permission_definitions')) {
            return;
        }

        foreach (self::DEFINITIONS as $definition) {
            DB::table('permission_definitions')->insertOrIgnore(array_merge($definition, [
                'scope_type' => 'workspace',
                'applicable_scopes' => '{"workspace"}',
                'created_at' => now(),
            ]));
        }
    }

    private function backfillRolePermissions(): void
    {
        if (! Schema::hasTable('roles')) {
            return;
        }

        DB::table('roles')->chunkById(100, function ($roles): void {
            foreach ($roles as $role) {
                $permissions = $this->decodePermissions($role->permissions ?? null);

                // A truly empty role remains empty. This preserves explicit no-access roles.
                if ($permissions === []) {
                    continue;
                }

                $grant = ['ai.chat', 'ai.actions', 'ai.insights.view'];

                if ($this->hasAny($permissions, ['ai_advisor.view'])) {
                    $grant[] = 'ai_advisor.manage';
                    $grant[] = 'ai.insights.manage';
                }

                if ($this->hasAny($permissions, ['settings.manage'])) {
                    array_push(
                        $grant,
                        'ai.manage',
                        'ai.insights.manage',
                        'reports.manage',
                        'document_checklists.manage',
                        'ownership.manage',
                        'duplicates.manage',
                        'duplicates.resolve',
                        'billing.manual_payment',
                    );
                }

                if ($this->hasAny($permissions, ['accounting.view', 'accounts.list', 'journal_entries.list'])) {
                    $grant[] = 'finance.view';
                }

                if ($this->hasAny($permissions, ['accounts.create', 'accounts.update', 'journal_entries.create', 'journal_entries.update'])) {
                    $grant[] = 'finance.manage';
                    $grant[] = 'finance.post';
                }

                if ($this->hasAny($permissions, ['reports.view'])) {
                    $grant[] = 'reports.run';
                }

                if ($this->hasAny($permissions, ['pipelines.list'])) {
                    $grant[] = 'document_checklists.view';
                }

                if ($this->hasAny($permissions, ['pipelines.manage'])) {
                    $grant[] = 'document_checklists.manage';
                }

                if ($this->hasAny($permissions, ['contacts.list', 'pipelines.list'])) {
                    array_push($grant, 'ownership.view', 'duplicates.view', 'duplicates.check');
                }

                if ($this->hasAny($permissions, ['contacts.assign', 'contacts.manage_all', 'pipelines.manage'])) {
                    $grant[] = 'ownership.manage';
                }

                if ($this->hasAny($permissions, ['contacts.manage_all'])) {
                    array_push($grant, 'duplicates.manage', 'duplicates.resolve');
                }

                $merged = array_values(array_unique(array_merge($permissions, $grant)));
                sort($merged);

                if ($merged !== $permissions) {
                    DB::table('roles')->where('id', $role->id)->update([
                        'permissions' => json_encode($merged),
                        'updated_at' => now(),
                    ]);
                }
            }
        });
    }

    /** @return string[] */
    private function decodePermissions(mixed $value): array
    {
        if (is_string($value)) {
            if (trim($value) === '') {
                return [];
            }

            $value = json_decode($value, true);
        }

        if (! is_array($value)) {
            return [];
        }

        // Current roles use a flat list, while older installations may still
        // contain nested permission objects such as {"reports":{"view":true}}.
        if (array_is_list($value)) {
            return array_values(array_unique(array_filter($value, 'is_string')));
        }

        $permissions = [];

        foreach ($value as $module => $actions) {
            if (! is_string($module) || ! is_array($actions)) {
                continue;
            }

            foreach ($actions as $action => $enabled) {
                if (is_string($action) && $enabled) {
                    $permissions[] = "{$module}.{$action}";
                }
            }
        }

        return array_values(array_unique($permissions));
    }

    /** @param string[] $permissions @param string[] $needles */
    private function hasAny(array $permissions, array $needles): bool
    {
        return array_intersect($permissions, $needles) !== [];
    }
};
