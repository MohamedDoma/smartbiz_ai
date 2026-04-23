<?php
/**
 * Migration 023 — AI Advisor / Recommendations
 *
 * Creates:
 * - ai_recommendations table (scored, explainable, actionable recommendations)
 * - RLS + indexes
 */

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        DB::statement("
            CREATE TABLE IF NOT EXISTS ai_recommendations (
                id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                workspace_id      UUID NOT NULL REFERENCES workspaces(id),
                category          VARCHAR(30) NOT NULL
                                  CHECK (category IN ('operational','optimization','erp','automation','risk')),
                title             VARCHAR(500) NOT NULL,
                description       TEXT NOT NULL,
                impact_level      VARCHAR(10) NOT NULL DEFAULT 'medium'
                                  CHECK (impact_level IN ('low','medium','high')),
                confidence_score  INT NOT NULL DEFAULT 50
                                  CHECK (confidence_score BETWEEN 0 AND 100),
                status            VARCHAR(20) NOT NULL DEFAULT 'pending'
                                  CHECK (status IN ('pending','accepted','rejected','applied','dismissed')),

                -- Explainability
                reasoning         TEXT NOT NULL,
                data_triggers     JSONB NOT NULL DEFAULT '{}',
                expected_impact   TEXT,

                -- Actionability
                action_type       VARCHAR(50),
                action_payload    JSONB DEFAULT '{}',

                -- Relations
                related_entities  JSONB DEFAULT '[]',
                analyzer          VARCHAR(100),

                -- Lifecycle
                rejected_reason   TEXT,
                applied_by        UUID REFERENCES users(id),
                applied_at        TIMESTAMPTZ,
                created_at        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
            );
        ");

        DB::statement("CREATE INDEX IF NOT EXISTS idx_ai_rec_workspace ON ai_recommendations(workspace_id);");
        DB::statement("CREATE INDEX IF NOT EXISTS idx_ai_rec_status ON ai_recommendations(workspace_id, status);");
        DB::statement("CREATE INDEX IF NOT EXISTS idx_ai_rec_category ON ai_recommendations(workspace_id, category);");
        DB::statement("CREATE INDEX IF NOT EXISTS idx_ai_rec_impact ON ai_recommendations(impact_level);");

        // Dedup: same analyzer + workspace + day
        DB::statement("
            ALTER TABLE ai_recommendations ADD COLUMN IF NOT EXISTS dedup_key VARCHAR(255);
        ");
        DB::statement("
            CREATE UNIQUE INDEX IF NOT EXISTS uq_ai_rec_dedup
            ON ai_recommendations (workspace_id, dedup_key)
            WHERE dedup_key IS NOT NULL;
        ");

        // RLS
        DB::statement("ALTER TABLE ai_recommendations ENABLE ROW LEVEL SECURITY;");
        DB::statement("
            DO \$\$ BEGIN
                IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'ai_recommendations' AND policyname = 'ai_rec_workspace_isolation') THEN
                    CREATE POLICY ai_rec_workspace_isolation ON ai_recommendations
                        USING (workspace_id = current_setting('app.workspace_id')::UUID);
                END IF;
            END \$\$;
        ");
    }

    public function down(): void
    {
        DB::statement("DROP TABLE IF EXISTS ai_recommendations CASCADE;");
    }
};
