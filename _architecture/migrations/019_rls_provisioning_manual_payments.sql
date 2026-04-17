-- ============================================================
-- Migration 019: RLS for provisioning + manual payment tables
-- ============================================================

-- ── 1. provisioning_runs ─────────────────────────────────────
ALTER TABLE provisioning_runs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS ws_provisioning_runs ON provisioning_runs;
CREATE POLICY ws_provisioning_runs ON provisioning_runs
    USING (workspace_id = current_setting('app.workspace_id', true)::uuid)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::uuid);

-- ── 2. workspace_configurations ──────────────────────────────
ALTER TABLE workspace_configurations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS ws_workspace_configurations ON workspace_configurations;
CREATE POLICY ws_workspace_configurations ON workspace_configurations
    USING (workspace_id = current_setting('app.workspace_id', true)::uuid)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::uuid);

-- ── 3. manual_payments ───────────────────────────────────────
ALTER TABLE manual_payments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS ws_manual_payments ON manual_payments;
CREATE POLICY ws_manual_payments ON manual_payments
    USING (workspace_id = current_setting('app.workspace_id', true)::uuid)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::uuid);
