-- =============================================================================
-- Migration 014: Fix validate_workspace_fk() for membership-based model
-- =============================================================================
-- Problem:
--   The validate_workspace_fk() trigger function does:
--     EXECUTE format('SELECT workspace_id FROM %I WHERE id = $1', ref_table)
--   When ref_table = 'users', this fails because users.workspace_id was
--   removed in migration 006 (replaced by workspace_memberships model).
--
-- Fix:
--   When ref_table is 'users', resolve workspace_id via workspace_memberships
--   instead of directly from the users table. We validate that the user has
--   an active membership in NEW.workspace_id.
--
-- Impact:
--   32 triggers across the database reference 'users' in their TG_ARGV.
--   This fix handles all of them without modifying any trigger definitions.
-- =============================================================================

BEGIN;

-- ─── BEFORE (current broken function) ──────────────────────────────────────
-- EXECUTE format('SELECT workspace_id FROM %I WHERE id = $1', ref_table)
--   INTO ref_ws USING fk_value;
-- ↑ Fails when ref_table = 'users' because users has no workspace_id column

-- ─── AFTER (fixed function) ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.validate_workspace_fk()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    ref_ws UUID;
    col_name TEXT;
    ref_table TEXT;
    fk_value UUID;
    query TEXT;
BEGIN
    -- Reads column:table pairs from TG_ARGV[0]
    -- TG_ARGV[0] = 'column1:table1,column2:table2,...'
    FOR col_name, ref_table IN
        SELECT split_part(pair, ':', 1), split_part(pair, ':', 2)
        FROM unnest(string_to_array(TG_ARGV[0], ',')) AS pair
    LOOP
        EXECUTE format('SELECT ($1).%I', col_name) INTO fk_value USING NEW;
        IF fk_value IS NOT NULL THEN
            -- Special case: 'users' table has no workspace_id column.
            -- Resolve via workspace_memberships instead.
            IF ref_table = 'users' THEN
                SELECT wm.workspace_id INTO ref_ws
                FROM workspace_memberships wm
                WHERE wm.user_id = fk_value
                  AND wm.workspace_id = NEW.workspace_id
                  AND wm.status = 'active'
                LIMIT 1;

                -- If no active membership found in this workspace, it's a violation
                IF ref_ws IS NULL THEN
                    RAISE EXCEPTION 'Workspace isolation violation: %.% references a user (%) who has no active membership in workspace %',
                        TG_TABLE_NAME, col_name, fk_value, NEW.workspace_id;
                END IF;
            ELSE
                -- Standard path: ref_table has a workspace_id column
                EXECUTE format('SELECT workspace_id FROM %I WHERE id = $1', ref_table)
                    INTO ref_ws USING fk_value;
                IF ref_ws IS DISTINCT FROM NEW.workspace_id THEN
                    RAISE EXCEPTION 'Workspace isolation violation: %.% references a record in a different workspace (% instead of %)',
                        TG_TABLE_NAME, col_name, ref_ws, NEW.workspace_id;
                END IF;
            END IF;
        END IF;
    END LOOP;
    RETURN NEW;
END;
$function$;

COMMIT;
