-- =============================================================================
-- Migration 015: AI Discovery + ERP Generation Foundation
-- =============================================================================
-- Purpose:
--   Adds the core tables for SmartBiz AI business discovery sessions,
--   conversation messages, and generated ERP blueprints.
--
-- Tables:
--   1. discovery_sessions   — One session per business onboarding/discovery
--   2. discovery_messages   — Conversation log (child table)
--   3. discovery_blueprints — Generated ERP blueprints (one per session)
--
-- All tables are workspace-scoped with RLS.
-- =============================================================================

BEGIN;

-- ─── 1. discovery_sessions ─────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.discovery_sessions (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id                UUID NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
    created_by                  UUID NOT NULL REFERENCES public.users(id),

    status                      VARCHAR(30) NOT NULL DEFAULT 'intake'
                                CHECK (status IN ('intake','questioning','classifying','blueprint_ready','completed')),

    business_description        TEXT NOT NULL,

    -- Classification output
    business_type               VARCHAR(50),
    classification_confidence   NUMERIC(5,2) CHECK (classification_confidence IS NULL OR (classification_confidence >= 0 AND classification_confidence <= 100)),

    -- Generator metadata
    classification_method       VARCHAR(30) DEFAULT 'rule_based_v1',
    classification_version      VARCHAR(20) DEFAULT '1.0.0',

    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_discovery_sessions_workspace ON public.discovery_sessions(workspace_id);
CREATE INDEX idx_discovery_sessions_created_by ON public.discovery_sessions(created_by);

ALTER TABLE public.discovery_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY discovery_sessions_workspace_isolation
    ON public.discovery_sessions
    USING (workspace_id = current_setting('app.current_workspace_id')::uuid);

-- ─── 2. discovery_messages ─────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.discovery_messages (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id                  UUID NOT NULL REFERENCES public.discovery_sessions(id) ON DELETE CASCADE,
    workspace_id                UUID NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,

    role                        VARCHAR(10) NOT NULL CHECK (role IN ('user','ai')),
    content                     TEXT NOT NULL,
    message_type                VARCHAR(30) NOT NULL
                                CHECK (message_type IN ('description','follow_up_question','answer','classification','blueprint')),

    metadata                    JSONB DEFAULT '{}'::jsonb,

    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_discovery_messages_session ON public.discovery_messages(session_id);
CREATE INDEX idx_discovery_messages_workspace ON public.discovery_messages(workspace_id);

ALTER TABLE public.discovery_messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY discovery_messages_workspace_isolation
    ON public.discovery_messages
    USING (workspace_id = current_setting('app.current_workspace_id')::uuid);

-- ─── 3. discovery_blueprints ───────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.discovery_blueprints (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id                  UUID NOT NULL REFERENCES public.discovery_sessions(id) ON DELETE CASCADE,
    workspace_id                UUID NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,

    business_type               VARCHAR(50) NOT NULL,
    blueprint                   JSONB NOT NULL DEFAULT '{}'::jsonb,
    version                     INTEGER NOT NULL DEFAULT 1,

    -- Generator metadata
    generator_method            VARCHAR(30) NOT NULL DEFAULT 'rule_based_v1',
    generator_version           VARCHAR(20) NOT NULL DEFAULT '1.0.0',

    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT uq_discovery_blueprints_session UNIQUE (session_id)
);

CREATE INDEX idx_discovery_blueprints_workspace ON public.discovery_blueprints(workspace_id);

ALTER TABLE public.discovery_blueprints ENABLE ROW LEVEL SECURITY;
CREATE POLICY discovery_blueprints_workspace_isolation
    ON public.discovery_blueprints
    USING (workspace_id = current_setting('app.current_workspace_id')::uuid);

-- ─── Updated-at trigger ────────────────────────────────────────────────────

CREATE TRIGGER set_updated_at_discovery_sessions
    BEFORE UPDATE ON public.discovery_sessions
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER set_updated_at_discovery_blueprints
    BEFORE UPDATE ON public.discovery_blueprints
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

COMMIT;
