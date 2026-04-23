-- ============================================================
-- Migration 021: Advanced AI — Memory, Execution Plans, Insights
-- ============================================================

-- 1. AI Memory (session context, entity frequency, business memory)
CREATE TABLE IF NOT EXISTS ai_memory (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL,
    user_id      UUID,
    memory_type  VARCHAR(50) NOT NULL CHECK (memory_type IN ('session_context', 'entity_frequency', 'business_memory')),
    key          VARCHAR(255) NOT NULL,
    value        JSONB NOT NULL DEFAULT '{}',
    score        REAL NOT NULL DEFAULT 0,
    expires_at   TIMESTAMPTZ,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_ai_memory_ws_type ON ai_memory(workspace_id, memory_type);
CREATE INDEX idx_ai_memory_ws_key ON ai_memory(workspace_id, key);
CREATE INDEX idx_ai_memory_user ON ai_memory(workspace_id, user_id) WHERE user_id IS NOT NULL;
CREATE UNIQUE INDEX uq_ai_memory_ws_type_key ON ai_memory(workspace_id, COALESCE(user_id, '00000000-0000-0000-0000-000000000000'::uuid), memory_type, key);

ALTER TABLE ai_memory ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS ws_ai_memory ON ai_memory;
CREATE POLICY ws_ai_memory ON ai_memory
    USING (workspace_id = current_setting('app.workspace_id', true)::uuid);

-- 2. AI Execution Plans (multi-step workflows)
CREATE TABLE IF NOT EXISTS ai_execution_plans (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id    UUID NOT NULL,
    conversation_id UUID REFERENCES ai_conversations(id) ON DELETE SET NULL,
    user_id         UUID NOT NULL,
    plan_name       VARCHAR(255) NOT NULL,
    steps           JSONB NOT NULL DEFAULT '[]',
    status          VARCHAR(50) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'in_progress', 'completed', 'failed', 'cancelled')),
    current_step    INTEGER NOT NULL DEFAULT 0,
    metadata        JSONB NOT NULL DEFAULT '{}',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_ai_plans_ws ON ai_execution_plans(workspace_id, status);
ALTER TABLE ai_execution_plans ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS ws_ai_execution_plans ON ai_execution_plans;
CREATE POLICY ws_ai_execution_plans ON ai_execution_plans
    USING (workspace_id = current_setting('app.workspace_id', true)::uuid);

-- 3. AI Insights (proactive suggestions)
CREATE TABLE IF NOT EXISTS ai_insights (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL,
    insight_type VARCHAR(50) NOT NULL CHECK (insight_type IN ('low_inventory', 'overdue_receivables', 'sales_trend', 'top_products', 'idle_customers', 'general')),
    severity     VARCHAR(20) NOT NULL DEFAULT 'info' CHECK (severity IN ('info', 'warning', 'critical')),
    title        VARCHAR(500) NOT NULL,
    detail       JSONB NOT NULL DEFAULT '{}',
    status       VARCHAR(30) NOT NULL DEFAULT 'new' CHECK (status IN ('new', 'read', 'dismissed')),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_ai_insights_ws ON ai_insights(workspace_id, status);
ALTER TABLE ai_insights ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS ws_ai_insights ON ai_insights;
CREATE POLICY ws_ai_insights ON ai_insights
    USING (workspace_id = current_setting('app.workspace_id', true)::uuid);

-- 4. Expand ai_change_requests.change_type CHECK
ALTER TABLE ai_change_requests DROP CONSTRAINT IF EXISTS ai_change_requests_change_type_check;
ALTER TABLE ai_change_requests ADD CONSTRAINT ai_change_requests_change_type_check
    CHECK (change_type IN (
        'navigation', 'dashboard', 'module_toggle', 'page_layout', 'workflow',
        'settings', 'role_suggestion', 'order', 'payment', 'inventory', 'status_update', 'multi_step'
    ));
