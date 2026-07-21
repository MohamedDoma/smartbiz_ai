<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    /**
     * Replace legacy AI and discovery policies with one fail-closed policy
     * using the canonical SmartBiz workspace context variable.
     */
    public function up(): void
    {
        $tables = [
            'ai_conversations' => [
                'ai_conversations_tenant_isolation',
                'ws_ai_conversations',
            ],
            'ai_messages' => [
                'ai_messages_tenant_isolation',
            ],
            'ai_usage_logs' => [
                'ai_usage_logs_tenant_isolation',
            ],
            'ai_workspace_settings' => [
                'ai_workspace_settings_tenant_isolation',
            ],
            'ai_memory' => [
                'ai_memory_tenant_isolation',
                'ws_ai_memory',
            ],
            'ai_change_requests' => [
                'ai_change_requests_tenant_isolation',
                'ws_ai_change_requests',
            ],
            'ai_execution_plans' => [
                'ai_execution_plans_tenant_isolation',
                'ws_ai_execution_plans',
            ],
            'ai_insights' => [
                'ai_insights_tenant_isolation',
                'ws_ai_insights',
            ],
            'discovery_blueprints' => [
                'discovery_blueprints_workspace_isolation',
                'discovery_blueprints_tenant_isolation',
            ],
            'discovery_messages' => [
                'discovery_messages_workspace_isolation',
                'discovery_messages_tenant_isolation',
            ],
            'discovery_sessions' => [
                'discovery_sessions_workspace_isolation',
                'discovery_sessions_tenant_isolation',
            ],
        ];

        foreach ($tables as $table => $legacyPolicies) {
            DB::statement("ALTER TABLE {$table} ENABLE ROW LEVEL SECURITY");

            foreach ($legacyPolicies as $policy) {
                DB::statement("DROP POLICY IF EXISTS {$policy} ON {$table}");
            }

            DB::statement(<<<SQL
                CREATE POLICY {$table}_tenant_isolation ON {$table}
                    USING (
                        workspace_id = NULLIF(current_setting('app.workspace_id', TRUE), '')::UUID
                    )
                    WITH CHECK (
                        workspace_id = NULLIF(current_setting('app.workspace_id', TRUE), '')::UUID
                    )
            SQL);
        }
    }

    /**
     * This security hardening is intentionally irreversible. Reintroducing the
     * legacy policies would restore inconsistent or fail-open tenant behavior.
     */
    public function down(): void
    {
        // Intentionally left as a no-op.
    }
};
