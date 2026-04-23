<?php
/**
 * Migration 022 — Email Communication Layer
 *
 * Creates:
 * - email_logs (rich audit: provider, actor, event, template version, delivery mode)
 * - email_settings (per-workspace toggles + overrides)
 * - platform_settings seed for global email toggle
 * - Unique dedup index for event-driven emails
 */

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // ────────────────────────────────────────────────────
        // 1. email_logs — full audit trail for every email
        // ────────────────────────────────────────────────────
        DB::statement("
            CREATE TABLE IF NOT EXISTS email_logs (
                id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                workspace_id    UUID NOT NULL REFERENCES workspaces(id),

                -- recipient
                recipient_email VARCHAR(255) NOT NULL,
                recipient_name  VARCHAR(255),

                -- template & content
                template        VARCHAR(100) NOT NULL,
                template_version VARCHAR(20) DEFAULT 'v1',
                subject         VARCHAR(500) NOT NULL,

                -- delivery
                status          VARCHAR(20) NOT NULL DEFAULT 'queued'
                                CHECK (status IN ('queued','sending','sent','failed','retrying')),
                delivery_mode   VARCHAR(20) NOT NULL DEFAULT 'immediate'
                                CHECK (delivery_mode IN ('immediate','queued','retry')),
                retries         INT NOT NULL DEFAULT 0,
                max_retries     INT NOT NULL DEFAULT 3,

                -- provider / audit
                mailer_provider VARCHAR(50) DEFAULT 'smtp',
                actor_user_id   UUID REFERENCES users(id),
                event_name      VARCHAR(100),
                correlation_key VARCHAR(255),

                -- related entity
                related_entity_type VARCHAR(50),
                related_entity_id   UUID,

                -- error
                error_message   TEXT,
                metadata        JSONB DEFAULT '{}',

                -- timestamps
                sent_at         TIMESTAMPTZ,
                created_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
            );
        ");

        // Indexes
        DB::statement("CREATE INDEX IF NOT EXISTS idx_email_logs_workspace ON email_logs(workspace_id);");
        DB::statement("CREATE INDEX IF NOT EXISTS idx_email_logs_status ON email_logs(status);");
        DB::statement("CREATE INDEX IF NOT EXISTS idx_email_logs_template ON email_logs(template, workspace_id);");
        DB::statement("CREATE INDEX IF NOT EXISTS idx_email_logs_entity ON email_logs(related_entity_type, related_entity_id);");
        DB::statement("CREATE INDEX IF NOT EXISTS idx_email_logs_correlation ON email_logs(correlation_key);");

        // Deduplication: application builds dedup_key as template:entity_type:entity_id:date
        DB::statement("ALTER TABLE email_logs ADD COLUMN IF NOT EXISTS dedup_key VARCHAR(255);");
        DB::statement("
            CREATE UNIQUE INDEX IF NOT EXISTS uq_email_logs_dedup
            ON email_logs (workspace_id, dedup_key)
            WHERE dedup_key IS NOT NULL;
        ");

        // ────────────────────────────────────────────────────
        // 2. email_settings — per-workspace email config
        // ────────────────────────────────────────────────────
        DB::statement("
            CREATE TABLE IF NOT EXISTS email_settings (
                workspace_id        UUID PRIMARY KEY REFERENCES workspaces(id),
                enabled             BOOLEAN NOT NULL DEFAULT true,
                daily_limit         INT DEFAULT 200,
                from_name_override  VARCHAR(255),
                from_email_override VARCHAR(255),
                reply_to            VARCHAR(255),
                created_at          TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at          TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
            );
        ");

        // ────────────────────────────────────────────────────
        // 3. RLS
        // ────────────────────────────────────────────────────
        DB::statement("ALTER TABLE email_logs ENABLE ROW LEVEL SECURITY;");
        DB::statement("
            DO \$\$ BEGIN
                IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'email_logs' AND policyname = 'email_logs_workspace_isolation') THEN
                    CREATE POLICY email_logs_workspace_isolation ON email_logs
                        USING (workspace_id = current_setting('app.workspace_id')::UUID);
                END IF;
            END \$\$;
        ");

        DB::statement("ALTER TABLE email_settings ENABLE ROW LEVEL SECURITY;");
        DB::statement("
            DO \$\$ BEGIN
                IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'email_settings' AND policyname = 'email_settings_workspace_isolation') THEN
                    CREATE POLICY email_settings_workspace_isolation ON email_settings
                        USING (workspace_id = current_setting('app.workspace_id')::UUID);
                END IF;
            END \$\$;
        ");

        // ────────────────────────────────────────────────────
        // 4. Global email toggle in platform_settings (key/value)
        // ────────────────────────────────────────────────────
        DB::table('platform_settings')->insertOrIgnore([
            ['key' => 'email.enabled', 'value' => 'true', 'description' => 'Global email delivery toggle (true/false)'],
            ['key' => 'email.default_from_name', 'value' => 'SmartBiz AI', 'description' => 'Default sender name for all emails'],
            ['key' => 'email.default_from_email', 'value' => 'noreply@smartbiz.ai', 'description' => 'Default sender email address'],
            ['key' => 'email.global_daily_limit', 'value' => '5000', 'description' => 'Global daily email sending limit'],
        ]);

        // ────────────────────────────────────────────────────
        // 5. Expand ai_change_requests constraint for 'email' type
        // ────────────────────────────────────────────────────
        DB::statement("
            ALTER TABLE ai_change_requests
                DROP CONSTRAINT IF EXISTS ai_change_requests_change_type_check;
        ");
        DB::statement("
            ALTER TABLE ai_change_requests
                ADD CONSTRAINT ai_change_requests_change_type_check
                CHECK (change_type IN ('settings','module','role','workflow','order','payment','inventory','status_update','multi_step','email'));
        ");
    }

    public function down(): void
    {
        DB::statement("DROP TABLE IF EXISTS email_settings CASCADE;");
        DB::statement("DROP TABLE IF EXISTS email_logs CASCADE;");
        DB::statement("DELETE FROM platform_settings WHERE key LIKE 'email.%';");
    }
};
