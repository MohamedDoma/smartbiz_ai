<?php
/**
 * Migration 035 — AI Foundation Tables (Step 59.1)
 *
 * Creates:
 * - ai_conversations
 * - ai_messages
 * - ai_usage_logs (replaces old ai_request_logs schema)
 * - ai_workspace_settings
 * - ai_memory (needed by existing AiMemoryService)
 * - ai_change_requests (needed by existing AiActionService)
 * - ai_execution_plans (needed by existing AiStepPlanner)
 * - ai_insights (needed by existing AiInsightService)
 */

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        // ── ai_conversations ────────────────────────────────────────
        DB::statement(<<<'SQL'
            CREATE TABLE IF NOT EXISTS ai_conversations (
                id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                workspace_id    UUID REFERENCES workspaces(id) ON DELETE CASCADE,
                user_id         UUID REFERENCES users(id) ON DELETE SET NULL,
                title           VARCHAR(500),
                "type"          VARCHAR(30) NOT NULL DEFAULT 'chat'
                                CHECK ("type" IN ('chat','onboarding','advisor','system_test')),
                mode            VARCHAR(30) NOT NULL DEFAULT 'chat',
                status          VARCHAR(20) NOT NULL DEFAULT 'active'
                                CHECK (status IN ('active','archived','failed')),
                message_count   INT NOT NULL DEFAULT 0,
                last_message_at TIMESTAMPTZ,
                metadata        JSONB DEFAULT '{}',
                created_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
        SQL);
        DB::statement("CREATE INDEX IF NOT EXISTS idx_ai_conv_ws ON ai_conversations(workspace_id)");
        DB::statement("CREATE INDEX IF NOT EXISTS idx_ai_conv_user ON ai_conversations(user_id)");
        DB::statement('CREATE INDEX IF NOT EXISTS idx_ai_conv_type ON ai_conversations("type")');
        DB::statement("CREATE INDEX IF NOT EXISTS idx_ai_conv_status ON ai_conversations(status)");
        DB::statement("CREATE INDEX IF NOT EXISTS idx_ai_conv_created ON ai_conversations(created_at)");

        // ── ai_messages (replaces ai_conversation_messages) ─────────
        DB::statement("
            CREATE TABLE IF NOT EXISTS ai_messages (
                id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                conversation_id     UUID NOT NULL REFERENCES ai_conversations(id) ON DELETE CASCADE,
                workspace_id        UUID REFERENCES workspaces(id) ON DELETE CASCADE,
                user_id             UUID REFERENCES users(id) ON DELETE SET NULL,
                role                VARCHAR(20) NOT NULL
                                    CHECK (role IN ('user','assistant','system','tool')),
                content             TEXT,
                structured_payload  JSONB,
                model               VARCHAR(100),
                input_tokens        INT NOT NULL DEFAULT 0,
                output_tokens       INT NOT NULL DEFAULT 0,
                total_tokens        INT NOT NULL DEFAULT 0,
                estimated_cost_usd  DECIMAL(12,6) NOT NULL DEFAULT 0,
                metadata            JSONB DEFAULT '{}',
                created_at          TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at          TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
        ");
        DB::statement("CREATE INDEX IF NOT EXISTS idx_ai_msg_conv ON ai_messages(conversation_id)");
        DB::statement("CREATE INDEX IF NOT EXISTS idx_ai_msg_ws ON ai_messages(workspace_id)");
        DB::statement("CREATE INDEX IF NOT EXISTS idx_ai_msg_user ON ai_messages(user_id)");
        DB::statement("CREATE INDEX IF NOT EXISTS idx_ai_msg_role ON ai_messages(role)");
        DB::statement("CREATE INDEX IF NOT EXISTS idx_ai_msg_created ON ai_messages(created_at)");

        // ── View: ai_conversation_messages (backward compat) ────────
        // Drop if it existed as a table from older migrations
        DB::statement("DROP TABLE IF EXISTS ai_conversation_messages CASCADE");
        DB::statement("
            CREATE OR REPLACE VIEW ai_conversation_messages AS
            SELECT id, conversation_id, role, content, structured_payload AS tool_calls,
                   metadata, created_at, updated_at
            FROM ai_messages
        ");

        // ── ai_usage_logs ───────────────────────────────────────────
        // Drop old schema (different columns from older migration)
        DB::statement("DROP TABLE IF EXISTS ai_usage_logs CASCADE");
        DB::statement("
            CREATE TABLE IF NOT EXISTS ai_usage_logs (
                id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                workspace_id        UUID REFERENCES workspaces(id) ON DELETE SET NULL,
                user_id             UUID REFERENCES users(id) ON DELETE SET NULL,
                conversation_id     UUID REFERENCES ai_conversations(id) ON DELETE SET NULL,
                message_id          UUID REFERENCES ai_messages(id) ON DELETE SET NULL,
                provider            VARCHAR(30) NOT NULL DEFAULT 'openai',
                model               VARCHAR(100) NOT NULL,
                operation           VARCHAR(50) NOT NULL DEFAULT 'chat',
                input_tokens        INT NOT NULL DEFAULT 0,
                output_tokens       INT NOT NULL DEFAULT 0,
                total_tokens        INT NOT NULL DEFAULT 0,
                estimated_cost_usd  DECIMAL(12,6) NOT NULL DEFAULT 0,
                success             BOOLEAN NOT NULL DEFAULT TRUE,
                error_code          VARCHAR(100),
                error_message       TEXT,
                request_id          VARCHAR(200),
                duration_ms         INT DEFAULT 0,
                metadata            JSONB DEFAULT '{}',
                created_at          TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at          TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
        ");
        DB::statement("CREATE INDEX IF NOT EXISTS idx_ai_ulog_ws ON ai_usage_logs(workspace_id)");
        DB::statement("CREATE INDEX IF NOT EXISTS idx_ai_ulog_user ON ai_usage_logs(user_id)");
        DB::statement("CREATE INDEX IF NOT EXISTS idx_ai_ulog_provider ON ai_usage_logs(provider)");
        DB::statement("CREATE INDEX IF NOT EXISTS idx_ai_ulog_model ON ai_usage_logs(model)");
        DB::statement("CREATE INDEX IF NOT EXISTS idx_ai_ulog_op ON ai_usage_logs(operation)");
        DB::statement("CREATE INDEX IF NOT EXISTS idx_ai_ulog_success ON ai_usage_logs(success)");
        DB::statement("CREATE INDEX IF NOT EXISTS idx_ai_ulog_created ON ai_usage_logs(created_at)");

        // ── View: ai_request_logs (backward compat for old code) ────
        DB::statement("DROP TABLE IF EXISTS ai_request_logs CASCADE");
        DB::statement("
            CREATE OR REPLACE VIEW ai_request_logs AS
            SELECT id, workspace_id, user_id, operation AS action_type,
                   total_tokens AS credits_charged, metadata AS request_metadata,
                   metadata AS response_metadata, duration_ms, created_at
            FROM ai_usage_logs
        ");

        // ── ai_workspace_settings ───────────────────────────────────
        DB::statement("
            CREATE TABLE IF NOT EXISTS ai_workspace_settings (
                id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                workspace_id            UUID NOT NULL UNIQUE REFERENCES workspaces(id) ON DELETE CASCADE,
                ai_enabled              BOOLEAN NOT NULL DEFAULT TRUE,
                monthly_budget_usd      DECIMAL(12,2),
                daily_message_limit     INT,
                monthly_message_limit   INT,
                default_model           VARCHAR(100),
                smart_model             VARCHAR(100),
                metadata                JSONB DEFAULT '{}',
                created_at              TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at              TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
        ");
        DB::statement("CREATE INDEX IF NOT EXISTS idx_ai_ws_settings_ws ON ai_workspace_settings(workspace_id)");

        // ── ai_memory (needed by existing AiMemoryService) ──────────
        DB::statement("
            CREATE TABLE IF NOT EXISTS ai_memory (
                id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                workspace_id    UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
                user_id         UUID REFERENCES users(id) ON DELETE SET NULL,
                memory_type     VARCHAR(30) NOT NULL DEFAULT 'session',
                key             VARCHAR(200) NOT NULL,
                value           TEXT,
                score           DOUBLE PRECISION DEFAULT 0,
                expires_at      TIMESTAMPTZ,
                created_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
        ");
        DB::statement("CREATE INDEX IF NOT EXISTS idx_ai_mem_ws ON ai_memory(workspace_id)");
        DB::statement("CREATE INDEX IF NOT EXISTS idx_ai_mem_user ON ai_memory(user_id)");
        DB::statement("CREATE INDEX IF NOT EXISTS idx_ai_mem_type ON ai_memory(memory_type)");

        // ── ai_change_requests (needed by AiActionService) ──────────
        DB::statement("
            CREATE TABLE IF NOT EXISTS ai_change_requests (
                id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                workspace_id      UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
                user_id           UUID REFERENCES users(id) ON DELETE SET NULL,
                conversation_id   UUID REFERENCES ai_conversations(id) ON DELETE SET NULL,
                action_type       VARCHAR(100) NOT NULL,
                description       TEXT,
                payload           JSONB DEFAULT '{}',
                status            VARCHAR(20) NOT NULL DEFAULT 'pending'
                                  CHECK (status IN ('pending','confirmed','rejected','executed','failed')),
                result            JSONB DEFAULT '{}',
                created_at        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
        ");
        DB::statement("CREATE INDEX IF NOT EXISTS idx_ai_cr_ws ON ai_change_requests(workspace_id)");
        DB::statement("CREATE INDEX IF NOT EXISTS idx_ai_cr_status ON ai_change_requests(status)");

        // ── ai_execution_plans (needed by AiStepPlanner) ────────────
        DB::statement("
            CREATE TABLE IF NOT EXISTS ai_execution_plans (
                id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                workspace_id      UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
                user_id           UUID REFERENCES users(id) ON DELETE SET NULL,
                conversation_id   UUID REFERENCES ai_conversations(id) ON DELETE SET NULL,
                title             VARCHAR(500),
                steps             JSONB NOT NULL DEFAULT '[]',
                status            VARCHAR(20) NOT NULL DEFAULT 'pending'
                                  CHECK (status IN ('pending','running','completed','failed','cancelled')),
                current_step      INT DEFAULT 0,
                result            JSONB DEFAULT '{}',
                created_at        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
        ");
        DB::statement("CREATE INDEX IF NOT EXISTS idx_ai_ep_ws ON ai_execution_plans(workspace_id)");

        // ── ai_insights (needed by AiInsightService) ────────────────
        DB::statement("
            CREATE TABLE IF NOT EXISTS ai_insights (
                id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                workspace_id      UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
                category          VARCHAR(50) NOT NULL DEFAULT 'general',
                title             VARCHAR(500) NOT NULL,
                summary           TEXT,
                severity          VARCHAR(20) DEFAULT 'info',
                data              JSONB DEFAULT '{}',
                status            VARCHAR(20) NOT NULL DEFAULT 'active'
                                  CHECK (status IN ('active','dismissed','resolved')),
                dismissed_at      TIMESTAMPTZ,
                created_at        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
        ");
        DB::statement("CREATE INDEX IF NOT EXISTS idx_ai_ins_ws ON ai_insights(workspace_id)");
        DB::statement("CREATE INDEX IF NOT EXISTS idx_ai_ins_status ON ai_insights(status)");

        // ── RLS policies ────────────────────────────────────────────
        $tables = [
            'ai_conversations', 'ai_messages', 'ai_usage_logs',
            'ai_workspace_settings', 'ai_memory', 'ai_change_requests',
            'ai_execution_plans', 'ai_insights',
        ];
        foreach ($tables as $t) {
            DB::statement("ALTER TABLE {$t} ENABLE ROW LEVEL SECURITY");
            DB::statement("
                DO \$\$ BEGIN
                    CREATE POLICY {$t}_tenant_isolation ON {$t}
                        USING (workspace_id = current_setting('app.current_workspace_id', TRUE)::UUID
                               OR current_setting('app.current_workspace_id', TRUE) IS NULL);
                EXCEPTION WHEN duplicate_object THEN NULL;
                END \$\$
            ");
        }
    }

    public function down(): void
    {
        DB::statement("DROP VIEW IF EXISTS ai_request_logs");
        DB::statement("DROP VIEW IF EXISTS ai_conversation_messages");
        DB::statement("DROP TABLE IF EXISTS ai_insights CASCADE");
        DB::statement("DROP TABLE IF EXISTS ai_execution_plans CASCADE");
        DB::statement("DROP TABLE IF EXISTS ai_change_requests CASCADE");
        DB::statement("DROP TABLE IF EXISTS ai_memory CASCADE");
        DB::statement("DROP TABLE IF EXISTS ai_workspace_settings CASCADE");
        DB::statement("DROP TABLE IF EXISTS ai_usage_logs CASCADE");
        DB::statement("DROP TABLE IF EXISTS ai_messages CASCADE");
        DB::statement("DROP TABLE IF EXISTS ai_conversations CASCADE");
    }
};
