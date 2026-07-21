--
-- PostgreSQL database dump
--


-- Dumped from database version 16.13
-- Dumped by pg_dump version 16.13

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA IF NOT EXISTS public;


--
-- Name: check_journal_balance(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_journal_balance() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_entry_id UUID;
    total_debit DECIMAL(15, 2);
    total_credit DECIMAL(15, 2);
BEGIN
    -- استخدام COALESCE للتعامل مع DELETE حيث NEW غير موجود
    v_entry_id := COALESCE(NEW.entry_id, OLD.entry_id);

    SELECT COALESCE(SUM(debit), 0), COALESCE(SUM(credit), 0)
    INTO total_debit, total_credit
    FROM journal_lines
    WHERE entry_id = v_entry_id;

    IF total_debit <> total_credit THEN
        RAISE EXCEPTION 'القيد المحاسبي غير متوازن: المدين (%) لا يساوي الدائن (%)', total_debit, total_credit;
    END IF;

    RETURN COALESCE(NEW, OLD);
END;
$$;


--
-- Name: check_owner_membership_active(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_owner_membership_active() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_owner_count INT;
    v_has_owner_role BOOLEAN;
BEGIN
    IF NEW.status IN ('suspended', 'removed') AND OLD.status = 'active' THEN
        SELECT EXISTS(
            SELECT 1 FROM membership_roles mr
            JOIN roles r ON r.id = mr.role_id
            WHERE mr.membership_id = OLD.id AND r.role_key = 'owner'
        ) INTO v_has_owner_role;

        IF v_has_owner_role THEN
            SELECT COUNT(*) INTO v_owner_count
            FROM membership_roles mr
            JOIN roles r ON r.id = mr.role_id
            JOIN workspace_memberships wm ON wm.id = mr.membership_id
            WHERE wm.workspace_id = OLD.workspace_id
              AND r.role_key = 'owner'
              AND wm.status = 'active'
              AND wm.id <> OLD.id;

            IF v_owner_count < 1 THEN
                RAISE EXCEPTION 'Cannot deactivate the last owner membership in workspace %. '
                    'Transfer ownership first (RBAC §13.1).',
                    OLD.workspace_id
                    USING ERRCODE = 'check_violation';
            END IF;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;


--
-- Name: FUNCTION check_owner_membership_active(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.check_owner_membership_active() IS 'DB-ENFORCED: Prevents deactivating the last owner membership. Implements RBAC §13.1.';


--
-- Name: check_workspace_owner_exists(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_workspace_owner_exists() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_workspace_id UUID;
    v_owner_count INT;
    v_role_key VARCHAR;
BEGIN
    IF TG_OP = 'DELETE' THEN
        SELECT r.role_key INTO v_role_key FROM roles r WHERE r.id = OLD.role_id;
        SELECT wm.workspace_id INTO v_workspace_id
        FROM workspace_memberships wm WHERE wm.id = OLD.membership_id;
    ELSE
        SELECT r.role_key INTO v_role_key FROM roles r WHERE r.id = NEW.role_id;
        SELECT wm.workspace_id INTO v_workspace_id
        FROM workspace_memberships wm WHERE wm.id = NEW.membership_id;
    END IF;

    IF v_role_key = 'owner' AND (TG_OP = 'DELETE' OR (TG_OP = 'UPDATE' AND OLD.role_id <> NEW.role_id)) THEN
        SELECT COUNT(*) INTO v_owner_count
        FROM membership_roles mr
        JOIN roles r ON r.id = mr.role_id
        JOIN workspace_memberships wm ON wm.id = mr.membership_id
        WHERE wm.workspace_id = v_workspace_id
          AND r.role_key = 'owner'
          AND wm.status = 'active'
          AND mr.id <> COALESCE(OLD.id, '00000000-0000-0000-0000-000000000000'::UUID);

        IF v_owner_count < 1 THEN
            RAISE EXCEPTION 'Cannot remove the last owner from workspace %. '
                'Every workspace must have at least one active owner (RBAC §13.1).',
                v_workspace_id
                USING ERRCODE = 'check_violation';
        END IF;
    END IF;

    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;


--
-- Name: FUNCTION check_workspace_owner_exists(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.check_workspace_owner_exists() IS 'DB-ENFORCED: Prevents removing the last owner from a workspace. Implements RBAC §13.1 ownership rule.';


--
-- Name: guard_reservation_lifecycle(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.guard_reservation_lifecycle() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF OLD.status = 'released' AND NEW.fulfilled_quantity > OLD.fulfilled_quantity THEN
        RAISE EXCEPTION 'Cannot fulfill reservation % after it has been fully released.',
            OLD.id USING ERRCODE = 'check_violation';
    END IF;
    IF OLD.status = 'fulfilled' AND NEW.released_quantity > OLD.released_quantity THEN
        RAISE EXCEPTION 'Cannot release reservation % after it has been fully fulfilled.',
            OLD.id USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.fulfilled_quantity + NEW.released_quantity > NEW.reserved_quantity THEN
        RAISE EXCEPTION 'fulfilled (%) + released (%) exceeds reserved (%) for reservation %.',
            NEW.fulfilled_quantity, NEW.released_quantity, NEW.reserved_quantity, OLD.id
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: prevent_immutable_update(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prevent_immutable_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    RAISE EXCEPTION 'This table is immutable. Rows cannot be updated after insertion.'
        USING ERRCODE = 'check_violation';
    RETURN NULL;
END;
$$;


--
-- Name: prevent_locked_payroll_run_modification(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prevent_locked_payroll_run_modification() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF OLD.status = 'locked' THEN
        RAISE EXCEPTION 'Cannot modify a locked payroll run (id: %). Locked payroll runs are permanently sealed.', OLD.id
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: FUNCTION prevent_locked_payroll_run_modification(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.prevent_locked_payroll_run_modification() IS 'Prevents any modification to payroll_runs with status=locked. Locked is a terminal state (BR-PRL-004). This is a DB-level guard; the application layer should also prevent locked-run modifications.';


--
-- Name: set_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;


--
-- Name: FUNCTION set_updated_at(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.set_updated_at() IS 'Shared trigger function: auto-sets updated_at to CURRENT_TIMESTAMP on every UPDATE.';


--
-- Name: sync_inventory_available(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sync_inventory_available() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.available := NEW.quantity - NEW.reserved;
    RETURN NEW;
END;
$$;


--
-- Name: FUNCTION sync_inventory_available(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.sync_inventory_available() IS 'DB-ENFORCED trigger ensuring available = quantity - reserved on every INSERT/UPDATE. This makes the CHECK constraint chk_inventory_available_consistency always pass and provides a safety net against application bugs that set available incorrectly.';


--
-- Name: update_timestamp(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_timestamp() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;


--
-- Name: validate_workspace_fk(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validate_workspace_fk() RETURNS trigger
    LANGUAGE plpgsql
    AS $_$
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
$_$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: _deprecation_registry; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public._deprecation_registry (
    id integer NOT NULL,
    object_type character varying(50) NOT NULL,
    object_name character varying(255) NOT NULL,
    deprecated_in character varying(50) NOT NULL,
    replaced_by text NOT NULL,
    rollback_sql text NOT NULL,
    deprecated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: TABLE _deprecation_registry; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public._deprecation_registry IS 'Operational tracking of deprecated schema objects. One row per deprecated item with replacement info and rollback SQL. Used by ops team to track deprecation lifecycle.';


--
-- Name: _deprecation_registry_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public._deprecation_registry_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: _deprecation_registry_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public._deprecation_registry_id_seq OWNED BY public._deprecation_registry.id;


--
-- Name: accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid,
    code character varying(50) NOT NULL,
    name character varying(255) NOT NULL,
    type character varying(50) NOT NULL,
    parent_id uuid,
    balance numeric(15,2) DEFAULT 0.00,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT accounts_type_check CHECK (((type)::text = ANY (ARRAY[('asset'::character varying)::text, ('liability'::character varying)::text, ('equity'::character varying)::text, ('revenue'::character varying)::text, ('expense'::character varying)::text])))
);


--
-- Name: ai_change_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ai_change_requests (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    conversation_id uuid,
    requested_by uuid NOT NULL,
    reviewed_by uuid,
    change_type character varying(50) NOT NULL,
    risk_level character varying(20) DEFAULT 'medium'::character varying NOT NULL,
    status character varying(50) DEFAULT 'proposed'::character varying NOT NULL,
    proposed_diff jsonb NOT NULL,
    applied_diff jsonb,
    review_notes text,
    proposed_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    reviewed_at timestamp with time zone,
    applied_at timestamp with time zone,
    expires_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT ai_change_requests_change_type_check CHECK (((change_type)::text = ANY (ARRAY[('settings'::character varying)::text, ('module'::character varying)::text, ('role'::character varying)::text, ('workflow'::character varying)::text, ('order'::character varying)::text, ('payment'::character varying)::text, ('inventory'::character varying)::text, ('status_update'::character varying)::text, ('multi_step'::character varying)::text, ('email'::character varying)::text]))),
    CONSTRAINT ai_change_requests_risk_level_check CHECK (((risk_level)::text = ANY (ARRAY[('low'::character varying)::text, ('medium'::character varying)::text, ('high'::character varying)::text, ('critical'::character varying)::text]))),
    CONSTRAINT ai_change_requests_status_check CHECK (((status)::text = ANY (ARRAY[('proposed'::character varying)::text, ('approved'::character varying)::text, ('rejected'::character varying)::text, ('applied'::character varying)::text, ('rolled_back'::character varying)::text, ('expired'::character varying)::text])))
);


--
-- Name: TABLE ai_change_requests; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.ai_change_requests IS 'Governed AI change proposals (BR-AI-004). AI proposes → owner/admin reviews → approved → system applies. Supports rollback and auto-expiry.';


--
-- Name: COLUMN ai_change_requests.risk_level; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ai_change_requests.risk_level IS 'AI-classified risk: low (cosmetic), medium (UI changes), high (workflow/module), critical (permissions/accounting).';


--
-- Name: COLUMN ai_change_requests.proposed_diff; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ai_change_requests.proposed_diff IS 'Structured JSON diff showing exactly what the AI wants to change (before/after per field).';


--
-- Name: COLUMN ai_change_requests.expires_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ai_change_requests.expires_at IS 'If set, unreviewed proposals auto-expire after this time. Background job should mark status=expired.';


--
-- Name: ai_messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ai_messages (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    conversation_id uuid NOT NULL,
    workspace_id uuid,
    user_id uuid,
    role character varying(20) NOT NULL,
    content text,
    structured_payload jsonb,
    model character varying(100),
    input_tokens integer DEFAULT 0 NOT NULL,
    output_tokens integer DEFAULT 0 NOT NULL,
    total_tokens integer DEFAULT 0 NOT NULL,
    estimated_cost_usd numeric(12,6) DEFAULT 0 NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT ai_messages_role_check CHECK (((role)::text = ANY (ARRAY[('user'::character varying)::text, ('assistant'::character varying)::text, ('system'::character varying)::text, ('tool'::character varying)::text])))
);


--
-- Name: ai_conversation_messages; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.ai_conversation_messages AS
 SELECT id,
    conversation_id,
    role,
    content,
    structured_payload AS tool_calls,
    metadata,
    created_at,
    updated_at
   FROM public.ai_messages;


--
-- Name: ai_conversations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ai_conversations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    user_id uuid NOT NULL,
    title character varying(255),
    mode character varying(50) NOT NULL,
    status character varying(50) DEFAULT 'active'::character varying NOT NULL,
    message_count integer DEFAULT 0 NOT NULL,
    last_message_at timestamp with time zone,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    type character varying(30) DEFAULT 'chat'::character varying NOT NULL,
    CONSTRAINT ai_conversations_message_count_check CHECK ((message_count >= 0)),
    CONSTRAINT ai_conversations_mode_check CHECK (((mode)::text = ANY (ARRAY[('discovery'::character varying)::text, ('chat'::character varying)::text, ('advisory'::character varying)::text, ('general'::character varying)::text]))),
    CONSTRAINT ai_conversations_status_check CHECK (((status)::text = ANY (ARRAY[('active'::character varying)::text, ('archived'::character varying)::text, ('deleted'::character varying)::text]))),
    CONSTRAINT ai_conversations_type_check CHECK (((type)::text = ANY (ARRAY[('chat'::character varying)::text, ('onboarding'::character varying)::text, ('advisor'::character varying)::text, ('system_test'::character varying)::text])))
);


--
-- Name: TABLE ai_conversations; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.ai_conversations IS 'Groups multi-turn AI chat messages. Each conversation belongs to one user in one workspace. ai_request_logs rows link here via conversation_id.';


--
-- Name: COLUMN ai_conversations.mode; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ai_conversations.mode IS 'AI mode: onboarding (Mode A), change_request (Mode B), advisory (Mode C), general.';


--
-- Name: COLUMN ai_conversations.metadata; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.ai_conversations.metadata IS 'Extensible JSON: referenced_entity_ids, conversation_parameters, context_summary.';


--
-- Name: ai_credit_balances; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ai_credit_balances (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    included_credits integer DEFAULT 0 NOT NULL,
    purchased_credits integer DEFAULT 0 NOT NULL,
    bonus_credits integer DEFAULT 0 NOT NULL,
    trial_credits integer DEFAULT 0 NOT NULL,
    used_credits integer DEFAULT 0 NOT NULL,
    hard_limit boolean DEFAULT false NOT NULL,
    soft_limit_threshold integer DEFAULT 0 NOT NULL,
    period_start timestamp with time zone NOT NULL,
    period_end timestamp with time zone NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: ai_credit_transactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ai_credit_transactions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    transaction_type character varying(30) NOT NULL,
    bucket character varying(20) NOT NULL,
    credits integer NOT NULL,
    balance_after integer NOT NULL,
    description text,
    reference_type character varying(50),
    reference_id uuid,
    actor_id uuid,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ai_credit_transactions_bucket_check CHECK (((bucket)::text = ANY (ARRAY[('included'::character varying)::text, ('purchased'::character varying)::text, ('bonus'::character varying)::text, ('trial'::character varying)::text]))),
    CONSTRAINT ai_credit_transactions_transaction_type_check CHECK (((transaction_type)::text = ANY (ARRAY[('usage'::character varying)::text, ('purchase'::character varying)::text, ('refund'::character varying)::text, ('monthly_reset'::character varying)::text, ('admin_adjustment'::character varying)::text, ('bonus'::character varying)::text, ('trial_grant'::character varying)::text])))
);


--
-- Name: ai_execution_plans; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ai_execution_plans (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    conversation_id uuid,
    user_id uuid NOT NULL,
    plan_name character varying(255) NOT NULL,
    steps jsonb DEFAULT '[]'::jsonb NOT NULL,
    status character varying(50) DEFAULT 'pending'::character varying NOT NULL,
    current_step integer DEFAULT 0 NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT ai_execution_plans_status_check CHECK (((status)::text = ANY (ARRAY[('pending'::character varying)::text, ('in_progress'::character varying)::text, ('completed'::character varying)::text, ('failed'::character varying)::text, ('cancelled'::character varying)::text])))
);


--
-- Name: ai_insights; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ai_insights (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    insight_type character varying(50) NOT NULL,
    severity character varying(20) DEFAULT 'info'::character varying NOT NULL,
    title character varying(500) NOT NULL,
    detail jsonb DEFAULT '{}'::jsonb NOT NULL,
    status character varying(30) DEFAULT 'new'::character varying NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT ai_insights_insight_type_check CHECK (((insight_type)::text = ANY (ARRAY[('low_inventory'::character varying)::text, ('overdue_receivables'::character varying)::text, ('sales_trend'::character varying)::text, ('top_products'::character varying)::text, ('idle_customers'::character varying)::text, ('general'::character varying)::text]))),
    CONSTRAINT ai_insights_severity_check CHECK (((severity)::text = ANY (ARRAY[('info'::character varying)::text, ('warning'::character varying)::text, ('critical'::character varying)::text]))),
    CONSTRAINT ai_insights_status_check CHECK (((status)::text = ANY (ARRAY[('new'::character varying)::text, ('read'::character varying)::text, ('dismissed'::character varying)::text])))
);


--
-- Name: ai_memory; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ai_memory (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    user_id uuid,
    memory_type character varying(50) NOT NULL,
    key character varying(255) NOT NULL,
    value jsonb DEFAULT '{}'::jsonb NOT NULL,
    score real DEFAULT 0 NOT NULL,
    expires_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT ai_memory_memory_type_check CHECK (((memory_type)::text = ANY (ARRAY[('session_context'::character varying)::text, ('entity_frequency'::character varying)::text, ('business_memory'::character varying)::text])))
);


--
-- Name: ai_recommendations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ai_recommendations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    category character varying(30) NOT NULL,
    title character varying(500) NOT NULL,
    description text NOT NULL,
    impact_level character varying(10) DEFAULT 'medium'::character varying NOT NULL,
    confidence_score integer DEFAULT 50 NOT NULL,
    status character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    reasoning text NOT NULL,
    data_triggers jsonb DEFAULT '{}'::jsonb NOT NULL,
    expected_impact text,
    action_type character varying(50),
    action_payload jsonb DEFAULT '{}'::jsonb,
    related_entities jsonb DEFAULT '[]'::jsonb,
    analyzer character varying(100),
    rejected_reason text,
    applied_by uuid,
    applied_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    dedup_key character varying(255),
    CONSTRAINT ai_recommendations_category_check CHECK (((category)::text = ANY (ARRAY[('operational'::character varying)::text, ('optimization'::character varying)::text, ('erp'::character varying)::text, ('automation'::character varying)::text, ('risk'::character varying)::text]))),
    CONSTRAINT ai_recommendations_confidence_score_check CHECK (((confidence_score >= 0) AND (confidence_score <= 100))),
    CONSTRAINT ai_recommendations_impact_level_check CHECK (((impact_level)::text = ANY (ARRAY[('low'::character varying)::text, ('medium'::character varying)::text, ('high'::character varying)::text]))),
    CONSTRAINT ai_recommendations_status_check CHECK (((status)::text = ANY (ARRAY[('pending'::character varying)::text, ('accepted'::character varying)::text, ('rejected'::character varying)::text, ('applied'::character varying)::text, ('dismissed'::character varying)::text])))
);


--
-- Name: ai_usage_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ai_usage_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid,
    user_id uuid,
    conversation_id uuid,
    message_id uuid,
    provider character varying(30) DEFAULT 'openai'::character varying NOT NULL,
    model character varying(100) NOT NULL,
    operation character varying(50) DEFAULT 'chat'::character varying NOT NULL,
    input_tokens integer DEFAULT 0 NOT NULL,
    output_tokens integer DEFAULT 0 NOT NULL,
    total_tokens integer DEFAULT 0 NOT NULL,
    estimated_cost_usd numeric(12,6) DEFAULT 0 NOT NULL,
    success boolean DEFAULT true NOT NULL,
    error_code character varying(100),
    error_message text,
    request_id character varying(200),
    duration_ms integer DEFAULT 0,
    metadata jsonb DEFAULT '{}'::jsonb,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: ai_request_logs; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.ai_request_logs AS
 SELECT id,
    workspace_id,
    user_id,
    operation AS action_type,
    total_tokens AS credits_charged,
    metadata AS request_metadata,
    metadata AS response_metadata,
    duration_ms,
    created_at
   FROM public.ai_usage_logs;


--
-- Name: ai_tool_calls; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ai_tool_calls (
    id uuid NOT NULL,
    workspace_id uuid,
    user_id uuid,
    conversation_id uuid,
    message_id uuid,
    tool_name character varying(120) NOT NULL,
    status character varying(20) DEFAULT 'success'::character varying NOT NULL,
    required_permission character varying(120),
    denial_reason text,
    input_payload jsonb,
    output_summary jsonb,
    duration_ms integer DEFAULT 0 NOT NULL,
    error_message text,
    created_at timestamp(0) with time zone,
    updated_at timestamp(0) with time zone
);


--
-- Name: ai_workspace_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ai_workspace_settings (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    ai_enabled boolean DEFAULT true NOT NULL,
    monthly_budget_usd numeric(12,2),
    daily_message_limit integer,
    monthly_message_limit integer,
    default_model character varying(100),
    smart_model character varying(100),
    metadata jsonb DEFAULT '{}'::jsonb,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: approval_decisions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.approval_decisions (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    approval_request_id uuid NOT NULL,
    approval_request_step_id uuid NOT NULL,
    actor_membership_id uuid NOT NULL,
    decision character varying(20) NOT NULL,
    notes text,
    actor_snapshot jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(0) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: approval_request_steps; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.approval_request_steps (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    approval_request_id uuid NOT NULL,
    workflow_step_id uuid NOT NULL,
    step_order integer NOT NULL,
    status character varying(30) DEFAULT 'pending'::character varying NOT NULL,
    decided_by_membership_id uuid,
    decision_notes text,
    decided_at timestamp(0) without time zone,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone
);


--
-- Name: approval_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.approval_requests (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    workflow_id uuid NOT NULL,
    entity_type character varying(100) NOT NULL,
    entity_id uuid NOT NULL,
    requester_membership_id uuid NOT NULL,
    status character varying(30) DEFAULT 'pending'::character varying NOT NULL,
    current_step_order integer DEFAULT 1 NOT NULL,
    entity_snapshot jsonb DEFAULT '{}'::jsonb NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    final_notes text,
    resolved_at timestamp(0) without time zone,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone
);


--
-- Name: approval_workflow_steps; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.approval_workflow_steps (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    workflow_id uuid NOT NULL,
    name character varying(255) NOT NULL,
    step_order integer NOT NULL,
    approver_type character varying(50) NOT NULL,
    approver_permission_key character varying(100),
    approver_membership_id uuid,
    conditions jsonb DEFAULT '{}'::jsonb NOT NULL,
    allow_self_approval boolean DEFAULT false NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone
);


--
-- Name: approval_workflows; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.approval_workflows (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    workflow_key character varying(100) NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    entity_type character varying(100) NOT NULL,
    trigger_conditions jsonb DEFAULT '{}'::jsonb NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    created_by uuid,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone
);


--
-- Name: archival_jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.archival_jobs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    entity_type character varying(100) NOT NULL,
    records_archived integer DEFAULT 0 NOT NULL,
    retention_policy_id uuid,
    archived_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: TABLE archival_jobs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.archival_jobs IS '[Expansion Pack] Archival execution log. Tracks how many records were processed per run.';


--
-- Name: async_jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.async_jobs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid,
    user_id uuid,
    job_type character varying(100) NOT NULL,
    status character varying(50) DEFAULT 'pending'::character varying NOT NULL,
    progress_pct integer DEFAULT 0 NOT NULL,
    result_url text,
    error text,
    metadata jsonb,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    started_at timestamp with time zone,
    completed_at timestamp with time zone,
    CONSTRAINT async_jobs_progress_pct_check CHECK (((progress_pct >= 0) AND (progress_pct <= 100))),
    CONSTRAINT async_jobs_status_check CHECK (((status)::text = ANY (ARRAY[('pending'::character varying)::text, ('running'::character varying)::text, ('completed'::character varying)::text, ('failed'::character varying)::text, ('cancelled'::character varying)::text])))
);


--
-- Name: TABLE async_jobs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.async_jobs IS 'Tracks long-running asynchronous operations (report exports, bulk imports, payroll calculations). Platform-level jobs (workspace_id IS NULL) are invisible to workspace RLS sessions.';


--
-- Name: attachments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.attachments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid,
    uploaded_by uuid,
    entity_type character varying(100) NOT NULL,
    entity_id uuid NOT NULL,
    file_name character varying(255) NOT NULL,
    file_url text NOT NULL,
    file_type character varying(50),
    file_size integer,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: attendance; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.attendance (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid,
    user_id uuid,
    check_in timestamp with time zone,
    check_out timestamp with time zone,
    status character varying(50) DEFAULT 'present'::character varying,
    notes text,
    date date DEFAULT CURRENT_DATE NOT NULL,
    shift_id uuid,
    shift_assignment_id uuid,
    worked_hours numeric(6,2),
    overtime_hours numeric(6,2) DEFAULT 0.00,
    late_minutes integer DEFAULT 0,
    early_departure_minutes integer DEFAULT 0,
    source character varying(50) DEFAULT 'manual'::character varying,
    is_manually_adjusted boolean DEFAULT false,
    adjustment_approved_by uuid,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT attendance_check CHECK (((check_out IS NULL) OR (check_in IS NULL) OR (check_out >= check_in))),
    CONSTRAINT attendance_early_departure_minutes_check CHECK (((early_departure_minutes IS NULL) OR (early_departure_minutes >= 0))),
    CONSTRAINT attendance_late_minutes_check CHECK (((late_minutes IS NULL) OR (late_minutes >= 0))),
    CONSTRAINT attendance_overtime_hours_check CHECK (((overtime_hours IS NULL) OR (overtime_hours >= (0)::numeric))),
    CONSTRAINT attendance_source_check CHECK (((source IS NULL) OR ((source)::text = ANY (ARRAY[('manual'::character varying)::text, ('biometric'::character varying)::text, ('gps'::character varying)::text, ('web'::character varying)::text, ('mobile'::character varying)::text])))),
    CONSTRAINT attendance_status_check CHECK (((status)::text = ANY (ARRAY[('present'::character varying)::text, ('absent'::character varying)::text, ('late'::character varying)::text, ('half_day'::character varying)::text, ('remote'::character varying)::text]))),
    CONSTRAINT attendance_worked_hours_check CHECK (((worked_hours IS NULL) OR (worked_hours >= (0)::numeric)))
);


--
-- Name: COLUMN attendance.shift_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.attendance.shift_id IS 'APPLICATION-MAINTAINED. Shift that was active for this attendance record. Resolved by the service layer from shift_assignments (if exists for user+date) or falling back to users.shift_id. Set on clock-in or attendance creation.';


--
-- Name: COLUMN attendance.worked_hours; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.attendance.worked_hours IS 'APPLICATION-MAINTAINED. Total hours worked = clock_out - clock_in (excluding breaks). Calculated by the service layer on clock-out or when attendance is finalized. NOT a DB-generated column. The application MUST update this on any clock time change.';


--
-- Name: COLUMN attendance.overtime_hours; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.attendance.overtime_hours IS 'APPLICATION-MAINTAINED. Hours exceeding shift duration or daily max (BR-ATT-003). Calculated as: worked_hours - shift.regular_hours (if shift linked), or worked_hours - workspace.daily_max_hours. Overtime rate multiplier is workspace-configurable (default 1.5x). NOT a DB-generated column. Set by the service layer during attendance finalization.';


--
-- Name: COLUMN attendance.late_minutes; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.attendance.late_minutes IS 'APPLICATION-MAINTAINED. Minutes late from shift start time, after subtracting the shift grace_period_minutes. Zero if not late or no shift linked. Calculated as: MAX(0, clock_in_time - shift.start_time - grace_period). NOT a DB-generated column. Set by the service layer on clock-in.';


--
-- Name: COLUMN attendance.early_departure_minutes; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.attendance.early_departure_minutes IS 'APPLICATION-MAINTAINED. Minutes departed before shift end time. Calculated as: MAX(0, shift.end_time - clock_out_time). NOT a DB-generated column. Set by the service layer on clock-out.';


--
-- Name: COLUMN attendance.source; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.attendance.source IS 'How check-in was recorded: manual, biometric, gps, web, mobile (BR-ATT-001). Set at creation time.';


--
-- Name: COLUMN attendance.is_manually_adjusted; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.attendance.is_manually_adjusted IS 'TRUE if record was manually corrected (BR-ATT-005). Requires manager approval (adjustment_approved_by). Manually adjusted records are flagged for payroll review.';


--
-- Name: audit_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid,
    user_id uuid,
    action character varying(100) NOT NULL,
    entity_type character varying(100) NOT NULL,
    entity_id uuid NOT NULL,
    old_values jsonb,
    new_values jsonb,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    ip_address inet,
    user_agent text
);
ALTER TABLE ONLY public.audit_logs ALTER COLUMN workspace_id SET STATISTICS 500;
ALTER TABLE ONLY public.audit_logs ALTER COLUMN entity_type SET STATISTICS 200;


--
-- Name: COLUMN audit_logs.ip_address; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.audit_logs.ip_address IS 'Client IP address at time of action (for security auditing).';


--
-- Name: COLUMN audit_logs.user_agent; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.audit_logs.user_agent IS 'Client user-agent string at time of action.';


--
-- Name: automation_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.automation_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    automation_id uuid NOT NULL,
    outbound_message_id uuid,
    triggered_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    entity_type character varying(100),
    entity_id uuid
);


--
-- Name: TABLE automation_logs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.automation_logs IS 'Execution log for communication automations. Links trigger events to sent messages.';


--
-- Name: bill_of_materials; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bill_of_materials (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid,
    final_product_id uuid,
    raw_material_id uuid,
    unit_id uuid,
    quantity_required numeric(10,4) NOT NULL
);


--
-- Name: billing_invoices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.billing_invoices (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    subscription_id uuid NOT NULL,
    invoice_number character varying(50),
    period_start date NOT NULL,
    period_end date NOT NULL,
    amount numeric(10,2) NOT NULL,
    currency character varying(10) DEFAULT 'USD'::character varying NOT NULL,
    status character varying(50) DEFAULT 'draft'::character varying NOT NULL,
    issued_at timestamp with time zone,
    paid_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT billing_invoices_amount_check CHECK ((amount >= (0)::numeric)),
    CONSTRAINT billing_invoices_check CHECK ((period_end > period_start)),
    CONSTRAINT billing_invoices_status_check CHECK (((status)::text = ANY (ARRAY[('draft'::character varying)::text, ('issued'::character varying)::text, ('paid'::character varying)::text, ('overdue'::character varying)::text, ('void'::character varying)::text])))
);


--
-- Name: TABLE billing_invoices; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.billing_invoices IS 'Platform-generated billing invoices for workspace subscription charges.';


--
-- Name: billing_payments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.billing_payments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    billing_invoice_id uuid NOT NULL,
    amount numeric(10,2) NOT NULL,
    method character varying(50) NOT NULL,
    reference character varying(255),
    paid_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT billing_payments_amount_check CHECK ((amount > (0)::numeric)),
    CONSTRAINT billing_payments_method_check CHECK (((method)::text = ANY (ARRAY[('card'::character varying)::text, ('bank_transfer'::character varying)::text, ('paypal'::character varying)::text, ('wire'::character varying)::text, ('manual'::character varying)::text])))
);


--
-- Name: TABLE billing_payments; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.billing_payments IS 'Individual payment records against platform billing invoices. Carries workspace_id for direct tenant isolation.';


--
-- Name: billing_snapshots; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.billing_snapshots (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    period_start timestamp with time zone NOT NULL,
    period_end timestamp with time zone NOT NULL,
    plan_name character varying(100) NOT NULL,
    billing_cycle character varying(20) NOT NULL,
    base_price numeric(15,2) DEFAULT 0 NOT NULL,
    employee_count integer DEFAULT 0 NOT NULL,
    included_employees integer DEFAULT 0 NOT NULL,
    overage_employees integer DEFAULT 0 NOT NULL,
    employee_overage_charge numeric(15,2) DEFAULT 0 NOT NULL,
    ai_credits_included integer DEFAULT 0 NOT NULL,
    ai_credits_used integer DEFAULT 0 NOT NULL,
    ai_credits_overage integer DEFAULT 0 NOT NULL,
    ai_overage_charge numeric(15,2) DEFAULT 0 NOT NULL,
    total_amount numeric(15,2) DEFAULT 0 NOT NULL,
    status character varying(20) DEFAULT 'draft'::character varying NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT billing_snapshots_status_check CHECK (((status)::text = ANY (ARRAY[('draft'::character varying)::text, ('finalized'::character varying)::text, ('paid'::character varying)::text, ('void'::character varying)::text])))
);


--
-- Name: bookings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bookings (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid,
    branch_id uuid,
    contact_id uuid,
    assigned_to uuid,
    product_id uuid,
    booking_type character varying(50) DEFAULT 'appointment'::character varying,
    title character varying(255),
    start_datetime timestamp with time zone NOT NULL,
    end_datetime timestamp with time zone NOT NULL,
    status character varying(50) DEFAULT 'scheduled'::character varying,
    reminder_sent boolean DEFAULT false,
    notes text,
    invoice_id uuid,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT bookings_booking_type_check CHECK (((booking_type)::text = ANY (ARRAY[('appointment'::character varying)::text, ('reservation'::character varying)::text, ('session'::character varying)::text]))),
    CONSTRAINT bookings_check CHECK ((end_datetime > start_datetime)),
    CONSTRAINT bookings_status_check CHECK (((status)::text = ANY (ARRAY[('scheduled'::character varying)::text, ('confirmed'::character varying)::text, ('in_progress'::character varying)::text, ('completed'::character varying)::text, ('cancelled'::character varying)::text, ('no_show'::character varying)::text])))
);


--
-- Name: branches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.branches (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid,
    name character varying(255) NOT NULL,
    location text,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    phone character varying(50),
    metadata jsonb
);


--
-- Name: brand_kits; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.brand_kits (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    primary_color character varying(9),
    secondary_color character varying(9),
    accent_color character varying(9),
    font_family character varying(100),
    logo_path character varying(500),
    tone_description text,
    guidelines jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: TABLE brand_kits; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.brand_kits IS '[Core v1] Workspace brand identity. Singleton per workspace. AI uses this for content generation context.';


--
-- Name: business_template_custom_fields; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.business_template_custom_fields (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    business_template_id uuid NOT NULL,
    entity_type character varying(255) NOT NULL,
    field_key character varying(255) NOT NULL,
    label character varying(255) NOT NULL,
    field_type character varying(255) NOT NULL,
    is_required boolean DEFAULT false NOT NULL,
    options jsonb,
    validation_rules jsonb,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone
);


--
-- Name: business_template_modules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.business_template_modules (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    business_template_id uuid NOT NULL,
    module_key character varying(255) NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    is_enabled boolean DEFAULT true NOT NULL,
    is_required boolean DEFAULT false NOT NULL,
    settings jsonb,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone
);


--
-- Name: business_template_roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.business_template_roles (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    business_template_id uuid NOT NULL,
    role_key character varying(255) NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    hierarchy_level integer DEFAULT 100 NOT NULL,
    permissions jsonb,
    is_primary_owner_role boolean DEFAULT false NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone
);


--
-- Name: business_template_workflows; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.business_template_workflows (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    business_template_id uuid NOT NULL,
    workflow_type character varying(255) NOT NULL,
    workflow_key character varying(255) NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    config jsonb,
    is_active boolean DEFAULT true NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone
);


--
-- Name: business_templates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.business_templates (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    template_key character varying(255) NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    industry_type character varying(255) NOT NULL,
    business_size character varying(255),
    version integer DEFAULT 1 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    is_default boolean DEFAULT false NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    metadata jsonb,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone
);


--
-- Name: campaign_metrics; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.campaign_metrics (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    campaign_id uuid NOT NULL,
    sent_count integer DEFAULT 0 NOT NULL,
    delivered_count integer DEFAULT 0 NOT NULL,
    opened_count integer DEFAULT 0 NOT NULL,
    clicked_count integer DEFAULT 0 NOT NULL,
    converted_count integer DEFAULT 0 NOT NULL,
    unsubscribed_count integer DEFAULT 0 NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: TABLE campaign_metrics; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.campaign_metrics IS '[Expansion Pack] Aggregated campaign performance counters.';


--
-- Name: campaigns; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.campaigns (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    name character varying(255) NOT NULL,
    type character varying(50) NOT NULL,
    status character varying(50) DEFAULT 'draft'::character varying NOT NULL,
    segment_id uuid,
    template_id uuid,
    budget numeric(12,2),
    spent numeric(12,2) DEFAULT 0,
    scheduled_at timestamp with time zone,
    started_at timestamp with time zone,
    completed_at timestamp with time zone,
    created_by uuid,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT campaigns_status_check CHECK (((status)::text = ANY (ARRAY[('draft'::character varying)::text, ('active'::character varying)::text, ('paused'::character varying)::text, ('completed'::character varying)::text, ('archived'::character varying)::text]))),
    CONSTRAINT campaigns_type_check CHECK (((type)::text = ANY (ARRAY[('email'::character varying)::text, ('sms'::character varying)::text, ('multi_channel'::character varying)::text])))
);


--
-- Name: TABLE campaigns; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.campaigns IS '[Expansion Pack] Marketing campaign lifecycle management.';


--
-- Name: cod_collections; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cod_collections (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    assignment_id uuid NOT NULL,
    driver_id uuid NOT NULL,
    amount_expected numeric(12,2) NOT NULL,
    amount_collected numeric(12,2),
    variance numeric(12,2) GENERATED ALWAYS AS ((COALESCE(amount_collected, (0)::numeric) - amount_expected)) STORED,
    settled boolean DEFAULT false NOT NULL,
    settled_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT cod_collections_amount_collected_check CHECK ((amount_collected >= (0)::numeric)),
    CONSTRAINT cod_collections_amount_expected_check CHECK ((amount_expected >= (0)::numeric))
);


--
-- Name: TABLE cod_collections; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.cod_collections IS '[Core v1] Cash-on-delivery collection tracking per assignment with variance detection.';


--
-- Name: commission_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.commission_entries (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    commission_plan_id uuid,
    commission_rule_id uuid,
    pipeline_record_id uuid NOT NULL,
    recipient_membership_id uuid NOT NULL,
    source_membership_id uuid,
    base_amount numeric(15,2) NOT NULL,
    commission_amount numeric(15,2) NOT NULL,
    currency character varying(10) DEFAULT 'LYD'::character varying NOT NULL,
    calculation_type character varying(50) NOT NULL,
    percentage_rate numeric(10,4),
    fixed_amount numeric(15,2),
    status character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    calculated_at timestamp(0) without time zone,
    approved_at timestamp(0) without time zone,
    paid_at timestamp(0) without time zone,
    notes text,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone
);


--
-- Name: commission_plans; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.commission_plans (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    plan_key character varying(255),
    name character varying(255) NOT NULL,
    description text,
    applies_to character varying(50) DEFAULT 'pipeline_record'::character varying NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone
);


--
-- Name: commission_rules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.commission_rules (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    commission_plan_id uuid NOT NULL,
    pipeline_id uuid,
    stage_id uuid,
    role_id uuid,
    department_id uuid,
    team_id uuid,
    target_type character varying(50) DEFAULT 'assigned_employee'::character varying NOT NULL,
    calculation_type character varying(50) DEFAULT 'percentage'::character varying NOT NULL,
    percentage_rate numeric(10,4),
    fixed_amount numeric(15,2),
    currency character varying(10) DEFAULT 'LYD'::character varying,
    min_record_value numeric(15,2),
    max_record_value numeric(15,2),
    trigger_status character varying(20) DEFAULT 'won'::character varying NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone
);


--
-- Name: communication_automations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.communication_automations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    name character varying(255) NOT NULL,
    trigger_event character varying(255) NOT NULL,
    conditions jsonb DEFAULT '{}'::jsonb NOT NULL,
    template_id uuid NOT NULL,
    channel_type character varying(50) NOT NULL,
    delay_minutes integer DEFAULT 0 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT communication_automations_channel_type_check CHECK (((channel_type)::text = ANY (ARRAY[('email'::character varying)::text, ('sms'::character varying)::text, ('whatsapp'::character varying)::text, ('push'::character varying)::text])))
);


--
-- Name: TABLE communication_automations; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.communication_automations IS 'Event-triggered messaging rules. Fires template-based messages when business events occur.';


--
-- Name: communication_channels; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.communication_channels (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    type character varying(50) NOT NULL,
    provider_name character varying(100) NOT NULL,
    provider_config jsonb DEFAULT '{}'::jsonb NOT NULL,
    is_default boolean DEFAULT false NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT communication_channels_type_check CHECK (((type)::text = ANY (ARRAY[('email'::character varying)::text, ('sms'::character varying)::text, ('whatsapp'::character varying)::text, ('push'::character varying)::text])))
);


--
-- Name: TABLE communication_channels; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.communication_channels IS 'Workspace channel provider registry. Each workspace configures its own email/SMS/push providers.';


--
-- Name: contacts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contacts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid,
    type character varying(50) NOT NULL,
    name character varying(255) NOT NULL,
    phone character varying(50),
    email character varying(255),
    address text,
    tax_number character varying(50),
    balance numeric(12,2) DEFAULT 0.00,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    assigned_membership_id uuid,
    CONSTRAINT chk_contact_balance_nonneg CHECK (((balance IS NULL) OR (balance >= (0)::numeric))),
    CONSTRAINT contacts_type_check CHECK (((type)::text = ANY (ARRAY[('customer'::character varying)::text, ('supplier'::character varying)::text, ('both'::character varying)::text])))
);


--
-- Name: country_packs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.country_packs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    country_code character varying(3) NOT NULL,
    name character varying(255) NOT NULL,
    version character varying(20) DEFAULT '1.0.0'::character varying NOT NULL,
    tax_config jsonb DEFAULT '{}'::jsonb NOT NULL,
    payroll_config jsonb DEFAULT '{}'::jsonb NOT NULL,
    invoice_config jsonb DEFAULT '{}'::jsonb NOT NULL,
    constants jsonb DEFAULT '{}'::jsonb NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: TABLE country_packs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.country_packs IS '[Core v1 framework] Platform-scoped country configuration bundles. Not workspace-scoped — no RLS.';


--
-- Name: coupons; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.coupons (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid,
    promotion_id uuid,
    code character varying(50) NOT NULL,
    max_uses integer,
    used_count integer DEFAULT 0,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT coupons_max_uses_check CHECK (((max_uses IS NULL) OR (max_uses > 0))),
    CONSTRAINT coupons_used_count_check CHECK ((used_count >= 0))
);


--
-- Name: credit_note_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.credit_note_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    credit_note_id uuid NOT NULL,
    product_id uuid,
    variant_id uuid,
    unit_id uuid,
    warehouse_id uuid,
    quantity numeric(12,4) NOT NULL,
    unit_price numeric(10,2) NOT NULL,
    discount_amount numeric(12,2) DEFAULT 0.00 NOT NULL,
    tax_amount numeric(12,2) DEFAULT 0.00 NOT NULL,
    subtotal numeric(12,2) NOT NULL,
    product_name_snapshot character varying(255),
    sku_snapshot character varying(100),
    tax_rate_snapshot numeric(5,2),
    original_invoice_item_id uuid,
    CONSTRAINT credit_note_items_discount_amount_check CHECK ((discount_amount >= (0)::numeric)),
    CONSTRAINT credit_note_items_quantity_check CHECK ((quantity > (0)::numeric)),
    CONSTRAINT credit_note_items_subtotal_check CHECK ((subtotal >= (0)::numeric)),
    CONSTRAINT credit_note_items_tax_amount_check CHECK ((tax_amount >= (0)::numeric)),
    CONSTRAINT credit_note_items_unit_price_check CHECK ((unit_price >= (0)::numeric))
);


--
-- Name: TABLE credit_note_items; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.credit_note_items IS 'Line-level detail for credit notes. Has direct workspace_id for RLS safety — never query this table without workspace scoping.';


--
-- Name: credit_notes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.credit_notes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    branch_id uuid,
    original_invoice_id uuid NOT NULL,
    contact_id uuid,
    created_by uuid,
    total_amount numeric(12,2) NOT NULL,
    tax_amount numeric(12,2) DEFAULT 0.00 NOT NULL,
    net_amount numeric(12,2) NOT NULL,
    reason text NOT NULL,
    status character varying(50) DEFAULT 'draft'::character varying NOT NULL,
    credit_note_number character varying(50),
    currency character varying(10) DEFAULT 'LYD'::character varying NOT NULL,
    exchange_rate numeric(10,4) DEFAULT 1.0000 NOT NULL,
    reversal_journal_entry_id uuid,
    issued_at timestamp with time zone,
    voided_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT credit_notes_check CHECK ((net_amount <= total_amount)),
    CONSTRAINT credit_notes_net_amount_check CHECK ((net_amount > (0)::numeric)),
    CONSTRAINT credit_notes_status_check CHECK (((status)::text = ANY (ARRAY[('draft'::character varying)::text, ('issued'::character varying)::text, ('applied'::character varying)::text, ('void'::character varying)::text]))),
    CONSTRAINT credit_notes_tax_amount_check CHECK ((tax_amount >= (0)::numeric)),
    CONSTRAINT credit_notes_total_amount_check CHECK ((total_amount > (0)::numeric))
);


--
-- Name: TABLE credit_notes; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.credit_notes IS 'Credit notes issued against invoices (BR-INV-004). A credit note is a negative adjustment that can be applied as a customer credit or refunded.';


--
-- Name: COLUMN credit_notes.contact_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.credit_notes.contact_id IS 'Must match original invoice contact (app-enforced). Denormalized here for query convenience.';


--
-- Name: COLUMN credit_notes.total_amount; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.credit_notes.total_amount IS 'Positive value representing the credited amount (before tax adjustments). Must not exceed original invoice creditable balance (app-enforced).';


--
-- Name: COLUMN credit_notes.status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.credit_notes.status IS 'FSM: draft → issued → applied | void. Issued credit notes are immutable.';


--
-- Name: COLUMN credit_notes.currency; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.credit_notes.currency IS 'Must match original invoice currency (app-enforced). Mismatches rejected at service layer.';


--
-- Name: crm_activities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.crm_activities (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid,
    user_id uuid,
    lead_id uuid,
    opportunity_id uuid,
    contact_id uuid,
    activity_type character varying(50) NOT NULL,
    subject character varying(255),
    description text,
    scheduled_at timestamp with time zone,
    completed_at timestamp with time zone,
    status character varying(50) DEFAULT 'planned'::character varying,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT crm_activities_activity_type_check CHECK (((activity_type)::text = ANY (ARRAY[('call'::character varying)::text, ('email'::character varying)::text, ('meeting'::character varying)::text, ('note'::character varying)::text, ('whatsapp'::character varying)::text]))),
    CONSTRAINT crm_activities_status_check CHECK (((status)::text = ANY (ARRAY[('planned'::character varying)::text, ('completed'::character varying)::text, ('cancelled'::character varying)::text])))
);


--
-- Name: custom_field_values; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.custom_field_values (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    custom_field_id uuid NOT NULL,
    record_type character varying(50) DEFAULT 'pipeline_record'::character varying NOT NULL,
    record_id uuid NOT NULL,
    value_text text,
    value_number numeric(18,4),
    value_boolean boolean,
    value_date date,
    value_json json,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone
);


--
-- Name: custom_fields; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.custom_fields (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    pipeline_id uuid,
    field_key character varying(255),
    label character varying(255) NOT NULL,
    field_type character varying(30) NOT NULL,
    options json,
    is_required boolean DEFAULT false NOT NULL,
    applies_to character varying(50) DEFAULT 'pipeline_record'::character varying NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone
);


--
-- Name: customer_credits; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customer_credits (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    contact_id uuid NOT NULL,
    movement_type character varying(50) NOT NULL,
    amount numeric(12,2) NOT NULL,
    balance_after numeric(12,2) NOT NULL,
    payment_id uuid,
    credit_note_id uuid,
    invoice_id uuid,
    currency character varying(10) DEFAULT 'LYD'::character varying NOT NULL,
    created_by uuid,
    notes text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT customer_credits_amount_check CHECK ((amount <> (0)::numeric)),
    CONSTRAINT customer_credits_balance_after_check CHECK ((balance_after >= (0)::numeric)),
    CONSTRAINT customer_credits_movement_type_check CHECK (((movement_type)::text = ANY (ARRAY[('overpayment'::character varying)::text, ('credit_note'::character varying)::text, ('manual_grant'::character varying)::text, ('invoice_offset'::character varying)::text, ('refund'::character varying)::text, ('manual_debit'::character varying)::text, ('expiry'::character varying)::text])))
);


--
-- Name: TABLE customer_credits; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.customer_credits IS 'Ledger of customer credit movements (BR-PAY-004). Tracks overpayments, credit note applications, offsets against invoices, and refunds.';


--
-- Name: COLUMN customer_credits.amount; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.customer_credits.amount IS 'Positive = credit granted; negative = credit consumed. Zero is forbidden.';


--
-- Name: COLUMN customer_credits.balance_after; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.customer_credits.balance_after IS 'APPLICATION-MAINTAINED running balance for this contact after this movement. Must never go negative (enforced by CHECK constraint). Calculated at application layer as: previous balance_after + current amount. The application MUST use SELECT FOR UPDATE on the latest row for this (workspace_id, contact_id) ordered by created_at DESC to prevent race conditions. Periodic reconciliation jobs SHOULD verify balance_after consistency against SUM(amount). This column is NOT maintained by database triggers — it is the responsibility of the service layer.';


--
-- Name: customer_subscriptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customer_subscriptions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid,
    contact_id uuid,
    product_id uuid,
    plan_name character varying(255) NOT NULL,
    billing_cycle character varying(50) DEFAULT 'monthly'::character varying,
    amount numeric(12,2) NOT NULL,
    start_date date NOT NULL,
    end_date date,
    next_billing_date date NOT NULL,
    auto_renew boolean DEFAULT true,
    status character varying(50) DEFAULT 'active'::character varying,
    cancellation_reason text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT customer_subscriptions_amount_check CHECK ((amount > (0)::numeric)),
    CONSTRAINT customer_subscriptions_billing_cycle_check CHECK (((billing_cycle)::text = ANY (ARRAY[('weekly'::character varying)::text, ('monthly'::character varying)::text, ('quarterly'::character varying)::text, ('semi_annual'::character varying)::text, ('annual'::character varying)::text]))),
    CONSTRAINT customer_subscriptions_status_check CHECK (((status)::text = ANY (ARRAY[('active'::character varying)::text, ('paused'::character varying)::text, ('cancelled'::character varying)::text, ('expired'::character varying)::text])))
);


--
-- Name: delivery_assignments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.delivery_assignments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    order_id uuid NOT NULL,
    driver_id uuid NOT NULL,
    zone_id uuid,
    status character varying(50) DEFAULT 'pending'::character varying NOT NULL,
    assigned_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    accepted_at timestamp with time zone,
    picked_up_at timestamp with time zone,
    delivered_at timestamp with time zone,
    failed_reason text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT delivery_assignments_status_check CHECK (((status)::text = ANY (ARRAY[('pending'::character varying)::text, ('accepted'::character varying)::text, ('rejected'::character varying)::text, ('picked_up'::character varying)::text, ('in_transit'::character varying)::text, ('delivered'::character varying)::text, ('failed'::character varying)::text, ('returned'::character varying)::text])))
);


--
-- Name: TABLE delivery_assignments; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.delivery_assignments IS '[Core v1] Order-to-driver assignment lifecycle. Strict FSM: pending→accepted→picked_up→in_transit→delivered|failed.';


--
-- Name: delivery_proofs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.delivery_proofs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    assignment_id uuid NOT NULL,
    photo_path character varying(500),
    signature_path character varying(500),
    pin_code character varying(10),
    receiver_name character varying(255),
    captured_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: TABLE delivery_proofs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.delivery_proofs IS '[Core v1] Proof of delivery: photo, signature, and/or PIN. One proof per assignment.';


--
-- Name: delivery_sla_breaches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.delivery_sla_breaches (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    assignment_id uuid NOT NULL,
    zone_id uuid,
    target_minutes integer NOT NULL,
    actual_minutes integer NOT NULL,
    breached_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: TABLE delivery_sla_breaches; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.delivery_sla_breaches IS '[Expansion Pack] Delivery SLA breach records for performance analysis.';


--
-- Name: delivery_tracking; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.delivery_tracking (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    assignment_id uuid NOT NULL,
    latitude numeric(10,7) NOT NULL,
    longitude numeric(10,7) NOT NULL,
    captured_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    event_type character varying(50) DEFAULT 'location_update'::character varying,
    CONSTRAINT delivery_tracking_event_type_check CHECK (((event_type)::text = ANY (ARRAY[('location_update'::character varying)::text, ('status_change'::character varying)::text])))
);


--
-- Name: TABLE delivery_tracking; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.delivery_tracking IS '[Expansion Pack] Real-time GPS tracking points for active deliveries.';


--
-- Name: delivery_zones; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.delivery_zones (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    name character varying(255) NOT NULL,
    boundary_geojson jsonb,
    sla_minutes integer,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: TABLE delivery_zones; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.delivery_zones IS '[Core v1] Delivery zones with optional GeoJSON boundaries and SLA targets.';


--
-- Name: departments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.departments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid,
    name character varying(255) NOT NULL,
    manager_id uuid,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    parent_department_id uuid,
    description text,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    department_key character varying(255),
    manager_membership_id uuid,
    is_active boolean DEFAULT true NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL
);


--
-- Name: COLUMN departments.parent_department_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.departments.parent_department_id IS 'Self-referencing FK for department hierarchy (NULL = top-level).';


--
-- Name: dining_tables; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dining_tables (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid,
    branch_id uuid,
    table_number character varying(50) NOT NULL,
    capacity integer DEFAULT 4,
    location_zone character varying(100),
    status character varying(50) DEFAULT 'available'::character varying,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT dining_tables_status_check CHECK (((status)::text = ANY (ARRAY[('available'::character varying)::text, ('occupied'::character varying)::text, ('reserved'::character varying)::text, ('maintenance'::character varying)::text])))
);


--
-- Name: discovery_blueprints; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.discovery_blueprints (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    session_id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    business_type character varying(50) NOT NULL,
    blueprint jsonb DEFAULT '{}'::jsonb NOT NULL,
    version integer DEFAULT 1 NOT NULL,
    generator_method character varying(30) DEFAULT 'rule_based_v1'::character varying NOT NULL,
    generator_version character varying(20) DEFAULT '1.0.0'::character varying NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: discovery_messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.discovery_messages (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    session_id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    role character varying(10) NOT NULL,
    content text NOT NULL,
    message_type character varying(30) NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT discovery_messages_message_type_check CHECK (((message_type)::text = ANY ((ARRAY['description'::character varying, 'follow_up_question'::character varying, 'answer'::character varying, 'classification'::character varying, 'blueprint'::character varying, 'ready'::character varying])::text[]))),
    CONSTRAINT discovery_messages_role_check CHECK (((role)::text = ANY (ARRAY[('user'::character varying)::text, ('ai'::character varying)::text])))
);


--
-- Name: discovery_sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.discovery_sessions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    created_by uuid NOT NULL,
    status character varying(30) DEFAULT 'intake'::character varying NOT NULL,
    business_description text NOT NULL,
    business_type character varying(50),
    classification_confidence numeric(5,2),
    classification_method character varying(30) DEFAULT 'rule_based_v1'::character varying,
    classification_version character varying(20) DEFAULT '1.0.0'::character varying,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    discovery_state jsonb,
    CONSTRAINT discovery_sessions_classification_confidence_check CHECK (((classification_confidence IS NULL) OR ((classification_confidence >= (0)::numeric) AND (classification_confidence <= (100)::numeric)))),
    CONSTRAINT discovery_sessions_status_check CHECK (((status)::text = ANY (ARRAY[('intake'::character varying)::text, ('questioning'::character varying)::text, ('classifying'::character varying)::text, ('blueprint_ready'::character varying)::text, ('completed'::character varying)::text])))
);


--
-- Name: document_checklist_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.document_checklist_items (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    document_checklist_id uuid NOT NULL,
    item_key character varying(255),
    title character varying(255) NOT NULL,
    description text,
    is_required boolean DEFAULT true NOT NULL,
    accepted_file_types json,
    max_file_size_mb integer DEFAULT 10,
    sort_order integer DEFAULT 0 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone
);


--
-- Name: document_checklists; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.document_checklists (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    pipeline_id uuid,
    stage_id uuid,
    checklist_key character varying(255),
    name character varying(255) NOT NULL,
    description text,
    is_active boolean DEFAULT true NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone
);


--
-- Name: document_sequences; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.document_sequences (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid,
    document_type character varying(50) NOT NULL,
    prefix character varying(20) DEFAULT ''::character varying,
    suffix character varying(20) DEFAULT ''::character varying,
    next_number integer DEFAULT 1 NOT NULL,
    padding integer DEFAULT 4,
    reset_period character varying(20),
    last_reset_date date,
    include_year boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT document_sequences_document_type_check CHECK (((document_type)::text = ANY (ARRAY[('invoice'::character varying)::text, ('order'::character varying)::text, ('payment'::character varying)::text, ('shipment'::character varying)::text, ('production_order'::character varying)::text, ('stock_transfer'::character varying)::text]))),
    CONSTRAINT document_sequences_reset_period_check CHECK (((reset_period IS NULL) OR ((reset_period)::text = ANY (ARRAY[('yearly'::character varying)::text, ('monthly'::character varying)::text, ('never'::character varying)::text]))))
);


--
-- Name: drivers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.drivers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    user_id uuid NOT NULL,
    vehicle_type character varying(50),
    vehicle_plate character varying(50),
    license_number character varying(100),
    zone_ids jsonb DEFAULT '[]'::jsonb NOT NULL,
    status character varying(50) DEFAULT 'offline'::character varying NOT NULL,
    branch_id uuid,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT drivers_status_check CHECK (((status)::text = ANY (ARRAY[('available'::character varying)::text, ('busy'::character varying)::text, ('offline'::character varying)::text, ('suspended'::character varying)::text]))),
    CONSTRAINT drivers_vehicle_type_check CHECK (((vehicle_type)::text = ANY (ARRAY[('motorcycle'::character varying)::text, ('car'::character varying)::text, ('van'::character varying)::text, ('truck'::character varying)::text, ('bicycle'::character varying)::text, ('other'::character varying)::text])))
);


--
-- Name: TABLE drivers; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.drivers IS '[Core v1] Delivery driver/rider profiles with vehicle info and zone assignments.';


--
-- Name: duplicate_matches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.duplicate_matches (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    duplicate_rule_id uuid,
    entity_type character varying(50) NOT NULL,
    source_entity_id uuid NOT NULL,
    matched_entity_id uuid NOT NULL,
    match_fields json,
    match_score numeric(5,2) DEFAULT '100'::numeric,
    status character varying(20) DEFAULT 'open'::character varying NOT NULL,
    resolution character varying(30),
    resolved_by_membership_id uuid,
    resolved_at timestamp(0) without time zone,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone
);


--
-- Name: duplicate_rules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.duplicate_rules (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    rule_key character varying(255),
    name character varying(255) NOT NULL,
    entity_type character varying(50) NOT NULL,
    match_fields json NOT NULL,
    match_strategy character varying(30) DEFAULT 'normalized_exact'::character varying NOT NULL,
    action character varying(10) DEFAULT 'warn'::character varying NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone
);


--
-- Name: email_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.email_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    recipient_email character varying(255) NOT NULL,
    recipient_name character varying(255),
    template character varying(100) NOT NULL,
    template_version character varying(20) DEFAULT 'v1'::character varying,
    subject character varying(500) NOT NULL,
    status character varying(20) DEFAULT 'queued'::character varying NOT NULL,
    delivery_mode character varying(20) DEFAULT 'immediate'::character varying NOT NULL,
    retries integer DEFAULT 0 NOT NULL,
    max_retries integer DEFAULT 3 NOT NULL,
    mailer_provider character varying(50) DEFAULT 'smtp'::character varying,
    actor_user_id uuid,
    event_name character varying(100),
    correlation_key character varying(255),
    related_entity_type character varying(50),
    related_entity_id uuid,
    error_message text,
    metadata jsonb DEFAULT '{}'::jsonb,
    sent_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    dedup_key character varying(255),
    CONSTRAINT email_logs_delivery_mode_check CHECK (((delivery_mode)::text = ANY (ARRAY[('immediate'::character varying)::text, ('queued'::character varying)::text, ('retry'::character varying)::text]))),
    CONSTRAINT email_logs_status_check CHECK (((status)::text = ANY (ARRAY[('queued'::character varying)::text, ('sending'::character varying)::text, ('sent'::character varying)::text, ('failed'::character varying)::text, ('retrying'::character varying)::text])))
);


--
-- Name: email_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.email_settings (
    workspace_id uuid NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    daily_limit integer DEFAULT 200,
    from_name_override character varying(255),
    from_email_override character varying(255),
    reply_to character varying(255),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: exchange_rates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.exchange_rates (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    base_currency character varying(3) NOT NULL,
    target_currency character varying(3) NOT NULL,
    rate numeric(18,8) NOT NULL,
    inverse_rate numeric(18,8) NOT NULL,
    effective_date date NOT NULL,
    source character varying(50) DEFAULT 'manual'::character varying NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT exchange_rates_check CHECK (((base_currency)::text <> (target_currency)::text)),
    CONSTRAINT exchange_rates_inverse_rate_check CHECK ((inverse_rate > (0)::numeric)),
    CONSTRAINT exchange_rates_rate_check CHECK ((rate > (0)::numeric)),
    CONSTRAINT exchange_rates_source_check CHECK (((source)::text = ANY (ARRAY[('manual'::character varying)::text, ('api'::character varying)::text, ('central_bank'::character varying)::text])))
);


--
-- Name: TABLE exchange_rates; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.exchange_rates IS 'Workspace-scoped daily exchange rates. Used for multi-currency journal conversion and financial report consolidation.';


--
-- Name: COLUMN exchange_rates.rate; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.exchange_rates.rate IS '1 unit of base_currency = rate units of target_currency.';


--
-- Name: COLUMN exchange_rates.inverse_rate; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.exchange_rates.inverse_rate IS 'APPLICATION-MAINTAINED: must equal 1/rate. Pre-computed for query convenience. Application must set both rate and inverse_rate atomically on insert.';


--
-- Name: COLUMN exchange_rates.effective_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.exchange_rates.effective_date IS 'Date from which this rate is valid. Rate lookup uses the most recent effective_date <= transaction_date.';


--
-- Name: export_jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.export_jobs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    entity_type character varying(100) NOT NULL,
    format character varying(20) DEFAULT 'csv'::character varying NOT NULL,
    filters jsonb DEFAULT '{}'::jsonb NOT NULL,
    status character varying(50) DEFAULT 'queued'::character varying NOT NULL,
    file_path character varying(500),
    created_by uuid,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT export_jobs_format_check CHECK (((format)::text = ANY (ARRAY[('csv'::character varying)::text, ('xlsx'::character varying)::text, ('xml'::character varying)::text, ('json'::character varying)::text]))),
    CONSTRAINT export_jobs_status_check CHECK (((status)::text = ANY (ARRAY[('queued'::character varying)::text, ('processing'::character varying)::text, ('completed'::character varying)::text, ('failed'::character varying)::text])))
);


--
-- Name: TABLE export_jobs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.export_jobs IS '[Core v1] Bulk data export pipeline with format and filter options.';


--
-- Name: finance_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.finance_accounts (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    account_key character varying(50),
    code character varying(20),
    name character varying(255) NOT NULL,
    type character varying(20) NOT NULL,
    normal_balance character varying(10) NOT NULL,
    is_system boolean DEFAULT false NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone
);


--
-- Name: finance_expenses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.finance_expenses (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    expense_date date NOT NULL,
    category character varying(100),
    description text NOT NULL,
    amount numeric(15,2) NOT NULL,
    currency character varying(10) DEFAULT 'LYD'::character varying NOT NULL,
    payment_method character varying(30),
    paid_by_membership_id uuid,
    finance_transaction_id uuid,
    status character varying(20) DEFAULT 'posted'::character varying NOT NULL,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone
);


--
-- Name: finance_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.finance_settings (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    default_cash_account_id uuid,
    default_bank_account_id uuid,
    default_revenue_account_id uuid,
    default_accounts_receivable_account_id uuid,
    default_commission_expense_account_id uuid,
    default_commission_payable_account_id uuid,
    default_general_expense_account_id uuid,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone
);


--
-- Name: finance_transaction_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.finance_transaction_lines (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    finance_transaction_id uuid NOT NULL,
    finance_account_id uuid NOT NULL,
    description text,
    debit_amount numeric(15,2) DEFAULT '0'::numeric NOT NULL,
    credit_amount numeric(15,2) DEFAULT '0'::numeric NOT NULL,
    currency character varying(10) DEFAULT 'LYD'::character varying NOT NULL,
    line_order integer DEFAULT 0 NOT NULL,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone
);


--
-- Name: finance_transactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.finance_transactions (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    transaction_number character varying(50),
    transaction_date date NOT NULL,
    description text,
    source_type character varying(50),
    source_id uuid,
    status character varying(20) DEFAULT 'posted'::character varying NOT NULL,
    currency character varying(10) DEFAULT 'LYD'::character varying NOT NULL,
    total_debit numeric(15,2) DEFAULT '0'::numeric NOT NULL,
    total_credit numeric(15,2) DEFAULT '0'::numeric NOT NULL,
    posted_by_membership_id uuid,
    posted_at timestamp(0) without time zone,
    voided_at timestamp(0) without time zone,
    metadata json,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone
);


--
-- Name: fiscal_periods; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fiscal_periods (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    name character varying(100) NOT NULL,
    period_type character varying(50) DEFAULT 'monthly'::character varying NOT NULL,
    start_date date NOT NULL,
    end_date date NOT NULL,
    fiscal_year integer NOT NULL,
    status character varying(50) DEFAULT 'open'::character varying NOT NULL,
    closed_at timestamp with time zone,
    closed_by uuid,
    locked_at timestamp with time zone,
    locked_by uuid,
    last_reopened_at timestamp with time zone,
    last_reopened_by uuid,
    reopen_count integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT fiscal_periods_check CHECK ((end_date > start_date)),
    CONSTRAINT fiscal_periods_check1 CHECK ((((status)::text <> 'locked'::text) OR (locked_at IS NOT NULL))),
    CONSTRAINT fiscal_periods_check2 CHECK ((((status)::text <> ALL (ARRAY[('closed'::character varying)::text, ('locked'::character varying)::text])) OR (closed_at IS NOT NULL))),
    CONSTRAINT fiscal_periods_fiscal_year_check CHECK (((fiscal_year >= 2000) AND (fiscal_year <= 2100))),
    CONSTRAINT fiscal_periods_period_type_check CHECK (((period_type)::text = ANY (ARRAY[('monthly'::character varying)::text, ('quarterly'::character varying)::text, ('semi_annual'::character varying)::text, ('annual'::character varying)::text, ('custom'::character varying)::text]))),
    CONSTRAINT fiscal_periods_reopen_count_check CHECK ((reopen_count >= 0)),
    CONSTRAINT fiscal_periods_status_check CHECK (((status)::text = ANY (ARRAY[('open'::character varying)::text, ('closed'::character varying)::text, ('locked'::character varying)::text])))
);


--
-- Name: TABLE fiscal_periods; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.fiscal_periods IS 'Workspace fiscal periods for accounting period management (BR-FIN-004). Transactions may only be posted to open periods. Locked periods are permanently sealed. Overlapping periods within a workspace are prevented by exclusion constraint.';


--
-- Name: COLUMN fiscal_periods.status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.fiscal_periods.status IS 'open = accepts postings; closed = no postings, may be reopened; locked = permanently sealed, CANNOT be reopened.';


--
-- Name: COLUMN fiscal_periods.reopen_count; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.fiscal_periods.reopen_count IS 'Number of times this period has been reopened from closed state. Audit indicator.';


--
-- Name: fixed_assets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fixed_assets (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid,
    name character varying(255) NOT NULL,
    purchase_date date NOT NULL,
    purchase_price numeric(12,2) NOT NULL,
    current_value numeric(12,2) NOT NULL,
    depreciation_rate numeric(5,2) DEFAULT 0.00,
    status character varying(50) DEFAULT 'active'::character varying,
    notes text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fixed_assets_status_check CHECK (((status)::text = ANY (ARRAY[('active'::character varying)::text, ('disposed'::character varying)::text, ('under_maintenance'::character varying)::text])))
);


--
-- Name: goods_received_notes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.goods_received_notes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    po_id uuid NOT NULL,
    warehouse_id uuid NOT NULL,
    received_by uuid,
    grn_number character varying(50),
    status character varying(50) DEFAULT 'draft'::character varying NOT NULL,
    received_date date DEFAULT CURRENT_DATE NOT NULL,
    confirmed_at timestamp with time zone,
    cancelled_at timestamp with time zone,
    notes text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT goods_received_notes_check CHECK ((((status)::text <> 'confirmed'::text) OR (confirmed_at IS NOT NULL))),
    CONSTRAINT goods_received_notes_check1 CHECK ((((status)::text <> 'cancelled'::text) OR (cancelled_at IS NOT NULL))),
    CONSTRAINT goods_received_notes_status_check CHECK (((status)::text = ANY (ARRAY[('draft'::character varying)::text, ('confirmed'::character varying)::text, ('cancelled'::character varying)::text])))
);


--
-- Name: grn_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.grn_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    grn_id uuid NOT NULL,
    po_item_id uuid NOT NULL,
    product_id uuid NOT NULL,
    variant_id uuid,
    quantity_received numeric(12,4) NOT NULL,
    condition character varying(50) DEFAULT 'good'::character varying NOT NULL,
    batch_number character varying(100),
    expiry_date date,
    unit_cost numeric(12,4),
    notes text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT grn_items_condition_check CHECK (((condition)::text = ANY (ARRAY[('good'::character varying)::text, ('damaged'::character varying)::text, ('partial'::character varying)::text]))),
    CONSTRAINT grn_items_quantity_received_check CHECK ((quantity_received > (0)::numeric))
);


--
-- Name: idempotency_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.idempotency_keys (
    key character varying(255) NOT NULL,
    workspace_id uuid NOT NULL,
    user_id uuid,
    response_status integer,
    response_body jsonb,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    expires_at timestamp with time zone DEFAULT (CURRENT_TIMESTAMP + '24:00:00'::interval) NOT NULL
);


--
-- Name: TABLE idempotency_keys; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.idempotency_keys IS 'Stores idempotency key → response mappings to ensure financial write operations are safe to retry.';


--
-- Name: COLUMN idempotency_keys.expires_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.idempotency_keys.expires_at IS 'Keys expire after 24 hours by default; cleanup via scheduled job.';


--
-- Name: impersonation_sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.impersonation_sessions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    platform_user_id uuid NOT NULL,
    target_workspace_id uuid NOT NULL,
    target_user_id uuid,
    reason text NOT NULL,
    started_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    ended_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT chk_impersonation_future_expiry CHECK ((expires_at > started_at)),
    CONSTRAINT chk_impersonation_max_duration CHECK ((expires_at <= (started_at + '01:00:00'::interval)))
);


--
-- Name: TABLE impersonation_sessions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.impersonation_sessions IS 'Tracks platform admin impersonation of workspace users. DB-enforced 1-hour max duration. Immutable audit trail. Application MUST check expires_at on every impersonated request. ended_at is set when admin explicitly ends session or when expires_at is reached.';


--
-- Name: import_jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.import_jobs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    entity_type character varying(100) NOT NULL,
    file_path character varying(500) NOT NULL,
    status character varying(50) DEFAULT 'uploaded'::character varying NOT NULL,
    total_rows integer,
    valid_rows integer,
    error_rows integer,
    errors jsonb,
    created_by uuid,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT import_jobs_status_check CHECK (((status)::text = ANY (ARRAY[('uploaded'::character varying)::text, ('validating'::character varying)::text, ('preview'::character varying)::text, ('applying'::character varying)::text, ('completed'::character varying)::text, ('failed'::character varying)::text])))
);


--
-- Name: TABLE import_jobs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.import_jobs IS '[Core v1] Bulk data import pipeline with validation and preview.';


--
-- Name: inbound_messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inbound_messages (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    channel_type character varying(50) NOT NULL,
    from_address character varying(500) NOT NULL,
    thread_id uuid,
    contact_id uuid,
    entity_type character varying(100),
    entity_id uuid,
    body text NOT NULL,
    received_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT inbound_messages_channel_type_check CHECK (((channel_type)::text = ANY (ARRAY[('email'::character varying)::text, ('sms'::character varying)::text, ('whatsapp'::character varying)::text])))
);


--
-- Name: TABLE inbound_messages; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.inbound_messages IS '[Expansion Pack] Inbound message threading. Associates replies with contacts and business entities.';


--
-- Name: integration_providers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.integration_providers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    type character varying(50) NOT NULL,
    name character varying(100) NOT NULL,
    adapter_class character varying(255) NOT NULL,
    config_schema jsonb DEFAULT '{}'::jsonb NOT NULL,
    is_available boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT integration_providers_type_check CHECK (((type)::text = ANY (ARRAY[('payment'::character varying)::text, ('email'::character varying)::text, ('sms'::character varying)::text, ('ecommerce'::character varying)::text, ('accounting'::character varying)::text, ('storage'::character varying)::text, ('other'::character varying)::text])))
);


--
-- Name: TABLE integration_providers; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.integration_providers IS '[Core v1] Platform-scoped integration provider catalog. Not workspace-scoped — no RLS.';


--
-- Name: inventory_batches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventory_batches (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid,
    warehouse_id uuid,
    product_id uuid,
    variant_id uuid,
    batch_number character varying(100),
    serial_number character varying(100),
    expiry_date date,
    manufacturing_date date,
    quantity numeric(12,4) DEFAULT 0 NOT NULL,
    cost_per_unit numeric(10,2),
    status character varying(50) DEFAULT 'available'::character varying,
    notes text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT inventory_batches_status_check CHECK (((status)::text = ANY (ARRAY[('available'::character varying)::text, ('expired'::character varying)::text, ('recalled'::character varying)::text, ('consumed'::character varying)::text])))
);


--
-- Name: inventory_levels; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventory_levels (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    warehouse_id uuid NOT NULL,
    product_id uuid NOT NULL,
    variant_id uuid,
    quantity numeric(12,4) DEFAULT 0 NOT NULL,
    reserved numeric(12,4) DEFAULT 0 NOT NULL,
    available numeric(12,4) DEFAULT 0 NOT NULL,
    reorder_point numeric(12,4),
    max_stock numeric(12,4),
    workspace_id uuid NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT chk_inventory_available_consistency CHECK ((available = (quantity - reserved))),
    CONSTRAINT chk_inventory_no_negative_stock CHECK ((quantity >= (0)::numeric)),
    CONSTRAINT chk_inventory_reserved_consistency CHECK ((reserved <= quantity)),
    CONSTRAINT inventory_levels_max_stock_check CHECK (((max_stock IS NULL) OR (max_stock > (0)::numeric))),
    CONSTRAINT inventory_levels_reorder_point_check CHECK (((reorder_point IS NULL) OR (reorder_point >= (0)::numeric))),
    CONSTRAINT inventory_levels_reserved_check CHECK ((reserved >= (0)::numeric))
);
ALTER TABLE ONLY public.inventory_levels ALTER COLUMN warehouse_id SET STATISTICS 500;
ALTER TABLE ONLY public.inventory_levels ALTER COLUMN product_id SET STATISTICS 500;
ALTER TABLE ONLY public.inventory_levels ALTER COLUMN workspace_id SET STATISTICS 500;


--
-- Name: COLUMN inventory_levels.reserved; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.inventory_levels.reserved IS 'APPLICATION-MAINTAINED. Quantity reserved by confirmed orders. Increased on order confirmation (BR-STK-001), decreased on shipment or cancellation (BR-STK-002/003). MUST use SELECT FOR UPDATE for concurrency safety (see CONCURRENCY SAFETY MODEL in header).';


--
-- Name: COLUMN inventory_levels.available; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.inventory_levels.available IS 'DB-MAINTAINED via trg_inventory_levels_sync_available trigger: available = quantity - reserved. Also enforced by CHECK constraint chk_inventory_available_consistency. Used for fast stock availability queries without computing at read time.';


--
-- Name: COLUMN inventory_levels.reorder_point; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.inventory_levels.reorder_point IS 'When available drops to or below this value, a low_stock_alert notification is generated (BR-STK-012).';


--
-- Name: COLUMN inventory_levels.max_stock; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.inventory_levels.max_stock IS 'Maximum desired stock level. Used for reorder quantity suggestions: reorder_qty = max_stock - available.';


--
-- Name: CONSTRAINT chk_inventory_no_negative_stock ON inventory_levels; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON CONSTRAINT chk_inventory_no_negative_stock ON public.inventory_levels IS 'Default negative-stock prevention (BR-STK-004). Workspace override for negative stock is APP-ENFORCED; privileged operations may bypass this CHECK when allow_negative_stock is enabled.';


--
-- Name: inventory_logs_legacy; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventory_logs_legacy (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid,
    warehouse_id uuid,
    product_id uuid,
    user_id uuid,
    change_type character varying(50) NOT NULL,
    quantity_changed numeric(12,4) NOT NULL,
    new_quantity numeric(12,4) NOT NULL,
    notes text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: TABLE inventory_logs_legacy; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.inventory_logs_legacy IS '🚫 DEPRECATED (Migration 008). Renamed from inventory_logs. Replaced by inventory_movements (immutable, typed, with source references). Opening balances created in 007 Section 8. ROLLBACK: ALTER TABLE inventory_logs_legacy RENAME TO inventory_logs;';


--
-- Name: inventory_movements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventory_movements (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    warehouse_id uuid NOT NULL,
    product_id uuid NOT NULL,
    variant_id uuid,
    batch_id uuid,
    movement_type character varying(50) NOT NULL,
    quantity_change numeric(12,4) NOT NULL,
    quantity_before numeric(12,4) NOT NULL,
    quantity_after numeric(12,4) NOT NULL,
    unit_cost numeric(12,4),
    total_cost numeric(15,2),
    reference_type character varying(50),
    reference_id uuid,
    created_by uuid,
    reason_code character varying(100),
    notes text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT inventory_movements_check CHECK ((quantity_after = (quantity_before + quantity_change))),
    CONSTRAINT inventory_movements_check1 CHECK (((((movement_type)::text = ANY (ARRAY[('purchase_receipt'::character varying)::text, ('return_restock'::character varying)::text, ('adjustment_increase'::character varying)::text, ('transfer_in'::character varying)::text, ('production_output'::character varying)::text, ('opening_balance'::character varying)::text])) AND (quantity_change > (0)::numeric)) OR (((movement_type)::text = ANY (ARRAY[('sale_shipment'::character varying)::text, ('return_dispose'::character varying)::text, ('supplier_return'::character varying)::text, ('adjustment_decrease'::character varying)::text, ('transfer_out'::character varying)::text, ('production_consume'::character varying)::text, ('damage'::character varying)::text, ('shrinkage'::character varying)::text, ('expired'::character varying)::text])) AND (quantity_change < (0)::numeric)))),
    CONSTRAINT inventory_movements_check2 CHECK (((reference_type IS NULL) OR (((movement_type)::text = 'sale_shipment'::text) AND ((reference_type)::text = 'shipment'::text)) OR (((movement_type)::text = 'purchase_receipt'::text) AND ((reference_type)::text = 'grn'::text)) OR (((movement_type)::text = ANY (ARRAY[('return_restock'::character varying)::text, ('return_dispose'::character varying)::text])) AND ((reference_type)::text = 'return'::text)) OR (((movement_type)::text = 'supplier_return'::text) AND ((reference_type)::text = 'return'::text)) OR (((movement_type)::text = ANY (ARRAY[('transfer_out'::character varying)::text, ('transfer_in'::character varying)::text])) AND ((reference_type)::text = 'transfer'::text)) OR (((movement_type)::text = ANY (ARRAY[('production_consume'::character varying)::text, ('production_output'::character varying)::text])) AND ((reference_type)::text = 'production_order'::text)) OR (((movement_type)::text = ANY (ARRAY[('adjustment_increase'::character varying)::text, ('adjustment_decrease'::character varying)::text, ('damage'::character varying)::text, ('shrinkage'::character varying)::text, ('expired'::character varying)::text])) AND ((reference_type)::text = 'adjustment'::text)) OR (((movement_type)::text = 'opening_balance'::text) AND ((reference_type)::text = 'opening'::text)))),
    CONSTRAINT inventory_movements_movement_type_check CHECK (((movement_type)::text = ANY (ARRAY[('purchase_receipt'::character varying)::text, ('sale_shipment'::character varying)::text, ('return_restock'::character varying)::text, ('return_dispose'::character varying)::text, ('supplier_return'::character varying)::text, ('adjustment_increase'::character varying)::text, ('adjustment_decrease'::character varying)::text, ('transfer_out'::character varying)::text, ('transfer_in'::character varying)::text, ('production_consume'::character varying)::text, ('production_output'::character varying)::text, ('opening_balance'::character varying)::text, ('damage'::character varying)::text, ('shrinkage'::character varying)::text, ('expired'::character varying)::text]))),
    CONSTRAINT inventory_movements_quantity_change_check CHECK ((quantity_change <> (0)::numeric)),
    CONSTRAINT inventory_movements_reference_type_check CHECK (((reference_type IS NULL) OR ((reference_type)::text = ANY (ARRAY[('order'::character varying)::text, ('shipment'::character varying)::text, ('grn'::character varying)::text, ('return'::character varying)::text, ('transfer'::character varying)::text, ('production_order'::character varying)::text, ('adjustment'::character varying)::text, ('opening'::character varying)::text]))))
);
ALTER TABLE ONLY public.inventory_movements ALTER COLUMN workspace_id SET STATISTICS 500;
ALTER TABLE ONLY public.inventory_movements ALTER COLUMN product_id SET STATISTICS 500;


--
-- Name: TABLE inventory_movements; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.inventory_movements IS 'Immutable audit log of all stock quantity changes (BR-STK-005).';


--
-- Name: COLUMN inventory_movements.movement_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.inventory_movements.movement_type IS 'Classification per BR-STK-005.';


--
-- Name: COLUMN inventory_movements.unit_cost; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.inventory_movements.unit_cost IS 'Cost per unit at time of movement. Used for COGS and inventory valuation.';


--
-- Name: COLUMN inventory_movements.reference_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.inventory_movements.reference_type IS 'Must match movement_type per FIX #2 CHECK constraint.';


--
-- Name: invoice_format_rules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invoice_format_rules (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    country_pack_id uuid NOT NULL,
    field_requirements jsonb DEFAULT '{}'::jsonb NOT NULL,
    qr_code_required boolean DEFAULT false NOT NULL,
    digital_signature_required boolean DEFAULT false NOT NULL,
    format_template text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: TABLE invoice_format_rules; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.invoice_format_rules IS '[Expansion Pack] Country-specific invoice format requirements (e.g. ZATCA QR, Egypt ETA).';


--
-- Name: invoice_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invoice_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    invoice_id uuid,
    product_id uuid,
    variant_id uuid,
    unit_id uuid,
    warehouse_id uuid,
    quantity numeric(12,4) NOT NULL,
    unit_price numeric(10,2) NOT NULL,
    discount_amount numeric(12,2) DEFAULT 0.00,
    tax_amount numeric(12,2) DEFAULT 0.00,
    subtotal numeric(12,2) NOT NULL,
    product_name_snapshot character varying(255),
    sku_snapshot character varying(100),
    tax_rate_snapshot numeric(5,2),
    CONSTRAINT invoice_items_discount_amount_check CHECK ((discount_amount >= (0)::numeric)),
    CONSTRAINT invoice_items_quantity_check CHECK ((quantity > (0)::numeric)),
    CONSTRAINT invoice_items_subtotal_check CHECK ((subtotal >= (0)::numeric)),
    CONSTRAINT invoice_items_tax_amount_check CHECK ((tax_amount >= (0)::numeric)),
    CONSTRAINT invoice_items_unit_price_check CHECK ((unit_price >= (0)::numeric))
);


--
-- Name: invoices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invoices (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid,
    branch_id uuid,
    dining_table_id uuid,
    created_by uuid,
    contact_id uuid,
    order_id uuid,
    parent_invoice_id uuid,
    invoice_type character varying(50) DEFAULT 'sale'::character varying,
    return_reason text,
    currency character varying(10) DEFAULT 'LYD'::character varying,
    exchange_rate numeric(10,4) DEFAULT 1.0000,
    total_amount numeric(12,2) NOT NULL,
    discount_amount numeric(12,2) DEFAULT 0.00,
    net_amount numeric(12,2) NOT NULL,
    payment_status character varying(50) DEFAULT 'unpaid'::character varying,
    tax_amount numeric(12,2) DEFAULT 0.00,
    due_date date,
    invoice_number character varying(50),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_invoice_net_lte_total CHECK ((net_amount <= total_amount)),
    CONSTRAINT invoices_invoice_type_check CHECK (((invoice_type)::text = ANY (ARRAY[('sale'::character varying)::text, ('purchase'::character varying)::text, ('return'::character varying)::text, ('refund'::character varying)::text]))),
    CONSTRAINT invoices_payment_status_check CHECK (((payment_status)::text = ANY (ARRAY[('unpaid'::character varying)::text, ('partial'::character varying)::text, ('paid'::character varying)::text, ('overdue'::character varying)::text, ('refunded'::character varying)::text])))
);
ALTER TABLE ONLY public.invoices ALTER COLUMN workspace_id SET STATISTICS 500;
ALTER TABLE ONLY public.invoices ALTER COLUMN contact_id SET STATISTICS 500;
ALTER TABLE ONLY public.invoices ALTER COLUMN payment_status SET STATISTICS 200;


--
-- Name: journal_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.journal_entries (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid,
    reference character varying(100),
    description text NOT NULL,
    date date DEFAULT CURRENT_DATE NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    currency character varying(3) DEFAULT 'LYD'::character varying NOT NULL,
    exchange_rate numeric(18,8) DEFAULT 1.0 NOT NULL,
    status character varying(50) DEFAULT 'draft'::character varying NOT NULL,
    CONSTRAINT chk_journal_entries_exchange_rate CHECK ((exchange_rate > (0)::numeric)),
    CONSTRAINT chk_journal_entries_status CHECK (((status)::text = ANY (ARRAY[('draft'::character varying)::text, ('posted'::character varying)::text, ('reversed'::character varying)::text])))
);


--
-- Name: COLUMN journal_entries.currency; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.journal_entries.currency IS 'ISO 4217 currency code the journal was recorded in.';


--
-- Name: COLUMN journal_entries.exchange_rate; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.journal_entries.exchange_rate IS 'Exchange rate to workspace base currency at time of posting. 1 journal_currency = exchange_rate * base_currency.';


--
-- Name: COLUMN journal_entries.status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.journal_entries.status IS 'Journal lifecycle: draft → posted → reversed. Posted journals are immutable.';


--
-- Name: journal_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.journal_lines (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    entry_id uuid NOT NULL,
    account_id uuid NOT NULL,
    debit numeric(15,2) DEFAULT 0.00,
    credit numeric(15,2) DEFAULT 0.00,
    description text,
    reporting_amount numeric(15,2),
    CONSTRAINT journal_lines_check CHECK ((((debit > (0)::numeric) AND (credit = (0)::numeric)) OR ((credit > (0)::numeric) AND (debit = (0)::numeric))))
);


--
-- Name: COLUMN journal_lines.reporting_amount; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.journal_lines.reporting_amount IS 'Debit or credit amount converted to workspace default_currency. Nullable for legacy rows — populated on journal posting.';


--
-- Name: leads; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.leads (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid,
    assigned_to uuid,
    name character varying(255) NOT NULL,
    company_name character varying(255),
    phone character varying(50),
    email character varying(255),
    source character varying(100),
    status character varying(50) DEFAULT 'new'::character varying,
    converted_contact_id uuid,
    notes text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT leads_status_check CHECK (((status)::text = ANY (ARRAY[('new'::character varying)::text, ('contacted'::character varying)::text, ('qualified'::character varying)::text, ('unqualified'::character varying)::text, ('converted'::character varying)::text])))
);


--
-- Name: leave_balances; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.leave_balances (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    user_id uuid NOT NULL,
    leave_type_id uuid NOT NULL,
    fiscal_year integer NOT NULL,
    entitled numeric(6,2) DEFAULT 0.00 NOT NULL,
    used numeric(6,2) DEFAULT 0.00 NOT NULL,
    pending numeric(6,2) DEFAULT 0.00 NOT NULL,
    carried_forward numeric(6,2) DEFAULT 0.00 NOT NULL,
    manually_adjusted numeric(6,2) DEFAULT 0.00 NOT NULL,
    last_accrual_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT leave_balances_carried_forward_check CHECK ((carried_forward >= (0)::numeric)),
    CONSTRAINT leave_balances_check CHECK ((used <= ((entitled + carried_forward) + GREATEST(manually_adjusted, (0)::numeric)))),
    CONSTRAINT leave_balances_entitled_check CHECK ((entitled >= (0)::numeric)),
    CONSTRAINT leave_balances_fiscal_year_check CHECK (((fiscal_year >= 2000) AND (fiscal_year <= 2100))),
    CONSTRAINT leave_balances_pending_check CHECK ((pending >= (0)::numeric)),
    CONSTRAINT leave_balances_used_check CHECK ((used >= (0)::numeric))
);


--
-- Name: TABLE leave_balances; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.leave_balances IS 'Per-user per-leave-type balance for each fiscal year (BR-LVE-002). All balance fields are APPLICATION-MAINTAINED by the service layer. Accrual is performed by a scheduled background job per leave_type.accrual_policy. remaining = entitled + carried_forward + manually_adjusted - used - pending. Negative balance prevention depends on leave_type.allow_negative_balance (app-enforced).';


--
-- Name: COLUMN leave_balances.entitled; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.leave_balances.entitled IS 'Total days entitled for this fiscal year (accrued or manually set).';


--
-- Name: COLUMN leave_balances.used; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.leave_balances.used IS 'Days actually taken (approved + completed leave requests).';


--
-- Name: COLUMN leave_balances.pending; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.leave_balances.pending IS 'Days in submitted/approved-but-not-yet-taken requests. Released on cancel/reject.';


--
-- Name: COLUMN leave_balances.carried_forward; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.leave_balances.carried_forward IS 'Days carried over from previous fiscal year per carry-forward policy.';


--
-- Name: COLUMN leave_balances.manually_adjusted; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.leave_balances.manually_adjusted IS 'Manual adjustments by HR (positive = grant, negative = deduction).';


--
-- Name: leave_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.leave_requests (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    user_id uuid NOT NULL,
    leave_type_id uuid NOT NULL,
    start_date date NOT NULL,
    end_date date NOT NULL,
    duration_days numeric(6,2) NOT NULL,
    is_half_day boolean DEFAULT false NOT NULL,
    half_day_period character varying(20),
    reason text,
    attachment_url text,
    status character varying(50) DEFAULT 'draft'::character varying NOT NULL,
    approved_by uuid,
    approved_at timestamp with time zone,
    rejected_by uuid,
    rejected_at timestamp with time zone,
    rejection_reason text,
    cancelled_by uuid,
    cancelled_at timestamp with time zone,
    cancelled_days numeric(6,2),
    submitted_at timestamp with time zone,
    completed_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT leave_requests_cancelled_days_check CHECK (((cancelled_days IS NULL) OR (cancelled_days > (0)::numeric))),
    CONSTRAINT leave_requests_check CHECK ((end_date >= start_date)),
    CONSTRAINT leave_requests_check1 CHECK (((is_half_day = false) OR ((duration_days = 0.5) AND (start_date = end_date) AND (half_day_period IS NOT NULL)))),
    CONSTRAINT leave_requests_check2 CHECK ((((status)::text <> 'approved'::text) OR (approved_at IS NOT NULL))),
    CONSTRAINT leave_requests_check3 CHECK ((((status)::text <> 'rejected'::text) OR ((rejected_at IS NOT NULL) AND (rejection_reason IS NOT NULL)))),
    CONSTRAINT leave_requests_check4 CHECK ((((status)::text <> 'cancelled'::text) OR (cancelled_at IS NOT NULL))),
    CONSTRAINT leave_requests_duration_days_check CHECK ((duration_days > (0)::numeric)),
    CONSTRAINT leave_requests_half_day_period_check CHECK (((half_day_period IS NULL) OR ((half_day_period)::text = ANY (ARRAY[('morning'::character varying)::text, ('afternoon'::character varying)::text])))),
    CONSTRAINT leave_requests_status_check CHECK (((status)::text = ANY (ARRAY[('draft'::character varying)::text, ('submitted'::character varying)::text, ('approved'::character varying)::text, ('rejected'::character varying)::text, ('cancelled'::character varying)::text, ('completed'::character varying)::text])))
);


--
-- Name: TABLE leave_requests; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.leave_requests IS 'Full leave request lifecycle (BR-LVE-003/004/005). FSM: draft → submitted → approved → completed | cancelled; submitted → rejected. Approval requires hr.leaves.approve @ team|dept scope. Maker-checker enforced at app layer: approved_by != user_id. On approval, leave_balances.used is incremented and pending decremented. On cancellation of approved leave, used is decremented (only future days).';


--
-- Name: COLUMN leave_requests.duration_days; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.leave_requests.duration_days IS 'Total working days requested. Supports half-days (0.5). Excludes weekends/holidays (app-calculated).';


--
-- Name: COLUMN leave_requests.status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.leave_requests.status IS 'FSM states: draft, submitted, approved, rejected, cancelled, completed. FIX #6: FSM TRANSITIONS ARE APPLICATION-ENFORCED. The database only validates that status is one of the allowed values via CHECK constraint. The service layer enforces the valid transition graph: draft→submitted, draft→cancelled, submitted→approved, submitted→rejected, approved→completed, approved→cancelled. No direct transitions like draft→approved or rejected→approved are permitted. The application MUST validate the current status before applying a transition.';


--
-- Name: COLUMN leave_requests.cancelled_days; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.leave_requests.cancelled_days IS 'Number of days actually cancelled (may be less than duration_days if leave partially taken, per BR-LVE-005).';


--
-- Name: leave_types; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.leave_types (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    name character varying(100) NOT NULL,
    code character varying(50) NOT NULL,
    description text,
    accrual_policy character varying(50) DEFAULT 'yearly'::character varying NOT NULL,
    accrual_amount numeric(6,2) DEFAULT 0.00 NOT NULL,
    max_balance numeric(6,2),
    carry_forward_allowed boolean DEFAULT false NOT NULL,
    carry_forward_limit numeric(6,2) DEFAULT 0.00,
    carry_forward_expiry_months integer,
    is_paid boolean DEFAULT true NOT NULL,
    requires_approval boolean DEFAULT true NOT NULL,
    requires_documentation boolean DEFAULT false NOT NULL,
    allow_negative_balance boolean DEFAULT false NOT NULL,
    allow_half_day boolean DEFAULT true NOT NULL,
    color character varying(7),
    sort_order integer DEFAULT 0 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT leave_types_accrual_amount_check CHECK ((accrual_amount >= (0)::numeric)),
    CONSTRAINT leave_types_accrual_policy_check CHECK (((accrual_policy)::text = ANY (ARRAY[('monthly'::character varying)::text, ('yearly'::character varying)::text, ('none'::character varying)::text]))),
    CONSTRAINT leave_types_carry_forward_expiry_months_check CHECK (((carry_forward_expiry_months IS NULL) OR (carry_forward_expiry_months > 0))),
    CONSTRAINT leave_types_carry_forward_limit_check CHECK (((carry_forward_limit IS NULL) OR (carry_forward_limit >= (0)::numeric))),
    CONSTRAINT leave_types_max_balance_check CHECK (((max_balance IS NULL) OR (max_balance > (0)::numeric)))
);


--
-- Name: TABLE leave_types; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.leave_types IS 'Workspace-configurable leave types (BR-LVE-001). Defines accrual, carry-forward, and approval policies per type.';


--
-- Name: COLUMN leave_types.accrual_policy; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.leave_types.accrual_policy IS 'How leave days are accrued: monthly (days/month), yearly (days/year), none (manual grant only).';


--
-- Name: COLUMN leave_types.max_balance; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.leave_types.max_balance IS 'Maximum balance cap. NULL = no cap. Accrual stops when balance reaches this value.';


--
-- Name: COLUMN leave_types.allow_negative_balance; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.leave_types.allow_negative_balance IS 'If TRUE, leave requests are allowed even if they would cause a negative balance. Useful for sick leave.';


--
-- Name: leaves_legacy; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.leaves_legacy (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid,
    user_id uuid,
    leave_type character varying(50) NOT NULL,
    start_date date NOT NULL,
    end_date date NOT NULL,
    status character varying(50) DEFAULT 'pending'::character varying,
    reason text,
    leave_type_id uuid,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT leaves_check CHECK ((end_date >= start_date)),
    CONSTRAINT leaves_leave_type_check CHECK (((leave_type)::text = ANY (ARRAY[('annual'::character varying)::text, ('sick'::character varying)::text, ('unpaid'::character varying)::text, ('maternity'::character varying)::text, ('paternity'::character varying)::text, ('emergency'::character varying)::text]))),
    CONSTRAINT leaves_status_check CHECK (((status)::text = ANY (ARRAY[('pending'::character varying)::text, ('approved'::character varying)::text, ('rejected'::character varying)::text, ('cancelled'::character varying)::text])))
);


--
-- Name: TABLE leaves_legacy; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.leaves_legacy IS '🚫 DEPRECATED (Migration 008). Renamed from leaves. Replaced by leave_requests + leave_types (configurable, with approval workflow). Data migrated in 007 Section 2C. ROLLBACK: ALTER TABLE leaves_legacy RENAME TO leaves;';


--
-- Name: COLUMN leaves_legacy.leave_type_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.leaves_legacy.leave_type_id IS 'FK to leave_types. Coexists with legacy leave_type VARCHAR for backward compatibility.';


--
-- Name: loyalty_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.loyalty_accounts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    contact_id uuid NOT NULL,
    program_id uuid NOT NULL,
    points_balance integer DEFAULT 0 NOT NULL,
    lifetime_points integer DEFAULT 0 NOT NULL,
    current_tier character varying(100),
    tier_updated_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT loyalty_accounts_lifetime_points_check CHECK ((lifetime_points >= 0)),
    CONSTRAINT loyalty_accounts_points_balance_check CHECK ((points_balance >= 0))
);


--
-- Name: TABLE loyalty_accounts; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.loyalty_accounts IS '[Core v1] Individual customer loyalty balances and tier status.';


--
-- Name: loyalty_programs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.loyalty_programs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    name character varying(255) NOT NULL,
    earn_rules jsonb DEFAULT '[]'::jsonb NOT NULL,
    burn_rules jsonb DEFAULT '[]'::jsonb NOT NULL,
    tiers jsonb DEFAULT '[]'::jsonb NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: TABLE loyalty_programs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.loyalty_programs IS '[Core v1] Customer loyalty programs with points earn/burn rules and tier definitions.';


--
-- Name: loyalty_transactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.loyalty_transactions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    account_id uuid NOT NULL,
    type character varying(50) NOT NULL,
    points integer NOT NULL,
    reason character varying(500),
    reference_entity_type character varying(100),
    reference_entity_id uuid,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT loyalty_transactions_type_check CHECK (((type)::text = ANY (ARRAY[('earn'::character varying)::text, ('burn'::character varying)::text, ('adjust'::character varying)::text, ('expire'::character varying)::text])))
);


--
-- Name: TABLE loyalty_transactions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.loyalty_transactions IS '[Core v1] Immutable ledger of loyalty point movements.';


--
-- Name: manual_payments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.manual_payments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    amount numeric(15,2) DEFAULT 0 NOT NULL,
    currency character varying(3) DEFAULT 'usd'::character varying NOT NULL,
    method character varying(30) NOT NULL,
    reference character varying(100),
    status character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    plan_id uuid,
    billing_cycle character varying(20),
    notes text,
    submitted_by uuid,
    confirmed_by uuid,
    confirmed_at timestamp with time zone,
    rejected_reason text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT manual_payments_method_check CHECK (((method)::text = ANY (ARRAY[('manual_cash'::character varying)::text, ('bank_transfer'::character varying)::text, ('cheque'::character varying)::text, ('enterprise_manual'::character varying)::text]))),
    CONSTRAINT manual_payments_status_check CHECK (((status)::text = ANY (ARRAY[('pending'::character varying)::text, ('confirmed'::character varying)::text, ('rejected'::character varying)::text])))
);


--
-- Name: media_assets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.media_assets (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    name character varying(255) NOT NULL,
    file_path character varying(500) NOT NULL,
    mime_type character varying(100) NOT NULL,
    file_size integer,
    tags jsonb DEFAULT '[]'::jsonb NOT NULL,
    folder character varying(255),
    source character varying(50) DEFAULT 'upload'::character varying NOT NULL,
    status character varying(50) DEFAULT 'draft'::character varying NOT NULL,
    approved_by uuid,
    approved_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT media_assets_source_check CHECK (((source)::text = ANY (ARRAY[('upload'::character varying)::text, ('ai_generated'::character varying)::text]))),
    CONSTRAINT media_assets_status_check CHECK (((status)::text = ANY (ARRAY[('draft'::character varying)::text, ('approved'::character varying)::text, ('archived'::character varying)::text])))
);


--
-- Name: TABLE media_assets; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.media_assets IS '[Core v1] Centralized media asset library with approval workflow. Sources: upload or AI-generated.';


--
-- Name: media_generation_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.media_generation_requests (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    prompt text NOT NULL,
    brand_kit_id uuid,
    ai_model character varying(100),
    status character varying(50) DEFAULT 'pending'::character varying NOT NULL,
    result_asset_id uuid,
    tokens_used integer DEFAULT 0,
    error_message text,
    created_by uuid,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT media_generation_requests_status_check CHECK (((status)::text = ANY (ARRAY[('pending'::character varying)::text, ('processing'::character varying)::text, ('completed'::character varying)::text, ('failed'::character varying)::text])))
);


--
-- Name: TABLE media_generation_requests; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.media_generation_requests IS '[Expansion Pack] AI content generation request tracking. Consumes AI token quota.';


--
-- Name: membership_roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.membership_roles (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    membership_id uuid NOT NULL,
    role_id uuid NOT NULL,
    is_primary boolean DEFAULT false NOT NULL,
    assigned_by uuid,
    assigned_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: TABLE membership_roles; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.membership_roles IS 'Junction table: membership → role (multi-role). Every membership MUST have exactly one is_primary=TRUE role. Enforced by application layer and validated by migration 007 Section 1C. UNIQUE on (payroll_id, line_type, label) prevents duplicate logical roles.';


--
-- Name: COLUMN membership_roles.is_primary; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.membership_roles.is_primary IS 'UI display hint. Exactly one primary role per membership, enforced at application layer.';


--
-- Name: message_templates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.message_templates (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    channel_type character varying(50) NOT NULL,
    name character varying(255) NOT NULL,
    subject character varying(500),
    body text NOT NULL,
    variables jsonb DEFAULT '[]'::jsonb NOT NULL,
    locale character varying(10) DEFAULT 'en'::character varying,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT message_templates_channel_type_check CHECK (((channel_type)::text = ANY (ARRAY[('email'::character varying)::text, ('sms'::character varying)::text, ('whatsapp'::character varying)::text, ('push'::character varying)::text])))
);


--
-- Name: TABLE message_templates; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.message_templates IS 'Reusable message templates per channel. Variables are interpolated at send time.';


--
-- Name: message_threads; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.message_threads (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    contact_id uuid,
    subject character varying(500),
    last_message_at timestamp with time zone,
    status character varying(50) DEFAULT 'open'::character varying NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT message_threads_status_check CHECK (((status)::text = ANY (ARRAY[('open'::character varying)::text, ('closed'::character varying)::text])))
);


--
-- Name: TABLE message_threads; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.message_threads IS '[Expansion Pack] Conversation threads grouping inbound + outbound messages per contact.';


--
-- Name: migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.migrations (
    id integer NOT NULL,
    migration character varying(255) NOT NULL,
    batch integer NOT NULL
);


--
-- Name: migrations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.migrations_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: migrations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.migrations_id_seq OWNED BY public.migrations.id;


--
-- Name: notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notifications (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid,
    user_id uuid,
    title character varying(255) NOT NULL,
    message text NOT NULL,
    type character varying(50) DEFAULT 'info'::character varying,
    is_read boolean DEFAULT false,
    link_url text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT notifications_type_check CHECK (((type)::text = ANY (ARRAY[('info'::character varying)::text, ('warning'::character varying)::text, ('alert'::character varying)::text, ('success'::character varying)::text])))
);


--
-- Name: nurturing_enrollments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.nurturing_enrollments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    sequence_id uuid NOT NULL,
    contact_id uuid NOT NULL,
    current_step integer DEFAULT 0 NOT NULL,
    status character varying(50) DEFAULT 'active'::character varying NOT NULL,
    last_step_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT nurturing_enrollments_status_check CHECK (((status)::text = ANY (ARRAY[('active'::character varying)::text, ('completed'::character varying)::text, ('paused'::character varying)::text, ('exited'::character varying)::text])))
);


--
-- Name: TABLE nurturing_enrollments; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.nurturing_enrollments IS '[Expansion Pack] Per-contact enrollment in nurturing sequences.';


--
-- Name: nurturing_sequences; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.nurturing_sequences (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    name character varying(255) NOT NULL,
    trigger_event character varying(255) NOT NULL,
    steps jsonb DEFAULT '[]'::jsonb NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: TABLE nurturing_sequences; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.nurturing_sequences IS '[Expansion Pack] Multi-step lead nurturing automation.';


--
-- Name: opportunities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.opportunities (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid,
    lead_id uuid,
    contact_id uuid,
    assigned_to uuid,
    title character varying(255) NOT NULL,
    stage character varying(50) DEFAULT 'prospecting'::character varying,
    expected_amount numeric(12,2) DEFAULT 0.00,
    probability integer DEFAULT 0,
    expected_close_date date,
    actual_close_date date,
    lost_reason text,
    notes text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT opportunities_probability_check CHECK (((probability >= 0) AND (probability <= 100))),
    CONSTRAINT opportunities_stage_check CHECK (((stage)::text = ANY (ARRAY[('prospecting'::character varying)::text, ('proposal'::character varying)::text, ('negotiation'::character varying)::text, ('closed_won'::character varying)::text, ('closed_lost'::character varying)::text])))
);


--
-- Name: order_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.order_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    order_id uuid,
    product_id uuid,
    variant_id uuid,
    unit_id uuid,
    quantity numeric(12,4) NOT NULL,
    unit_price numeric(10,2) NOT NULL,
    subtotal numeric(12,2) NOT NULL,
    product_name_snapshot character varying(255),
    sku_snapshot character varying(100),
    CONSTRAINT order_items_quantity_check CHECK ((quantity > (0)::numeric)),
    CONSTRAINT order_items_subtotal_check CHECK ((subtotal >= (0)::numeric)),
    CONSTRAINT order_items_unit_price_check CHECK ((unit_price >= (0)::numeric))
);


--
-- Name: orders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.orders (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid,
    branch_id uuid,
    dining_table_id uuid,
    created_by uuid,
    contact_id uuid,
    order_type character varying(50) NOT NULL,
    status character varying(50) DEFAULT 'draft'::character varying,
    currency character varying(10) DEFAULT 'LYD'::character varying,
    exchange_rate numeric(10,4) DEFAULT 1.0000,
    total_amount numeric(12,2) NOT NULL,
    valid_until date,
    order_number character varying(50),
    notes text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_order_total_nonneg CHECK ((total_amount >= (0)::numeric)),
    CONSTRAINT orders_order_type_check CHECK (((order_type)::text = ANY (ARRAY[('quote'::character varying)::text, ('sale_order'::character varying)::text, ('purchase_order'::character varying)::text, ('dine_in'::character varying)::text, ('takeaway'::character varying)::text]))),
    CONSTRAINT orders_status_check CHECK (((status)::text = ANY (ARRAY[('draft'::character varying)::text, ('confirmed'::character varying)::text, ('processing'::character varying)::text, ('completed'::character varying)::text, ('cancelled'::character varying)::text])))
);
ALTER TABLE ONLY public.orders ALTER COLUMN workspace_id SET STATISTICS 500;
ALTER TABLE ONLY public.orders ALTER COLUMN contact_id SET STATISTICS 500;


--
-- Name: outbound_messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.outbound_messages (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    channel_type character varying(50) NOT NULL,
    template_id uuid,
    recipient_contact_id uuid,
    recipient_user_id uuid,
    recipient_address character varying(500) NOT NULL,
    subject character varying(500),
    body text NOT NULL,
    status character varying(50) DEFAULT 'queued'::character varying NOT NULL,
    provider_message_id character varying(255),
    error_message text,
    attempts integer DEFAULT 0 NOT NULL,
    sent_at timestamp with time zone,
    delivered_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT outbound_messages_channel_type_check CHECK (((channel_type)::text = ANY (ARRAY[('email'::character varying)::text, ('sms'::character varying)::text, ('whatsapp'::character varying)::text, ('push'::character varying)::text]))),
    CONSTRAINT outbound_messages_status_check CHECK (((status)::text = ANY (ARRAY[('queued'::character varying)::text, ('sending'::character varying)::text, ('sent'::character varying)::text, ('delivered'::character varying)::text, ('failed'::character varying)::text, ('bounced'::character varying)::text])))
);


--
-- Name: TABLE outbound_messages; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.outbound_messages IS 'Outbound message dispatch log. Tracks every message sent across all channels.';


--
-- Name: ownership_assignments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ownership_assignments (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    entity_type character varying(50) NOT NULL,
    entity_id uuid NOT NULL,
    owner_membership_id uuid NOT NULL,
    team_id uuid,
    department_id uuid,
    source character varying(30) DEFAULT 'manual'::character varying NOT NULL,
    status character varying(20) DEFAULT 'active'::character varying NOT NULL,
    assigned_by_membership_id uuid,
    assigned_at timestamp(0) without time zone,
    released_at timestamp(0) without time zone,
    notes text,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone
);


--
-- Name: ownership_transfer_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ownership_transfer_logs (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    ownership_assignment_id uuid,
    entity_type character varying(50) NOT NULL,
    entity_id uuid NOT NULL,
    from_membership_id uuid,
    to_membership_id uuid NOT NULL,
    transferred_by_membership_id uuid,
    reason text,
    transferred_at timestamp(0) without time zone,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone
);


--
-- Name: payment_transactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payment_transactions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    stripe_payment_intent_id character varying(100),
    stripe_invoice_id character varying(100),
    type character varying(30) NOT NULL,
    amount numeric(15,2) DEFAULT 0 NOT NULL,
    currency character varying(3) DEFAULT 'usd'::character varying NOT NULL,
    status character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    description text,
    metadata jsonb,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT payment_transactions_status_check CHECK (((status)::text = ANY (ARRAY[('succeeded'::character varying)::text, ('failed'::character varying)::text, ('pending'::character varying)::text, ('refunded'::character varying)::text]))),
    CONSTRAINT payment_transactions_type_check CHECK (((type)::text = ANY (ARRAY[('subscription'::character varying)::text, ('credit_purchase'::character varying)::text, ('one_time'::character varying)::text])))
);


--
-- Name: payments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid,
    invoice_id uuid,
    account_id uuid,
    amount numeric(12,2) NOT NULL,
    payment_method character varying(50) NOT NULL,
    reference_number character varying(100),
    payment_date date DEFAULT CURRENT_DATE,
    created_by uuid,
    payment_number character varying(50),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    reversal_of_payment_id uuid,
    status character varying(50) DEFAULT 'completed'::character varying NOT NULL,
    is_reversal boolean DEFAULT false NOT NULL,
    reversal_reason text,
    reversed_at timestamp with time zone,
    reversed_by uuid,
    pos_session_id uuid,
    CONSTRAINT chk_no_reversal_of_reversal CHECK (((is_reversal = false) OR ((status)::text <> 'reversed'::text))),
    CONSTRAINT chk_reversal_consistency CHECK ((((is_reversal = false) AND (reversal_of_payment_id IS NULL)) OR ((is_reversal = true) AND (reversal_of_payment_id IS NOT NULL)))),
    CONSTRAINT payments_amount_check CHECK ((amount > (0)::numeric)),
    CONSTRAINT payments_payment_method_check CHECK (((payment_method)::text = ANY (ARRAY[('cash'::character varying)::text, ('bank_transfer'::character varying)::text, ('check'::character varying)::text, ('card'::character varying)::text, ('mobile_payment'::character varying)::text]))),
    CONSTRAINT payments_status_check CHECK (((status)::text = ANY (ARRAY[('pending'::character varying)::text, ('completed'::character varying)::text, ('failed'::character varying)::text, ('reversed'::character varying)::text])))
);
ALTER TABLE ONLY public.payments ALTER COLUMN workspace_id SET STATISTICS 500;
ALTER TABLE ONLY public.payments ALTER COLUMN invoice_id SET STATISTICS 500;


--
-- Name: COLUMN payments.reversal_of_payment_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.payments.reversal_of_payment_id IS 'Self-FK: if this payment is a reversal, references the original payment being reversed (BR-PAY-005). DB-enforced: unique index prevents multiple reversals of the same original. APP-enforced: original payment must have status=completed at time of reversal insert.';


--
-- Name: COLUMN payments.status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.payments.status IS 'Payment lifecycle: pending → completed → reversed. Failed is a terminal error state. APP-enforced: only the application may transition status; service layer must set original payment to reversed atomically with reversal insert (same transaction).';


--
-- Name: COLUMN payments.is_reversal; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.payments.is_reversal IS 'TRUE if this record is a reversal of another payment. Amount is still positive; the accounting direction is reversed via contra journal entry.';


--
-- Name: COLUMN payments.pos_session_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.payments.pos_session_id IS 'Links cash/card payments to the POS session they were processed in (BR-PAY-007).';


--
-- Name: payroll; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payroll (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid,
    user_id uuid,
    month integer NOT NULL,
    year integer NOT NULL,
    base_salary numeric(10,2) NOT NULL,
    bonuses numeric(10,2) DEFAULT 0.00,
    deductions numeric(10,2) DEFAULT 0.00,
    net_salary numeric(10,2) GENERATED ALWAYS AS (((base_salary + bonuses) - deductions)) STORED,
    payment_status character varying(50) DEFAULT 'unpaid'::character varying,
    processed_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    payroll_run_id uuid,
    status character varying(50) DEFAULT 'draft'::character varying,
    CONSTRAINT payroll_month_check CHECK (((month >= 1) AND (month <= 12))),
    CONSTRAINT payroll_payment_status_check CHECK (((payment_status)::text = ANY (ARRAY[('unpaid'::character varying)::text, ('paid'::character varying)::text, ('partial'::character varying)::text]))),
    CONSTRAINT payroll_status_check CHECK (((status IS NULL) OR ((status)::text = ANY (ARRAY[('draft'::character varying)::text, ('calculated'::character varying)::text, ('approved'::character varying)::text, ('disbursed'::character varying)::text])))),
    CONSTRAINT payroll_year_check CHECK ((year >= 2000))
);


--
-- Name: COLUMN payroll.base_salary; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.payroll.base_salary IS '⚠️ LEGACY (Migration 008). For payroll records linked to payroll_runs via payroll_run_id, use payroll_lines (line_type=base_salary) instead. This column remains for backward compatibility with unlinked records.';


--
-- Name: COLUMN payroll.bonuses; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.payroll.bonuses IS '⚠️ LEGACY (Migration 008). For linked records, use payroll_lines (line_type=bonus). This column remains for unlinked legacy records.';


--
-- Name: COLUMN payroll.deductions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.payroll.deductions IS '⚠️ LEGACY (Migration 008). For linked records, use payroll_lines (line_type=other_deduction). This column remains for unlinked legacy records.';


--
-- Name: COLUMN payroll.net_salary; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.payroll.net_salary IS '⚠️ LEGACY (Migration 008). For linked records, net = SUM(payroll_lines.amount). This generated column remains valid for unlinked legacy records.';


--
-- Name: COLUMN payroll.payroll_run_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.payroll.payroll_run_id IS 'FK to the batch payroll_run this record belongs to.';


--
-- Name: COLUMN payroll.status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.payroll.status IS 'Individual payslip status, mirrors the parent payroll_run status.';


--
-- Name: payroll_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payroll_lines (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    payroll_id uuid NOT NULL,
    line_type character varying(50) NOT NULL,
    label character varying(255) NOT NULL,
    amount numeric(12,2) NOT NULL,
    quantity numeric(10,4),
    rate numeric(10,4),
    notes text,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT payroll_lines_amount_check CHECK ((amount <> (0)::numeric)),
    CONSTRAINT payroll_lines_check CHECK (((((line_type)::text = ANY (ARRAY[('base_salary'::character varying)::text, ('allowance'::character varying)::text, ('overtime'::character varying)::text, ('bonus'::character varying)::text, ('commission'::character varying)::text, ('back_pay'::character varying)::text])) AND (amount > (0)::numeric)) OR (((line_type)::text = ANY (ARRAY[('tax'::character varying)::text, ('insurance'::character varying)::text, ('loan_repayment'::character varying)::text, ('absence_deduction'::character varying)::text, ('late_deduction'::character varying)::text, ('advance_recovery'::character varying)::text, ('other_deduction'::character varying)::text])) AND (amount < (0)::numeric)))),
    CONSTRAINT payroll_lines_line_type_check CHECK (((line_type)::text = ANY (ARRAY[('base_salary'::character varying)::text, ('allowance'::character varying)::text, ('overtime'::character varying)::text, ('bonus'::character varying)::text, ('commission'::character varying)::text, ('back_pay'::character varying)::text, ('tax'::character varying)::text, ('insurance'::character varying)::text, ('loan_repayment'::character varying)::text, ('absence_deduction'::character varying)::text, ('late_deduction'::character varying)::text, ('advance_recovery'::character varying)::text, ('other_deduction'::character varying)::text])))
);


--
-- Name: TABLE payroll_lines; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.payroll_lines IS 'Line-item detail for employee payslips (BR-PRL-002). Each line represents a single salary component. Earnings are positive; deductions are negative. SUM(amount) over all lines for a payroll record should equal payroll.net_salary. Consistency between payroll_lines total and payroll.net_salary is APP-ENFORCED. Duplicate (payroll_id, line_type, label) combinations are DB-ENFORCED by unique constraint.';


--
-- Name: COLUMN payroll_lines.line_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.payroll_lines.line_type IS 'Categorization of the salary component. Earnings are positive; deductions are negative.';


--
-- Name: COLUMN payroll_lines.quantity; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.payroll_lines.quantity IS 'Optional: number of units (hours, days) used in calculation. For audit trail.';


--
-- Name: COLUMN payroll_lines.rate; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.payroll_lines.rate IS 'Optional: per-unit rate (hourly rate, daily deduction). For audit trail.';


--
-- Name: payroll_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payroll_runs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    period_start date NOT NULL,
    period_end date NOT NULL,
    department_id uuid,
    branch_id uuid,
    status character varying(50) DEFAULT 'draft'::character varying NOT NULL,
    employee_count integer,
    total_gross numeric(15,2),
    total_deductions numeric(15,2),
    total_net numeric(15,2),
    calculated_at timestamp with time zone,
    calculated_by uuid,
    approved_at timestamp with time zone,
    approved_by uuid,
    disbursed_at timestamp with time zone,
    disbursed_by uuid,
    locked_at timestamp with time zone,
    locked_by uuid,
    journal_entry_id uuid,
    notes text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT payroll_runs_check CHECK ((period_end > period_start)),
    CONSTRAINT payroll_runs_check1 CHECK ((((status)::text <> ALL (ARRAY[('calculated'::character varying)::text, ('approved'::character varying)::text, ('disbursed'::character varying)::text, ('locked'::character varying)::text])) OR (calculated_at IS NOT NULL))),
    CONSTRAINT payroll_runs_check2 CHECK ((((status)::text <> ALL (ARRAY[('approved'::character varying)::text, ('disbursed'::character varying)::text, ('locked'::character varying)::text])) OR (approved_at IS NOT NULL))),
    CONSTRAINT payroll_runs_check3 CHECK ((((status)::text <> ALL (ARRAY[('disbursed'::character varying)::text, ('locked'::character varying)::text])) OR (disbursed_at IS NOT NULL))),
    CONSTRAINT payroll_runs_check4 CHECK ((((status)::text <> 'locked'::text) OR (locked_at IS NOT NULL))),
    CONSTRAINT payroll_runs_employee_count_check CHECK (((employee_count IS NULL) OR (employee_count >= 0))),
    CONSTRAINT payroll_runs_status_check CHECK (((status)::text = ANY (ARRAY[('draft'::character varying)::text, ('calculated'::character varying)::text, ('approved'::character varying)::text, ('disbursed'::character varying)::text, ('locked'::character varying)::text]))),
    CONSTRAINT payroll_runs_total_deductions_check CHECK (((total_deductions IS NULL) OR (total_deductions >= (0)::numeric))),
    CONSTRAINT payroll_runs_total_gross_check CHECK (((total_gross IS NULL) OR (total_gross >= (0)::numeric))),
    CONSTRAINT payroll_runs_total_net_check CHECK (((total_net IS NULL) OR (total_net >= (0)::numeric)))
);


--
-- Name: TABLE payroll_runs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.payroll_runs IS 'Batch-level payroll execution (BR-PRL-001/003/004). FSM: draft → calculated → approved → disbursed → locked. Approved → rejected returns to draft (recalculate). Locked is terminal — no modifications allowed (DB-ENFORCED by trigger). Maker-checker: calculated_by != approved_by (app-enforced per BR-PRL-003). FSM transitions are APP-ENFORCED; the DB only validates allowed status values. Dependencies on attendance and leave_requests are documented in the file header.';


--
-- Name: COLUMN payroll_runs.status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.payroll_runs.status IS 'FSM: draft, calculated, approved, disbursed, locked. Transitions are APP-ENFORCED. Lock is terminal and DB-ENFORCED by trigger.';


--
-- Name: COLUMN payroll_runs.employee_count; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.payroll_runs.employee_count IS 'Number of employees included in this run. Set on calculate.';


--
-- Name: payroll_statutory_rules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payroll_statutory_rules (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    country_pack_id uuid NOT NULL,
    deduction_type character varying(100) NOT NULL,
    calculation_method character varying(50) NOT NULL,
    brackets jsonb DEFAULT '[]'::jsonb NOT NULL,
    effective_from date NOT NULL,
    effective_to date,
    CONSTRAINT payroll_statutory_rules_calculation_method_check CHECK (((calculation_method)::text = ANY (ARRAY[('flat'::character varying)::text, ('percentage'::character varying)::text, ('bracket'::character varying)::text]))),
    CONSTRAINT payroll_statutory_rules_check CHECK (((effective_to IS NULL) OR (effective_to > effective_from)))
);


--
-- Name: TABLE payroll_statutory_rules; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.payroll_statutory_rules IS '[Expansion Pack] Per-country payroll statutory deduction definitions. Platform-scoped.';


--
-- Name: permission_definitions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.permission_definitions (
    key character varying(100) NOT NULL,
    module character varying(50) NOT NULL,
    entity character varying(50) NOT NULL,
    action character varying(50) NOT NULL,
    scope_type character varying(20) DEFAULT 'workspace'::character varying NOT NULL,
    applicable_scopes character varying(20)[] DEFAULT ARRAY['ws'::text] NOT NULL,
    description text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT permission_definitions_scope_type_check CHECK (((scope_type)::text = ANY (ARRAY[('workspace'::character varying)::text, ('platform'::character varying)::text])))
);


--
-- Name: TABLE permission_definitions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.permission_definitions IS 'Platform-scoped read-only catalogue of all 242 permission keys (209 workspace + 33 platform). Provides DB-level FK target for override and delegation integrity.';


--
-- Name: COLUMN permission_definitions.applicable_scopes; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.permission_definitions.applicable_scopes IS 'Valid scope codes for this permission per RBAC spec §3.3. Application layer validates scope assignments against this array.';


--
-- Name: permission_delegation_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.permission_delegation_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    delegation_id uuid NOT NULL,
    permission_key character varying(100) NOT NULL,
    scope character varying(20) NOT NULL,
    CONSTRAINT permission_delegation_items_scope_check CHECK (((scope)::text = ANY (ARRAY[('own'::character varying)::text, ('team'::character varying)::text, ('dept'::character varying)::text, ('branch'::character varying)::text, ('wh'::character varying)::text, ('ws'::character varying)::text])))
);


--
-- Name: TABLE permission_delegation_items; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.permission_delegation_items IS 'Normalized child table for permission_delegations. Each row = one delegated permission key with DB-level FK integrity.';


--
-- Name: COLUMN permission_delegation_items.scope; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.permission_delegation_items.scope IS 'The scope at which this permission is delegated. Cannot exceed the delegator''s own scope for this key (enforced at application layer).';


--
-- Name: permission_delegations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.permission_delegations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    delegator_membership_id uuid NOT NULL,
    delegate_membership_id uuid NOT NULL,
    start_at timestamp with time zone NOT NULL,
    end_at timestamp with time zone NOT NULL,
    reason text NOT NULL,
    status character varying(50) DEFAULT 'active'::character varying NOT NULL,
    revoked_at timestamp with time zone,
    revoked_by uuid,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT permission_delegations_check CHECK ((end_at > start_at)),
    CONSTRAINT permission_delegations_check1 CHECK ((delegator_membership_id <> delegate_membership_id)),
    CONSTRAINT permission_delegations_status_check CHECK (((status)::text = ANY (ARRAY[('active'::character varying)::text, ('expired'::character varying)::text, ('revoked'::character varying)::text])))
);


--
-- Name: TABLE permission_delegations; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.permission_delegations IS 'Temporary permission transfers between workspace members. Bounded by time window. Individual permissions listed in permission_delegation_items.';


--
-- Name: COLUMN permission_delegations.status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.permission_delegations.status IS 'active = in effect; expired = past end_at; revoked = manually cancelled.';


--
-- Name: COLUMN permission_delegations.revoked_by; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.permission_delegations.revoked_by IS 'User who revoked (kept as users FK — actor identity, not workspace binding). Application verifies revoker has membership.';


--
-- Name: personal_access_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.personal_access_tokens (
    id bigint NOT NULL,
    tokenable_type character varying(255) NOT NULL,
    tokenable_id uuid NOT NULL,
    name character varying(255) NOT NULL,
    token character varying(64) NOT NULL,
    abilities text,
    last_used_at timestamp with time zone,
    expires_at timestamp with time zone,
    created_at timestamp with time zone,
    updated_at timestamp with time zone
);


--
-- Name: personal_access_tokens_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.personal_access_tokens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: personal_access_tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.personal_access_tokens_id_seq OWNED BY public.personal_access_tokens.id;


--
-- Name: pipeline_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pipeline_records (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    pipeline_id uuid NOT NULL,
    stage_id uuid NOT NULL,
    title character varying(255) NOT NULL,
    description text,
    contact_id uuid,
    assigned_membership_id uuid,
    value_amount numeric(15,2),
    currency character varying(10),
    status character varying(20) DEFAULT 'open'::character varying NOT NULL,
    expected_close_date date,
    closed_at timestamp(0) without time zone,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone
);


--
-- Name: pipeline_stages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pipeline_stages (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    pipeline_id uuid NOT NULL,
    stage_key character varying(255),
    name character varying(255) NOT NULL,
    description text,
    status_type character varying(20) DEFAULT 'open'::character varying NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone
);


--
-- Name: pipelines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pipelines (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    pipeline_key character varying(255),
    name character varying(255) NOT NULL,
    description text,
    entity_type character varying(50) DEFAULT 'generic'::character varying NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone
);


--
-- Name: plan_features; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.plan_features (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    plan_id uuid NOT NULL,
    feature_key character varying(100) NOT NULL,
    is_enabled boolean DEFAULT true NOT NULL
);


--
-- Name: platform_activation_campaigns; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.platform_activation_campaigns (
    id uuid NOT NULL,
    campaign_key character varying(255),
    name character varying(255) NOT NULL,
    description text,
    target_market character varying(255),
    default_plan_key character varying(255),
    trial_days integer DEFAULT 14,
    starts_at timestamp(0) without time zone,
    expires_at timestamp(0) without time zone,
    status character varying(255) DEFAULT 'active'::character varying NOT NULL,
    created_by_user_id uuid,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone
);


--
-- Name: platform_activation_codes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.platform_activation_codes (
    id uuid NOT NULL,
    campaign_id uuid,
    code character varying(255) NOT NULL,
    registration_url text,
    default_plan_key character varying(255),
    trial_days integer,
    max_uses integer DEFAULT 1 NOT NULL,
    used_count integer DEFAULT 0 NOT NULL,
    status character varying(255) DEFAULT 'unused'::character varying NOT NULL,
    assigned_to_name character varying(255),
    assigned_to_phone character varying(255),
    used_by_user_id uuid,
    used_workspace_id uuid,
    used_at timestamp(0) without time zone,
    expires_at timestamp(0) without time zone,
    metadata jsonb,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone
);


--
-- Name: platform_broadcasts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.platform_broadcasts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    title character varying(255) NOT NULL,
    message text NOT NULL,
    type character varying(50) DEFAULT 'info'::character varying,
    audience_definition jsonb DEFAULT '{"target": "all"}'::jsonb NOT NULL,
    delivery_channels jsonb DEFAULT '["in_app"]'::jsonb,
    status character varying(50) DEFAULT 'draft'::character varying,
    scheduled_at timestamp with time zone,
    sent_at timestamp with time zone,
    targeted_count integer DEFAULT 0,
    delivered_count integer DEFAULT 0,
    opened_count integer DEFAULT 0,
    created_by uuid,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT platform_broadcasts_status_check CHECK (((status)::text = ANY (ARRAY[('draft'::character varying)::text, ('scheduled'::character varying)::text, ('sending'::character varying)::text, ('sent'::character varying)::text, ('cancelled'::character varying)::text, ('archived'::character varying)::text]))),
    CONSTRAINT platform_broadcasts_type_check CHECK (((type)::text = ANY (ARRAY[('info'::character varying)::text, ('release'::character varying)::text, ('warning'::character varying)::text, ('maintenance'::character varying)::text, ('survey'::character varying)::text, ('product_tip'::character varying)::text])))
);


--
-- Name: platform_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.platform_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    event_type character varying(100) NOT NULL,
    severity character varying(50) DEFAULT 'info'::character varying,
    workspace_id uuid,
    user_id uuid,
    actor_type character varying(50),
    entity_type character varying(100),
    entity_id uuid,
    metadata jsonb,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT platform_events_actor_type_check CHECK (((actor_type)::text = ANY (ARRAY[('user'::character varying)::text, ('system'::character varying)::text, ('ai'::character varying)::text, ('platform_admin'::character varying)::text]))),
    CONSTRAINT platform_events_severity_check CHECK (((severity)::text = ANY (ARRAY[('info'::character varying)::text, ('warning'::character varying)::text, ('error'::character varying)::text, ('critical'::character varying)::text])))
);


--
-- Name: platform_feature_request_votes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.platform_feature_request_votes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    feature_request_id uuid NOT NULL,
    workspace_id uuid,
    user_id uuid,
    source_type character varying(50) NOT NULL,
    request_text text,
    industry_type character varying(100),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT platform_feature_request_votes_source_type_check CHECK (((source_type)::text = ANY (ARRAY[('ai_unsupported'::character varying)::text, ('user_submission'::character varying)::text, ('support_submission'::character varying)::text, ('internal'::character varying)::text])))
);


--
-- Name: platform_feature_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.platform_feature_requests (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    title character varying(255) NOT NULL,
    normalized_key character varying(255) NOT NULL,
    category character varying(100),
    description text,
    status character varying(50) DEFAULT 'new'::character varying,
    priority character varying(50) DEFAULT 'normal'::character varying,
    request_count integer DEFAULT 1,
    workspace_count integer DEFAULT 1,
    platform_note text,
    first_requested_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    last_requested_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    released_at timestamp with time zone,
    rejected_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT platform_feature_requests_priority_check CHECK (((priority)::text = ANY (ARRAY[('low'::character varying)::text, ('normal'::character varying)::text, ('high'::character varying)::text, ('critical'::character varying)::text]))),
    CONSTRAINT platform_feature_requests_request_count_check CHECK ((request_count >= 0)),
    CONSTRAINT platform_feature_requests_status_check CHECK (((status)::text = ANY (ARRAY[('new'::character varying)::text, ('under_review'::character varying)::text, ('planned'::character varying)::text, ('in_progress'::character varying)::text, ('released'::character varying)::text, ('rejected'::character varying)::text, ('duplicate'::character varying)::text]))),
    CONSTRAINT platform_feature_requests_workspace_count_check CHECK ((workspace_count >= 0))
);


--
-- Name: platform_plan_prices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.platform_plan_prices (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    plan_id uuid NOT NULL,
    billing_cycle character varying(20) NOT NULL,
    base_price numeric(15,2) DEFAULT 0 NOT NULL,
    included_employees integer DEFAULT 1 NOT NULL,
    price_per_employee numeric(10,2) DEFAULT 0 NOT NULL,
    included_ai_credits integer DEFAULT 0 NOT NULL,
    ai_overage_price_per_credit numeric(10,4) DEFAULT 0 NOT NULL,
    currency character varying(3) DEFAULT 'USD'::character varying NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    effective_from date DEFAULT CURRENT_DATE NOT NULL,
    effective_until date,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT platform_plan_prices_billing_cycle_check CHECK (((billing_cycle)::text = ANY (ARRAY[('monthly'::character varying)::text, ('quarterly'::character varying)::text, ('semi_annual'::character varying)::text, ('annual'::character varying)::text, ('multi_year'::character varying)::text, ('custom'::character varying)::text])))
);


--
-- Name: platform_plans; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.platform_plans (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(100) NOT NULL,
    slug character varying(100) NOT NULL,
    description text,
    max_employees integer DEFAULT 5 NOT NULL,
    max_workspaces integer DEFAULT 1 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: platform_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.platform_settings (
    key character varying(100) NOT NULL,
    value text NOT NULL,
    description text,
    updated_by uuid,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: platform_survey_responses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.platform_survey_responses (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    survey_id uuid NOT NULL,
    workspace_id uuid,
    user_id uuid,
    answers jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: platform_surveys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.platform_surveys (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    title character varying(255) NOT NULL,
    description text,
    audience_definition jsonb DEFAULT '{"target": "all"}'::jsonb NOT NULL,
    questions jsonb NOT NULL,
    status character varying(50) DEFAULT 'draft'::character varying,
    starts_at timestamp with time zone,
    ends_at timestamp with time zone,
    invites_sent integer DEFAULT 0,
    responses_received integer DEFAULT 0,
    created_by uuid,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT platform_surveys_check CHECK (((ends_at IS NULL) OR (starts_at IS NULL) OR (ends_at > starts_at))),
    CONSTRAINT platform_surveys_status_check CHECK (((status)::text = ANY (ARRAY[('draft'::character varying)::text, ('scheduled'::character varying)::text, ('active'::character varying)::text, ('closed'::character varying)::text, ('archived'::character varying)::text])))
);


--
-- Name: platform_users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.platform_users (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    email character varying(255) NOT NULL,
    password_hash character varying(255) NOT NULL,
    full_name character varying(255) NOT NULL,
    role character varying(50) NOT NULL,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT platform_users_role_check CHECK (((role)::text = ANY (ARRAY[('platform_owner'::character varying)::text, ('platform_admin'::character varying)::text, ('platform_support'::character varying)::text, ('platform_operations'::character varying)::text, ('platform_engineer'::character varying)::text])))
);


--
-- Name: pos_sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pos_sessions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid,
    terminal_id uuid,
    user_id uuid,
    opening_balance numeric(12,2) DEFAULT 0.00 NOT NULL,
    closing_balance numeric(12,2),
    expected_balance numeric(12,2),
    total_cash_sales numeric(12,2) DEFAULT 0.00,
    total_card_sales numeric(12,2) DEFAULT 0.00,
    total_refunds numeric(12,2) DEFAULT 0.00,
    difference numeric(12,2) DEFAULT 0.00,
    status character varying(50) DEFAULT 'open'::character varying,
    opened_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    closed_at timestamp with time zone,
    notes text,
    session_number character varying(50),
    branch_id uuid,
    total_mobile_sales numeric(12,2) DEFAULT 0.00,
    counted_balance numeric(12,2),
    closed_by uuid,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT pos_sessions_check CHECK (((closed_at IS NULL) OR (closed_at >= opened_at))),
    CONSTRAINT pos_sessions_status_check CHECK (((status)::text = ANY (ARRAY[('open'::character varying)::text, ('closed'::character varying)::text, ('suspended'::character varying)::text]))),
    CONSTRAINT pos_sessions_total_mobile_sales_check CHECK (((total_mobile_sales IS NULL) OR (total_mobile_sales >= (0)::numeric)))
);


--
-- Name: COLUMN pos_sessions.session_number; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.pos_sessions.session_number IS 'Sequential session identifier from document_sequences (e.g. POS-2026-0042).';


--
-- Name: COLUMN pos_sessions.branch_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.pos_sessions.branch_id IS 'Branch where this POS session operated. Enables branch-scoped reporting and filtering.';


--
-- Name: COLUMN pos_sessions.total_mobile_sales; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.pos_sessions.total_mobile_sales IS 'Total mobile payment sales during this session.';


--
-- Name: COLUMN pos_sessions.counted_balance; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.pos_sessions.counted_balance IS 'Physically counted cash balance at session close. Used with expected_balance to calculate variance.';


--
-- Name: COLUMN pos_sessions.closed_by; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.pos_sessions.closed_by IS 'User who closed the session (may differ from session opener).';


--
-- Name: pos_terminals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pos_terminals (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid,
    branch_id uuid,
    name character varying(100) NOT NULL,
    terminal_code character varying(50),
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: price_list_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.price_list_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    price_list_id uuid,
    product_id uuid,
    variant_id uuid,
    price numeric(10,2) NOT NULL,
    min_quantity numeric(12,4) DEFAULT 1,
    CONSTRAINT price_list_items_min_quantity_check CHECK ((min_quantity > (0)::numeric)),
    CONSTRAINT price_list_items_price_check CHECK ((price >= (0)::numeric))
);


--
-- Name: price_lists; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.price_lists (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid,
    name character varying(255) NOT NULL,
    currency character varying(10) DEFAULT 'LYD'::character varying,
    type character varying(50) DEFAULT 'sale'::character varying,
    is_default boolean DEFAULT false,
    start_date date,
    end_date date,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT price_lists_type_check CHECK (((type)::text = ANY (ARRAY[('sale'::character varying)::text, ('purchase'::character varying)::text])))
);


--
-- Name: product_categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.product_categories (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid,
    name character varying(255) NOT NULL,
    parent_id uuid,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: product_variants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.product_variants (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    product_id uuid,
    sku character varying(100),
    name character varying(255) NOT NULL,
    price_override numeric(10,2),
    cost_override numeric(10,2),
    attributes jsonb NOT NULL,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: production_orders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.production_orders (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid,
    created_by uuid,
    product_id uuid,
    work_center_id uuid,
    target_quantity numeric(12,4) NOT NULL,
    status character varying(50) DEFAULT 'planned'::character varying,
    warehouse_id uuid,
    production_order_number character varying(50),
    start_date date,
    end_date date,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT production_orders_status_check CHECK (((status)::text = ANY (ARRAY[('planned'::character varying)::text, ('in_progress'::character varying)::text, ('done'::character varying)::text, ('cancelled'::character varying)::text]))),
    CONSTRAINT production_orders_target_quantity_check CHECK ((target_quantity > (0)::numeric))
);


--
-- Name: products; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.products (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid,
    category_id uuid,
    type character varying(50) DEFAULT 'physical'::character varying,
    name character varying(255) NOT NULL,
    sku character varying(100),
    unit_id uuid,
    base_price numeric(10,2) NOT NULL,
    cost_price numeric(10,2) DEFAULT 0.00 NOT NULL,
    tax_id uuid,
    min_stock_alert integer DEFAULT 5,
    dynamic_attributes jsonb,
    is_deleted boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_product_cost_nonneg CHECK (((cost_price IS NULL) OR (cost_price >= (0)::numeric))),
    CONSTRAINT products_base_price_check CHECK ((base_price >= (0)::numeric)),
    CONSTRAINT products_cost_price_check CHECK ((cost_price >= (0)::numeric)),
    CONSTRAINT products_type_check CHECK (((type)::text = ANY (ARRAY[('physical'::character varying)::text, ('service'::character varying)::text, ('digital'::character varying)::text, ('subscription'::character varying)::text])))
);


--
-- Name: projects; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.projects (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid,
    name character varying(255) NOT NULL,
    contact_id uuid,
    manager_id uuid,
    status character varying(50) DEFAULT 'planning'::character varying,
    budget numeric(12,2) DEFAULT 0.00,
    start_date date,
    end_date date,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT projects_check CHECK (((end_date IS NULL) OR (end_date >= start_date))),
    CONSTRAINT projects_status_check CHECK (((status)::text = ANY (ARRAY[('planning'::character varying)::text, ('in_progress'::character varying)::text, ('on_hold'::character varying)::text, ('completed'::character varying)::text, ('cancelled'::character varying)::text])))
);


--
-- Name: promotions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.promotions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid,
    name character varying(255) NOT NULL,
    type character varying(50) NOT NULL,
    value numeric(10,2),
    buy_quantity integer,
    get_quantity integer,
    min_order_amount numeric(12,2),
    max_discount_amount numeric(12,2),
    applicable_products jsonb,
    applicable_categories jsonb,
    start_date timestamp with time zone NOT NULL,
    end_date timestamp with time zone NOT NULL,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT promotions_check CHECK ((end_date >= start_date)),
    CONSTRAINT promotions_type_check CHECK (((type)::text = ANY (ARRAY[('percentage'::character varying)::text, ('fixed_amount'::character varying)::text, ('buy_x_get_y'::character varying)::text, ('free_shipping'::character varying)::text])))
);


--
-- Name: provisioning_entity_bindings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.provisioning_entity_bindings (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    entity_type character varying(50) NOT NULL,
    local_key character varying(100) NOT NULL,
    entity_id character varying(36) NOT NULL,
    last_provisioning_run_id uuid,
    last_blueprint_id uuid,
    last_blueprint_version integer DEFAULT 1 NOT NULL,
    metadata jsonb,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone,
    ownership_type character varying(30) DEFAULT 'created_by_provisioning'::character varying NOT NULL
);


--
-- Name: provisioning_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.provisioning_runs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    blueprint_id uuid NOT NULL,
    status character varying(20) DEFAULT 'preview'::character varying NOT NULL,
    config jsonb DEFAULT '{}'::jsonb NOT NULL,
    applied_by uuid,
    applied_at timestamp with time zone,
    version integer DEFAULT 1 NOT NULL,
    rollback_config jsonb,
    error_message text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT provisioning_runs_status_check CHECK (((status)::text = ANY (ARRAY[('preview'::character varying)::text, ('prepared'::character varying)::text, ('processing'::character varying)::text, ('foundation_applied'::character varying)::text, ('applied'::character varying)::text, ('onboarding_complete'::character varying)::text, ('rolled_back'::character varying)::text, ('failed'::character varying)::text])))
);


--
-- Name: purchase_order_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.purchase_order_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    po_id uuid NOT NULL,
    product_id uuid NOT NULL,
    variant_id uuid,
    unit_id uuid,
    ordered_quantity numeric(12,4) NOT NULL,
    received_quantity numeric(12,4) DEFAULT 0 NOT NULL,
    unit_cost numeric(12,4) NOT NULL,
    tax_rate numeric(5,2) DEFAULT 0.00,
    subtotal numeric(15,2) NOT NULL,
    product_name_snapshot character varying(255),
    sku_snapshot character varying(100),
    is_cancelled boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT purchase_order_items_check CHECK ((received_quantity <= (ordered_quantity * 1.10))),
    CONSTRAINT purchase_order_items_ordered_quantity_check CHECK ((ordered_quantity > (0)::numeric)),
    CONSTRAINT purchase_order_items_received_quantity_check CHECK ((received_quantity >= (0)::numeric)),
    CONSTRAINT purchase_order_items_subtotal_check CHECK ((subtotal >= (0)::numeric)),
    CONSTRAINT purchase_order_items_tax_rate_check CHECK ((tax_rate >= (0)::numeric)),
    CONSTRAINT purchase_order_items_unit_cost_check CHECK ((unit_cost >= (0)::numeric))
);


--
-- Name: purchase_orders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.purchase_orders (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    supplier_contact_id uuid NOT NULL,
    branch_id uuid,
    created_by uuid,
    approved_by uuid,
    po_number character varying(50),
    reference character varying(100),
    currency character varying(10) DEFAULT 'LYD'::character varying NOT NULL,
    exchange_rate numeric(10,4) DEFAULT 1.0000 NOT NULL,
    subtotal numeric(15,2) DEFAULT 0.00 NOT NULL,
    tax_amount numeric(12,2) DEFAULT 0.00 NOT NULL,
    total_amount numeric(15,2) DEFAULT 0.00 NOT NULL,
    status character varying(50) DEFAULT 'draft'::character varying NOT NULL,
    expected_delivery_date date,
    submitted_at timestamp with time zone,
    approved_at timestamp with time zone,
    received_at timestamp with time zone,
    cancelled_at timestamp with time zone,
    notes text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT purchase_orders_check CHECK ((((status)::text <> 'approved'::text) OR (approved_at IS NOT NULL))),
    CONSTRAINT purchase_orders_check1 CHECK ((((status)::text <> 'cancelled'::text) OR (cancelled_at IS NOT NULL))),
    CONSTRAINT purchase_orders_exchange_rate_check CHECK ((exchange_rate > (0)::numeric)),
    CONSTRAINT purchase_orders_status_check CHECK (((status)::text = ANY (ARRAY[('draft'::character varying)::text, ('submitted'::character varying)::text, ('approved'::character varying)::text, ('partially_received'::character varying)::text, ('received'::character varying)::text, ('invoiced'::character varying)::text, ('closed'::character varying)::text, ('cancelled'::character varying)::text, ('rejected'::character varying)::text]))),
    CONSTRAINT purchase_orders_subtotal_check CHECK ((subtotal >= (0)::numeric)),
    CONSTRAINT purchase_orders_tax_amount_check CHECK ((tax_amount >= (0)::numeric)),
    CONSTRAINT purchase_orders_total_amount_check CHECK ((total_amount >= (0)::numeric))
);


--
-- Name: record_documents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.record_documents (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    pipeline_record_id uuid NOT NULL,
    document_checklist_item_id uuid,
    title character varying(255) NOT NULL,
    status character varying(20) DEFAULT 'uploaded'::character varying NOT NULL,
    file_path character varying(255),
    original_filename character varying(255),
    mime_type character varying(100),
    file_size integer,
    external_reference character varying(255),
    notes text,
    uploaded_by_membership_id uuid,
    uploaded_at timestamp(0) without time zone,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone
);


--
-- Name: recurring_expenses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recurring_expenses (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid,
    category character varying(100) NOT NULL,
    amount numeric(12,2) NOT NULL,
    frequency character varying(50) DEFAULT 'monthly'::character varying,
    next_due_date date NOT NULL,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT recurring_expenses_frequency_check CHECK (((frequency)::text = ANY (ARRAY[('daily'::character varying)::text, ('weekly'::character varying)::text, ('monthly'::character varying)::text, ('quarterly'::character varying)::text, ('semi_annual'::character varying)::text, ('annual'::character varying)::text])))
);


--
-- Name: referral_programs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.referral_programs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    name character varying(255) NOT NULL,
    referrer_reward jsonb DEFAULT '{}'::jsonb NOT NULL,
    referee_reward jsonb DEFAULT '{}'::jsonb NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: TABLE referral_programs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.referral_programs IS '[Expansion Pack] Customer referral program definitions.';


--
-- Name: referrals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.referrals (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    program_id uuid NOT NULL,
    referrer_contact_id uuid NOT NULL,
    referee_contact_id uuid,
    referral_code character varying(50) NOT NULL,
    status character varying(50) DEFAULT 'pending'::character varying NOT NULL,
    converted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT referrals_status_check CHECK (((status)::text = ANY (ARRAY[('pending'::character varying)::text, ('converted'::character varying)::text, ('expired'::character varying)::text, ('cancelled'::character varying)::text])))
);


--
-- Name: TABLE referrals; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.referrals IS '[Expansion Pack] Individual referral tracking with attribution.';


--
-- Name: report_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.report_runs (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    report_template_id uuid,
    data_source character varying(50) NOT NULL,
    run_by_membership_id uuid,
    status character varying(20) DEFAULT 'completed'::character varying NOT NULL,
    parameters json,
    result_summary json,
    row_count integer DEFAULT 0 NOT NULL,
    error_message text,
    started_at timestamp(0) without time zone,
    finished_at timestamp(0) without time zone,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone
);


--
-- Name: report_templates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.report_templates (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    template_key character varying(255),
    name character varying(255) NOT NULL,
    description text,
    data_source character varying(50) NOT NULL,
    columns json NOT NULL,
    filters json,
    group_by json,
    sort_by json,
    visibility character varying(20) DEFAULT 'workspace'::character varying NOT NULL,
    created_by_membership_id uuid,
    is_active boolean DEFAULT true NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone
);


--
-- Name: retention_policies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.retention_policies (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    entity_type character varying(100) NOT NULL,
    retention_years integer NOT NULL,
    action character varying(50) DEFAULT 'archive'::character varying NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT retention_policies_action_check CHECK (((action)::text = ANY (ARRAY[('archive'::character varying)::text, ('anonymize'::character varying)::text, ('delete'::character varying)::text]))),
    CONSTRAINT retention_policies_retention_years_check CHECK ((retention_years >= 1))
);


--
-- Name: TABLE retention_policies; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.retention_policies IS '[Expansion Pack] Per-entity data retention policies with configurable action.';


--
-- Name: return_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.return_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    return_id uuid NOT NULL,
    product_id uuid NOT NULL,
    variant_id uuid,
    quantity numeric(12,4) NOT NULL,
    reason_code character varying(100) NOT NULL,
    reason_detail text,
    condition character varying(50),
    disposition character varying(50),
    restocked_warehouse_id uuid,
    restocked_quantity numeric(12,4) DEFAULT 0,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT return_items_check CHECK ((restocked_quantity <= quantity)),
    CONSTRAINT return_items_check1 CHECK ((((disposition)::text <> 'restock'::text) OR (restocked_warehouse_id IS NOT NULL))),
    CONSTRAINT return_items_check2 CHECK ((((disposition)::text <> 'restock'::text) OR (restocked_quantity > (0)::numeric))),
    CONSTRAINT return_items_condition_check CHECK (((condition IS NULL) OR ((condition)::text = ANY (ARRAY[('good'::character varying)::text, ('damaged'::character varying)::text, ('defective'::character varying)::text])))),
    CONSTRAINT return_items_disposition_check CHECK (((disposition IS NULL) OR ((disposition)::text = ANY (ARRAY[('restock'::character varying)::text, ('dispose'::character varying)::text])))),
    CONSTRAINT return_items_quantity_check CHECK ((quantity > (0)::numeric)),
    CONSTRAINT return_items_restocked_quantity_check CHECK ((restocked_quantity >= (0)::numeric))
);


--
-- Name: returns; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.returns (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    order_id uuid,
    invoice_id uuid,
    contact_id uuid NOT NULL,
    created_by uuid,
    approved_by uuid,
    return_type character varying(50) DEFAULT 'customer'::character varying NOT NULL,
    status character varying(50) DEFAULT 'requested'::character varying NOT NULL,
    return_number character varying(50),
    refund_amount numeric(12,2),
    credit_note_id uuid,
    reason text NOT NULL,
    requested_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    approved_at timestamp with time zone,
    received_at timestamp with time zone,
    inspected_at timestamp with time zone,
    notes text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT returns_check CHECK ((((status)::text <> 'approved'::text) OR (approved_at IS NOT NULL))),
    CONSTRAINT returns_refund_amount_check CHECK (((refund_amount IS NULL) OR (refund_amount >= (0)::numeric))),
    CONSTRAINT returns_return_type_check CHECK (((return_type)::text = ANY (ARRAY[('customer'::character varying)::text, ('supplier'::character varying)::text]))),
    CONSTRAINT returns_status_check CHECK (((status)::text = ANY (ARRAY[('requested'::character varying)::text, ('approved'::character varying)::text, ('received'::character varying)::text, ('inspected'::character varying)::text, ('restocked'::character varying)::text, ('disposed'::character varying)::text, ('rejected'::character varying)::text, ('cancelled'::character varying)::text])))
);


--
-- Name: roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.roles (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid,
    name character varying(100) NOT NULL,
    permissions jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    role_key character varying(50),
    description text,
    hierarchy_level integer DEFAULT 10 NOT NULL,
    is_system boolean DEFAULT false NOT NULL,
    is_default boolean DEFAULT false NOT NULL,
    is_deletable boolean DEFAULT true NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    CONSTRAINT roles_hierarchy_level_check CHECK (((hierarchy_level >= 0) AND (hierarchy_level <= 100)))
);


--
-- Name: COLUMN roles.permissions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.roles.permissions IS 'JSONB array of {key, scope} objects. This is the canonical role-permission persistence model. Custom roles are created by cloning and modifying this JSONB.';


--
-- Name: COLUMN roles.role_key; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.roles.role_key IS 'Machine-readable identifier for template roles (e.g. owner, admin, employee). NULL for custom roles.';


--
-- Name: COLUMN roles.hierarchy_level; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.roles.hierarchy_level IS 'Role assignment authority: users can only assign roles with equal or lower level. Range: 0-100.';


--
-- Name: COLUMN roles.is_system; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.roles.is_system IS 'System roles (owner, co_owner) cannot be deleted or have core permissions removed.';


--
-- Name: COLUMN roles.is_default; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.roles.is_default IS 'New members auto-assigned this role when no explicit role is specified.';


--
-- Name: COLUMN roles.is_deletable; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.roles.is_deletable IS 'FALSE = protected from deletion (e.g. owner, co_owner). TRUE = can be deleted by authorized users.';


--
-- Name: segment_contacts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.segment_contacts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    segment_id uuid NOT NULL,
    contact_id uuid NOT NULL,
    added_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: TABLE segment_contacts; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.segment_contacts IS 'Materialized segment membership. Refreshed by async recalculation job.';


--
-- Name: segments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.segments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    name character varying(255) NOT NULL,
    rules jsonb DEFAULT '[]'::jsonb NOT NULL,
    contact_count integer DEFAULT 0 NOT NULL,
    is_dynamic boolean DEFAULT true NOT NULL,
    recalculated_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: TABLE segments; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.segments IS '[Core v1] Rule-based customer segmentation. Dynamic segments auto-recalculate.';


--
-- Name: shift_assignments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shift_assignments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    user_id uuid NOT NULL,
    shift_id uuid NOT NULL,
    effective_date date NOT NULL,
    end_date date,
    assigned_by uuid,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT shift_assignments_check CHECK (((end_date IS NULL) OR (end_date >= effective_date)))
);


--
-- Name: TABLE shift_assignments; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.shift_assignments IS 'Per-user shift scheduling (BR-ATT-002). Overrides users.shift_id for specific date ranges. If a user has no assignment for a given date, the default users.shift_id applies. Overlapping assignments for the same user are DB-ENFORCED by exclusion constraint.';


--
-- Name: shifts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shifts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid,
    name character varying(100) NOT NULL,
    start_time time without time zone NOT NULL,
    end_time time without time zone NOT NULL,
    grace_period_minutes integer DEFAULT 15,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    is_overnight boolean DEFAULT false,
    is_active boolean DEFAULT true,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: COLUMN shifts.is_overnight; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.shifts.is_overnight IS 'TRUE when shift crosses midnight (e.g. 22:00–06:00).';


--
-- Name: shipment_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shipment_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    shipment_id uuid NOT NULL,
    order_item_id uuid,
    product_id uuid NOT NULL,
    variant_id uuid,
    warehouse_id uuid NOT NULL,
    quantity numeric(12,4) NOT NULL,
    batch_id uuid,
    reservation_id uuid,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT shipment_items_quantity_check CHECK ((quantity > (0)::numeric))
);


--
-- Name: shipments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shipments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid,
    invoice_id uuid,
    contact_id uuid,
    delivery_driver_id uuid,
    tracking_number character varying(100),
    shipping_provider character varying(100),
    origin text NOT NULL,
    destination text NOT NULL,
    weight numeric(10,2),
    customs_fees numeric(12,2) DEFAULT 0.00,
    shipping_cost numeric(12,2) DEFAULT 0.00 NOT NULL,
    status character varying(50) DEFAULT 'processing'::character varying,
    estimated_delivery_date date,
    shipped_at timestamp with time zone,
    delivered_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    shipment_number character varying(50),
    order_id uuid,
    warehouse_id uuid,
    return_id uuid,
    picked_at timestamp with time zone,
    packed_at timestamp with time zone,
    CONSTRAINT chk_shipments_status CHECK (((status)::text = ANY (ARRAY[('pending'::character varying)::text, ('picking'::character varying)::text, ('packed'::character varying)::text, ('shipped'::character varying)::text, ('delivered'::character varying)::text, ('cancelled'::character varying)::text, ('processing'::character varying)::text, ('picked_up'::character varying)::text, ('in_transit'::character varying)::text, ('out_for_delivery'::character varying)::text, ('returned'::character varying)::text]))),
    CONSTRAINT shipments_check CHECK (((delivered_at IS NULL) OR (shipped_at IS NULL) OR (delivered_at >= shipped_at)))
);


--
-- Name: stock_reservations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stock_reservations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    order_id uuid NOT NULL,
    order_item_id uuid NOT NULL,
    warehouse_id uuid NOT NULL,
    product_id uuid NOT NULL,
    variant_id uuid,
    reserved_quantity numeric(12,4) NOT NULL,
    fulfilled_quantity numeric(12,4) DEFAULT 0 NOT NULL,
    released_quantity numeric(12,4) DEFAULT 0 NOT NULL,
    status character varying(50) DEFAULT 'active'::character varying NOT NULL,
    reserved_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    fulfilled_at timestamp with time zone,
    released_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT stock_reservations_check CHECK (((fulfilled_quantity + released_quantity) <= reserved_quantity)),
    CONSTRAINT stock_reservations_check1 CHECK ((((status)::text <> 'fulfilled'::text) OR (fulfilled_at IS NOT NULL))),
    CONSTRAINT stock_reservations_check2 CHECK ((((status)::text <> 'released'::text) OR (released_at IS NOT NULL))),
    CONSTRAINT stock_reservations_check3 CHECK ((NOT (((status)::text = 'released'::text) AND (fulfilled_quantity > (0)::numeric) AND (fulfilled_at > released_at)))),
    CONSTRAINT stock_reservations_check4 CHECK ((NOT (((status)::text = 'fulfilled'::text) AND (released_quantity > (0)::numeric)))),
    CONSTRAINT stock_reservations_fulfilled_quantity_check CHECK ((fulfilled_quantity >= (0)::numeric)),
    CONSTRAINT stock_reservations_released_quantity_check CHECK ((released_quantity >= (0)::numeric)),
    CONSTRAINT stock_reservations_reserved_quantity_check CHECK ((reserved_quantity > (0)::numeric)),
    CONSTRAINT stock_reservations_status_check CHECK (((status)::text = ANY (ARRAY[('active'::character varying)::text, ('fulfilled'::character varying)::text, ('partially_fulfilled'::character varying)::text, ('released'::character varying)::text, ('expired'::character varying)::text])))
);


--
-- Name: stock_transfer_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stock_transfer_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    transfer_id uuid,
    product_id uuid,
    variant_id uuid,
    quantity numeric(12,4) NOT NULL,
    received_quantity numeric(12,4) DEFAULT 0,
    notes text
);


--
-- Name: stock_transfers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stock_transfers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid,
    from_warehouse_id uuid,
    to_warehouse_id uuid,
    created_by uuid,
    approved_by uuid,
    status character varying(50) DEFAULT 'draft'::character varying,
    reference character varying(100),
    transfer_number character varying(50),
    notes text,
    transfer_date date DEFAULT CURRENT_DATE,
    received_date date,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT stock_transfers_check CHECK ((from_warehouse_id <> to_warehouse_id)),
    CONSTRAINT stock_transfers_status_check CHECK (((status)::text = ANY (ARRAY[('draft'::character varying)::text, ('pending_approval'::character varying)::text, ('approved'::character varying)::text, ('in_transit'::character varying)::text, ('received'::character varying)::text, ('cancelled'::character varying)::text])))
);


--
-- Name: subscription_plans; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.subscription_plans (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(100) NOT NULL,
    tier character varying(50) NOT NULL,
    price_monthly numeric(10,2) DEFAULT 0.00 NOT NULL,
    price_annual numeric(10,2) DEFAULT 0.00 NOT NULL,
    max_users integer,
    max_ai_requests_daily integer,
    features_enabled jsonb DEFAULT '{}'::jsonb NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT subscription_plans_max_ai_requests_daily_check CHECK (((max_ai_requests_daily IS NULL) OR (max_ai_requests_daily > 0))),
    CONSTRAINT subscription_plans_max_users_check CHECK (((max_users IS NULL) OR (max_users > 0))),
    CONSTRAINT subscription_plans_price_annual_check CHECK ((price_annual >= (0)::numeric)),
    CONSTRAINT subscription_plans_price_monthly_check CHECK ((price_monthly >= (0)::numeric)),
    CONSTRAINT subscription_plans_tier_check CHECK (((tier)::text = ANY (ARRAY[('freemium'::character varying)::text, ('starter'::character varying)::text, ('professional'::character varying)::text, ('enterprise'::character varying)::text])))
);


--
-- Name: TABLE subscription_plans; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.subscription_plans IS 'Platform-scoped catalogue of subscription tiers and their feature entitlements.';


--
-- Name: COLUMN subscription_plans.features_enabled; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.subscription_plans.features_enabled IS 'JSON map of feature flags and module entitlements included with this plan.';


--
-- Name: sync_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sync_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    integration_id uuid NOT NULL,
    direction character varying(10) NOT NULL,
    entity_type character varying(100) NOT NULL,
    entity_id uuid,
    status character varying(50) NOT NULL,
    details jsonb,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT sync_logs_direction_check CHECK (((direction)::text = ANY (ARRAY[('inbound'::character varying)::text, ('outbound'::character varying)::text]))),
    CONSTRAINT sync_logs_status_check CHECK (((status)::text = ANY (ARRAY[('success'::character varying)::text, ('conflict'::character varying)::text, ('error'::character varying)::text])))
);


--
-- Name: TABLE sync_logs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.sync_logs IS '[Core v1] Integration sync activity log for debugging and audit.';


--
-- Name: tasks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tasks (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid,
    project_id uuid,
    assigned_to uuid,
    title character varying(255) NOT NULL,
    status character varying(50) DEFAULT 'todo'::character varying,
    due_date date,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT tasks_status_check CHECK (((status)::text = ANY (ARRAY[('todo'::character varying)::text, ('in_progress'::character varying)::text, ('review'::character varying)::text, ('done'::character varying)::text, ('cancelled'::character varying)::text])))
);


--
-- Name: tax_rules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tax_rules (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    country_pack_id uuid,
    rule_type character varying(50) NOT NULL,
    rate numeric(6,4) NOT NULL,
    conditions jsonb DEFAULT '{}'::jsonb NOT NULL,
    effective_from date NOT NULL,
    effective_to date,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT tax_rules_check CHECK (((effective_to IS NULL) OR (effective_to > effective_from))),
    CONSTRAINT tax_rules_rate_check CHECK (((rate >= (0)::numeric) AND (rate <= (1)::numeric))),
    CONSTRAINT tax_rules_rule_type_check CHECK (((rule_type)::text = ANY (ARRAY[('standard'::character varying)::text, ('reduced'::character varying)::text, ('zero'::character varying)::text, ('exempt'::character varying)::text, ('reverse_charge'::character varying)::text, ('withholding'::character varying)::text])))
);


--
-- Name: TABLE tax_rules; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.tax_rules IS '[Core v1] Country-specific tax rules. Effective-dated — never deleted, only superseded.';


--
-- Name: taxes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.taxes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid,
    name character varying(100) NOT NULL,
    rate numeric(5,2) NOT NULL,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT taxes_rate_check CHECK ((rate >= (0)::numeric))
);


--
-- Name: teams; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.teams (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    department_id uuid,
    team_key character varying(255),
    name character varying(255) NOT NULL,
    description text,
    manager_membership_id uuid,
    is_active boolean DEFAULT true NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone
);


--
-- Name: transactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.transactions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid,
    created_by uuid,
    contact_id uuid,
    account_id uuid,
    from_account_id uuid,
    to_account_id uuid,
    transaction_type character varying(50) NOT NULL,
    amount numeric(12,2) NOT NULL,
    payment_method character varying(50) DEFAULT 'cash'::character varying,
    notes text,
    transaction_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT transactions_amount_check CHECK ((amount > (0)::numeric)),
    CONSTRAINT transactions_check CHECK (((((transaction_type)::text = ANY (ARRAY[('income'::character varying)::text, ('expense'::character varying)::text])) AND (account_id IS NOT NULL)) OR (((transaction_type)::text = 'transfer'::text) AND (from_account_id IS NOT NULL) AND (to_account_id IS NOT NULL) AND (from_account_id <> to_account_id)))),
    CONSTRAINT transactions_payment_method_check CHECK (((payment_method)::text = ANY (ARRAY[('cash'::character varying)::text, ('bank_transfer'::character varying)::text, ('check'::character varying)::text, ('card'::character varying)::text, ('mobile_payment'::character varying)::text]))),
    CONSTRAINT transactions_transaction_type_check CHECK (((transaction_type)::text = ANY (ARRAY[('income'::character varying)::text, ('expense'::character varying)::text, ('transfer'::character varying)::text])))
);


--
-- Name: translations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.translations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    locale character varying(10) NOT NULL,
    namespace character varying(100) NOT NULL,
    key character varying(255) NOT NULL,
    value text NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: TABLE translations; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.translations IS 'Platform-global i18n string storage. No workspace_id — shared across all tenants. Managed by platform admins. Loaded by clients at app startup.';


--
-- Name: units_of_measure; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.units_of_measure (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid,
    name character varying(100) NOT NULL,
    symbol character varying(20) NOT NULL,
    category character varying(50),
    base_unit_id uuid,
    conversion_factor numeric(15,6) DEFAULT 1.000000,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: user_permission_overrides; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_permission_overrides (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    membership_id uuid NOT NULL,
    permission_key character varying(100) NOT NULL,
    scope character varying(20) NOT NULL,
    override_type character varying(10) NOT NULL,
    reason text,
    granted_by_membership_id uuid NOT NULL,
    expires_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT user_permission_overrides_override_type_check CHECK (((override_type)::text = ANY (ARRAY[('grant'::character varying)::text, ('deny'::character varying)::text]))),
    CONSTRAINT user_permission_overrides_scope_check CHECK (((scope)::text = ANY (ARRAY[('own'::character varying)::text, ('team'::character varying)::text, ('dept'::character varying)::text, ('branch'::character varying)::text, ('wh'::character varying)::text, ('ws'::character varying)::text])))
);


--
-- Name: TABLE user_permission_overrides; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.user_permission_overrides IS 'Per-user permission grants/denials that override role-level permissions. Deny takes precedence over grant in resolution.';


--
-- Name: COLUMN user_permission_overrides.override_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.user_permission_overrides.override_type IS 'grant = add permission beyond role; deny = block even if role grants it.';


--
-- Name: COLUMN user_permission_overrides.granted_by_membership_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.user_permission_overrides.granted_by_membership_id IS 'The membership of the user who applied this override. Workspace-safe FK (no dependency on users.workspace_id).';


--
-- Name: COLUMN user_permission_overrides.expires_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.user_permission_overrides.expires_at IS 'NULL = permanent. If set, override is inactive after this time; cleanup via scheduled job.';


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id_deprecated uuid,
    department_id_deprecated uuid,
    manager_id_deprecated uuid,
    shift_id_deprecated uuid,
    branch_id_deprecated uuid,
    role_id_deprecated uuid,
    full_name character varying(255) NOT NULL,
    phone_number character varying(20) NOT NULL,
    password_hash character varying(255) NOT NULL,
    permissions_deprecated jsonb,
    hire_date_deprecated date DEFAULT CURRENT_DATE,
    base_salary_deprecated numeric(10,2) DEFAULT 0.00,
    annual_leave_balance_deprecated integer DEFAULT 21,
    approval_status_deprecated character varying(50) DEFAULT 'pending'::character varying,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    is_active boolean DEFAULT false,
    email character varying(255) NOT NULL,
    preferred_locale character varying(10),
    is_super_admin boolean DEFAULT false NOT NULL,
    CONSTRAINT users_approval_status_check CHECK (((approval_status_deprecated)::text = ANY (ARRAY[('pending'::character varying)::text, ('approved'::character varying)::text, ('rejected'::character varying)::text])))
);


--
-- Name: COLUMN users.workspace_id_deprecated; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.users.workspace_id_deprecated IS '🚫 DEPRECATED (Migration 008). Renamed from workspace_id. Use workspace_memberships for user-to-workspace relationship. ROLLBACK: ALTER TABLE users RENAME COLUMN workspace_id_deprecated TO workspace_id;';


--
-- Name: COLUMN users.department_id_deprecated; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.users.department_id_deprecated IS '🚫 DEPRECATED (Migration 008). Renamed from department_id. Use workspace_memberships.department_id. ROLLBACK: ALTER TABLE users RENAME COLUMN department_id_deprecated TO department_id;';


--
-- Name: COLUMN users.manager_id_deprecated; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.users.manager_id_deprecated IS '🚫 DEPRECATED (Migration 008). Renamed from manager_id. Use workspace_memberships.manager_membership_id (workspace-safe FK). ROLLBACK: ALTER TABLE users RENAME COLUMN manager_id_deprecated TO manager_id;';


--
-- Name: COLUMN users.shift_id_deprecated; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.users.shift_id_deprecated IS '🚫 DEPRECATED (Migration 008). Renamed from shift_id. Use workspace_memberships.shift_id. ROLLBACK: ALTER TABLE users RENAME COLUMN shift_id_deprecated TO shift_id;';


--
-- Name: COLUMN users.branch_id_deprecated; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.users.branch_id_deprecated IS '🚫 DEPRECATED (Migration 008). Renamed from branch_id. Use workspace_memberships.branch_id. ROLLBACK: ALTER TABLE users RENAME COLUMN branch_id_deprecated TO branch_id;';


--
-- Name: COLUMN users.role_id_deprecated; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.users.role_id_deprecated IS '🚫 DEPRECATED (Migration 008). Renamed from role_id. Use membership_roles for role assignments. ROLLBACK: ALTER TABLE users RENAME COLUMN role_id_deprecated TO role_id;';


--
-- Name: COLUMN users.permissions_deprecated; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.users.permissions_deprecated IS '🚫 DEPRECATED (Migration 008). Renamed from permissions. Use user_permission_overrides table. ROLLBACK: ALTER TABLE users RENAME COLUMN permissions_deprecated TO permissions;';


--
-- Name: COLUMN users.hire_date_deprecated; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.users.hire_date_deprecated IS '🚫 DEPRECATED (Migration 008). Renamed from hire_date. Use workspace_memberships.hire_date (per-workspace). ROLLBACK: ALTER TABLE users RENAME COLUMN hire_date_deprecated TO hire_date;';


--
-- Name: COLUMN users.base_salary_deprecated; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.users.base_salary_deprecated IS '🚫 DEPRECATED (Migration 008). Renamed from base_salary. Use workspace_memberships.base_salary (per-workspace). ROLLBACK: ALTER TABLE users RENAME COLUMN base_salary_deprecated TO base_salary;';


--
-- Name: COLUMN users.annual_leave_balance_deprecated; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.users.annual_leave_balance_deprecated IS '🚫 DEPRECATED (Migration 008). Renamed from annual_leave_balance. Use leave_balances table (per leave type, per fiscal year). ROLLBACK: ALTER TABLE users RENAME COLUMN annual_leave_balance_deprecated TO annual_leave_balance;';


--
-- Name: COLUMN users.approval_status_deprecated; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.users.approval_status_deprecated IS '🚫 DEPRECATED (Migration 008). Renamed from approval_status. Use workspace_memberships.status (pending/active/suspended/removed). ROLLBACK: ALTER TABLE users RENAME COLUMN approval_status_deprecated TO approval_status;';


--
-- Name: COLUMN users.is_active; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.users.is_active IS 'Whether the user can log in. For workspace-specific status, use workspace_memberships.status instead.';


--
-- Name: COLUMN users.email; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.users.email IS 'User login identifier. Globally unique across all workspaces (one email = one human). Multi-workspace access is managed via workspace_memberships, not duplicate user rows. NOT NULL enforced as of migration 012. Primary authentication credential.';


--
-- Name: COLUMN users.preferred_locale; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.users.preferred_locale IS 'Per-user locale override. If NULL, workspace.default_locale is used.';


--
-- Name: workspace_memberships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workspace_memberships (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    user_id uuid NOT NULL,
    department_id uuid,
    branch_id uuid,
    shift_id uuid,
    manager_membership_id uuid,
    status character varying(50) DEFAULT 'pending'::character varying NOT NULL,
    hire_date date,
    base_salary numeric(10,2) DEFAULT 0.00,
    annual_leave_balance integer DEFAULT 21,
    assigned_warehouses jsonb DEFAULT '[]'::jsonb NOT NULL,
    joined_at timestamp with time zone,
    suspended_at timestamp with time zone,
    removed_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    team_id uuid,
    job_title character varying(255),
    CONSTRAINT workspace_memberships_annual_leave_balance_check CHECK (((annual_leave_balance IS NULL) OR (annual_leave_balance >= 0))),
    CONSTRAINT workspace_memberships_base_salary_check CHECK (((base_salary IS NULL) OR (base_salary >= (0)::numeric))),
    CONSTRAINT workspace_memberships_check CHECK (((manager_membership_id IS NULL) OR (manager_membership_id <> id))),
    CONSTRAINT workspace_memberships_status_check CHECK (((status)::text = ANY (ARRAY[('pending'::character varying)::text, ('active'::character varying)::text, ('suspended'::character varying)::text, ('removed'::character varying)::text])))
);
ALTER TABLE ONLY public.workspace_memberships ALTER COLUMN workspace_id SET STATISTICS 500;
ALTER TABLE ONLY public.workspace_memberships ALTER COLUMN user_id SET STATISTICS 500;
ALTER TABLE ONLY public.workspace_memberships ALTER COLUMN status SET STATISTICS 200;


--
-- Name: TABLE workspace_memberships; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.workspace_memberships IS 'Canonical user-to-workspace relationship (promoted from transitional in 006). Role assignments via membership_roles. Org-structure and HR data are per-workspace. Migration 008: sync triggers removed. workspace_memberships is now the SOLE source of truth. Legacy users.workspace_id_deprecated is retained for rollback safety only.';


--
-- Name: COLUMN workspace_memberships.manager_membership_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.workspace_memberships.manager_membership_id IS 'Self-FK to another membership in the same workspace. Identifies direct manager for team scope resolution.';


--
-- Name: COLUMN workspace_memberships.assigned_warehouses; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.workspace_memberships.assigned_warehouses IS 'JSONB array of warehouse UUIDs for wh scope resolution.';


--
-- Name: v_user_workspace_context; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_user_workspace_context AS
 SELECT wm.id AS membership_id,
    wm.workspace_id,
    wm.user_id,
    u.full_name,
    u.phone_number,
    u.email,
    wm.department_id,
    d.name AS department_name,
    wm.branch_id,
    b.name AS branch_name,
    wm.shift_id,
    wm.status AS membership_status,
    wm.hire_date,
    wm.base_salary,
    wm.annual_leave_balance,
    wm.assigned_warehouses,
    wm.manager_membership_id,
    r.id AS role_id,
    r.name AS role_name,
    r.role_key,
    r.hierarchy_level,
    r.permissions AS role_permissions,
    ((r.role_key)::text = ANY (ARRAY[('owner'::character varying)::text, ('co_owner'::character varying)::text])) AS is_admin_level,
    wm.joined_at,
    wm.created_at AS membership_created_at
   FROM (((((public.workspace_memberships wm
     JOIN public.users u ON ((u.id = wm.user_id)))
     LEFT JOIN public.membership_roles mr ON (((mr.membership_id = wm.id) AND (mr.is_primary = true))))
     LEFT JOIN public.roles r ON ((r.id = mr.role_id)))
     LEFT JOIN public.departments d ON ((d.id = wm.department_id)))
     LEFT JOIN public.branches b ON ((b.id = wm.branch_id)))
  WHERE ((wm.status)::text = ANY (ARRAY[('active'::character varying)::text, ('pending'::character varying)::text]));


--
-- Name: VIEW v_user_workspace_context; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_user_workspace_context IS 'Convenience view: flat user-per-workspace context with primary role, department, branch. Promoted from transitional (006) to permanent (008). No longer references deprecated columns. Use for API responses, dashboard context, and permission resolution.';


--
-- Name: v_workspace_members; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_workspace_members AS
 SELECT wm.workspace_id,
    wm.id AS membership_id,
    u.id AS user_id,
    u.full_name,
    u.phone_number,
    u.email,
    wm.status,
    wm.department_id,
    d.name AS department_name,
    wm.branch_id,
    b.name AS branch_name,
    wm.hire_date,
    wm.joined_at,
    COALESCE(jsonb_agg(jsonb_build_object('role_id', r.id, 'role_name', r.name, 'role_key', r.role_key, 'is_primary', mr.is_primary, 'hierarchy_level', r.hierarchy_level)) FILTER (WHERE (r.id IS NOT NULL)), '[]'::jsonb) AS roles
   FROM (((((public.workspace_memberships wm
     JOIN public.users u ON ((u.id = wm.user_id)))
     LEFT JOIN public.membership_roles mr ON ((mr.membership_id = wm.id)))
     LEFT JOIN public.roles r ON ((r.id = mr.role_id)))
     LEFT JOIN public.departments d ON ((d.id = wm.department_id)))
     LEFT JOIN public.branches b ON ((b.id = wm.branch_id)))
  GROUP BY wm.workspace_id, wm.id, u.id, u.full_name, u.phone_number, u.email, wm.status, wm.department_id, d.name, wm.branch_id, b.name, wm.hire_date, wm.joined_at;


--
-- Name: VIEW v_workspace_members; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_workspace_members IS 'Admin view: workspace members with aggregated roles. Promoted from transitional (006) to permanent (008). Use for workspace admin panel, member listing, and role management.';


--
-- Name: warehouses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.warehouses (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid,
    branch_id uuid,
    name character varying(255) NOT NULL,
    location text
);


--
-- Name: webhook_deliveries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.webhook_deliveries (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    subscription_id uuid NOT NULL,
    event_type character varying(255) NOT NULL,
    payload jsonb NOT NULL,
    status character varying(50) DEFAULT 'pending'::character varying NOT NULL,
    attempts integer DEFAULT 0 NOT NULL,
    last_attempted_at timestamp with time zone,
    response_code integer,
    response_body text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT webhook_deliveries_status_check CHECK (((status)::text = ANY (ARRAY[('pending'::character varying)::text, ('delivered'::character varying)::text, ('failed'::character varying)::text])))
);


--
-- Name: TABLE webhook_deliveries; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.webhook_deliveries IS '[Core v1] Webhook delivery attempts with retry tracking.';


--
-- Name: webhook_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.webhook_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    stripe_event_id character varying(100) NOT NULL,
    event_type character varying(100) NOT NULL,
    payload jsonb NOT NULL,
    status character varying(20) DEFAULT 'received'::character varying NOT NULL,
    processed_at timestamp with time zone,
    error_message text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT webhook_events_status_check CHECK (((status)::text = ANY (ARRAY[('received'::character varying)::text, ('processed'::character varying)::text, ('failed'::character varying)::text])))
);


--
-- Name: webhook_subscriptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.webhook_subscriptions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    event_type character varying(255) NOT NULL,
    target_url character varying(1000) NOT NULL,
    secret character varying(255),
    is_active boolean DEFAULT true NOT NULL,
    failure_count integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: TABLE webhook_subscriptions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.webhook_subscriptions IS '[Core v1] Outbound webhook event subscriptions with signing secrets.';


--
-- Name: work_centers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.work_centers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid,
    name character varying(255) NOT NULL,
    code character varying(50),
    capacity_per_hour numeric(10,2),
    cost_per_hour numeric(10,2) DEFAULT 0.00,
    is_active boolean DEFAULT true,
    notes text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: workspace_configurations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workspace_configurations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    enabled_modules jsonb DEFAULT '[]'::jsonb NOT NULL,
    role_configs jsonb DEFAULT '{}'::jsonb NOT NULL,
    pages jsonb DEFAULT '[]'::jsonb NOT NULL,
    workflows jsonb DEFAULT '[]'::jsonb NOT NULL,
    automations jsonb DEFAULT '[]'::jsonb NOT NULL,
    provisioning_run_id uuid,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: workspace_country_packs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workspace_country_packs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    country_pack_id uuid NOT NULL,
    installed_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    config_overrides jsonb DEFAULT '{}'::jsonb NOT NULL
);


--
-- Name: TABLE workspace_country_packs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.workspace_country_packs IS '[Core v1 framework] Links workspaces to installed country packs.';


--
-- Name: workspace_feature_flags; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workspace_feature_flags (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    feature_key character varying(100) NOT NULL,
    is_enabled boolean DEFAULT true NOT NULL,
    override_reason text,
    set_by uuid,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: workspace_integrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workspace_integrations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    provider_id uuid NOT NULL,
    credentials jsonb DEFAULT '{}'::jsonb NOT NULL,
    status character varying(50) DEFAULT 'pending'::character varying NOT NULL,
    last_sync_at timestamp with time zone,
    error_message text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT workspace_integrations_status_check CHECK (((status)::text = ANY (ARRAY[('pending'::character varying)::text, ('active'::character varying)::text, ('error'::character varying)::text, ('disconnected'::character varying)::text])))
);


--
-- Name: TABLE workspace_integrations; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.workspace_integrations IS '[Core v1] Per-workspace integration connections with encrypted credentials.';


--
-- Name: workspace_invitation_roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workspace_invitation_roles (
    id uuid NOT NULL,
    workspace_invitation_id uuid NOT NULL,
    role_id uuid NOT NULL,
    is_primary boolean DEFAULT false NOT NULL,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone
);


--
-- Name: workspace_invitations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workspace_invitations (
    id uuid NOT NULL,
    workspace_id uuid NOT NULL,
    email character varying(255) NOT NULL,
    full_name character varying(255),
    role_id uuid,
    invited_by_user_id uuid NOT NULL,
    accepted_user_id uuid,
    token_hash character varying(64) NOT NULL,
    status character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    expires_at timestamp(0) without time zone NOT NULL,
    accepted_at timestamp(0) without time zone,
    revoked_at timestamp(0) without time zone,
    metadata jsonb,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone,
    token_encrypted text,
    department_id uuid,
    team_id uuid,
    job_title character varying(255),
    preferred_locale character varying(5) DEFAULT 'ar'::character varying NOT NULL,
    last_sent_at timestamp(0) without time zone,
    send_count integer DEFAULT 0 NOT NULL,
    delivery_status character varying(20),
    delivery_error text
);


--
-- Name: workspace_subscriptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workspace_subscriptions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    plan_id uuid NOT NULL,
    plan_price_id uuid NOT NULL,
    status character varying(20) DEFAULT 'trial'::character varying NOT NULL,
    billing_cycle character varying(20) NOT NULL,
    current_period_start timestamp with time zone NOT NULL,
    current_period_end timestamp with time zone NOT NULL,
    trial_ends_at timestamp with time zone,
    included_employees integer DEFAULT 1 NOT NULL,
    current_employee_count integer DEFAULT 0 NOT NULL,
    billable_employee_count integer DEFAULT 0 NOT NULL,
    overage_employee_count integer DEFAULT 0 NOT NULL,
    price_per_extra_employee numeric(10,2) DEFAULT 0 NOT NULL,
    cancelled_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    stripe_customer_id character varying(50),
    stripe_subscription_id character varying(50),
    stripe_price_id character varying(100),
    CONSTRAINT workspace_subscriptions_status_check CHECK (((status)::text = ANY (ARRAY[('active'::character varying)::text, ('trial'::character varying)::text, ('past_due'::character varying)::text, ('suspended'::character varying)::text, ('cancelled'::character varying)::text])))
);


--
-- Name: workspace_template_applications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workspace_template_applications (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    workspace_id uuid NOT NULL,
    business_template_id uuid NOT NULL,
    template_key character varying(255) NOT NULL,
    template_version integer NOT NULL,
    status character varying(255) DEFAULT 'applied'::character varying NOT NULL,
    applied_at timestamp(0) without time zone,
    applied_by_user_id uuid,
    snapshot jsonb,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone
);


--
-- Name: workspaces; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workspaces (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(255) NOT NULL,
    industry_type character varying(100),
    business_size character varying(50),
    onboarding_data jsonb,
    invite_code character varying(50),
    ui_configuration jsonb,
    subscription_status character varying(50) DEFAULT 'freemium'::character varying,
    max_users integer DEFAULT 1,
    subscription_end_date timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    is_active boolean DEFAULT true,
    default_locale character varying(10) DEFAULT 'en'::character varying NOT NULL,
    default_currency character varying(3) DEFAULT 'LYD'::character varying NOT NULL,
    timezone character varying(50) DEFAULT 'UTC'::character varying NOT NULL,
    status character varying(50) DEFAULT 'active'::character varying,
    invite_expires_at timestamp with time zone,
    CONSTRAINT chk_workspace_status CHECK (((status)::text = ANY (ARRAY[('active'::character varying)::text, ('suspended'::character varying)::text, ('pending_deletion'::character varying)::text, ('deleted'::character varying)::text]))),
    CONSTRAINT workspaces_subscription_status_check CHECK (((subscription_status)::text = ANY (ARRAY[('freemium'::character varying)::text, ('trial'::character varying)::text, ('active'::character varying)::text, ('suspended'::character varying)::text, ('cancelled'::character varying)::text])))
);


--
-- Name: COLUMN workspaces.is_active; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.workspaces.is_active IS 'DEPRECATED — use workspaces.status for operational lifecycle management. Retained for backward compatibility. Application code should migrate to status column. is_active=TRUE ≈ status IN (active). is_active=FALSE ≈ status IN (suspended, pending_deletion, deleted).';


--
-- Name: COLUMN workspaces.default_locale; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.workspaces.default_locale IS 'ISO locale code (e.g. en, ar, fr, tr). Drives UI language for workspace when user has no preferred_locale.';


--
-- Name: COLUMN workspaces.default_currency; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.workspaces.default_currency IS 'ISO 4217 currency code. Base reporting currency for financial consolidation.';


--
-- Name: COLUMN workspaces.timezone; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.workspaces.timezone IS 'IANA timezone (e.g. Africa/Tripoli, Asia/Dubai). Used for date/time display and scheduling.';


--
-- Name: COLUMN workspaces.status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.workspaces.status IS 'Operational lifecycle: active → suspended → pending_deletion → deleted. This is SEPARATE from subscription_status (billing lifecycle). A workspace can be status=active + subscription_status=cancelled (grace period), or status=suspended + subscription_status=active (policy violation). See BR-WKS-005, BR-PLT-001.';


--
-- Name: COLUMN workspaces.invite_expires_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.workspaces.invite_expires_at IS 'Expiry timestamp for the current invite_code. Null = no active invite. Application MUST reject invite_code if NOW() > invite_expires_at. Default invite validity: 72 hours (workspace-configurable). Workspace admins may revoke invites by setting this to NOW().';


--
-- Name: _deprecation_registry id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public._deprecation_registry ALTER COLUMN id SET DEFAULT nextval('public._deprecation_registry_id_seq'::regclass);


--
-- Name: migrations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.migrations ALTER COLUMN id SET DEFAULT nextval('public.migrations_id_seq'::regclass);


--
-- Name: personal_access_tokens id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.personal_access_tokens ALTER COLUMN id SET DEFAULT nextval('public.personal_access_tokens_id_seq'::regclass);


--
-- Name: _deprecation_registry _deprecation_registry_object_type_object_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public._deprecation_registry
    ADD CONSTRAINT _deprecation_registry_object_type_object_name_key UNIQUE (object_type, object_name);


--
-- Name: _deprecation_registry _deprecation_registry_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public._deprecation_registry
    ADD CONSTRAINT _deprecation_registry_pkey PRIMARY KEY (id);


--
-- Name: accounts accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounts
    ADD CONSTRAINT accounts_pkey PRIMARY KEY (id);


--
-- Name: accounts accounts_workspace_id_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounts
    ADD CONSTRAINT accounts_workspace_id_code_key UNIQUE (workspace_id, code);


--
-- Name: ai_change_requests ai_change_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_change_requests
    ADD CONSTRAINT ai_change_requests_pkey PRIMARY KEY (id);


--
-- Name: ai_conversations ai_conversations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_conversations
    ADD CONSTRAINT ai_conversations_pkey PRIMARY KEY (id);


--
-- Name: ai_credit_balances ai_credit_balances_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_credit_balances
    ADD CONSTRAINT ai_credit_balances_pkey PRIMARY KEY (id);


--
-- Name: ai_credit_balances ai_credit_balances_workspace_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_credit_balances
    ADD CONSTRAINT ai_credit_balances_workspace_id_key UNIQUE (workspace_id);


--
-- Name: ai_credit_transactions ai_credit_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_credit_transactions
    ADD CONSTRAINT ai_credit_transactions_pkey PRIMARY KEY (id);


--
-- Name: ai_execution_plans ai_execution_plans_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_execution_plans
    ADD CONSTRAINT ai_execution_plans_pkey PRIMARY KEY (id);


--
-- Name: ai_insights ai_insights_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_insights
    ADD CONSTRAINT ai_insights_pkey PRIMARY KEY (id);


--
-- Name: ai_memory ai_memory_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_memory
    ADD CONSTRAINT ai_memory_pkey PRIMARY KEY (id);


--
-- Name: ai_messages ai_messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_messages
    ADD CONSTRAINT ai_messages_pkey PRIMARY KEY (id);


--
-- Name: ai_recommendations ai_recommendations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_recommendations
    ADD CONSTRAINT ai_recommendations_pkey PRIMARY KEY (id);


--
-- Name: ai_tool_calls ai_tool_calls_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_tool_calls
    ADD CONSTRAINT ai_tool_calls_pkey PRIMARY KEY (id);


--
-- Name: ai_usage_logs ai_usage_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_usage_logs
    ADD CONSTRAINT ai_usage_logs_pkey PRIMARY KEY (id);


--
-- Name: ai_workspace_settings ai_workspace_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_workspace_settings
    ADD CONSTRAINT ai_workspace_settings_pkey PRIMARY KEY (id);


--
-- Name: ai_workspace_settings ai_workspace_settings_workspace_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_workspace_settings
    ADD CONSTRAINT ai_workspace_settings_workspace_id_key UNIQUE (workspace_id);


--
-- Name: approval_decisions approval_decisions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_decisions
    ADD CONSTRAINT approval_decisions_pkey PRIMARY KEY (id);


--
-- Name: approval_request_steps approval_request_steps_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_request_steps
    ADD CONSTRAINT approval_request_steps_pkey PRIMARY KEY (id);


--
-- Name: approval_requests approval_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_requests
    ADD CONSTRAINT approval_requests_pkey PRIMARY KEY (id);


--
-- Name: approval_workflow_steps approval_workflow_steps_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_workflow_steps
    ADD CONSTRAINT approval_workflow_steps_pkey PRIMARY KEY (id);


--
-- Name: approval_workflows approval_workflows_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_workflows
    ADD CONSTRAINT approval_workflows_pkey PRIMARY KEY (id);


--
-- Name: archival_jobs archival_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.archival_jobs
    ADD CONSTRAINT archival_jobs_pkey PRIMARY KEY (id);


--
-- Name: async_jobs async_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.async_jobs
    ADD CONSTRAINT async_jobs_pkey PRIMARY KEY (id);


--
-- Name: attachments attachments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attachments
    ADD CONSTRAINT attachments_pkey PRIMARY KEY (id);


--
-- Name: attendance attendance_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance
    ADD CONSTRAINT attendance_pkey PRIMARY KEY (id);


--
-- Name: attendance attendance_workspace_id_user_id_date_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance
    ADD CONSTRAINT attendance_workspace_id_user_id_date_key UNIQUE (workspace_id, user_id, date);


--
-- Name: audit_logs audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (id);


--
-- Name: automation_logs automation_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_logs
    ADD CONSTRAINT automation_logs_pkey PRIMARY KEY (id);


--
-- Name: bill_of_materials bill_of_materials_final_product_id_raw_material_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bill_of_materials
    ADD CONSTRAINT bill_of_materials_final_product_id_raw_material_id_key UNIQUE (final_product_id, raw_material_id);


--
-- Name: bill_of_materials bill_of_materials_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bill_of_materials
    ADD CONSTRAINT bill_of_materials_pkey PRIMARY KEY (id);


--
-- Name: billing_invoices billing_invoices_invoice_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_invoices
    ADD CONSTRAINT billing_invoices_invoice_number_key UNIQUE (invoice_number);


--
-- Name: billing_invoices billing_invoices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_invoices
    ADD CONSTRAINT billing_invoices_pkey PRIMARY KEY (id);


--
-- Name: billing_payments billing_payments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_payments
    ADD CONSTRAINT billing_payments_pkey PRIMARY KEY (id);


--
-- Name: billing_snapshots billing_snapshots_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_snapshots
    ADD CONSTRAINT billing_snapshots_pkey PRIMARY KEY (id);


--
-- Name: bookings bookings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_pkey PRIMARY KEY (id);


--
-- Name: branches branches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.branches
    ADD CONSTRAINT branches_pkey PRIMARY KEY (id);


--
-- Name: branches branches_workspace_id_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.branches
    ADD CONSTRAINT branches_workspace_id_name_key UNIQUE (workspace_id, name);


--
-- Name: brand_kits brand_kits_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.brand_kits
    ADD CONSTRAINT brand_kits_pkey PRIMARY KEY (id);


--
-- Name: brand_kits brand_kits_workspace_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.brand_kits
    ADD CONSTRAINT brand_kits_workspace_id_key UNIQUE (workspace_id);


--
-- Name: business_template_custom_fields business_template_custom_fields_business_template_id_entity_typ; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.business_template_custom_fields
    ADD CONSTRAINT business_template_custom_fields_business_template_id_entity_typ UNIQUE (business_template_id, entity_type, field_key);


--
-- Name: business_template_custom_fields business_template_custom_fields_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.business_template_custom_fields
    ADD CONSTRAINT business_template_custom_fields_pkey PRIMARY KEY (id);


--
-- Name: business_template_modules business_template_modules_business_template_id_module_key_uniqu; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.business_template_modules
    ADD CONSTRAINT business_template_modules_business_template_id_module_key_uniqu UNIQUE (business_template_id, module_key);


--
-- Name: business_template_modules business_template_modules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.business_template_modules
    ADD CONSTRAINT business_template_modules_pkey PRIMARY KEY (id);


--
-- Name: business_template_roles business_template_roles_business_template_id_role_key_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.business_template_roles
    ADD CONSTRAINT business_template_roles_business_template_id_role_key_unique UNIQUE (business_template_id, role_key);


--
-- Name: business_template_roles business_template_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.business_template_roles
    ADD CONSTRAINT business_template_roles_pkey PRIMARY KEY (id);


--
-- Name: business_template_workflows business_template_workflows_business_template_id_workflow_type_; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.business_template_workflows
    ADD CONSTRAINT business_template_workflows_business_template_id_workflow_type_ UNIQUE (business_template_id, workflow_type, workflow_key);


--
-- Name: business_template_workflows business_template_workflows_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.business_template_workflows
    ADD CONSTRAINT business_template_workflows_pkey PRIMARY KEY (id);


--
-- Name: business_templates business_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.business_templates
    ADD CONSTRAINT business_templates_pkey PRIMARY KEY (id);


--
-- Name: business_templates business_templates_template_key_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.business_templates
    ADD CONSTRAINT business_templates_template_key_unique UNIQUE (template_key);


--
-- Name: campaign_metrics campaign_metrics_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campaign_metrics
    ADD CONSTRAINT campaign_metrics_pkey PRIMARY KEY (id);


--
-- Name: campaigns campaigns_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campaigns
    ADD CONSTRAINT campaigns_pkey PRIMARY KEY (id);


--
-- Name: cod_collections cod_collections_assignment_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cod_collections
    ADD CONSTRAINT cod_collections_assignment_id_key UNIQUE (assignment_id);


--
-- Name: cod_collections cod_collections_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cod_collections
    ADD CONSTRAINT cod_collections_pkey PRIMARY KEY (id);


--
-- Name: commission_entries comm_entry_rule_record_recipient_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commission_entries
    ADD CONSTRAINT comm_entry_rule_record_recipient_unique UNIQUE (commission_rule_id, pipeline_record_id, recipient_membership_id);


--
-- Name: commission_entries commission_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commission_entries
    ADD CONSTRAINT commission_entries_pkey PRIMARY KEY (id);


--
-- Name: commission_plans commission_plans_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commission_plans
    ADD CONSTRAINT commission_plans_pkey PRIMARY KEY (id);


--
-- Name: commission_plans commission_plans_ws_name_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commission_plans
    ADD CONSTRAINT commission_plans_ws_name_unique UNIQUE (workspace_id, name);


--
-- Name: commission_rules commission_rules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commission_rules
    ADD CONSTRAINT commission_rules_pkey PRIMARY KEY (id);


--
-- Name: communication_automations communication_automations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.communication_automations
    ADD CONSTRAINT communication_automations_pkey PRIMARY KEY (id);


--
-- Name: communication_automations communication_automations_workspace_id_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.communication_automations
    ADD CONSTRAINT communication_automations_workspace_id_name_key UNIQUE (workspace_id, name);


--
-- Name: communication_channels communication_channels_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.communication_channels
    ADD CONSTRAINT communication_channels_pkey PRIMARY KEY (id);


--
-- Name: communication_channels communication_channels_workspace_id_type_provider_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.communication_channels
    ADD CONSTRAINT communication_channels_workspace_id_type_provider_name_key UNIQUE (workspace_id, type, provider_name);


--
-- Name: contacts contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contacts
    ADD CONSTRAINT contacts_pkey PRIMARY KEY (id);


--
-- Name: country_packs country_packs_country_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.country_packs
    ADD CONSTRAINT country_packs_country_code_key UNIQUE (country_code);


--
-- Name: country_packs country_packs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.country_packs
    ADD CONSTRAINT country_packs_pkey PRIMARY KEY (id);


--
-- Name: coupons coupons_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coupons
    ADD CONSTRAINT coupons_pkey PRIMARY KEY (id);


--
-- Name: coupons coupons_workspace_id_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coupons
    ADD CONSTRAINT coupons_workspace_id_code_key UNIQUE (workspace_id, code);


--
-- Name: credit_note_items credit_note_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_note_items
    ADD CONSTRAINT credit_note_items_pkey PRIMARY KEY (id);


--
-- Name: credit_notes credit_notes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_notes
    ADD CONSTRAINT credit_notes_pkey PRIMARY KEY (id);


--
-- Name: credit_notes credit_notes_workspace_id_credit_note_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_notes
    ADD CONSTRAINT credit_notes_workspace_id_credit_note_number_key UNIQUE (workspace_id, credit_note_number);


--
-- Name: crm_activities crm_activities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_activities
    ADD CONSTRAINT crm_activities_pkey PRIMARY KEY (id);


--
-- Name: custom_field_values custom_field_values_custom_field_id_record_type_record_id_uniqu; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.custom_field_values
    ADD CONSTRAINT custom_field_values_custom_field_id_record_type_record_id_uniqu UNIQUE (custom_field_id, record_type, record_id);


--
-- Name: custom_field_values custom_field_values_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.custom_field_values
    ADD CONSTRAINT custom_field_values_pkey PRIMARY KEY (id);


--
-- Name: custom_fields custom_fields_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.custom_fields
    ADD CONSTRAINT custom_fields_pkey PRIMARY KEY (id);


--
-- Name: customer_credits customer_credits_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_credits
    ADD CONSTRAINT customer_credits_pkey PRIMARY KEY (id);


--
-- Name: customer_subscriptions customer_subscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_subscriptions
    ADD CONSTRAINT customer_subscriptions_pkey PRIMARY KEY (id);


--
-- Name: delivery_assignments delivery_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.delivery_assignments
    ADD CONSTRAINT delivery_assignments_pkey PRIMARY KEY (id);


--
-- Name: delivery_proofs delivery_proofs_assignment_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.delivery_proofs
    ADD CONSTRAINT delivery_proofs_assignment_id_key UNIQUE (assignment_id);


--
-- Name: delivery_proofs delivery_proofs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.delivery_proofs
    ADD CONSTRAINT delivery_proofs_pkey PRIMARY KEY (id);


--
-- Name: delivery_sla_breaches delivery_sla_breaches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.delivery_sla_breaches
    ADD CONSTRAINT delivery_sla_breaches_pkey PRIMARY KEY (id);


--
-- Name: delivery_tracking delivery_tracking_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.delivery_tracking
    ADD CONSTRAINT delivery_tracking_pkey PRIMARY KEY (id);


--
-- Name: delivery_zones delivery_zones_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.delivery_zones
    ADD CONSTRAINT delivery_zones_pkey PRIMARY KEY (id);


--
-- Name: delivery_zones delivery_zones_workspace_id_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.delivery_zones
    ADD CONSTRAINT delivery_zones_workspace_id_name_key UNIQUE (workspace_id, name);


--
-- Name: departments departments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT departments_pkey PRIMARY KEY (id);


--
-- Name: departments departments_workspace_id_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT departments_workspace_id_name_key UNIQUE (workspace_id, name);


--
-- Name: departments departments_ws_name_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT departments_ws_name_unique UNIQUE (workspace_id, name);


--
-- Name: dining_tables dining_tables_branch_id_table_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dining_tables
    ADD CONSTRAINT dining_tables_branch_id_table_number_key UNIQUE (branch_id, table_number);


--
-- Name: dining_tables dining_tables_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dining_tables
    ADD CONSTRAINT dining_tables_pkey PRIMARY KEY (id);


--
-- Name: discovery_blueprints discovery_blueprints_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.discovery_blueprints
    ADD CONSTRAINT discovery_blueprints_pkey PRIMARY KEY (id);


--
-- Name: discovery_messages discovery_messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.discovery_messages
    ADD CONSTRAINT discovery_messages_pkey PRIMARY KEY (id);


--
-- Name: discovery_sessions discovery_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.discovery_sessions
    ADD CONSTRAINT discovery_sessions_pkey PRIMARY KEY (id);


--
-- Name: document_checklists doc_checklists_ws_pip_stage_name_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_checklists
    ADD CONSTRAINT doc_checklists_ws_pip_stage_name_unique UNIQUE (workspace_id, pipeline_id, stage_id, name);


--
-- Name: document_checklist_items doc_items_checklist_title_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_checklist_items
    ADD CONSTRAINT doc_items_checklist_title_unique UNIQUE (document_checklist_id, title);


--
-- Name: document_checklist_items document_checklist_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_checklist_items
    ADD CONSTRAINT document_checklist_items_pkey PRIMARY KEY (id);


--
-- Name: document_checklists document_checklists_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_checklists
    ADD CONSTRAINT document_checklists_pkey PRIMARY KEY (id);


--
-- Name: document_sequences document_sequences_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_sequences
    ADD CONSTRAINT document_sequences_pkey PRIMARY KEY (id);


--
-- Name: document_sequences document_sequences_workspace_id_document_type_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_sequences
    ADD CONSTRAINT document_sequences_workspace_id_document_type_key UNIQUE (workspace_id, document_type);


--
-- Name: drivers drivers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.drivers
    ADD CONSTRAINT drivers_pkey PRIMARY KEY (id);


--
-- Name: drivers drivers_workspace_id_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.drivers
    ADD CONSTRAINT drivers_workspace_id_user_id_key UNIQUE (workspace_id, user_id);


--
-- Name: duplicate_matches dup_match_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.duplicate_matches
    ADD CONSTRAINT dup_match_unique UNIQUE (workspace_id, entity_type, source_entity_id, matched_entity_id, duplicate_rule_id);


--
-- Name: duplicate_rules dup_rules_ws_type_name_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.duplicate_rules
    ADD CONSTRAINT dup_rules_ws_type_name_unique UNIQUE (workspace_id, entity_type, name);


--
-- Name: duplicate_matches duplicate_matches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.duplicate_matches
    ADD CONSTRAINT duplicate_matches_pkey PRIMARY KEY (id);


--
-- Name: duplicate_rules duplicate_rules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.duplicate_rules
    ADD CONSTRAINT duplicate_rules_pkey PRIMARY KEY (id);


--
-- Name: email_logs email_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_logs
    ADD CONSTRAINT email_logs_pkey PRIMARY KEY (id);


--
-- Name: email_settings email_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_settings
    ADD CONSTRAINT email_settings_pkey PRIMARY KEY (workspace_id);


--
-- Name: exchange_rates exchange_rates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exchange_rates
    ADD CONSTRAINT exchange_rates_pkey PRIMARY KEY (id);


--
-- Name: exchange_rates exchange_rates_workspace_id_base_currency_target_currency_e_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exchange_rates
    ADD CONSTRAINT exchange_rates_workspace_id_base_currency_target_currency_e_key UNIQUE (workspace_id, base_currency, target_currency, effective_date);


--
-- Name: fiscal_periods excl_fiscal_periods_no_overlap; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fiscal_periods
    ADD CONSTRAINT excl_fiscal_periods_no_overlap EXCLUDE USING gist (workspace_id WITH =, daterange(start_date, end_date, '[]'::text) WITH &&);


--
-- Name: CONSTRAINT excl_fiscal_periods_no_overlap ON fiscal_periods; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON CONSTRAINT excl_fiscal_periods_no_overlap ON public.fiscal_periods IS 'Prevents overlapping fiscal periods within the same workspace. Uses daterange with inclusive bounds [start_date, end_date]. Adjacent periods (end_date of period A = start_date of period B) are allowed because the range is closed-closed and overlap operator (&&) handles adjacency correctly.';


--
-- Name: leave_requests excl_leave_requests_no_overlap; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_requests
    ADD CONSTRAINT excl_leave_requests_no_overlap EXCLUDE USING gist (user_id WITH =, daterange(start_date, end_date, '[]'::text) WITH &&) WHERE (((status)::text <> ALL (ARRAY[('rejected'::character varying)::text, ('cancelled'::character varying)::text])));


--
-- Name: CONSTRAINT excl_leave_requests_no_overlap ON leave_requests; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON CONSTRAINT excl_leave_requests_no_overlap ON public.leave_requests IS 'Prevents overlapping leave requests for the same user. Only applies to active requests (status not in rejected, cancelled). Uses daterange with inclusive bounds [start_date, end_date].';


--
-- Name: shift_assignments excl_shift_assignments_no_overlap; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shift_assignments
    ADD CONSTRAINT excl_shift_assignments_no_overlap EXCLUDE USING gist (user_id WITH =, daterange(effective_date, COALESCE(end_date, '9999-12-31'::date), '[]'::text) WITH &&);


--
-- Name: CONSTRAINT excl_shift_assignments_no_overlap ON shift_assignments; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON CONSTRAINT excl_shift_assignments_no_overlap ON public.shift_assignments IS 'Prevents overlapping shift assignments for the same user. Open-ended assignments (end_date IS NULL) use 9999-12-31 as effective upper bound. Uses daterange with inclusive bounds [effective_date, end_date].';


--
-- Name: export_jobs export_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.export_jobs
    ADD CONSTRAINT export_jobs_pkey PRIMARY KEY (id);


--
-- Name: finance_accounts fin_acct_ws_code_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.finance_accounts
    ADD CONSTRAINT fin_acct_ws_code_unique UNIQUE (workspace_id, code);


--
-- Name: finance_accounts finance_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.finance_accounts
    ADD CONSTRAINT finance_accounts_pkey PRIMARY KEY (id);


--
-- Name: finance_expenses finance_expenses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.finance_expenses
    ADD CONSTRAINT finance_expenses_pkey PRIMARY KEY (id);


--
-- Name: finance_settings finance_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.finance_settings
    ADD CONSTRAINT finance_settings_pkey PRIMARY KEY (id);


--
-- Name: finance_settings finance_settings_workspace_id_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.finance_settings
    ADD CONSTRAINT finance_settings_workspace_id_unique UNIQUE (workspace_id);


--
-- Name: finance_transaction_lines finance_transaction_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.finance_transaction_lines
    ADD CONSTRAINT finance_transaction_lines_pkey PRIMARY KEY (id);


--
-- Name: finance_transactions finance_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.finance_transactions
    ADD CONSTRAINT finance_transactions_pkey PRIMARY KEY (id);


--
-- Name: fiscal_periods fiscal_periods_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fiscal_periods
    ADD CONSTRAINT fiscal_periods_pkey PRIMARY KEY (id);


--
-- Name: fiscal_periods fiscal_periods_workspace_id_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fiscal_periods
    ADD CONSTRAINT fiscal_periods_workspace_id_name_key UNIQUE (workspace_id, name);


--
-- Name: fixed_assets fixed_assets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fixed_assets
    ADD CONSTRAINT fixed_assets_pkey PRIMARY KEY (id);


--
-- Name: goods_received_notes goods_received_notes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.goods_received_notes
    ADD CONSTRAINT goods_received_notes_pkey PRIMARY KEY (id);


--
-- Name: goods_received_notes goods_received_notes_workspace_id_grn_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.goods_received_notes
    ADD CONSTRAINT goods_received_notes_workspace_id_grn_number_key UNIQUE (workspace_id, grn_number);


--
-- Name: grn_items grn_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grn_items
    ADD CONSTRAINT grn_items_pkey PRIMARY KEY (id);


--
-- Name: idempotency_keys idempotency_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.idempotency_keys
    ADD CONSTRAINT idempotency_keys_pkey PRIMARY KEY (workspace_id, key);


--
-- Name: impersonation_sessions impersonation_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.impersonation_sessions
    ADD CONSTRAINT impersonation_sessions_pkey PRIMARY KEY (id);


--
-- Name: import_jobs import_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_jobs
    ADD CONSTRAINT import_jobs_pkey PRIMARY KEY (id);


--
-- Name: inbound_messages inbound_messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inbound_messages
    ADD CONSTRAINT inbound_messages_pkey PRIMARY KEY (id);


--
-- Name: integration_providers integration_providers_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_providers
    ADD CONSTRAINT integration_providers_name_key UNIQUE (name);


--
-- Name: integration_providers integration_providers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_providers
    ADD CONSTRAINT integration_providers_pkey PRIMARY KEY (id);


--
-- Name: inventory_batches inventory_batches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_batches
    ADD CONSTRAINT inventory_batches_pkey PRIMARY KEY (id);


--
-- Name: inventory_batches inventory_batches_workspace_id_serial_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_batches
    ADD CONSTRAINT inventory_batches_workspace_id_serial_number_key UNIQUE (workspace_id, serial_number);


--
-- Name: inventory_levels inventory_levels_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_levels
    ADD CONSTRAINT inventory_levels_pkey PRIMARY KEY (id);


--
-- Name: inventory_logs_legacy inventory_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_logs_legacy
    ADD CONSTRAINT inventory_logs_pkey PRIMARY KEY (id);


--
-- Name: inventory_movements inventory_movements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_movements
    ADD CONSTRAINT inventory_movements_pkey PRIMARY KEY (id);


--
-- Name: invoice_format_rules invoice_format_rules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_format_rules
    ADD CONSTRAINT invoice_format_rules_pkey PRIMARY KEY (id);


--
-- Name: invoice_items invoice_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_items
    ADD CONSTRAINT invoice_items_pkey PRIMARY KEY (id);


--
-- Name: invoices invoices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_pkey PRIMARY KEY (id);


--
-- Name: invoices invoices_workspace_id_invoice_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_workspace_id_invoice_number_key UNIQUE (workspace_id, invoice_number);


--
-- Name: journal_entries journal_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_entries
    ADD CONSTRAINT journal_entries_pkey PRIMARY KEY (id);


--
-- Name: journal_lines journal_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_lines
    ADD CONSTRAINT journal_lines_pkey PRIMARY KEY (id);


--
-- Name: leads leads_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leads
    ADD CONSTRAINT leads_pkey PRIMARY KEY (id);


--
-- Name: leave_balances leave_balances_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_balances
    ADD CONSTRAINT leave_balances_pkey PRIMARY KEY (id);


--
-- Name: leave_balances leave_balances_workspace_id_user_id_leave_type_id_fiscal_ye_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_balances
    ADD CONSTRAINT leave_balances_workspace_id_user_id_leave_type_id_fiscal_ye_key UNIQUE (workspace_id, user_id, leave_type_id, fiscal_year);


--
-- Name: leave_requests leave_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_requests
    ADD CONSTRAINT leave_requests_pkey PRIMARY KEY (id);


--
-- Name: leave_types leave_types_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_types
    ADD CONSTRAINT leave_types_pkey PRIMARY KEY (id);


--
-- Name: leave_types leave_types_workspace_id_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_types
    ADD CONSTRAINT leave_types_workspace_id_code_key UNIQUE (workspace_id, code);


--
-- Name: leave_types leave_types_workspace_id_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_types
    ADD CONSTRAINT leave_types_workspace_id_name_key UNIQUE (workspace_id, name);


--
-- Name: leaves_legacy leaves_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leaves_legacy
    ADD CONSTRAINT leaves_pkey PRIMARY KEY (id);


--
-- Name: loyalty_accounts loyalty_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.loyalty_accounts
    ADD CONSTRAINT loyalty_accounts_pkey PRIMARY KEY (id);


--
-- Name: loyalty_accounts loyalty_accounts_workspace_id_contact_id_program_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.loyalty_accounts
    ADD CONSTRAINT loyalty_accounts_workspace_id_contact_id_program_id_key UNIQUE (workspace_id, contact_id, program_id);


--
-- Name: loyalty_programs loyalty_programs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.loyalty_programs
    ADD CONSTRAINT loyalty_programs_pkey PRIMARY KEY (id);


--
-- Name: loyalty_programs loyalty_programs_workspace_id_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.loyalty_programs
    ADD CONSTRAINT loyalty_programs_workspace_id_name_key UNIQUE (workspace_id, name);


--
-- Name: loyalty_transactions loyalty_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.loyalty_transactions
    ADD CONSTRAINT loyalty_transactions_pkey PRIMARY KEY (id);


--
-- Name: manual_payments manual_payments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.manual_payments
    ADD CONSTRAINT manual_payments_pkey PRIMARY KEY (id);


--
-- Name: media_assets media_assets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.media_assets
    ADD CONSTRAINT media_assets_pkey PRIMARY KEY (id);


--
-- Name: media_generation_requests media_generation_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.media_generation_requests
    ADD CONSTRAINT media_generation_requests_pkey PRIMARY KEY (id);


--
-- Name: membership_roles membership_roles_membership_id_role_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.membership_roles
    ADD CONSTRAINT membership_roles_membership_id_role_id_key UNIQUE (membership_id, role_id);


--
-- Name: membership_roles membership_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.membership_roles
    ADD CONSTRAINT membership_roles_pkey PRIMARY KEY (id);


--
-- Name: message_templates message_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message_templates
    ADD CONSTRAINT message_templates_pkey PRIMARY KEY (id);


--
-- Name: message_templates message_templates_workspace_id_channel_type_name_locale_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message_templates
    ADD CONSTRAINT message_templates_workspace_id_channel_type_name_locale_key UNIQUE (workspace_id, channel_type, name, locale);


--
-- Name: message_threads message_threads_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message_threads
    ADD CONSTRAINT message_threads_pkey PRIMARY KEY (id);


--
-- Name: migrations migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.migrations
    ADD CONSTRAINT migrations_pkey PRIMARY KEY (id);


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


--
-- Name: nurturing_enrollments nurturing_enrollments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nurturing_enrollments
    ADD CONSTRAINT nurturing_enrollments_pkey PRIMARY KEY (id);


--
-- Name: nurturing_enrollments nurturing_enrollments_sequence_id_contact_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nurturing_enrollments
    ADD CONSTRAINT nurturing_enrollments_sequence_id_contact_id_key UNIQUE (sequence_id, contact_id);


--
-- Name: nurturing_sequences nurturing_sequences_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nurturing_sequences
    ADD CONSTRAINT nurturing_sequences_pkey PRIMARY KEY (id);


--
-- Name: nurturing_sequences nurturing_sequences_workspace_id_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nurturing_sequences
    ADD CONSTRAINT nurturing_sequences_workspace_id_name_key UNIQUE (workspace_id, name);


--
-- Name: opportunities opportunities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opportunities
    ADD CONSTRAINT opportunities_pkey PRIMARY KEY (id);


--
-- Name: order_items order_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_pkey PRIMARY KEY (id);


--
-- Name: orders orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_pkey PRIMARY KEY (id);


--
-- Name: orders orders_workspace_id_order_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_workspace_id_order_number_key UNIQUE (workspace_id, order_number);


--
-- Name: outbound_messages outbound_messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.outbound_messages
    ADD CONSTRAINT outbound_messages_pkey PRIMARY KEY (id);


--
-- Name: ownership_assignments ownership_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ownership_assignments
    ADD CONSTRAINT ownership_assignments_pkey PRIMARY KEY (id);


--
-- Name: ownership_transfer_logs ownership_transfer_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ownership_transfer_logs
    ADD CONSTRAINT ownership_transfer_logs_pkey PRIMARY KEY (id);


--
-- Name: ownership_assignments ownership_ws_entity_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ownership_assignments
    ADD CONSTRAINT ownership_ws_entity_unique UNIQUE (workspace_id, entity_type, entity_id);


--
-- Name: payment_transactions payment_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_transactions
    ADD CONSTRAINT payment_transactions_pkey PRIMARY KEY (id);


--
-- Name: payment_transactions payment_transactions_stripe_payment_intent_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_transactions
    ADD CONSTRAINT payment_transactions_stripe_payment_intent_id_key UNIQUE (stripe_payment_intent_id);


--
-- Name: payments payments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_pkey PRIMARY KEY (id);


--
-- Name: payments payments_workspace_id_payment_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_workspace_id_payment_number_key UNIQUE (workspace_id, payment_number);


--
-- Name: payroll_lines payroll_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_lines
    ADD CONSTRAINT payroll_lines_pkey PRIMARY KEY (id);


--
-- Name: payroll payroll_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll
    ADD CONSTRAINT payroll_pkey PRIMARY KEY (id);


--
-- Name: payroll_runs payroll_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_runs
    ADD CONSTRAINT payroll_runs_pkey PRIMARY KEY (id);


--
-- Name: payroll_statutory_rules payroll_statutory_rules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_statutory_rules
    ADD CONSTRAINT payroll_statutory_rules_pkey PRIMARY KEY (id);


--
-- Name: payroll payroll_workspace_id_user_id_month_year_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll
    ADD CONSTRAINT payroll_workspace_id_user_id_month_year_key UNIQUE (workspace_id, user_id, month, year);


--
-- Name: permission_definitions permission_definitions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permission_definitions
    ADD CONSTRAINT permission_definitions_pkey PRIMARY KEY (key);


--
-- Name: permission_delegation_items permission_delegation_items_delegation_id_permission_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permission_delegation_items
    ADD CONSTRAINT permission_delegation_items_delegation_id_permission_key_key UNIQUE (delegation_id, permission_key);


--
-- Name: permission_delegation_items permission_delegation_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permission_delegation_items
    ADD CONSTRAINT permission_delegation_items_pkey PRIMARY KEY (id);


--
-- Name: permission_delegations permission_delegations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permission_delegations
    ADD CONSTRAINT permission_delegations_pkey PRIMARY KEY (id);


--
-- Name: permission_delegations permission_delegations_workspace_id_delegator_membership_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permission_delegations
    ADD CONSTRAINT permission_delegations_workspace_id_delegator_membership_id_key UNIQUE (workspace_id, delegator_membership_id, delegate_membership_id, start_at);


--
-- Name: personal_access_tokens personal_access_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.personal_access_tokens
    ADD CONSTRAINT personal_access_tokens_pkey PRIMARY KEY (id);


--
-- Name: personal_access_tokens personal_access_tokens_token_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.personal_access_tokens
    ADD CONSTRAINT personal_access_tokens_token_key UNIQUE (token);


--
-- Name: pipeline_records pipeline_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pipeline_records
    ADD CONSTRAINT pipeline_records_pkey PRIMARY KEY (id);


--
-- Name: pipeline_stages pipeline_stages_pipeline_id_name_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pipeline_stages
    ADD CONSTRAINT pipeline_stages_pipeline_id_name_unique UNIQUE (pipeline_id, name);


--
-- Name: pipeline_stages pipeline_stages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pipeline_stages
    ADD CONSTRAINT pipeline_stages_pkey PRIMARY KEY (id);


--
-- Name: pipelines pipelines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pipelines
    ADD CONSTRAINT pipelines_pkey PRIMARY KEY (id);


--
-- Name: pipelines pipelines_workspace_id_name_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pipelines
    ADD CONSTRAINT pipelines_workspace_id_name_unique UNIQUE (workspace_id, name);


--
-- Name: plan_features plan_features_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plan_features
    ADD CONSTRAINT plan_features_pkey PRIMARY KEY (id);


--
-- Name: plan_features plan_features_plan_id_feature_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plan_features
    ADD CONSTRAINT plan_features_plan_id_feature_key_key UNIQUE (plan_id, feature_key);


--
-- Name: platform_activation_campaigns platform_activation_campaigns_campaign_key_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_activation_campaigns
    ADD CONSTRAINT platform_activation_campaigns_campaign_key_unique UNIQUE (campaign_key);


--
-- Name: platform_activation_campaigns platform_activation_campaigns_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_activation_campaigns
    ADD CONSTRAINT platform_activation_campaigns_pkey PRIMARY KEY (id);


--
-- Name: platform_activation_codes platform_activation_codes_code_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_activation_codes
    ADD CONSTRAINT platform_activation_codes_code_unique UNIQUE (code);


--
-- Name: platform_activation_codes platform_activation_codes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_activation_codes
    ADD CONSTRAINT platform_activation_codes_pkey PRIMARY KEY (id);


--
-- Name: platform_broadcasts platform_broadcasts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_broadcasts
    ADD CONSTRAINT platform_broadcasts_pkey PRIMARY KEY (id);


--
-- Name: platform_events platform_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_events
    ADD CONSTRAINT platform_events_pkey PRIMARY KEY (id);


--
-- Name: platform_feature_request_votes platform_feature_request_vote_feature_request_id_workspace__key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_feature_request_votes
    ADD CONSTRAINT platform_feature_request_vote_feature_request_id_workspace__key UNIQUE (feature_request_id, workspace_id, user_id);


--
-- Name: platform_feature_request_votes platform_feature_request_votes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_feature_request_votes
    ADD CONSTRAINT platform_feature_request_votes_pkey PRIMARY KEY (id);


--
-- Name: platform_feature_requests platform_feature_requests_normalized_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_feature_requests
    ADD CONSTRAINT platform_feature_requests_normalized_key_key UNIQUE (normalized_key);


--
-- Name: platform_feature_requests platform_feature_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_feature_requests
    ADD CONSTRAINT platform_feature_requests_pkey PRIMARY KEY (id);


--
-- Name: platform_plan_prices platform_plan_prices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_plan_prices
    ADD CONSTRAINT platform_plan_prices_pkey PRIMARY KEY (id);


--
-- Name: platform_plan_prices platform_plan_prices_plan_id_billing_cycle_currency_effecti_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_plan_prices
    ADD CONSTRAINT platform_plan_prices_plan_id_billing_cycle_currency_effecti_key UNIQUE (plan_id, billing_cycle, currency, effective_from);


--
-- Name: platform_plans platform_plans_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_plans
    ADD CONSTRAINT platform_plans_pkey PRIMARY KEY (id);


--
-- Name: platform_plans platform_plans_slug_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_plans
    ADD CONSTRAINT platform_plans_slug_key UNIQUE (slug);


--
-- Name: platform_settings platform_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_settings
    ADD CONSTRAINT platform_settings_pkey PRIMARY KEY (key);


--
-- Name: platform_survey_responses platform_survey_responses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_survey_responses
    ADD CONSTRAINT platform_survey_responses_pkey PRIMARY KEY (id);


--
-- Name: platform_survey_responses platform_survey_responses_survey_id_workspace_id_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_survey_responses
    ADD CONSTRAINT platform_survey_responses_survey_id_workspace_id_user_id_key UNIQUE (survey_id, workspace_id, user_id);


--
-- Name: platform_surveys platform_surveys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_surveys
    ADD CONSTRAINT platform_surveys_pkey PRIMARY KEY (id);


--
-- Name: platform_users platform_users_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_users
    ADD CONSTRAINT platform_users_email_key UNIQUE (email);


--
-- Name: platform_users platform_users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_users
    ADD CONSTRAINT platform_users_pkey PRIMARY KEY (id);


--
-- Name: pos_sessions pos_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pos_sessions
    ADD CONSTRAINT pos_sessions_pkey PRIMARY KEY (id);


--
-- Name: pos_terminals pos_terminals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pos_terminals
    ADD CONSTRAINT pos_terminals_pkey PRIMARY KEY (id);


--
-- Name: pos_terminals pos_terminals_workspace_id_terminal_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pos_terminals
    ADD CONSTRAINT pos_terminals_workspace_id_terminal_code_key UNIQUE (workspace_id, terminal_code);


--
-- Name: price_list_items price_list_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.price_list_items
    ADD CONSTRAINT price_list_items_pkey PRIMARY KEY (id);


--
-- Name: price_lists price_lists_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.price_lists
    ADD CONSTRAINT price_lists_pkey PRIMARY KEY (id);


--
-- Name: product_categories product_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_categories
    ADD CONSTRAINT product_categories_pkey PRIMARY KEY (id);


--
-- Name: product_categories product_categories_workspace_id_parent_id_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_categories
    ADD CONSTRAINT product_categories_workspace_id_parent_id_name_key UNIQUE (workspace_id, parent_id, name);


--
-- Name: product_variants product_variants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_variants
    ADD CONSTRAINT product_variants_pkey PRIMARY KEY (id);


--
-- Name: product_variants product_variants_product_id_sku_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_variants
    ADD CONSTRAINT product_variants_product_id_sku_key UNIQUE (product_id, sku);


--
-- Name: production_orders production_orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.production_orders
    ADD CONSTRAINT production_orders_pkey PRIMARY KEY (id);


--
-- Name: products products_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (id);


--
-- Name: products products_workspace_id_sku_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_workspace_id_sku_key UNIQUE (workspace_id, sku);


--
-- Name: projects projects_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT projects_pkey PRIMARY KEY (id);


--
-- Name: promotions promotions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promotions
    ADD CONSTRAINT promotions_pkey PRIMARY KEY (id);


--
-- Name: provisioning_entity_bindings provisioning_entity_bindings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provisioning_entity_bindings
    ADD CONSTRAINT provisioning_entity_bindings_pkey PRIMARY KEY (id);


--
-- Name: provisioning_runs provisioning_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provisioning_runs
    ADD CONSTRAINT provisioning_runs_pkey PRIMARY KEY (id);


--
-- Name: purchase_order_items purchase_order_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_order_items
    ADD CONSTRAINT purchase_order_items_pkey PRIMARY KEY (id);


--
-- Name: purchase_orders purchase_orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_orders
    ADD CONSTRAINT purchase_orders_pkey PRIMARY KEY (id);


--
-- Name: purchase_orders purchase_orders_workspace_id_po_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_orders
    ADD CONSTRAINT purchase_orders_workspace_id_po_number_key UNIQUE (workspace_id, po_number);


--
-- Name: record_documents record_documents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.record_documents
    ADD CONSTRAINT record_documents_pkey PRIMARY KEY (id);


--
-- Name: recurring_expenses recurring_expenses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recurring_expenses
    ADD CONSTRAINT recurring_expenses_pkey PRIMARY KEY (id);


--
-- Name: referral_programs referral_programs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.referral_programs
    ADD CONSTRAINT referral_programs_pkey PRIMARY KEY (id);


--
-- Name: referral_programs referral_programs_workspace_id_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.referral_programs
    ADD CONSTRAINT referral_programs_workspace_id_name_key UNIQUE (workspace_id, name);


--
-- Name: referrals referrals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.referrals
    ADD CONSTRAINT referrals_pkey PRIMARY KEY (id);


--
-- Name: referrals referrals_workspace_id_referral_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.referrals
    ADD CONSTRAINT referrals_workspace_id_referral_code_key UNIQUE (workspace_id, referral_code);


--
-- Name: report_runs report_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.report_runs
    ADD CONSTRAINT report_runs_pkey PRIMARY KEY (id);


--
-- Name: report_templates report_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.report_templates
    ADD CONSTRAINT report_templates_pkey PRIMARY KEY (id);


--
-- Name: report_templates report_tpl_ws_name_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.report_templates
    ADD CONSTRAINT report_tpl_ws_name_unique UNIQUE (workspace_id, name);


--
-- Name: retention_policies retention_policies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.retention_policies
    ADD CONSTRAINT retention_policies_pkey PRIMARY KEY (id);


--
-- Name: retention_policies retention_policies_workspace_id_entity_type_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.retention_policies
    ADD CONSTRAINT retention_policies_workspace_id_entity_type_key UNIQUE (workspace_id, entity_type);


--
-- Name: return_items return_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.return_items
    ADD CONSTRAINT return_items_pkey PRIMARY KEY (id);


--
-- Name: returns returns_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.returns
    ADD CONSTRAINT returns_pkey PRIMARY KEY (id);


--
-- Name: returns returns_workspace_id_return_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.returns
    ADD CONSTRAINT returns_workspace_id_return_number_key UNIQUE (workspace_id, return_number);


--
-- Name: roles roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_pkey PRIMARY KEY (id);


--
-- Name: roles roles_workspace_id_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_workspace_id_name_key UNIQUE (workspace_id, name);


--
-- Name: segment_contacts segment_contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.segment_contacts
    ADD CONSTRAINT segment_contacts_pkey PRIMARY KEY (id);


--
-- Name: segment_contacts segment_contacts_segment_id_contact_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.segment_contacts
    ADD CONSTRAINT segment_contacts_segment_id_contact_id_key UNIQUE (segment_id, contact_id);


--
-- Name: segments segments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.segments
    ADD CONSTRAINT segments_pkey PRIMARY KEY (id);


--
-- Name: segments segments_workspace_id_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.segments
    ADD CONSTRAINT segments_workspace_id_name_key UNIQUE (workspace_id, name);


--
-- Name: shift_assignments shift_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shift_assignments
    ADD CONSTRAINT shift_assignments_pkey PRIMARY KEY (id);


--
-- Name: shifts shifts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shifts
    ADD CONSTRAINT shifts_pkey PRIMARY KEY (id);


--
-- Name: shipment_items shipment_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shipment_items
    ADD CONSTRAINT shipment_items_pkey PRIMARY KEY (id);


--
-- Name: shipments shipments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shipments
    ADD CONSTRAINT shipments_pkey PRIMARY KEY (id);


--
-- Name: shipments shipments_workspace_id_shipment_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shipments
    ADD CONSTRAINT shipments_workspace_id_shipment_number_key UNIQUE (workspace_id, shipment_number);


--
-- Name: shipments shipments_workspace_id_tracking_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shipments
    ADD CONSTRAINT shipments_workspace_id_tracking_number_key UNIQUE (workspace_id, tracking_number);


--
-- Name: stock_reservations stock_reservations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_reservations
    ADD CONSTRAINT stock_reservations_pkey PRIMARY KEY (id);


--
-- Name: stock_transfer_items stock_transfer_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_transfer_items
    ADD CONSTRAINT stock_transfer_items_pkey PRIMARY KEY (id);


--
-- Name: stock_transfers stock_transfers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_transfers
    ADD CONSTRAINT stock_transfers_pkey PRIMARY KEY (id);


--
-- Name: subscription_plans subscription_plans_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscription_plans
    ADD CONSTRAINT subscription_plans_name_key UNIQUE (name);


--
-- Name: subscription_plans subscription_plans_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscription_plans
    ADD CONSTRAINT subscription_plans_pkey PRIMARY KEY (id);


--
-- Name: sync_logs sync_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sync_logs
    ADD CONSTRAINT sync_logs_pkey PRIMARY KEY (id);


--
-- Name: tasks tasks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT tasks_pkey PRIMARY KEY (id);


--
-- Name: tax_rules tax_rules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tax_rules
    ADD CONSTRAINT tax_rules_pkey PRIMARY KEY (id);


--
-- Name: taxes taxes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taxes
    ADD CONSTRAINT taxes_pkey PRIMARY KEY (id);


--
-- Name: taxes taxes_workspace_id_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taxes
    ADD CONSTRAINT taxes_workspace_id_name_key UNIQUE (workspace_id, name);


--
-- Name: teams teams_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teams
    ADD CONSTRAINT teams_pkey PRIMARY KEY (id);


--
-- Name: teams teams_ws_name_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teams
    ADD CONSTRAINT teams_ws_name_unique UNIQUE (workspace_id, name);


--
-- Name: transactions transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transactions
    ADD CONSTRAINT transactions_pkey PRIMARY KEY (id);


--
-- Name: translations translations_locale_namespace_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.translations
    ADD CONSTRAINT translations_locale_namespace_key_key UNIQUE (locale, namespace, key);


--
-- Name: translations translations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.translations
    ADD CONSTRAINT translations_pkey PRIMARY KEY (id);


--
-- Name: units_of_measure units_of_measure_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.units_of_measure
    ADD CONSTRAINT units_of_measure_pkey PRIMARY KEY (id);


--
-- Name: units_of_measure units_of_measure_workspace_id_symbol_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.units_of_measure
    ADD CONSTRAINT units_of_measure_workspace_id_symbol_key UNIQUE (workspace_id, symbol);


--
-- Name: accounts uq_accounts_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounts
    ADD CONSTRAINT uq_accounts_ws_id UNIQUE (workspace_id, id);


--
-- Name: ai_change_requests uq_ai_change_requests_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_change_requests
    ADD CONSTRAINT uq_ai_change_requests_ws_id UNIQUE (workspace_id, id);


--
-- Name: ai_conversations uq_ai_conversations_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_conversations
    ADD CONSTRAINT uq_ai_conversations_ws_id UNIQUE (workspace_id, id);


--
-- Name: approval_workflows uq_aw_ws_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_workflows
    ADD CONSTRAINT uq_aw_ws_key UNIQUE (workspace_id, workflow_key);


--
-- Name: approval_workflow_steps uq_aws_workflow_order; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_workflow_steps
    ADD CONSTRAINT uq_aws_workflow_order UNIQUE (workflow_id, step_order);


--
-- Name: billing_invoices uq_billing_invoices_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_invoices
    ADD CONSTRAINT uq_billing_invoices_ws_id UNIQUE (workspace_id, id);


--
-- Name: billing_payments uq_billing_payments_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_payments
    ADD CONSTRAINT uq_billing_payments_ws_id UNIQUE (workspace_id, id);


--
-- Name: branches uq_branches_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.branches
    ADD CONSTRAINT uq_branches_ws_id UNIQUE (workspace_id, id);


--
-- Name: product_categories uq_categories_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_categories
    ADD CONSTRAINT uq_categories_ws_id UNIQUE (workspace_id, id);


--
-- Name: contacts uq_contacts_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contacts
    ADD CONSTRAINT uq_contacts_ws_id UNIQUE (workspace_id, id);


--
-- Name: credit_note_items uq_credit_note_items_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_note_items
    ADD CONSTRAINT uq_credit_note_items_ws_id UNIQUE (workspace_id, id);


--
-- Name: credit_notes uq_credit_notes_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_notes
    ADD CONSTRAINT uq_credit_notes_ws_id UNIQUE (workspace_id, id);


--
-- Name: customer_credits uq_customer_credits_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_credits
    ADD CONSTRAINT uq_customer_credits_ws_id UNIQUE (workspace_id, id);


--
-- Name: departments uq_departments_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT uq_departments_ws_id UNIQUE (workspace_id, id);


--
-- Name: dining_tables uq_dining_tables_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dining_tables
    ADD CONSTRAINT uq_dining_tables_ws_id UNIQUE (workspace_id, id);


--
-- Name: discovery_blueprints uq_discovery_blueprints_session; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.discovery_blueprints
    ADD CONSTRAINT uq_discovery_blueprints_session UNIQUE (session_id);


--
-- Name: exchange_rates uq_exchange_rates_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exchange_rates
    ADD CONSTRAINT uq_exchange_rates_ws_id UNIQUE (workspace_id, id);


--
-- Name: fiscal_periods uq_fiscal_periods_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fiscal_periods
    ADD CONSTRAINT uq_fiscal_periods_ws_id UNIQUE (workspace_id, id);


--
-- Name: grn_items uq_grn_items_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grn_items
    ADD CONSTRAINT uq_grn_items_ws_id UNIQUE (workspace_id, id);


--
-- Name: goods_received_notes uq_grn_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.goods_received_notes
    ADD CONSTRAINT uq_grn_ws_id UNIQUE (workspace_id, id);


--
-- Name: workspace_invitation_roles uq_inv_role; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_invitation_roles
    ADD CONSTRAINT uq_inv_role UNIQUE (workspace_invitation_id, role_id);


--
-- Name: inventory_movements uq_inventory_movements_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_movements
    ADD CONSTRAINT uq_inventory_movements_ws_id UNIQUE (workspace_id, id);


--
-- Name: invoices uq_invoices_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT uq_invoices_ws_id UNIQUE (workspace_id, id);


--
-- Name: journal_entries uq_journal_entries_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_entries
    ADD CONSTRAINT uq_journal_entries_ws_id UNIQUE (workspace_id, id);


--
-- Name: leads uq_leads_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leads
    ADD CONSTRAINT uq_leads_ws_id UNIQUE (workspace_id, id);


--
-- Name: leave_balances uq_leave_balances_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_balances
    ADD CONSTRAINT uq_leave_balances_ws_id UNIQUE (workspace_id, id);


--
-- Name: leave_requests uq_leave_requests_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_requests
    ADD CONSTRAINT uq_leave_requests_ws_id UNIQUE (workspace_id, id);


--
-- Name: leave_types uq_leave_types_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_types
    ADD CONSTRAINT uq_leave_types_ws_id UNIQUE (workspace_id, id);


--
-- Name: membership_roles uq_membership_roles_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.membership_roles
    ADD CONSTRAINT uq_membership_roles_ws_id UNIQUE (workspace_id, id);


--
-- Name: workspace_memberships uq_memberships_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_memberships
    ADD CONSTRAINT uq_memberships_ws_id UNIQUE (workspace_id, id);


--
-- Name: opportunities uq_opportunities_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opportunities
    ADD CONSTRAINT uq_opportunities_ws_id UNIQUE (workspace_id, id);


--
-- Name: orders uq_orders_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT uq_orders_ws_id UNIQUE (workspace_id, id);


--
-- Name: payments uq_payments_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT uq_payments_ws_id UNIQUE (workspace_id, id);


--
-- Name: payroll_lines uq_payroll_lines_no_duplicates; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_lines
    ADD CONSTRAINT uq_payroll_lines_no_duplicates UNIQUE (payroll_id, line_type, label);


--
-- Name: CONSTRAINT uq_payroll_lines_no_duplicates ON payroll_lines; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON CONSTRAINT uq_payroll_lines_no_duplicates ON public.payroll_lines IS 'Prevents duplicate logical lines within the same payslip. A payroll record cannot have two lines with the same (line_type, label) combination.';


--
-- Name: payroll_lines uq_payroll_lines_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_lines
    ADD CONSTRAINT uq_payroll_lines_ws_id UNIQUE (workspace_id, id);


--
-- Name: payroll_runs uq_payroll_runs_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_runs
    ADD CONSTRAINT uq_payroll_runs_ws_id UNIQUE (workspace_id, id);


--
-- Name: purchase_order_items uq_po_items_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_order_items
    ADD CONSTRAINT uq_po_items_ws_id UNIQUE (workspace_id, id);


--
-- Name: pos_sessions uq_pos_sessions_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pos_sessions
    ADD CONSTRAINT uq_pos_sessions_ws_id UNIQUE (workspace_id, id);


--
-- Name: pos_terminals uq_pos_terminals_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pos_terminals
    ADD CONSTRAINT uq_pos_terminals_ws_id UNIQUE (workspace_id, id);


--
-- Name: price_lists uq_price_lists_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.price_lists
    ADD CONSTRAINT uq_price_lists_ws_id UNIQUE (workspace_id, id);


--
-- Name: products uq_products_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT uq_products_ws_id UNIQUE (workspace_id, id);


--
-- Name: projects uq_projects_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT uq_projects_ws_id UNIQUE (workspace_id, id);


--
-- Name: promotions uq_promotions_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promotions
    ADD CONSTRAINT uq_promotions_ws_id UNIQUE (workspace_id, id);


--
-- Name: provisioning_entity_bindings uq_prov_binding_ws_type_entity; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provisioning_entity_bindings
    ADD CONSTRAINT uq_prov_binding_ws_type_entity UNIQUE (workspace_id, entity_type, entity_id);


--
-- Name: provisioning_entity_bindings uq_prov_binding_ws_type_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provisioning_entity_bindings
    ADD CONSTRAINT uq_prov_binding_ws_type_key UNIQUE (workspace_id, entity_type, local_key);


--
-- Name: purchase_orders uq_purchase_orders_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_orders
    ADD CONSTRAINT uq_purchase_orders_ws_id UNIQUE (workspace_id, id);


--
-- Name: return_items uq_return_items_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.return_items
    ADD CONSTRAINT uq_return_items_ws_id UNIQUE (workspace_id, id);


--
-- Name: returns uq_returns_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.returns
    ADD CONSTRAINT uq_returns_ws_id UNIQUE (workspace_id, id);


--
-- Name: roles uq_roles_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT uq_roles_ws_id UNIQUE (workspace_id, id);


--
-- Name: shift_assignments uq_shift_assignments_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shift_assignments
    ADD CONSTRAINT uq_shift_assignments_ws_id UNIQUE (workspace_id, id);


--
-- Name: shifts uq_shifts_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shifts
    ADD CONSTRAINT uq_shifts_ws_id UNIQUE (workspace_id, id);


--
-- Name: shipment_items uq_shipment_items_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shipment_items
    ADD CONSTRAINT uq_shipment_items_ws_id UNIQUE (workspace_id, id);


--
-- Name: stock_reservations uq_stock_reservations_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_reservations
    ADD CONSTRAINT uq_stock_reservations_ws_id UNIQUE (workspace_id, id);


--
-- Name: stock_transfers uq_stock_transfers_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_transfers
    ADD CONSTRAINT uq_stock_transfers_ws_id UNIQUE (workspace_id, id);


--
-- Name: taxes uq_taxes_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taxes
    ADD CONSTRAINT uq_taxes_ws_id UNIQUE (workspace_id, id);


--
-- Name: units_of_measure uq_units_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.units_of_measure
    ADD CONSTRAINT uq_units_ws_id UNIQUE (workspace_id, id);


--
-- Name: users uq_users_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT uq_users_ws_id UNIQUE (workspace_id_deprecated, id);


--
-- Name: warehouses uq_warehouses_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.warehouses
    ADD CONSTRAINT uq_warehouses_ws_id UNIQUE (workspace_id, id);


--
-- Name: work_centers uq_work_centers_ws_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_centers
    ADD CONSTRAINT uq_work_centers_ws_id UNIQUE (workspace_id, id);


--
-- Name: user_permission_overrides user_permission_overrides_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_permission_overrides
    ADD CONSTRAINT user_permission_overrides_pkey PRIMARY KEY (id);


--
-- Name: user_permission_overrides user_permission_overrides_workspace_id_membership_id_permis_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_permission_overrides
    ADD CONSTRAINT user_permission_overrides_workspace_id_membership_id_permis_key UNIQUE (workspace_id, membership_id, permission_key);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: warehouses warehouses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.warehouses
    ADD CONSTRAINT warehouses_pkey PRIMARY KEY (id);


--
-- Name: warehouses warehouses_workspace_id_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.warehouses
    ADD CONSTRAINT warehouses_workspace_id_name_key UNIQUE (workspace_id, name);


--
-- Name: webhook_deliveries webhook_deliveries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_deliveries
    ADD CONSTRAINT webhook_deliveries_pkey PRIMARY KEY (id);


--
-- Name: webhook_events webhook_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_events
    ADD CONSTRAINT webhook_events_pkey PRIMARY KEY (id);


--
-- Name: webhook_events webhook_events_stripe_event_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_events
    ADD CONSTRAINT webhook_events_stripe_event_id_key UNIQUE (stripe_event_id);


--
-- Name: webhook_subscriptions webhook_subscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_subscriptions
    ADD CONSTRAINT webhook_subscriptions_pkey PRIMARY KEY (id);


--
-- Name: work_centers work_centers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_centers
    ADD CONSTRAINT work_centers_pkey PRIMARY KEY (id);


--
-- Name: work_centers work_centers_workspace_id_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_centers
    ADD CONSTRAINT work_centers_workspace_id_code_key UNIQUE (workspace_id, code);


--
-- Name: workspace_configurations workspace_configurations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_configurations
    ADD CONSTRAINT workspace_configurations_pkey PRIMARY KEY (id);


--
-- Name: workspace_configurations workspace_configurations_workspace_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_configurations
    ADD CONSTRAINT workspace_configurations_workspace_id_key UNIQUE (workspace_id);


--
-- Name: workspace_country_packs workspace_country_packs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_country_packs
    ADD CONSTRAINT workspace_country_packs_pkey PRIMARY KEY (id);


--
-- Name: workspace_country_packs workspace_country_packs_workspace_id_country_pack_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_country_packs
    ADD CONSTRAINT workspace_country_packs_workspace_id_country_pack_id_key UNIQUE (workspace_id, country_pack_id);


--
-- Name: workspace_feature_flags workspace_feature_flags_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_feature_flags
    ADD CONSTRAINT workspace_feature_flags_pkey PRIMARY KEY (id);


--
-- Name: workspace_feature_flags workspace_feature_flags_workspace_id_feature_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_feature_flags
    ADD CONSTRAINT workspace_feature_flags_workspace_id_feature_key_key UNIQUE (workspace_id, feature_key);


--
-- Name: workspace_integrations workspace_integrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_integrations
    ADD CONSTRAINT workspace_integrations_pkey PRIMARY KEY (id);


--
-- Name: workspace_integrations workspace_integrations_workspace_id_provider_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_integrations
    ADD CONSTRAINT workspace_integrations_workspace_id_provider_id_key UNIQUE (workspace_id, provider_id);


--
-- Name: workspace_invitation_roles workspace_invitation_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_invitation_roles
    ADD CONSTRAINT workspace_invitation_roles_pkey PRIMARY KEY (id);


--
-- Name: workspace_invitations workspace_invitations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_invitations
    ADD CONSTRAINT workspace_invitations_pkey PRIMARY KEY (id);


--
-- Name: workspace_invitations workspace_invitations_token_hash_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_invitations
    ADD CONSTRAINT workspace_invitations_token_hash_unique UNIQUE (token_hash);


--
-- Name: workspace_memberships workspace_memberships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_memberships
    ADD CONSTRAINT workspace_memberships_pkey PRIMARY KEY (id);


--
-- Name: workspace_memberships workspace_memberships_workspace_id_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_memberships
    ADD CONSTRAINT workspace_memberships_workspace_id_user_id_key UNIQUE (workspace_id, user_id);


--
-- Name: workspace_subscriptions workspace_subscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_subscriptions
    ADD CONSTRAINT workspace_subscriptions_pkey PRIMARY KEY (id);


--
-- Name: workspace_subscriptions workspace_subscriptions_workspace_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_subscriptions
    ADD CONSTRAINT workspace_subscriptions_workspace_id_key UNIQUE (workspace_id);


--
-- Name: workspace_template_applications workspace_template_applications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_template_applications
    ADD CONSTRAINT workspace_template_applications_pkey PRIMARY KEY (id);


--
-- Name: workspace_template_applications workspace_template_applications_workspace_id_business_template_; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_template_applications
    ADD CONSTRAINT workspace_template_applications_workspace_id_business_template_ UNIQUE (workspace_id, business_template_id);


--
-- Name: workspaces workspaces_invite_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspaces
    ADD CONSTRAINT workspaces_invite_code_key UNIQUE (invite_code);


--
-- Name: workspaces workspaces_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspaces
    ADD CONSTRAINT workspaces_pkey PRIMARY KEY (id);


--
-- Name: ai_tool_calls_conversation_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ai_tool_calls_conversation_id_index ON public.ai_tool_calls USING btree (conversation_id);


--
-- Name: ai_tool_calls_created_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ai_tool_calls_created_at_index ON public.ai_tool_calls USING btree (created_at);


--
-- Name: ai_tool_calls_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ai_tool_calls_status_index ON public.ai_tool_calls USING btree (status);


--
-- Name: ai_tool_calls_tool_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ai_tool_calls_tool_name_index ON public.ai_tool_calls USING btree (tool_name);


--
-- Name: ai_tool_calls_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ai_tool_calls_user_id_index ON public.ai_tool_calls USING btree (user_id);


--
-- Name: ai_tool_calls_workspace_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ai_tool_calls_workspace_id_index ON public.ai_tool_calls USING btree (workspace_id);


--
-- Name: commission_entries_calculated_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX commission_entries_calculated_at_index ON public.commission_entries USING btree (calculated_at);


--
-- Name: commission_entries_pipeline_record_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX commission_entries_pipeline_record_id_index ON public.commission_entries USING btree (pipeline_record_id);


--
-- Name: commission_entries_recipient_membership_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX commission_entries_recipient_membership_id_index ON public.commission_entries USING btree (recipient_membership_id);


--
-- Name: commission_entries_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX commission_entries_status_index ON public.commission_entries USING btree (status);


--
-- Name: commission_entries_workspace_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX commission_entries_workspace_id_index ON public.commission_entries USING btree (workspace_id);


--
-- Name: commission_plans_applies_to_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX commission_plans_applies_to_index ON public.commission_plans USING btree (applies_to);


--
-- Name: commission_plans_is_active_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX commission_plans_is_active_index ON public.commission_plans USING btree (is_active);


--
-- Name: commission_plans_workspace_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX commission_plans_workspace_id_index ON public.commission_plans USING btree (workspace_id);


--
-- Name: commission_rules_commission_plan_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX commission_rules_commission_plan_id_index ON public.commission_rules USING btree (commission_plan_id);


--
-- Name: commission_rules_department_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX commission_rules_department_id_index ON public.commission_rules USING btree (department_id);


--
-- Name: commission_rules_is_active_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX commission_rules_is_active_index ON public.commission_rules USING btree (is_active);


--
-- Name: commission_rules_pipeline_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX commission_rules_pipeline_id_index ON public.commission_rules USING btree (pipeline_id);


--
-- Name: commission_rules_role_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX commission_rules_role_id_index ON public.commission_rules USING btree (role_id);


--
-- Name: commission_rules_stage_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX commission_rules_stage_id_index ON public.commission_rules USING btree (stage_id);


--
-- Name: commission_rules_team_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX commission_rules_team_id_index ON public.commission_rules USING btree (team_id);


--
-- Name: commission_rules_workspace_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX commission_rules_workspace_id_index ON public.commission_rules USING btree (workspace_id);


--
-- Name: contacts_assigned_membership_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contacts_assigned_membership_id_index ON public.contacts USING btree (assigned_membership_id);


--
-- Name: custom_field_values_custom_field_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX custom_field_values_custom_field_id_index ON public.custom_field_values USING btree (custom_field_id);


--
-- Name: custom_field_values_record_type_record_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX custom_field_values_record_type_record_id_index ON public.custom_field_values USING btree (record_type, record_id);


--
-- Name: custom_field_values_workspace_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX custom_field_values_workspace_id_index ON public.custom_field_values USING btree (workspace_id);


--
-- Name: custom_fields_applies_to_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX custom_fields_applies_to_index ON public.custom_fields USING btree (applies_to);


--
-- Name: custom_fields_is_active_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX custom_fields_is_active_index ON public.custom_fields USING btree (is_active);


--
-- Name: custom_fields_pipeline_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX custom_fields_pipeline_id_index ON public.custom_fields USING btree (pipeline_id);


--
-- Name: custom_fields_workspace_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX custom_fields_workspace_id_index ON public.custom_fields USING btree (workspace_id);


--
-- Name: document_checklist_items_document_checklist_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX document_checklist_items_document_checklist_id_index ON public.document_checklist_items USING btree (document_checklist_id);


--
-- Name: document_checklist_items_is_active_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX document_checklist_items_is_active_index ON public.document_checklist_items USING btree (is_active);


--
-- Name: document_checklist_items_is_required_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX document_checklist_items_is_required_index ON public.document_checklist_items USING btree (is_required);


--
-- Name: document_checklist_items_workspace_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX document_checklist_items_workspace_id_index ON public.document_checklist_items USING btree (workspace_id);


--
-- Name: document_checklists_is_active_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX document_checklists_is_active_index ON public.document_checklists USING btree (is_active);


--
-- Name: document_checklists_pipeline_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX document_checklists_pipeline_id_index ON public.document_checklists USING btree (pipeline_id);


--
-- Name: document_checklists_stage_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX document_checklists_stage_id_index ON public.document_checklists USING btree (stage_id);


--
-- Name: document_checklists_workspace_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX document_checklists_workspace_id_index ON public.document_checklists USING btree (workspace_id);


--
-- Name: duplicate_matches_entity_type_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX duplicate_matches_entity_type_index ON public.duplicate_matches USING btree (entity_type);


--
-- Name: duplicate_matches_matched_entity_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX duplicate_matches_matched_entity_id_index ON public.duplicate_matches USING btree (matched_entity_id);


--
-- Name: duplicate_matches_source_entity_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX duplicate_matches_source_entity_id_index ON public.duplicate_matches USING btree (source_entity_id);


--
-- Name: duplicate_matches_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX duplicate_matches_status_index ON public.duplicate_matches USING btree (status);


--
-- Name: duplicate_matches_workspace_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX duplicate_matches_workspace_id_index ON public.duplicate_matches USING btree (workspace_id);


--
-- Name: duplicate_rules_entity_type_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX duplicate_rules_entity_type_index ON public.duplicate_rules USING btree (entity_type);


--
-- Name: duplicate_rules_is_active_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX duplicate_rules_is_active_index ON public.duplicate_rules USING btree (is_active);


--
-- Name: duplicate_rules_workspace_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX duplicate_rules_workspace_id_index ON public.duplicate_rules USING btree (workspace_id);


--
-- Name: finance_accounts_is_active_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX finance_accounts_is_active_index ON public.finance_accounts USING btree (is_active);


--
-- Name: finance_accounts_is_system_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX finance_accounts_is_system_index ON public.finance_accounts USING btree (is_system);


--
-- Name: finance_accounts_type_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX finance_accounts_type_index ON public.finance_accounts USING btree (type);


--
-- Name: finance_accounts_workspace_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX finance_accounts_workspace_id_index ON public.finance_accounts USING btree (workspace_id);


--
-- Name: finance_expenses_category_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX finance_expenses_category_index ON public.finance_expenses USING btree (category);


--
-- Name: finance_expenses_expense_date_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX finance_expenses_expense_date_index ON public.finance_expenses USING btree (expense_date);


--
-- Name: finance_expenses_finance_transaction_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX finance_expenses_finance_transaction_id_index ON public.finance_expenses USING btree (finance_transaction_id);


--
-- Name: finance_expenses_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX finance_expenses_status_index ON public.finance_expenses USING btree (status);


--
-- Name: finance_expenses_workspace_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX finance_expenses_workspace_id_index ON public.finance_expenses USING btree (workspace_id);


--
-- Name: finance_transaction_lines_finance_account_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX finance_transaction_lines_finance_account_id_index ON public.finance_transaction_lines USING btree (finance_account_id);


--
-- Name: finance_transaction_lines_finance_transaction_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX finance_transaction_lines_finance_transaction_id_index ON public.finance_transaction_lines USING btree (finance_transaction_id);


--
-- Name: finance_transaction_lines_workspace_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX finance_transaction_lines_workspace_id_index ON public.finance_transaction_lines USING btree (workspace_id);


--
-- Name: finance_transactions_posted_by_membership_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX finance_transactions_posted_by_membership_id_index ON public.finance_transactions USING btree (posted_by_membership_id);


--
-- Name: finance_transactions_source_type_source_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX finance_transactions_source_type_source_id_index ON public.finance_transactions USING btree (source_type, source_id);


--
-- Name: finance_transactions_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX finance_transactions_status_index ON public.finance_transactions USING btree (status);


--
-- Name: finance_transactions_transaction_date_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX finance_transactions_transaction_date_index ON public.finance_transactions USING btree (transaction_date);


--
-- Name: finance_transactions_workspace_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX finance_transactions_workspace_id_index ON public.finance_transactions USING btree (workspace_id);


--
-- Name: idx_accounts_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_accounts_workspace ON public.accounts USING btree (workspace_id);


--
-- Name: idx_accounts_ws_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_accounts_ws_type ON public.accounts USING btree (workspace_id, type);


--
-- Name: INDEX idx_accounts_ws_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_accounts_ws_type IS 'Finance: chart of accounts partitioned by type for balance sheet / P&L generation.';


--
-- Name: idx_ad_req; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ad_req ON public.approval_decisions USING btree (workspace_id, approval_request_id);


--
-- Name: idx_ai_change_reqs_conv; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_change_reqs_conv ON public.ai_change_requests USING btree (conversation_id) WHERE (conversation_id IS NOT NULL);


--
-- Name: idx_ai_change_reqs_pending; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_change_reqs_pending ON public.ai_change_requests USING btree (workspace_id, proposed_at DESC) WHERE ((status)::text = 'proposed'::text);


--
-- Name: idx_ai_change_reqs_ws_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_change_reqs_ws_status ON public.ai_change_requests USING btree (workspace_id, status);


--
-- Name: idx_ai_conv_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_conv_created ON public.ai_conversations USING btree (created_at);


--
-- Name: idx_ai_conv_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_conv_status ON public.ai_conversations USING btree (status);


--
-- Name: idx_ai_conv_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_conv_type ON public.ai_conversations USING btree (type);


--
-- Name: idx_ai_conv_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_conv_user ON public.ai_conversations USING btree (user_id);


--
-- Name: idx_ai_conv_ws; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_conv_ws ON public.ai_conversations USING btree (workspace_id);


--
-- Name: idx_ai_conversations_last_msg; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_conversations_last_msg ON public.ai_conversations USING btree (workspace_id, last_message_at DESC NULLS LAST);


--
-- Name: idx_ai_conversations_ws_mode; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_conversations_ws_mode ON public.ai_conversations USING btree (workspace_id, mode);


--
-- Name: idx_ai_conversations_ws_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_conversations_ws_user ON public.ai_conversations USING btree (workspace_id, user_id);


--
-- Name: idx_ai_cr_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_cr_status ON public.ai_change_requests USING btree (status);


--
-- Name: idx_ai_cr_ws; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_cr_ws ON public.ai_change_requests USING btree (workspace_id);


--
-- Name: idx_ai_credit_balances_ws; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_credit_balances_ws ON public.ai_credit_balances USING btree (workspace_id);


--
-- Name: idx_ai_credit_tx_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_credit_tx_created ON public.ai_credit_transactions USING btree (created_at);


--
-- Name: idx_ai_credit_tx_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_credit_tx_type ON public.ai_credit_transactions USING btree (transaction_type);


--
-- Name: idx_ai_credit_tx_ws; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_credit_tx_ws ON public.ai_credit_transactions USING btree (workspace_id);


--
-- Name: idx_ai_ep_ws; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_ep_ws ON public.ai_execution_plans USING btree (workspace_id);


--
-- Name: idx_ai_ins_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_ins_status ON public.ai_insights USING btree (status);


--
-- Name: idx_ai_ins_ws; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_ins_ws ON public.ai_insights USING btree (workspace_id);


--
-- Name: idx_ai_insights_ws; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_insights_ws ON public.ai_insights USING btree (workspace_id, status);


--
-- Name: idx_ai_mem_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_mem_type ON public.ai_memory USING btree (memory_type);


--
-- Name: idx_ai_mem_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_mem_user ON public.ai_memory USING btree (user_id);


--
-- Name: idx_ai_mem_ws; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_mem_ws ON public.ai_memory USING btree (workspace_id);


--
-- Name: idx_ai_memory_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_memory_user ON public.ai_memory USING btree (workspace_id, user_id) WHERE (user_id IS NOT NULL);


--
-- Name: idx_ai_memory_ws_key; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_memory_ws_key ON public.ai_memory USING btree (workspace_id, key);


--
-- Name: idx_ai_memory_ws_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_memory_ws_type ON public.ai_memory USING btree (workspace_id, memory_type);


--
-- Name: idx_ai_msg_conv; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_msg_conv ON public.ai_messages USING btree (conversation_id);


--
-- Name: idx_ai_msg_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_msg_created ON public.ai_messages USING btree (created_at);


--
-- Name: idx_ai_msg_role; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_msg_role ON public.ai_messages USING btree (role);


--
-- Name: idx_ai_msg_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_msg_user ON public.ai_messages USING btree (user_id);


--
-- Name: idx_ai_msg_ws; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_msg_ws ON public.ai_messages USING btree (workspace_id);


--
-- Name: idx_ai_plans_ws; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_plans_ws ON public.ai_execution_plans USING btree (workspace_id, status);


--
-- Name: idx_ai_rec_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_rec_category ON public.ai_recommendations USING btree (workspace_id, category);


--
-- Name: idx_ai_rec_impact; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_rec_impact ON public.ai_recommendations USING btree (impact_level);


--
-- Name: idx_ai_rec_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_rec_status ON public.ai_recommendations USING btree (workspace_id, status);


--
-- Name: idx_ai_rec_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_rec_workspace ON public.ai_recommendations USING btree (workspace_id);


--
-- Name: idx_ai_ulog_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_ulog_created ON public.ai_usage_logs USING btree (created_at);


--
-- Name: idx_ai_ulog_model; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_ulog_model ON public.ai_usage_logs USING btree (model);


--
-- Name: idx_ai_ulog_op; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_ulog_op ON public.ai_usage_logs USING btree (operation);


--
-- Name: idx_ai_ulog_provider; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_ulog_provider ON public.ai_usage_logs USING btree (provider);


--
-- Name: idx_ai_ulog_success; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_ulog_success ON public.ai_usage_logs USING btree (success);


--
-- Name: idx_ai_ulog_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_ulog_user ON public.ai_usage_logs USING btree (user_id);


--
-- Name: idx_ai_ulog_ws; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_ulog_ws ON public.ai_usage_logs USING btree (workspace_id);


--
-- Name: idx_ai_ws_settings_ws; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ai_ws_settings_ws ON public.ai_workspace_settings USING btree (workspace_id);


--
-- Name: idx_ar_entity; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ar_entity ON public.approval_requests USING btree (workspace_id, entity_type, entity_id);


--
-- Name: idx_ar_requester; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ar_requester ON public.approval_requests USING btree (workspace_id, requester_membership_id, status);


--
-- Name: idx_ar_ws_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ar_ws_status ON public.approval_requests USING btree (workspace_id, status);


--
-- Name: idx_ars_req_order; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ars_req_order ON public.approval_request_steps USING btree (workspace_id, approval_request_id, step_order);


--
-- Name: idx_ars_ws_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ars_ws_status ON public.approval_request_steps USING btree (workspace_id, status);


--
-- Name: idx_async_jobs_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_async_jobs_created ON public.async_jobs USING btree (created_at);


--
-- Name: idx_async_jobs_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_async_jobs_status ON public.async_jobs USING btree (status);


--
-- Name: idx_async_jobs_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_async_jobs_type ON public.async_jobs USING btree (job_type);


--
-- Name: idx_async_jobs_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_async_jobs_user ON public.async_jobs USING btree (user_id);


--
-- Name: idx_async_jobs_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_async_jobs_workspace ON public.async_jobs USING btree (workspace_id);


--
-- Name: idx_attachments_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_attachments_workspace ON public.attachments USING btree (workspace_id);


--
-- Name: idx_attendance_adjusted; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_attendance_adjusted ON public.attendance USING btree (workspace_id) WHERE (is_manually_adjusted = true);


--
-- Name: idx_attendance_overtime; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_attendance_overtime ON public.attendance USING btree (workspace_id, user_id, date) WHERE (overtime_hours > (0)::numeric);


--
-- Name: idx_attendance_shift; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_attendance_shift ON public.attendance USING btree (shift_id) WHERE (shift_id IS NOT NULL);


--
-- Name: idx_attendance_user_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_attendance_user_date ON public.attendance USING btree (workspace_id, user_id, date);


--
-- Name: INDEX idx_attendance_user_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_attendance_user_date IS 'HR: attendance lookup by user and date range for monthly reports.';


--
-- Name: idx_audit_logs_entity; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_logs_entity ON public.audit_logs USING btree (workspace_id, entity_type, entity_id);


--
-- Name: INDEX idx_audit_logs_entity; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_audit_logs_entity IS 'Audit: entity change history lookup for compliance and debugging.';


--
-- Name: idx_audit_logs_ip; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_logs_ip ON public.audit_logs USING btree (ip_address) WHERE (ip_address IS NOT NULL);


--
-- Name: idx_audit_logs_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_logs_workspace ON public.audit_logs USING btree (workspace_id);


--
-- Name: idx_audit_logs_ws_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_logs_ws_user ON public.audit_logs USING btree (workspace_id, user_id, created_at DESC);


--
-- Name: INDEX idx_audit_logs_ws_user; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_audit_logs_ws_user IS 'Audit: user activity report ordered by most recent.';


--
-- Name: idx_automation_logs_ws; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_automation_logs_ws ON public.automation_logs USING btree (workspace_id, triggered_at);


--
-- Name: idx_aw_entity_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_aw_entity_active ON public.approval_workflows USING btree (workspace_id, entity_type, is_active);


--
-- Name: idx_aws_wf_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_aws_wf_active ON public.approval_workflow_steps USING btree (workspace_id, workflow_id, is_active);


--
-- Name: idx_bill_of_materials_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bill_of_materials_workspace ON public.bill_of_materials USING btree (workspace_id);


--
-- Name: idx_billing_invoices_period; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_billing_invoices_period ON public.billing_invoices USING btree (period_start, period_end);


--
-- Name: idx_billing_invoices_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_billing_invoices_status ON public.billing_invoices USING btree (status);


--
-- Name: idx_billing_invoices_subscription; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_billing_invoices_subscription ON public.billing_invoices USING btree (subscription_id);


--
-- Name: idx_billing_invoices_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_billing_invoices_workspace ON public.billing_invoices USING btree (workspace_id);


--
-- Name: idx_billing_payments_invoice; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_billing_payments_invoice ON public.billing_payments USING btree (billing_invoice_id);


--
-- Name: idx_billing_payments_paid_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_billing_payments_paid_at ON public.billing_payments USING btree (paid_at);


--
-- Name: idx_billing_payments_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_billing_payments_workspace ON public.billing_payments USING btree (workspace_id);


--
-- Name: idx_billing_snapshots_period; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_billing_snapshots_period ON public.billing_snapshots USING btree (period_start, period_end);


--
-- Name: idx_billing_snapshots_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_billing_snapshots_status ON public.billing_snapshots USING btree (status);


--
-- Name: idx_billing_snapshots_ws; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_billing_snapshots_ws ON public.billing_snapshots USING btree (workspace_id);


--
-- Name: idx_bookings_assigned; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bookings_assigned ON public.bookings USING btree (assigned_to);


--
-- Name: idx_bookings_contact; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bookings_contact ON public.bookings USING btree (contact_id);


--
-- Name: idx_bookings_datetime; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bookings_datetime ON public.bookings USING btree (start_datetime, end_datetime);


--
-- Name: idx_bookings_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bookings_workspace ON public.bookings USING btree (workspace_id);


--
-- Name: idx_branches_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_branches_workspace ON public.branches USING btree (workspace_id);


--
-- Name: idx_broadcasts_scheduled; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_broadcasts_scheduled ON public.platform_broadcasts USING btree (scheduled_at) WHERE ((status)::text = 'scheduled'::text);


--
-- Name: idx_broadcasts_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_broadcasts_status ON public.platform_broadcasts USING btree (status);


--
-- Name: idx_broadcasts_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_broadcasts_type ON public.platform_broadcasts USING btree (type);


--
-- Name: idx_campaigns_ws_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_campaigns_ws_status ON public.campaigns USING btree (workspace_id, status);


--
-- Name: idx_cod_collections_ws_settled; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cod_collections_ws_settled ON public.cod_collections USING btree (workspace_id, settled);


--
-- Name: idx_contacts_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_contacts_workspace ON public.contacts USING btree (workspace_id);


--
-- Name: idx_contacts_ws_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_contacts_ws_name ON public.contacts USING btree (workspace_id, name);


--
-- Name: INDEX idx_contacts_ws_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_contacts_ws_name IS 'Contacts: alphabetical contact search within workspace.';


--
-- Name: idx_contacts_ws_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_contacts_ws_type ON public.contacts USING btree (workspace_id, type);


--
-- Name: INDEX idx_contacts_ws_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_contacts_ws_type IS 'Contacts: filter contacts by type (customer, supplier, both).';


--
-- Name: idx_coupons_code; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_coupons_code ON public.coupons USING btree (code);


--
-- Name: idx_coupons_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_coupons_workspace ON public.coupons USING btree (workspace_id);


--
-- Name: idx_credit_note_items_note; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_credit_note_items_note ON public.credit_note_items USING btree (credit_note_id);


--
-- Name: idx_credit_note_items_original; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_credit_note_items_original ON public.credit_note_items USING btree (original_invoice_item_id) WHERE (original_invoice_item_id IS NOT NULL);


--
-- Name: idx_credit_note_items_product; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_credit_note_items_product ON public.credit_note_items USING btree (product_id);


--
-- Name: idx_credit_note_items_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_credit_note_items_workspace ON public.credit_note_items USING btree (workspace_id);


--
-- Name: idx_credit_notes_active_per_invoice; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_credit_notes_active_per_invoice ON public.credit_notes USING btree (original_invoice_id) WHERE ((status)::text <> 'void'::text);


--
-- Name: idx_credit_notes_branch; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_credit_notes_branch ON public.credit_notes USING btree (branch_id);


--
-- Name: idx_credit_notes_contact; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_credit_notes_contact ON public.credit_notes USING btree (contact_id);


--
-- Name: idx_credit_notes_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_credit_notes_created ON public.credit_notes USING btree (created_at);


--
-- Name: idx_credit_notes_invoice; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_credit_notes_invoice ON public.credit_notes USING btree (original_invoice_id);


--
-- Name: INDEX idx_credit_notes_invoice; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_credit_notes_invoice IS 'Finance: lookup credit notes issued against a specific invoice.';


--
-- Name: idx_credit_notes_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_credit_notes_status ON public.credit_notes USING btree (status);


--
-- Name: idx_credit_notes_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_credit_notes_workspace ON public.credit_notes USING btree (workspace_id);


--
-- Name: idx_crm_activities_lead; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_crm_activities_lead ON public.crm_activities USING btree (lead_id);


--
-- Name: idx_crm_activities_opportunity; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_crm_activities_opportunity ON public.crm_activities USING btree (opportunity_id);


--
-- Name: idx_crm_activities_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_crm_activities_workspace ON public.crm_activities USING btree (workspace_id);


--
-- Name: idx_customer_credits_contact; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customer_credits_contact ON public.customer_credits USING btree (contact_id);


--
-- Name: idx_customer_credits_contact_latest; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customer_credits_contact_latest ON public.customer_credits USING btree (workspace_id, contact_id, created_at DESC);


--
-- Name: INDEX idx_customer_credits_contact_latest; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_customer_credits_contact_latest IS 'Finance: fast lookup of latest customer credit balance_after. Critical for concurrency: SELECT FOR UPDATE on this index path.';


--
-- Name: idx_customer_credits_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customer_credits_created ON public.customer_credits USING btree (created_at);


--
-- Name: idx_customer_credits_credit_note; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customer_credits_credit_note ON public.customer_credits USING btree (credit_note_id) WHERE (credit_note_id IS NOT NULL);


--
-- Name: idx_customer_credits_invoice; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customer_credits_invoice ON public.customer_credits USING btree (invoice_id) WHERE (invoice_id IS NOT NULL);


--
-- Name: idx_customer_credits_payment; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customer_credits_payment ON public.customer_credits USING btree (payment_id) WHERE (payment_id IS NOT NULL);


--
-- Name: idx_customer_credits_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customer_credits_type ON public.customer_credits USING btree (movement_type);


--
-- Name: idx_customer_credits_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customer_credits_workspace ON public.customer_credits USING btree (workspace_id);


--
-- Name: idx_customer_credits_ws_contact; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customer_credits_ws_contact ON public.customer_credits USING btree (workspace_id, contact_id);


--
-- Name: idx_customer_subscriptions_contact; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customer_subscriptions_contact ON public.customer_subscriptions USING btree (contact_id);


--
-- Name: idx_customer_subscriptions_next_billing; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customer_subscriptions_next_billing ON public.customer_subscriptions USING btree (next_billing_date);


--
-- Name: idx_customer_subscriptions_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customer_subscriptions_status ON public.customer_subscriptions USING btree (status);


--
-- Name: idx_customer_subscriptions_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customer_subscriptions_workspace ON public.customer_subscriptions USING btree (workspace_id);


--
-- Name: idx_delegation_items_delegation; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_delegation_items_delegation ON public.permission_delegation_items USING btree (delegation_id);


--
-- Name: idx_delegation_items_permission; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_delegation_items_permission ON public.permission_delegation_items USING btree (permission_key);


--
-- Name: idx_delegations_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_delegations_active ON public.permission_delegations USING btree (delegate_membership_id, status) WHERE ((status)::text = 'active'::text);


--
-- Name: idx_delegations_delegate; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_delegations_delegate ON public.permission_delegations USING btree (delegate_membership_id);


--
-- Name: idx_delegations_delegate_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_delegations_delegate_active ON public.permission_delegations USING btree (delegate_membership_id) WHERE ((status)::text = 'active'::text);


--
-- Name: INDEX idx_delegations_delegate_active; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_delegations_delegate_active IS 'RBAC: fast lookup of active delegations received by a membership.';


--
-- Name: idx_delegations_delegator; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_delegations_delegator ON public.permission_delegations USING btree (delegator_membership_id);


--
-- Name: idx_delegations_end_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_delegations_end_at ON public.permission_delegations USING btree (end_at) WHERE ((status)::text = 'active'::text);


--
-- Name: idx_delegations_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_delegations_status ON public.permission_delegations USING btree (status);


--
-- Name: idx_delegations_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_delegations_workspace ON public.permission_delegations USING btree (workspace_id);


--
-- Name: idx_delivery_assignments_driver; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_delivery_assignments_driver ON public.delivery_assignments USING btree (driver_id, status);


--
-- Name: idx_delivery_assignments_order; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_delivery_assignments_order ON public.delivery_assignments USING btree (order_id);


--
-- Name: idx_delivery_assignments_ws_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_delivery_assignments_ws_status ON public.delivery_assignments USING btree (workspace_id, status);


--
-- Name: idx_delivery_tracking_assign; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_delivery_tracking_assign ON public.delivery_tracking USING btree (assignment_id, captured_at);


--
-- Name: idx_departments_parent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_departments_parent ON public.departments USING btree (parent_department_id);


--
-- Name: idx_departments_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_departments_workspace ON public.departments USING btree (workspace_id);


--
-- Name: idx_dining_tables_branch; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dining_tables_branch ON public.dining_tables USING btree (branch_id);


--
-- Name: idx_dining_tables_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dining_tables_status ON public.dining_tables USING btree (status);


--
-- Name: idx_dining_tables_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dining_tables_workspace ON public.dining_tables USING btree (workspace_id);


--
-- Name: idx_discovery_blueprints_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_discovery_blueprints_workspace ON public.discovery_blueprints USING btree (workspace_id);


--
-- Name: idx_discovery_messages_session; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_discovery_messages_session ON public.discovery_messages USING btree (session_id);


--
-- Name: idx_discovery_messages_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_discovery_messages_workspace ON public.discovery_messages USING btree (workspace_id);


--
-- Name: idx_discovery_sessions_created_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_discovery_sessions_created_by ON public.discovery_sessions USING btree (created_by);


--
-- Name: idx_discovery_sessions_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_discovery_sessions_workspace ON public.discovery_sessions USING btree (workspace_id);


--
-- Name: idx_document_sequences_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_document_sequences_workspace ON public.document_sequences USING btree (workspace_id);


--
-- Name: idx_drivers_ws_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_drivers_ws_status ON public.drivers USING btree (workspace_id, status);


--
-- Name: idx_email_logs_correlation; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_email_logs_correlation ON public.email_logs USING btree (correlation_key);


--
-- Name: idx_email_logs_entity; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_email_logs_entity ON public.email_logs USING btree (related_entity_type, related_entity_id);


--
-- Name: idx_email_logs_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_email_logs_status ON public.email_logs USING btree (status);


--
-- Name: idx_email_logs_template; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_email_logs_template ON public.email_logs USING btree (template, workspace_id);


--
-- Name: idx_email_logs_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_email_logs_workspace ON public.email_logs USING btree (workspace_id);


--
-- Name: idx_events_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_events_created ON public.platform_events USING btree (created_at);


--
-- Name: idx_events_severity; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_events_severity ON public.platform_events USING btree (severity);


--
-- Name: idx_events_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_events_type ON public.platform_events USING btree (event_type);


--
-- Name: idx_events_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_events_workspace ON public.platform_events USING btree (workspace_id);


--
-- Name: idx_exchange_rates_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_exchange_rates_lookup ON public.exchange_rates USING btree (workspace_id, base_currency, target_currency, effective_date DESC);


--
-- Name: idx_exchange_rates_ws_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_exchange_rates_ws_date ON public.exchange_rates USING btree (workspace_id, effective_date DESC);


--
-- Name: idx_exchange_rates_ws_pair; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_exchange_rates_ws_pair ON public.exchange_rates USING btree (workspace_id, base_currency, target_currency);


--
-- Name: idx_export_jobs_ws_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_export_jobs_ws_status ON public.export_jobs USING btree (workspace_id, status);


--
-- Name: idx_feature_requests_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_feature_requests_category ON public.platform_feature_requests USING btree (category);


--
-- Name: idx_feature_requests_normalized; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_feature_requests_normalized ON public.platform_feature_requests USING btree (normalized_key);


--
-- Name: idx_feature_requests_priority; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_feature_requests_priority ON public.platform_feature_requests USING btree (priority);


--
-- Name: idx_feature_requests_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_feature_requests_status ON public.platform_feature_requests USING btree (status);


--
-- Name: idx_feature_votes_request; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_feature_votes_request ON public.platform_feature_request_votes USING btree (feature_request_id);


--
-- Name: idx_feature_votes_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_feature_votes_workspace ON public.platform_feature_request_votes USING btree (workspace_id);


--
-- Name: idx_fiscal_periods_dates; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fiscal_periods_dates ON public.fiscal_periods USING btree (workspace_id, start_date, end_date);


--
-- Name: idx_fiscal_periods_open; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fiscal_periods_open ON public.fiscal_periods USING btree (workspace_id, start_date, end_date) WHERE ((status)::text = 'open'::text);


--
-- Name: idx_fiscal_periods_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fiscal_periods_status ON public.fiscal_periods USING btree (status);


--
-- Name: idx_fiscal_periods_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fiscal_periods_workspace ON public.fiscal_periods USING btree (workspace_id);


--
-- Name: idx_fiscal_periods_year; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fiscal_periods_year ON public.fiscal_periods USING btree (workspace_id, fiscal_year);


--
-- Name: idx_fixed_assets_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fixed_assets_workspace ON public.fixed_assets USING btree (workspace_id);


--
-- Name: idx_grn_items_grn; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_grn_items_grn ON public.grn_items USING btree (grn_id);


--
-- Name: idx_grn_items_po_item; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_grn_items_po_item ON public.grn_items USING btree (po_item_id);


--
-- Name: idx_grn_items_product; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_grn_items_product ON public.grn_items USING btree (product_id);


--
-- Name: idx_grn_po; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_grn_po ON public.goods_received_notes USING btree (po_id);


--
-- Name: idx_grn_purchase_order; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_grn_purchase_order ON public.goods_received_notes USING btree (po_id);


--
-- Name: INDEX idx_grn_purchase_order; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_grn_purchase_order IS 'Inventory: lookup goods received notes for a specific purchase order.';


--
-- Name: idx_grn_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_grn_status ON public.goods_received_notes USING btree (status);


--
-- Name: idx_grn_warehouse; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_grn_warehouse ON public.goods_received_notes USING btree (warehouse_id);


--
-- Name: idx_grn_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_grn_workspace ON public.goods_received_notes USING btree (workspace_id);


--
-- Name: idx_idempotency_keys_expires; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_idempotency_keys_expires ON public.idempotency_keys USING btree (expires_at);


--
-- Name: idx_impersonation_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_impersonation_active ON public.impersonation_sessions USING btree (platform_user_id, expires_at) WHERE (ended_at IS NULL);


--
-- Name: idx_import_jobs_ws_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_import_jobs_ws_status ON public.import_jobs USING btree (workspace_id, status);


--
-- Name: idx_inventory_batches_batch_number; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_inventory_batches_batch_number ON public.inventory_batches USING btree (batch_number);


--
-- Name: idx_inventory_batches_expiry; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_inventory_batches_expiry ON public.inventory_batches USING btree (expiry_date);


--
-- Name: idx_inventory_batches_warehouse_product; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_inventory_batches_warehouse_product ON public.inventory_batches USING btree (warehouse_id, product_id);


--
-- Name: idx_inventory_batches_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_inventory_batches_workspace ON public.inventory_batches USING btree (workspace_id);


--
-- Name: idx_inventory_levels_low_stock; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_inventory_levels_low_stock ON public.inventory_levels USING btree (workspace_id, product_id) WHERE ((reorder_point IS NOT NULL) AND (available <= reorder_point));


--
-- Name: idx_inventory_levels_warehouse; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_inventory_levels_warehouse ON public.inventory_levels USING btree (warehouse_id);


--
-- Name: idx_inventory_levels_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_inventory_levels_workspace ON public.inventory_levels USING btree (workspace_id) WHERE (workspace_id IS NOT NULL);


--
-- Name: idx_inventory_levels_ws_product; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_inventory_levels_ws_product ON public.inventory_levels USING btree (workspace_id, product_id);


--
-- Name: INDEX idx_inventory_levels_ws_product; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_inventory_levels_ws_product IS 'Inventory: stock level lookup for a product across all warehouses.';


--
-- Name: idx_inventory_logs_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_inventory_logs_created ON public.inventory_logs_legacy USING btree (created_at);


--
-- Name: idx_inventory_logs_product; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_inventory_logs_product ON public.inventory_logs_legacy USING btree (product_id);


--
-- Name: idx_inventory_low_stock; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_inventory_low_stock ON public.inventory_levels USING btree (workspace_id) WHERE ((available <= reorder_point) AND (reorder_point > (0)::numeric));


--
-- Name: INDEX idx_inventory_low_stock; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_inventory_low_stock IS 'Inventory: low stock alert — rows where available quantity is at or below reorder point. Used by background reorder suggestion jobs.';


--
-- Name: idx_inventory_movements_batch; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_inventory_movements_batch ON public.inventory_movements USING btree (batch_id) WHERE (batch_id IS NOT NULL);


--
-- Name: idx_inventory_movements_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_inventory_movements_created ON public.inventory_movements USING btree (workspace_id, created_at DESC);


--
-- Name: idx_inventory_movements_product; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_inventory_movements_product ON public.inventory_movements USING btree (product_id);


--
-- Name: idx_inventory_movements_product_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_inventory_movements_product_date ON public.inventory_movements USING btree (workspace_id, product_id, created_at DESC);


--
-- Name: INDEX idx_inventory_movements_product_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_inventory_movements_product_date IS 'Inventory: movement history for a product, ordered by most recent.';


--
-- Name: idx_inventory_movements_ref; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_inventory_movements_ref ON public.inventory_movements USING btree (reference_type, reference_id) WHERE (reference_id IS NOT NULL);


--
-- Name: idx_inventory_movements_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_inventory_movements_type ON public.inventory_movements USING btree (movement_type);


--
-- Name: idx_inventory_movements_warehouse; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_inventory_movements_warehouse ON public.inventory_movements USING btree (warehouse_id);


--
-- Name: idx_inventory_movements_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_inventory_movements_workspace ON public.inventory_movements USING btree (workspace_id);


--
-- Name: idx_inventory_movements_ws_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_inventory_movements_ws_type ON public.inventory_movements USING btree (workspace_id, movement_type);


--
-- Name: INDEX idx_inventory_movements_ws_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_inventory_movements_ws_type IS 'Inventory: aggregate movements by type for reporting dashboards.';


--
-- Name: idx_invoice_items_invoice; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invoice_items_invoice ON public.invoice_items USING btree (invoice_id);


--
-- Name: idx_invoices_aging; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invoices_aging ON public.invoices USING btree (workspace_id, due_date) WHERE ((payment_status)::text = ANY (ARRAY[('unpaid'::character varying)::text, ('partial'::character varying)::text, ('overdue'::character varying)::text]));


--
-- Name: INDEX idx_invoices_aging; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_invoices_aging IS 'Finance: invoice aging report — outstanding invoices ordered by due date.';


--
-- Name: idx_invoices_branch; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invoices_branch ON public.invoices USING btree (branch_id);


--
-- Name: idx_invoices_contact_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invoices_contact_status ON public.invoices USING btree (workspace_id, contact_id, payment_status);


--
-- Name: INDEX idx_invoices_contact_status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_invoices_contact_status IS 'Finance: customer/supplier ledger — invoice lookup by contact and payment status.';


--
-- Name: idx_invoices_parent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invoices_parent ON public.invoices USING btree (parent_invoice_id);


--
-- Name: idx_invoices_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invoices_workspace ON public.invoices USING btree (workspace_id);


--
-- Name: idx_journal_entries_currency; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_journal_entries_currency ON public.journal_entries USING btree (workspace_id, currency) WHERE ((currency)::text <> 'LYD'::text);


--
-- Name: idx_journal_entries_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_journal_entries_status ON public.journal_entries USING btree (workspace_id, status);


--
-- Name: idx_journal_entries_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_journal_entries_workspace ON public.journal_entries USING btree (workspace_id);


--
-- Name: idx_journal_entries_ws_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_journal_entries_ws_date ON public.journal_entries USING btree (workspace_id, date);


--
-- Name: INDEX idx_journal_entries_ws_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_journal_entries_ws_date IS 'Finance: journal entry lookups by date range for period reporting.';


--
-- Name: idx_journal_lines_account; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_journal_lines_account ON public.journal_lines USING btree (account_id);


--
-- Name: INDEX idx_journal_lines_account; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_journal_lines_account IS 'Finance: fast aggregate for account balance (SUM debit/credit by account).';


--
-- Name: idx_journal_lines_entry; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_journal_lines_entry ON public.journal_lines USING btree (entry_id);


--
-- Name: idx_leads_assigned; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leads_assigned ON public.leads USING btree (assigned_to);


--
-- Name: idx_leads_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leads_status ON public.leads USING btree (status);


--
-- Name: idx_leads_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leads_workspace ON public.leads USING btree (workspace_id);


--
-- Name: idx_leave_balances_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_balances_type ON public.leave_balances USING btree (leave_type_id);


--
-- Name: idx_leave_balances_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_balances_user ON public.leave_balances USING btree (user_id);


--
-- Name: idx_leave_balances_user_year; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_balances_user_year ON public.leave_balances USING btree (workspace_id, user_id, fiscal_year);


--
-- Name: idx_leave_balances_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_balances_workspace ON public.leave_balances USING btree (workspace_id);


--
-- Name: idx_leave_requests_approved_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_requests_approved_by ON public.leave_requests USING btree (approved_by) WHERE (approved_by IS NOT NULL);


--
-- Name: idx_leave_requests_dates; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_requests_dates ON public.leave_requests USING btree (start_date, end_date);


--
-- Name: idx_leave_requests_overlap; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_requests_overlap ON public.leave_requests USING btree (workspace_id, user_id, start_date, end_date) WHERE ((status)::text <> ALL (ARRAY[('rejected'::character varying)::text, ('cancelled'::character varying)::text]));


--
-- Name: idx_leave_requests_pending; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_requests_pending ON public.leave_requests USING btree (workspace_id, status) WHERE ((status)::text = 'submitted'::text);


--
-- Name: idx_leave_requests_pending_approval; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_requests_pending_approval ON public.leave_requests USING btree (workspace_id, submitted_at) WHERE ((status)::text = 'submitted'::text);


--
-- Name: INDEX idx_leave_requests_pending_approval; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_leave_requests_pending_approval IS 'HR: pending leave requests for manager approval queue.';


--
-- Name: idx_leave_requests_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_requests_status ON public.leave_requests USING btree (status);


--
-- Name: idx_leave_requests_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_requests_type ON public.leave_requests USING btree (leave_type_id);


--
-- Name: idx_leave_requests_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_requests_user ON public.leave_requests USING btree (user_id);


--
-- Name: idx_leave_requests_user_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_requests_user_status ON public.leave_requests USING btree (workspace_id, user_id, status);


--
-- Name: INDEX idx_leave_requests_user_status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_leave_requests_user_status IS 'HR: employee leave request listing by status (self-service portal).';


--
-- Name: idx_leave_requests_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_requests_workspace ON public.leave_requests USING btree (workspace_id);


--
-- Name: idx_leave_types_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_types_active ON public.leave_types USING btree (workspace_id) WHERE (is_active = true);


--
-- Name: idx_leave_types_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_types_workspace ON public.leave_types USING btree (workspace_id);


--
-- Name: idx_leaves_type_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leaves_type_id ON public.leaves_legacy USING btree (leave_type_id) WHERE (leave_type_id IS NOT NULL);


--
-- Name: idx_loyalty_accounts_ws_contact; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_loyalty_accounts_ws_contact ON public.loyalty_accounts USING btree (workspace_id, contact_id);


--
-- Name: idx_loyalty_transactions_account; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_loyalty_transactions_account ON public.loyalty_transactions USING btree (account_id, created_at);


--
-- Name: idx_manual_pay_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_manual_pay_status ON public.manual_payments USING btree (status);


--
-- Name: idx_manual_pay_ws; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_manual_pay_ws ON public.manual_payments USING btree (workspace_id);


--
-- Name: idx_media_assets_ws_folder; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_media_assets_ws_folder ON public.media_assets USING btree (workspace_id, folder);


--
-- Name: idx_media_assets_ws_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_media_assets_ws_status ON public.media_assets USING btree (workspace_id, status);


--
-- Name: idx_media_gen_ws_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_media_gen_ws_status ON public.media_generation_requests USING btree (workspace_id, status);


--
-- Name: idx_membership_roles_membership; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_membership_roles_membership ON public.membership_roles USING btree (membership_id);


--
-- Name: idx_membership_roles_primary; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_membership_roles_primary ON public.membership_roles USING btree (membership_id) WHERE (is_primary = true);


--
-- Name: idx_membership_roles_role; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_membership_roles_role ON public.membership_roles USING btree (role_id);


--
-- Name: idx_membership_roles_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_membership_roles_workspace ON public.membership_roles USING btree (workspace_id);


--
-- Name: idx_membership_roles_ws_membership; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_membership_roles_ws_membership ON public.membership_roles USING btree (workspace_id, membership_id);


--
-- Name: idx_memberships_branch; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_memberships_branch ON public.workspace_memberships USING btree (branch_id);


--
-- Name: idx_memberships_department; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_memberships_department ON public.workspace_memberships USING btree (department_id);


--
-- Name: idx_memberships_manager; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_memberships_manager ON public.workspace_memberships USING btree (manager_membership_id);


--
-- Name: idx_memberships_shift; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_memberships_shift ON public.workspace_memberships USING btree (shift_id);


--
-- Name: idx_memberships_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_memberships_status ON public.workspace_memberships USING btree (status);


--
-- Name: idx_memberships_status_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_memberships_status_active ON public.workspace_memberships USING btree (workspace_id, user_id) WHERE ((status)::text = 'active'::text);


--
-- Name: idx_memberships_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_memberships_user ON public.workspace_memberships USING btree (user_id);


--
-- Name: idx_memberships_user_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_memberships_user_active ON public.workspace_memberships USING btree (user_id, status) WHERE ((status)::text = 'active'::text);


--
-- Name: INDEX idx_memberships_user_active; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_memberships_user_active IS 'RBAC: fast lookup of active memberships by user_id. Used during login → workspace selection and permission resolution.';


--
-- Name: idx_memberships_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_memberships_workspace ON public.workspace_memberships USING btree (workspace_id);


--
-- Name: idx_memberships_ws_branch; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_memberships_ws_branch ON public.workspace_memberships USING btree (workspace_id, branch_id);


--
-- Name: idx_memberships_ws_dept; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_memberships_ws_dept ON public.workspace_memberships USING btree (workspace_id, department_id);


--
-- Name: idx_memberships_ws_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_memberships_ws_status ON public.workspace_memberships USING btree (workspace_id, status);


--
-- Name: idx_memberships_ws_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_memberships_ws_user ON public.workspace_memberships USING btree (workspace_id, user_id);


--
-- Name: idx_notifications_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notifications_user ON public.notifications USING btree (user_id);


--
-- Name: idx_notifications_user_unread; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notifications_user_unread ON public.notifications USING btree (user_id, created_at DESC) WHERE (is_read = false);


--
-- Name: INDEX idx_notifications_user_unread; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_notifications_user_unread IS 'UI: unread notifications for notification bell badge count.';


--
-- Name: idx_notifications_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notifications_workspace ON public.notifications USING btree (workspace_id);


--
-- Name: idx_opportunities_assigned; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_opportunities_assigned ON public.opportunities USING btree (assigned_to);


--
-- Name: idx_opportunities_stage; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_opportunities_stage ON public.opportunities USING btree (stage);


--
-- Name: idx_opportunities_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_opportunities_workspace ON public.opportunities USING btree (workspace_id);


--
-- Name: idx_order_items_order; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_order_items_order ON public.order_items USING btree (order_id);


--
-- Name: idx_orders_branch; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_orders_branch ON public.orders USING btree (branch_id);


--
-- Name: idx_orders_dining_table; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_orders_dining_table ON public.orders USING btree (dining_table_id);


--
-- Name: idx_orders_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_orders_workspace ON public.orders USING btree (workspace_id);


--
-- Name: idx_orders_ws_contact; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_orders_ws_contact ON public.orders USING btree (workspace_id, contact_id);


--
-- Name: INDEX idx_orders_ws_contact; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_orders_ws_contact IS 'Orders: customer/supplier order history lookup.';


--
-- Name: idx_orders_ws_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_orders_ws_status ON public.orders USING btree (workspace_id, status);


--
-- Name: INDEX idx_orders_ws_status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_orders_ws_status IS 'Orders: order listing by status for processing dashboard.';


--
-- Name: idx_outbound_messages_contact; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_outbound_messages_contact ON public.outbound_messages USING btree (recipient_contact_id);


--
-- Name: idx_outbound_messages_sent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_outbound_messages_sent ON public.outbound_messages USING btree (sent_at) WHERE (sent_at IS NOT NULL);


--
-- Name: idx_outbound_messages_ws_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_outbound_messages_ws_status ON public.outbound_messages USING btree (workspace_id, status);


--
-- Name: idx_overrides_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_overrides_active ON public.user_permission_overrides USING btree (membership_id, permission_key) WHERE (expires_at IS NULL);


--
-- Name: idx_overrides_granted_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_overrides_granted_by ON public.user_permission_overrides USING btree (granted_by_membership_id);


--
-- Name: idx_overrides_membership; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_overrides_membership ON public.user_permission_overrides USING btree (membership_id);


--
-- Name: idx_overrides_membership_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_overrides_membership_active ON public.user_permission_overrides USING btree (membership_id) WHERE (expires_at IS NULL);


--
-- Name: INDEX idx_overrides_membership_active; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_overrides_membership_active IS 'RBAC: fast lookup of active (non-expired) permission overrides for conflict resolution.';


--
-- Name: idx_overrides_permission; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_overrides_permission ON public.user_permission_overrides USING btree (permission_key);


--
-- Name: idx_overrides_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_overrides_type ON public.user_permission_overrides USING btree (override_type);


--
-- Name: idx_overrides_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_overrides_workspace ON public.user_permission_overrides USING btree (workspace_id);


--
-- Name: idx_pat_tokenable; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pat_tokenable ON public.personal_access_tokens USING btree (tokenable_type, tokenable_id);


--
-- Name: idx_payment_tx_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payment_tx_created ON public.payment_transactions USING btree (created_at);


--
-- Name: idx_payment_tx_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payment_tx_status ON public.payment_transactions USING btree (status);


--
-- Name: idx_payment_tx_stripe; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payment_tx_stripe ON public.payment_transactions USING btree (stripe_payment_intent_id);


--
-- Name: idx_payment_tx_ws; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payment_tx_ws ON public.payment_transactions USING btree (workspace_id);


--
-- Name: idx_payments_invoice; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payments_invoice ON public.payments USING btree (invoice_id);


--
-- Name: idx_payments_invoice_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payments_invoice_date ON public.payments USING btree (invoice_id, payment_date);


--
-- Name: INDEX idx_payments_invoice_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_payments_invoice_date IS 'Finance: payment history for an invoice, ordered by date.';


--
-- Name: idx_payments_pos_session; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payments_pos_session ON public.payments USING btree (pos_session_id) WHERE (pos_session_id IS NOT NULL);


--
-- Name: idx_payments_reversal; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payments_reversal ON public.payments USING btree (reversal_of_payment_id) WHERE (reversal_of_payment_id IS NOT NULL);


--
-- Name: INDEX idx_payments_reversal; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_payments_reversal IS 'Finance: sparse index for reversal chain lookups.';


--
-- Name: idx_payments_reversal_of; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payments_reversal_of ON public.payments USING btree (reversal_of_payment_id) WHERE (reversal_of_payment_id IS NOT NULL);


--
-- Name: idx_payments_reversible; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payments_reversible ON public.payments USING btree (workspace_id, id) WHERE (((status)::text = 'completed'::text) AND (is_reversal = false));


--
-- Name: idx_payments_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payments_status ON public.payments USING btree (status);


--
-- Name: idx_payments_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payments_workspace ON public.payments USING btree (workspace_id);


--
-- Name: idx_payments_ws_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payments_ws_date ON public.payments USING btree (workspace_id, payment_date);


--
-- Name: INDEX idx_payments_ws_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_payments_ws_date IS 'Finance: payment reconciliation by date range within workspace.';


--
-- Name: idx_payroll_lines_payroll; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payroll_lines_payroll ON public.payroll_lines USING btree (payroll_id);


--
-- Name: idx_payroll_lines_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payroll_lines_type ON public.payroll_lines USING btree (line_type);


--
-- Name: idx_payroll_lines_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payroll_lines_workspace ON public.payroll_lines USING btree (workspace_id);


--
-- Name: idx_payroll_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payroll_run_id ON public.payroll USING btree (payroll_run_id) WHERE (payroll_run_id IS NOT NULL);


--
-- Name: idx_payroll_runs_latest; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payroll_runs_latest ON public.payroll_runs USING btree (workspace_id, created_at DESC);


--
-- Name: idx_payroll_runs_period; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payroll_runs_period ON public.payroll_runs USING btree (workspace_id, period_start, period_end);


--
-- Name: idx_payroll_runs_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payroll_runs_status ON public.payroll_runs USING btree (status);


--
-- Name: idx_payroll_runs_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payroll_runs_workspace ON public.payroll_runs USING btree (workspace_id);


--
-- Name: idx_payroll_runs_ws_period_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payroll_runs_ws_period_status ON public.payroll_runs USING btree (workspace_id, period_start, status);


--
-- Name: INDEX idx_payroll_runs_ws_period_status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_payroll_runs_ws_period_status IS 'HR: payroll run lookup by period and status.';


--
-- Name: idx_payroll_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payroll_workspace ON public.payroll USING btree (workspace_id);


--
-- Name: idx_perm_defs_module; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_perm_defs_module ON public.permission_definitions USING btree (module);


--
-- Name: idx_perm_defs_scope_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_perm_defs_scope_type ON public.permission_definitions USING btree (scope_type);


--
-- Name: idx_plan_features_plan; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_plan_features_plan ON public.plan_features USING btree (plan_id);


--
-- Name: idx_plan_prices_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_plan_prices_active ON public.platform_plan_prices USING btree (is_active);


--
-- Name: idx_plan_prices_plan; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_plan_prices_plan ON public.platform_plan_prices USING btree (plan_id);


--
-- Name: idx_platform_plans_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_platform_plans_active ON public.platform_plans USING btree (is_active);


--
-- Name: idx_platform_plans_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_platform_plans_slug ON public.platform_plans USING btree (slug);


--
-- Name: idx_po_items_po; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_po_items_po ON public.purchase_order_items USING btree (po_id);


--
-- Name: idx_po_items_product; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_po_items_product ON public.purchase_order_items USING btree (product_id);


--
-- Name: idx_pos_sessions_branch; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pos_sessions_branch ON public.pos_sessions USING btree (branch_id) WHERE (branch_id IS NOT NULL);


--
-- Name: idx_pos_sessions_closed_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pos_sessions_closed_by ON public.pos_sessions USING btree (closed_by) WHERE (closed_by IS NOT NULL);


--
-- Name: idx_pos_sessions_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pos_sessions_status ON public.pos_sessions USING btree (status);


--
-- Name: idx_pos_sessions_terminal; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pos_sessions_terminal ON public.pos_sessions USING btree (terminal_id);


--
-- Name: idx_pos_sessions_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pos_sessions_user ON public.pos_sessions USING btree (user_id);


--
-- Name: idx_pos_sessions_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pos_sessions_workspace ON public.pos_sessions USING btree (workspace_id);


--
-- Name: idx_pos_terminals_branch; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pos_terminals_branch ON public.pos_terminals USING btree (branch_id);


--
-- Name: idx_pos_terminals_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pos_terminals_workspace ON public.pos_terminals USING btree (workspace_id);


--
-- Name: idx_price_list_items_list; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_price_list_items_list ON public.price_list_items USING btree (price_list_id);


--
-- Name: idx_price_list_items_product; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_price_list_items_product ON public.price_list_items USING btree (product_id);


--
-- Name: idx_price_lists_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_price_lists_workspace ON public.price_lists USING btree (workspace_id);


--
-- Name: idx_product_categories_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_product_categories_workspace ON public.product_categories USING btree (workspace_id);


--
-- Name: idx_product_variants_product; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_product_variants_product ON public.product_variants USING btree (product_id);


--
-- Name: idx_production_orders_work_center; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_production_orders_work_center ON public.production_orders USING btree (work_center_id);


--
-- Name: idx_production_orders_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_production_orders_workspace ON public.production_orders USING btree (workspace_id);


--
-- Name: idx_products_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_products_workspace ON public.products USING btree (workspace_id);


--
-- Name: idx_products_ws_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_products_ws_category ON public.products USING btree (workspace_id, category_id);


--
-- Name: INDEX idx_products_ws_category; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_products_ws_category IS 'Products: catalog browsing by category.';


--
-- Name: idx_products_ws_sku; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_products_ws_sku ON public.products USING btree (workspace_id, sku) WHERE (sku IS NOT NULL);


--
-- Name: INDEX idx_products_ws_sku; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_products_ws_sku IS 'Products: fast SKU/barcode lookup for POS and warehouse operations.';


--
-- Name: idx_projects_manager; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_projects_manager ON public.projects USING btree (manager_id);


--
-- Name: idx_projects_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_projects_workspace ON public.projects USING btree (workspace_id);


--
-- Name: idx_promotions_active_dates; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_promotions_active_dates ON public.promotions USING btree (start_date, end_date);


--
-- Name: idx_promotions_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_promotions_workspace ON public.promotions USING btree (workspace_id);


--
-- Name: idx_prov_binding_run; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_prov_binding_run ON public.provisioning_entity_bindings USING btree (last_provisioning_run_id);


--
-- Name: idx_prov_binding_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_prov_binding_workspace ON public.provisioning_entity_bindings USING btree (workspace_id);


--
-- Name: idx_prov_binding_ws_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_prov_binding_ws_type ON public.provisioning_entity_bindings USING btree (workspace_id, entity_type);


--
-- Name: idx_prov_runs_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_prov_runs_status ON public.provisioning_runs USING btree (status);


--
-- Name: idx_prov_runs_ws; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_prov_runs_ws ON public.provisioning_runs USING btree (workspace_id);


--
-- Name: idx_purchase_orders_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_purchase_orders_created ON public.purchase_orders USING btree (workspace_id, created_at DESC);


--
-- Name: idx_purchase_orders_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_purchase_orders_status ON public.purchase_orders USING btree (status);


--
-- Name: idx_purchase_orders_supplier; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_purchase_orders_supplier ON public.purchase_orders USING btree (supplier_contact_id);


--
-- Name: idx_purchase_orders_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_purchase_orders_workspace ON public.purchase_orders USING btree (workspace_id);


--
-- Name: idx_purchase_orders_ws_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_purchase_orders_ws_status ON public.purchase_orders USING btree (workspace_id, status);


--
-- Name: INDEX idx_purchase_orders_ws_status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_purchase_orders_ws_status IS 'Inventory: purchase order listing by status for procurement dashboard.';


--
-- Name: idx_recurring_expenses_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_recurring_expenses_workspace ON public.recurring_expenses USING btree (workspace_id);


--
-- Name: idx_referrals_ws_code; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_referrals_ws_code ON public.referrals USING btree (workspace_id, referral_code);


--
-- Name: idx_reservations_order_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_reservations_order_active ON public.stock_reservations USING btree (order_id, status) WHERE ((status)::text = 'active'::text);


--
-- Name: INDEX idx_reservations_order_active; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_reservations_order_active IS 'Inventory: active reservations for an order (fulfillment processing).';


--
-- Name: idx_return_items_product; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_return_items_product ON public.return_items USING btree (product_id);


--
-- Name: idx_return_items_return; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_return_items_return ON public.return_items USING btree (return_id);


--
-- Name: idx_returns_contact; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_returns_contact ON public.returns USING btree (contact_id);


--
-- Name: idx_returns_order; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_returns_order ON public.returns USING btree (order_id) WHERE (order_id IS NOT NULL);


--
-- Name: idx_returns_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_returns_status ON public.returns USING btree (status);


--
-- Name: idx_returns_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_returns_type ON public.returns USING btree (return_type);


--
-- Name: idx_returns_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_returns_workspace ON public.returns USING btree (workspace_id);


--
-- Name: idx_roles_hierarchy; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_roles_hierarchy ON public.roles USING btree (hierarchy_level);


--
-- Name: idx_roles_permissions_gin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_roles_permissions_gin ON public.roles USING gin (permissions jsonb_path_ops);


--
-- Name: INDEX idx_roles_permissions_gin; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_roles_permissions_gin IS 'RBAC: GIN index for JSONB containment queries on role permissions. Enables fast lookups like: which roles grant a specific permission key?';


--
-- Name: idx_roles_role_key; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_roles_role_key ON public.roles USING btree (role_key) WHERE (role_key IS NOT NULL);


--
-- Name: idx_roles_system; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_roles_system ON public.roles USING btree (is_system) WHERE (is_system = true);


--
-- Name: idx_roles_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_roles_workspace ON public.roles USING btree (workspace_id);


--
-- Name: idx_roles_ws_hierarchy; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_roles_ws_hierarchy ON public.roles USING btree (workspace_id, hierarchy_level DESC);


--
-- Name: INDEX idx_roles_ws_hierarchy; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_roles_ws_hierarchy IS 'RBAC: role listing ordered by hierarchy for assignment authority checks.';


--
-- Name: idx_segment_contacts_segment; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_segment_contacts_segment ON public.segment_contacts USING btree (segment_id);


--
-- Name: idx_segments_ws; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_segments_ws ON public.segments USING btree (workspace_id);


--
-- Name: idx_shift_assignments_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_shift_assignments_active ON public.shift_assignments USING btree (workspace_id, user_id, effective_date) WHERE (end_date IS NULL);


--
-- Name: idx_shift_assignments_dates; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_shift_assignments_dates ON public.shift_assignments USING btree (effective_date, end_date);


--
-- Name: idx_shift_assignments_shift; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_shift_assignments_shift ON public.shift_assignments USING btree (shift_id);


--
-- Name: idx_shift_assignments_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_shift_assignments_user ON public.shift_assignments USING btree (user_id);


--
-- Name: idx_shift_assignments_user_current; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_shift_assignments_user_current ON public.shift_assignments USING btree (workspace_id, user_id, effective_date);


--
-- Name: INDEX idx_shift_assignments_user_current; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_shift_assignments_user_current IS 'HR: current shift assignment lookup for a user.';


--
-- Name: idx_shift_assignments_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_shift_assignments_workspace ON public.shift_assignments USING btree (workspace_id);


--
-- Name: idx_shifts_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_shifts_workspace ON public.shifts USING btree (workspace_id);


--
-- Name: idx_shipment_items_order_item; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_shipment_items_order_item ON public.shipment_items USING btree (order_item_id) WHERE (order_item_id IS NOT NULL);


--
-- Name: idx_shipment_items_product; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_shipment_items_product ON public.shipment_items USING btree (product_id);


--
-- Name: idx_shipment_items_reservation; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_shipment_items_reservation ON public.shipment_items USING btree (reservation_id) WHERE (reservation_id IS NOT NULL);


--
-- Name: idx_shipment_items_shipment; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_shipment_items_shipment ON public.shipment_items USING btree (shipment_id);


--
-- Name: idx_shipment_items_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_shipment_items_workspace ON public.shipment_items USING btree (workspace_id);


--
-- Name: idx_shipments_driver; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_shipments_driver ON public.shipments USING btree (delivery_driver_id);


--
-- Name: idx_shipments_order; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_shipments_order ON public.shipments USING btree (order_id) WHERE (order_id IS NOT NULL);


--
-- Name: idx_shipments_return; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_shipments_return ON public.shipments USING btree (return_id) WHERE (return_id IS NOT NULL);


--
-- Name: idx_shipments_warehouse; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_shipments_warehouse ON public.shipments USING btree (warehouse_id) WHERE (warehouse_id IS NOT NULL);


--
-- Name: idx_shipments_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_shipments_workspace ON public.shipments USING btree (workspace_id);


--
-- Name: idx_shipments_ws_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_shipments_ws_status ON public.shipments USING btree (workspace_id, status);


--
-- Name: INDEX idx_shipments_ws_status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.idx_shipments_ws_status IS 'Shipments: logistics dashboard — shipments by delivery status.';


--
-- Name: idx_stock_reservations_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_stock_reservations_active ON public.stock_reservations USING btree (workspace_id, status) WHERE ((status)::text = 'active'::text);


--
-- Name: idx_stock_reservations_order; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_stock_reservations_order ON public.stock_reservations USING btree (order_id);


--
-- Name: idx_stock_reservations_order_item; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_stock_reservations_order_item ON public.stock_reservations USING btree (order_item_id);


--
-- Name: idx_stock_reservations_product; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_stock_reservations_product ON public.stock_reservations USING btree (product_id);


--
-- Name: idx_stock_reservations_warehouse; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_stock_reservations_warehouse ON public.stock_reservations USING btree (warehouse_id);


--
-- Name: idx_stock_reservations_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_stock_reservations_workspace ON public.stock_reservations USING btree (workspace_id);


--
-- Name: idx_stock_transfer_items_transfer; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_stock_transfer_items_transfer ON public.stock_transfer_items USING btree (transfer_id);


--
-- Name: idx_stock_transfers_from; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_stock_transfers_from ON public.stock_transfers USING btree (from_warehouse_id);


--
-- Name: idx_stock_transfers_to; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_stock_transfers_to ON public.stock_transfers USING btree (to_warehouse_id);


--
-- Name: idx_stock_transfers_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_stock_transfers_workspace ON public.stock_transfers USING btree (workspace_id);


--
-- Name: idx_subscription_plans_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_subscription_plans_active ON public.subscription_plans USING btree (is_active) WHERE (is_active = true);


--
-- Name: idx_subscription_plans_tier; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_subscription_plans_tier ON public.subscription_plans USING btree (tier);


--
-- Name: idx_survey_responses_survey; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_survey_responses_survey ON public.platform_survey_responses USING btree (survey_id);


--
-- Name: idx_surveys_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_surveys_status ON public.platform_surveys USING btree (status);


--
-- Name: idx_sync_logs_ws_integration; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sync_logs_ws_integration ON public.sync_logs USING btree (workspace_id, integration_id, created_at);


--
-- Name: idx_tasks_assigned; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tasks_assigned ON public.tasks USING btree (assigned_to);


--
-- Name: idx_tasks_project; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tasks_project ON public.tasks USING btree (project_id);


--
-- Name: idx_tasks_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tasks_workspace ON public.tasks USING btree (workspace_id);


--
-- Name: idx_tax_rules_ws_effective; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tax_rules_ws_effective ON public.tax_rules USING btree (workspace_id, effective_from, effective_to);


--
-- Name: idx_taxes_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_taxes_workspace ON public.taxes USING btree (workspace_id);


--
-- Name: idx_transactions_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_transactions_workspace ON public.transactions USING btree (workspace_id);


--
-- Name: idx_translations_key; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_translations_key ON public.translations USING btree (key);


--
-- Name: idx_translations_locale_ns; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_translations_locale_ns ON public.translations USING btree (locale, namespace);


--
-- Name: idx_units_of_measure_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_units_of_measure_workspace ON public.units_of_measure USING btree (workspace_id);


--
-- Name: idx_users_email_login; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_email_login ON public.users USING btree (email) WHERE ((email IS NOT NULL) AND (is_active = true));


--
-- Name: idx_users_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_workspace ON public.users USING btree (workspace_id_deprecated);


--
-- Name: idx_warehouses_branch; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_warehouses_branch ON public.warehouses USING btree (branch_id);


--
-- Name: idx_webhook_deliveries_sub_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_webhook_deliveries_sub_status ON public.webhook_deliveries USING btree (subscription_id, status);


--
-- Name: idx_webhook_events_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_webhook_events_status ON public.webhook_events USING btree (status);


--
-- Name: idx_webhook_events_stripe; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_webhook_events_stripe ON public.webhook_events USING btree (stripe_event_id);


--
-- Name: idx_webhook_events_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_webhook_events_type ON public.webhook_events USING btree (event_type);


--
-- Name: idx_webhook_subscriptions_ws_event; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_webhook_subscriptions_ws_event ON public.webhook_subscriptions USING btree (workspace_id, event_type);


--
-- Name: idx_work_centers_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_work_centers_workspace ON public.work_centers USING btree (workspace_id);


--
-- Name: idx_workspace_country_packs_ws; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_workspace_country_packs_ws ON public.workspace_country_packs USING btree (workspace_id);


--
-- Name: idx_workspace_integrations_ws; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_workspace_integrations_ws ON public.workspace_integrations USING btree (workspace_id);


--
-- Name: idx_workspace_invitations_department; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_workspace_invitations_department ON public.workspace_invitations USING btree (workspace_id, department_id);


--
-- Name: idx_workspace_invitations_team; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_workspace_invitations_team ON public.workspace_invitations USING btree (workspace_id, team_id);


--
-- Name: idx_workspaces_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_workspaces_status ON public.workspaces USING btree (status);


--
-- Name: idx_workspaces_status_subscription; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_workspaces_status_subscription ON public.workspaces USING btree (status, subscription_status);


--
-- Name: idx_ws_config_ws; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ws_config_ws ON public.workspace_configurations USING btree (workspace_id);


--
-- Name: idx_ws_feature_flags; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ws_feature_flags ON public.workspace_feature_flags USING btree (workspace_id);


--
-- Name: idx_ws_sub_stripe_cust; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ws_sub_stripe_cust ON public.workspace_subscriptions USING btree (stripe_customer_id);


--
-- Name: idx_ws_sub_stripe_sub; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ws_sub_stripe_sub ON public.workspace_subscriptions USING btree (stripe_subscription_id);


--
-- Name: idx_ws_subscriptions_plan; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ws_subscriptions_plan ON public.workspace_subscriptions USING btree (plan_id);


--
-- Name: idx_ws_subscriptions_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ws_subscriptions_status ON public.workspace_subscriptions USING btree (status);


--
-- Name: idx_ws_subscriptions_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ws_subscriptions_workspace ON public.workspace_subscriptions USING btree (workspace_id);


--
-- Name: ownership_assignments_department_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ownership_assignments_department_id_index ON public.ownership_assignments USING btree (department_id);


--
-- Name: ownership_assignments_entity_type_entity_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ownership_assignments_entity_type_entity_id_index ON public.ownership_assignments USING btree (entity_type, entity_id);


--
-- Name: ownership_assignments_owner_membership_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ownership_assignments_owner_membership_id_index ON public.ownership_assignments USING btree (owner_membership_id);


--
-- Name: ownership_assignments_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ownership_assignments_status_index ON public.ownership_assignments USING btree (status);


--
-- Name: ownership_assignments_team_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ownership_assignments_team_id_index ON public.ownership_assignments USING btree (team_id);


--
-- Name: ownership_assignments_workspace_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ownership_assignments_workspace_id_index ON public.ownership_assignments USING btree (workspace_id);


--
-- Name: ownership_transfer_logs_entity_type_entity_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ownership_transfer_logs_entity_type_entity_id_index ON public.ownership_transfer_logs USING btree (entity_type, entity_id);


--
-- Name: ownership_transfer_logs_from_membership_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ownership_transfer_logs_from_membership_id_index ON public.ownership_transfer_logs USING btree (from_membership_id);


--
-- Name: ownership_transfer_logs_to_membership_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ownership_transfer_logs_to_membership_id_index ON public.ownership_transfer_logs USING btree (to_membership_id);


--
-- Name: ownership_transfer_logs_transferred_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ownership_transfer_logs_transferred_at_index ON public.ownership_transfer_logs USING btree (transferred_at);


--
-- Name: ownership_transfer_logs_workspace_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ownership_transfer_logs_workspace_id_index ON public.ownership_transfer_logs USING btree (workspace_id);


--
-- Name: pipeline_records_assigned_membership_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pipeline_records_assigned_membership_id_index ON public.pipeline_records USING btree (assigned_membership_id);


--
-- Name: pipeline_records_pipeline_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pipeline_records_pipeline_id_index ON public.pipeline_records USING btree (pipeline_id);


--
-- Name: pipeline_records_stage_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pipeline_records_stage_id_index ON public.pipeline_records USING btree (stage_id);


--
-- Name: pipeline_records_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pipeline_records_status_index ON public.pipeline_records USING btree (status);


--
-- Name: pipeline_records_workspace_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pipeline_records_workspace_id_index ON public.pipeline_records USING btree (workspace_id);


--
-- Name: pipeline_stages_is_active_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pipeline_stages_is_active_index ON public.pipeline_stages USING btree (is_active);


--
-- Name: pipeline_stages_pipeline_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pipeline_stages_pipeline_id_index ON public.pipeline_stages USING btree (pipeline_id);


--
-- Name: pipeline_stages_workspace_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pipeline_stages_workspace_id_index ON public.pipeline_stages USING btree (workspace_id);


--
-- Name: pipelines_entity_type_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pipelines_entity_type_index ON public.pipelines USING btree (entity_type);


--
-- Name: pipelines_is_active_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pipelines_is_active_index ON public.pipelines USING btree (is_active);


--
-- Name: pipelines_workspace_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pipelines_workspace_id_index ON public.pipelines USING btree (workspace_id);


--
-- Name: platform_activation_campaigns_created_by_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX platform_activation_campaigns_created_by_user_id_index ON public.platform_activation_campaigns USING btree (created_by_user_id);


--
-- Name: platform_activation_campaigns_expires_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX platform_activation_campaigns_expires_at_index ON public.platform_activation_campaigns USING btree (expires_at);


--
-- Name: platform_activation_campaigns_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX platform_activation_campaigns_status_index ON public.platform_activation_campaigns USING btree (status);


--
-- Name: platform_activation_codes_assigned_to_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX platform_activation_codes_assigned_to_name_index ON public.platform_activation_codes USING btree (assigned_to_name);


--
-- Name: platform_activation_codes_campaign_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX platform_activation_codes_campaign_id_index ON public.platform_activation_codes USING btree (campaign_id);


--
-- Name: platform_activation_codes_expires_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX platform_activation_codes_expires_at_index ON public.platform_activation_codes USING btree (expires_at);


--
-- Name: platform_activation_codes_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX platform_activation_codes_status_index ON public.platform_activation_codes USING btree (status);


--
-- Name: platform_activation_codes_used_by_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX platform_activation_codes_used_by_user_id_index ON public.platform_activation_codes USING btree (used_by_user_id);


--
-- Name: platform_activation_codes_used_workspace_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX platform_activation_codes_used_workspace_id_index ON public.platform_activation_codes USING btree (used_workspace_id);


--
-- Name: record_documents_document_checklist_item_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX record_documents_document_checklist_item_id_index ON public.record_documents USING btree (document_checklist_item_id);


--
-- Name: record_documents_pipeline_record_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX record_documents_pipeline_record_id_index ON public.record_documents USING btree (pipeline_record_id);


--
-- Name: record_documents_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX record_documents_status_index ON public.record_documents USING btree (status);


--
-- Name: record_documents_workspace_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX record_documents_workspace_id_index ON public.record_documents USING btree (workspace_id);


--
-- Name: report_runs_data_source_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX report_runs_data_source_index ON public.report_runs USING btree (data_source);


--
-- Name: report_runs_report_template_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX report_runs_report_template_id_index ON public.report_runs USING btree (report_template_id);


--
-- Name: report_runs_run_by_membership_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX report_runs_run_by_membership_id_index ON public.report_runs USING btree (run_by_membership_id);


--
-- Name: report_runs_started_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX report_runs_started_at_index ON public.report_runs USING btree (started_at);


--
-- Name: report_runs_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX report_runs_status_index ON public.report_runs USING btree (status);


--
-- Name: report_runs_workspace_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX report_runs_workspace_id_index ON public.report_runs USING btree (workspace_id);


--
-- Name: report_templates_created_by_membership_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX report_templates_created_by_membership_id_index ON public.report_templates USING btree (created_by_membership_id);


--
-- Name: report_templates_data_source_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX report_templates_data_source_index ON public.report_templates USING btree (data_source);


--
-- Name: report_templates_is_active_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX report_templates_is_active_index ON public.report_templates USING btree (is_active);


--
-- Name: report_templates_visibility_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX report_templates_visibility_index ON public.report_templates USING btree (visibility);


--
-- Name: report_templates_workspace_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX report_templates_workspace_id_index ON public.report_templates USING btree (workspace_id);


--
-- Name: teams_department_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX teams_department_id_index ON public.teams USING btree (department_id);


--
-- Name: teams_is_active_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX teams_is_active_index ON public.teams USING btree (is_active);


--
-- Name: teams_workspace_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX teams_workspace_id_index ON public.teams USING btree (workspace_id);


--
-- Name: uq_ai_memory_ws_type_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_ai_memory_ws_type_key ON public.ai_memory USING btree (workspace_id, COALESCE(user_id, '00000000-0000-0000-0000-000000000000'::uuid), memory_type, key);


--
-- Name: uq_ai_rec_dedup; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_ai_rec_dedup ON public.ai_recommendations USING btree (workspace_id, dedup_key) WHERE (dedup_key IS NOT NULL);


--
-- Name: uq_email_logs_dedup; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_email_logs_dedup ON public.email_logs USING btree (workspace_id, dedup_key) WHERE (dedup_key IS NOT NULL);


--
-- Name: uq_inventory_no_variant; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_inventory_no_variant ON public.inventory_levels USING btree (warehouse_id, product_id) WHERE (variant_id IS NULL);


--
-- Name: uq_inventory_with_variant; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_inventory_with_variant ON public.inventory_levels USING btree (warehouse_id, product_id, variant_id) WHERE (variant_id IS NOT NULL);


--
-- Name: uq_membership_roles_primary; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_membership_roles_primary ON public.membership_roles USING btree (membership_id) WHERE (is_primary = true);


--
-- Name: uq_payments_one_reversal_per_original; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_payments_one_reversal_per_original ON public.payments USING btree (reversal_of_payment_id) WHERE (reversal_of_payment_id IS NOT NULL);


--
-- Name: uq_pos_sessions_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_pos_sessions_number ON public.pos_sessions USING btree (workspace_id, session_number) WHERE (session_number IS NOT NULL);


--
-- Name: uq_price_list_no_variant; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_price_list_no_variant ON public.price_list_items USING btree (price_list_id, product_id) WHERE (variant_id IS NULL);


--
-- Name: uq_price_list_with_variant; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_price_list_with_variant ON public.price_list_items USING btree (price_list_id, product_id, variant_id) WHERE (variant_id IS NOT NULL);


--
-- Name: uq_roles_role_key_per_workspace; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_roles_role_key_per_workspace ON public.roles USING btree (workspace_id, role_key) WHERE (role_key IS NOT NULL);


--
-- Name: uq_users_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_users_email ON public.users USING btree (email) WHERE (email IS NOT NULL);


--
-- Name: uq_users_ws_deprecated_phone; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_users_ws_deprecated_phone ON public.users USING btree (workspace_id_deprecated, phone_number);


--
-- Name: workspace_invitation_roles_role_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX workspace_invitation_roles_role_id_index ON public.workspace_invitation_roles USING btree (role_id);


--
-- Name: workspace_invitation_roles_workspace_invitation_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX workspace_invitation_roles_workspace_invitation_id_index ON public.workspace_invitation_roles USING btree (workspace_invitation_id);


--
-- Name: workspace_invitations_email_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX workspace_invitations_email_index ON public.workspace_invitations USING btree (email);


--
-- Name: workspace_invitations_expires_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX workspace_invitations_expires_at_index ON public.workspace_invitations USING btree (expires_at);


--
-- Name: workspace_invitations_pending_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX workspace_invitations_pending_unique ON public.workspace_invitations USING btree (workspace_id, lower((email)::text)) WHERE ((status)::text = 'pending'::text);


--
-- Name: workspace_invitations_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX workspace_invitations_status_index ON public.workspace_invitations USING btree (status);


--
-- Name: workspace_invitations_workspace_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX workspace_invitations_workspace_id_index ON public.workspace_invitations USING btree (workspace_id);


--
-- Name: discovery_blueprints set_updated_at_discovery_blueprints; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at_discovery_blueprints BEFORE UPDATE ON public.discovery_blueprints FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: discovery_sessions set_updated_at_discovery_sessions; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_updated_at_discovery_sessions BEFORE UPDATE ON public.discovery_sessions FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: ai_change_requests trg_ai_change_requests_ws_fk; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_ai_change_requests_ws_fk BEFORE INSERT OR UPDATE ON public.ai_change_requests FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('conversation_id:ai_conversations');


--
-- Name: ai_credit_balances trg_ai_credit_balances_updated; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_ai_credit_balances_updated BEFORE UPDATE ON public.ai_credit_balances FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();


--
-- Name: async_jobs trg_async_jobs_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_async_jobs_ws_check BEFORE INSERT OR UPDATE ON public.async_jobs FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('user_id:users');


--
-- Name: attendance trg_attendance_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_attendance_updated_at BEFORE UPDATE ON public.attendance FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: attendance trg_attendance_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_attendance_ws_check BEFORE INSERT OR UPDATE ON public.attendance FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('user_id:users,shift_id:shifts,shift_assignment_id:shift_assignments,adjustment_approved_by:users');


--
-- Name: inventory_batches trg_batches_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_batches_ws_check BEFORE INSERT OR UPDATE ON public.inventory_batches FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('warehouse_id:warehouses,product_id:products');


--
-- Name: billing_invoices trg_billing_invoices_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_billing_invoices_updated_at BEFORE UPDATE ON public.billing_invoices FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: billing_invoices trg_billing_invoices_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_billing_invoices_ws_check BEFORE INSERT OR UPDATE ON public.billing_invoices FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('subscription_id:workspace_subscriptions');


--
-- Name: billing_payments trg_billing_payments_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_billing_payments_ws_check BEFORE INSERT OR UPDATE ON public.billing_payments FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('billing_invoice_id:billing_invoices');


--
-- Name: bookings trg_bookings_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_bookings_updated_at BEFORE UPDATE ON public.bookings FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: bookings trg_bookings_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_bookings_ws_check BEFORE INSERT OR UPDATE ON public.bookings FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('branch_id:branches,contact_id:contacts,assigned_to:users,product_id:products,invoice_id:invoices');


--
-- Name: branches trg_branches_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_branches_updated_at BEFORE UPDATE ON public.branches FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: journal_lines trg_check_journal_balance; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER trg_check_journal_balance AFTER INSERT OR DELETE OR UPDATE ON public.journal_lines DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.check_journal_balance();


--
-- Name: workspace_memberships trg_check_owner_membership_active; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_check_owner_membership_active BEFORE UPDATE ON public.workspace_memberships FOR EACH ROW EXECUTE FUNCTION public.check_owner_membership_active();


--
-- Name: membership_roles trg_check_workspace_owner_exists; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_check_workspace_owner_exists BEFORE DELETE OR UPDATE ON public.membership_roles FOR EACH ROW EXECUTE FUNCTION public.check_workspace_owner_exists();


--
-- Name: contacts trg_contacts_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_contacts_updated_at BEFORE UPDATE ON public.contacts FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: coupons trg_coupons_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_coupons_updated_at BEFORE UPDATE ON public.coupons FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: coupons trg_coupons_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_coupons_ws_check BEFORE INSERT OR UPDATE ON public.coupons FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('promotion_id:promotions');


--
-- Name: credit_note_items trg_credit_note_items_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_credit_note_items_ws_check BEFORE INSERT OR UPDATE ON public.credit_note_items FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('credit_note_id:credit_notes,product_id:products,warehouse_id:warehouses');


--
-- Name: credit_notes trg_credit_notes_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_credit_notes_updated_at BEFORE UPDATE ON public.credit_notes FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: credit_notes trg_credit_notes_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_credit_notes_ws_check BEFORE INSERT OR UPDATE ON public.credit_notes FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('branch_id:branches,original_invoice_id:invoices,contact_id:contacts,created_by:users,reversal_journal_entry_id:journal_entries');


--
-- Name: crm_activities trg_crm_activities_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_crm_activities_ws_check BEFORE INSERT OR UPDATE ON public.crm_activities FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('user_id:users,lead_id:leads,opportunity_id:opportunities,contact_id:contacts');


--
-- Name: customer_credits trg_customer_credits_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_customer_credits_ws_check BEFORE INSERT OR UPDATE ON public.customer_credits FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('contact_id:contacts,payment_id:payments,credit_note_id:credit_notes,invoice_id:invoices,created_by:users');


--
-- Name: customer_subscriptions trg_customer_subscriptions_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_customer_subscriptions_updated_at BEFORE UPDATE ON public.customer_subscriptions FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: permission_delegations trg_delegations_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_delegations_ws_check BEFORE INSERT OR UPDATE ON public.permission_delegations FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('delegator_membership_id:workspace_memberships,delegate_membership_id:workspace_memberships');


--
-- Name: departments trg_departments_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_departments_updated_at BEFORE UPDATE ON public.departments FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: dining_tables trg_dining_tables_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_dining_tables_ws_check BEFORE INSERT OR UPDATE ON public.dining_tables FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('branch_id:branches');


--
-- Name: document_sequences trg_document_sequences_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_document_sequences_updated_at BEFORE UPDATE ON public.document_sequences FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: fiscal_periods trg_fiscal_periods_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_fiscal_periods_updated_at BEFORE UPDATE ON public.fiscal_periods FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: fiscal_periods trg_fiscal_periods_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_fiscal_periods_ws_check BEFORE INSERT OR UPDATE ON public.fiscal_periods FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('closed_by:users,locked_by:users,last_reopened_by:users');


--
-- Name: fixed_assets trg_fixed_assets_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_fixed_assets_updated_at BEFORE UPDATE ON public.fixed_assets FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: goods_received_notes trg_goods_received_notes_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_goods_received_notes_updated_at BEFORE UPDATE ON public.goods_received_notes FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: grn_items trg_grn_items_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_grn_items_ws_check BEFORE INSERT OR UPDATE ON public.grn_items FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('grn_id:goods_received_notes,po_item_id:purchase_order_items,product_id:products');


--
-- Name: goods_received_notes trg_grn_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_grn_ws_check BEFORE INSERT OR UPDATE ON public.goods_received_notes FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('po_id:purchase_orders,warehouse_id:warehouses,received_by:users');


--
-- Name: idempotency_keys trg_idempotency_keys_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_idempotency_keys_ws_check BEFORE INSERT OR UPDATE ON public.idempotency_keys FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('user_id:users');


--
-- Name: inventory_batches trg_inventory_batches_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_inventory_batches_updated_at BEFORE UPDATE ON public.inventory_batches FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: inventory_levels trg_inventory_levels_sync_available; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_inventory_levels_sync_available BEFORE INSERT OR UPDATE ON public.inventory_levels FOR EACH ROW EXECUTE FUNCTION public.sync_inventory_available();


--
-- Name: inventory_levels trg_inventory_levels_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_inventory_levels_updated_at BEFORE UPDATE ON public.inventory_levels FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: inventory_logs_legacy trg_inventory_logs_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_inventory_logs_ws_check BEFORE INSERT OR UPDATE ON public.inventory_logs_legacy FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('warehouse_id:warehouses,product_id:products,user_id:users');


--
-- Name: inventory_movements trg_inventory_movements_no_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_inventory_movements_no_update BEFORE UPDATE ON public.inventory_movements FOR EACH ROW EXECUTE FUNCTION public.prevent_immutable_update();


--
-- Name: inventory_movements trg_inventory_movements_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_inventory_movements_ws_check BEFORE INSERT OR UPDATE ON public.inventory_movements FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('warehouse_id:warehouses,product_id:products,created_by:users');


--
-- Name: invoices trg_invoices_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_invoices_updated_at BEFORE UPDATE ON public.invoices FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: invoices trg_invoices_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_invoices_ws_check BEFORE INSERT OR UPDATE ON public.invoices FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('branch_id:branches,created_by:users,contact_id:contacts,order_id:orders');


--
-- Name: leads trg_leads_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_leads_updated_at BEFORE UPDATE ON public.leads FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: leads trg_leads_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_leads_ws_check BEFORE INSERT OR UPDATE ON public.leads FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('assigned_to:users,converted_contact_id:contacts');


--
-- Name: leave_balances trg_leave_balances_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_leave_balances_updated_at BEFORE UPDATE ON public.leave_balances FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: leave_balances trg_leave_balances_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_leave_balances_ws_check BEFORE INSERT OR UPDATE ON public.leave_balances FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('user_id:users,leave_type_id:leave_types');


--
-- Name: leave_requests trg_leave_requests_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_leave_requests_updated_at BEFORE UPDATE ON public.leave_requests FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: leave_requests trg_leave_requests_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_leave_requests_ws_check BEFORE INSERT OR UPDATE ON public.leave_requests FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('user_id:users,leave_type_id:leave_types,approved_by:users,rejected_by:users,cancelled_by:users');


--
-- Name: leave_types trg_leave_types_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_leave_types_updated_at BEFORE UPDATE ON public.leave_types FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: leave_types trg_leave_types_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_leave_types_ws_check BEFORE INSERT OR UPDATE ON public.leave_types FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk();


--
-- Name: leaves_legacy trg_leaves_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_leaves_ws_check BEFORE INSERT OR UPDATE ON public.leaves_legacy FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('user_id:users,leave_type_id:leave_types');


--
-- Name: membership_roles trg_membership_roles_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_membership_roles_ws_check BEFORE INSERT OR UPDATE ON public.membership_roles FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('membership_id:workspace_memberships,role_id:roles');


--
-- Name: workspace_memberships trg_memberships_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_memberships_ws_check BEFORE INSERT OR UPDATE ON public.workspace_memberships FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('department_id:departments,branch_id:branches,shift_id:shifts,manager_membership_id:workspace_memberships');


--
-- Name: opportunities trg_opportunities_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_opportunities_updated_at BEFORE UPDATE ON public.opportunities FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: opportunities trg_opportunities_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_opportunities_ws_check BEFORE INSERT OR UPDATE ON public.opportunities FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('lead_id:leads,contact_id:contacts,assigned_to:users');


--
-- Name: orders trg_orders_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_orders_updated_at BEFORE UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: orders trg_orders_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_orders_ws_check BEFORE INSERT OR UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('branch_id:branches,created_by:users,contact_id:contacts');


--
-- Name: user_permission_overrides trg_overrides_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_overrides_ws_check BEFORE INSERT OR UPDATE ON public.user_permission_overrides FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('membership_id:workspace_memberships,granted_by_membership_id:workspace_memberships');


--
-- Name: payments trg_payments_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_payments_updated_at BEFORE UPDATE ON public.payments FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: payments trg_payments_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_payments_ws_check BEFORE INSERT OR UPDATE ON public.payments FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('invoice_id:invoices,account_id:accounts,created_by:users,reversal_of_payment_id:payments,reversed_by:users,pos_session_id:pos_sessions');


--
-- Name: payroll_lines trg_payroll_lines_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_payroll_lines_ws_check BEFORE INSERT OR UPDATE ON public.payroll_lines FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('payroll_id:payroll');


--
-- Name: payroll_runs trg_payroll_runs_lock_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_payroll_runs_lock_guard BEFORE UPDATE ON public.payroll_runs FOR EACH ROW EXECUTE FUNCTION public.prevent_locked_payroll_run_modification();


--
-- Name: payroll_runs trg_payroll_runs_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_payroll_runs_updated_at BEFORE UPDATE ON public.payroll_runs FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: payroll_runs trg_payroll_runs_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_payroll_runs_ws_check BEFORE INSERT OR UPDATE ON public.payroll_runs FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('department_id:departments,branch_id:branches,calculated_by:users,approved_by:users,disbursed_by:users,locked_by:users,journal_entry_id:journal_entries');


--
-- Name: payroll trg_payroll_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_payroll_ws_check BEFORE INSERT OR UPDATE ON public.payroll FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('user_id:users,payroll_run_id:payroll_runs');


--
-- Name: permission_delegations trg_permission_delegations_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_permission_delegations_updated_at BEFORE UPDATE ON public.permission_delegations FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: platform_plan_prices trg_plan_prices_updated; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_plan_prices_updated BEFORE UPDATE ON public.platform_plan_prices FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();


--
-- Name: platform_broadcasts trg_platform_broadcasts_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_platform_broadcasts_updated_at BEFORE UPDATE ON public.platform_broadcasts FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: platform_feature_requests trg_platform_feature_requests_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_platform_feature_requests_updated_at BEFORE UPDATE ON public.platform_feature_requests FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: platform_plans trg_platform_plans_updated; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_platform_plans_updated BEFORE UPDATE ON public.platform_plans FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();


--
-- Name: platform_surveys trg_platform_surveys_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_platform_surveys_updated_at BEFORE UPDATE ON public.platform_surveys FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: platform_users trg_platform_users_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_platform_users_updated_at BEFORE UPDATE ON public.platform_users FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: purchase_order_items trg_po_items_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_po_items_ws_check BEFORE INSERT OR UPDATE ON public.purchase_order_items FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('po_id:purchase_orders,product_id:products');


--
-- Name: pos_sessions trg_pos_sessions_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_pos_sessions_updated_at BEFORE UPDATE ON public.pos_sessions FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: pos_sessions trg_pos_sessions_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_pos_sessions_ws_check BEFORE INSERT OR UPDATE ON public.pos_sessions FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('terminal_id:pos_terminals,user_id:users,branch_id:branches,closed_by:users');


--
-- Name: pos_terminals trg_pos_terminals_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_pos_terminals_updated_at BEFORE UPDATE ON public.pos_terminals FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: pos_terminals trg_pos_terminals_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_pos_terminals_ws_check BEFORE INSERT OR UPDATE ON public.pos_terminals FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('branch_id:branches');


--
-- Name: product_categories trg_product_categories_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_product_categories_updated_at BEFORE UPDATE ON public.product_categories FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: product_variants trg_product_variants_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_product_variants_updated_at BEFORE UPDATE ON public.product_variants FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: production_orders trg_production_orders_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_production_orders_updated_at BEFORE UPDATE ON public.production_orders FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: production_orders trg_production_orders_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_production_orders_ws_check BEFORE INSERT OR UPDATE ON public.production_orders FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('created_by:users,product_id:products,warehouse_id:warehouses,work_center_id:work_centers');


--
-- Name: products trg_products_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_products_updated_at BEFORE UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: products trg_products_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_products_ws_check BEFORE INSERT OR UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('category_id:product_categories,tax_id:taxes');


--
-- Name: projects trg_projects_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_projects_updated_at BEFORE UPDATE ON public.projects FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: projects trg_projects_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_projects_ws_check BEFORE INSERT OR UPDATE ON public.projects FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('contact_id:contacts,manager_id:users');


--
-- Name: promotions trg_promotions_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_promotions_updated_at BEFORE UPDATE ON public.promotions FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: purchase_orders trg_purchase_orders_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_purchase_orders_updated_at BEFORE UPDATE ON public.purchase_orders FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: purchase_orders trg_purchase_orders_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_purchase_orders_ws_check BEFORE INSERT OR UPDATE ON public.purchase_orders FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('supplier_contact_id:contacts,branch_id:branches,created_by:users,approved_by:users');


--
-- Name: recurring_expenses trg_recurring_expenses_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_recurring_expenses_updated_at BEFORE UPDATE ON public.recurring_expenses FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: stock_reservations trg_reservation_lifecycle_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_reservation_lifecycle_guard BEFORE UPDATE ON public.stock_reservations FOR EACH ROW EXECUTE FUNCTION public.guard_reservation_lifecycle();


--
-- Name: return_items trg_return_items_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_return_items_ws_check BEFORE INSERT OR UPDATE ON public.return_items FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('return_id:returns,product_id:products');


--
-- Name: returns trg_returns_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_returns_updated_at BEFORE UPDATE ON public.returns FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: returns trg_returns_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_returns_ws_check BEFORE INSERT OR UPDATE ON public.returns FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('contact_id:contacts,created_by:users,approved_by:users');


--
-- Name: roles trg_roles_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_roles_updated_at BEFORE UPDATE ON public.roles FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: shift_assignments trg_shift_assignments_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_shift_assignments_updated_at BEFORE UPDATE ON public.shift_assignments FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: shift_assignments trg_shift_assignments_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_shift_assignments_ws_check BEFORE INSERT OR UPDATE ON public.shift_assignments FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('user_id:users,shift_id:shifts,assigned_by:users');


--
-- Name: shifts trg_shifts_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_shifts_updated_at BEFORE UPDATE ON public.shifts FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: shipment_items trg_shipment_items_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_shipment_items_ws_check BEFORE INSERT OR UPDATE ON public.shipment_items FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('shipment_id:shipments,product_id:products,warehouse_id:warehouses');


--
-- Name: shipments trg_shipments_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_shipments_updated_at BEFORE UPDATE ON public.shipments FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: shipments trg_shipments_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_shipments_ws_check BEFORE INSERT OR UPDATE ON public.shipments FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('invoice_id:invoices,contact_id:contacts,delivery_driver_id:users');


--
-- Name: stock_reservations trg_stock_reservations_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_stock_reservations_updated_at BEFORE UPDATE ON public.stock_reservations FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: stock_reservations trg_stock_reservations_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_stock_reservations_ws_check BEFORE INSERT OR UPDATE ON public.stock_reservations FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('order_id:orders,warehouse_id:warehouses,product_id:products');


--
-- Name: stock_transfers trg_stock_transfers_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_stock_transfers_updated_at BEFORE UPDATE ON public.stock_transfers FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: stock_transfers trg_stock_transfers_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_stock_transfers_ws_check BEFORE INSERT OR UPDATE ON public.stock_transfers FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('from_warehouse_id:warehouses,to_warehouse_id:warehouses,created_by:users,approved_by:users');


--
-- Name: subscription_plans trg_subscription_plans_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_subscription_plans_updated_at BEFORE UPDATE ON public.subscription_plans FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: customer_subscriptions trg_subscriptions_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_subscriptions_ws_check BEFORE INSERT OR UPDATE ON public.customer_subscriptions FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('contact_id:contacts,product_id:products');


--
-- Name: tasks trg_tasks_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_tasks_updated_at BEFORE UPDATE ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: tasks trg_tasks_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_tasks_ws_check BEFORE INSERT OR UPDATE ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('project_id:projects,assigned_to:users');


--
-- Name: taxes trg_taxes_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_taxes_updated_at BEFORE UPDATE ON public.taxes FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: transactions trg_transactions_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_transactions_ws_check BEFORE INSERT OR UPDATE ON public.transactions FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('contact_id:contacts,account_id:accounts,from_account_id:accounts,to_account_id:accounts,created_by:users');


--
-- Name: user_permission_overrides trg_user_permission_overrides_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_user_permission_overrides_updated_at BEFORE UPDATE ON public.user_permission_overrides FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: users trg_users_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_users_updated_at BEFORE UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: warehouses trg_warehouses_ws_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_warehouses_ws_check BEFORE INSERT OR UPDATE ON public.warehouses FOR EACH ROW EXECUTE FUNCTION public.validate_workspace_fk('branch_id:branches');


--
-- Name: workspace_memberships trg_workspace_memberships_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_workspace_memberships_updated_at BEFORE UPDATE ON public.workspace_memberships FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: workspaces trg_workspaces_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_workspaces_updated_at BEFORE UPDATE ON public.workspaces FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: workspace_feature_flags trg_ws_feature_flags_updated; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_ws_feature_flags_updated BEFORE UPDATE ON public.workspace_feature_flags FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();


--
-- Name: workspace_subscriptions trg_ws_subscriptions_updated; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_ws_subscriptions_updated BEFORE UPDATE ON public.workspace_subscriptions FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();


--
-- Name: accounts accounts_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounts
    ADD CONSTRAINT accounts_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.accounts(id) ON DELETE SET NULL;


--
-- Name: accounts accounts_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounts
    ADD CONSTRAINT accounts_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: ai_change_requests ai_change_requests_conversation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_change_requests
    ADD CONSTRAINT ai_change_requests_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.ai_conversations(id) ON DELETE SET NULL;


--
-- Name: ai_change_requests ai_change_requests_requested_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_change_requests
    ADD CONSTRAINT ai_change_requests_requested_by_fkey FOREIGN KEY (requested_by) REFERENCES public.users(id);


--
-- Name: ai_change_requests ai_change_requests_reviewed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_change_requests
    ADD CONSTRAINT ai_change_requests_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES public.users(id);


--
-- Name: ai_change_requests ai_change_requests_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_change_requests
    ADD CONSTRAINT ai_change_requests_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: ai_conversations ai_conversations_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_conversations
    ADD CONSTRAINT ai_conversations_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: ai_conversations ai_conversations_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_conversations
    ADD CONSTRAINT ai_conversations_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: ai_credit_balances ai_credit_balances_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_credit_balances
    ADD CONSTRAINT ai_credit_balances_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: ai_credit_transactions ai_credit_transactions_actor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_credit_transactions
    ADD CONSTRAINT ai_credit_transactions_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: ai_credit_transactions ai_credit_transactions_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_credit_transactions
    ADD CONSTRAINT ai_credit_transactions_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: ai_execution_plans ai_execution_plans_conversation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_execution_plans
    ADD CONSTRAINT ai_execution_plans_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.ai_conversations(id) ON DELETE SET NULL;


--
-- Name: ai_messages ai_messages_conversation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_messages
    ADD CONSTRAINT ai_messages_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.ai_conversations(id) ON DELETE CASCADE;


--
-- Name: ai_messages ai_messages_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_messages
    ADD CONSTRAINT ai_messages_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: ai_messages ai_messages_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_messages
    ADD CONSTRAINT ai_messages_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: ai_recommendations ai_recommendations_applied_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_recommendations
    ADD CONSTRAINT ai_recommendations_applied_by_fkey FOREIGN KEY (applied_by) REFERENCES public.users(id);


--
-- Name: ai_recommendations ai_recommendations_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_recommendations
    ADD CONSTRAINT ai_recommendations_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id);


--
-- Name: ai_tool_calls ai_tool_calls_conversation_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_tool_calls
    ADD CONSTRAINT ai_tool_calls_conversation_id_foreign FOREIGN KEY (conversation_id) REFERENCES public.ai_conversations(id) ON DELETE SET NULL;


--
-- Name: ai_tool_calls ai_tool_calls_user_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_tool_calls
    ADD CONSTRAINT ai_tool_calls_user_id_foreign FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: ai_tool_calls ai_tool_calls_workspace_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_tool_calls
    ADD CONSTRAINT ai_tool_calls_workspace_id_foreign FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE SET NULL;


--
-- Name: ai_usage_logs ai_usage_logs_conversation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_usage_logs
    ADD CONSTRAINT ai_usage_logs_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.ai_conversations(id) ON DELETE SET NULL;


--
-- Name: ai_usage_logs ai_usage_logs_message_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_usage_logs
    ADD CONSTRAINT ai_usage_logs_message_id_fkey FOREIGN KEY (message_id) REFERENCES public.ai_messages(id) ON DELETE SET NULL;


--
-- Name: ai_usage_logs ai_usage_logs_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_usage_logs
    ADD CONSTRAINT ai_usage_logs_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: ai_usage_logs ai_usage_logs_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_usage_logs
    ADD CONSTRAINT ai_usage_logs_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE SET NULL;


--
-- Name: ai_workspace_settings ai_workspace_settings_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_workspace_settings
    ADD CONSTRAINT ai_workspace_settings_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: approval_decisions approval_decisions_actor_membership_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_decisions
    ADD CONSTRAINT approval_decisions_actor_membership_id_foreign FOREIGN KEY (actor_membership_id) REFERENCES public.workspace_memberships(id) ON DELETE RESTRICT;


--
-- Name: approval_decisions approval_decisions_approval_request_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_decisions
    ADD CONSTRAINT approval_decisions_approval_request_id_foreign FOREIGN KEY (approval_request_id) REFERENCES public.approval_requests(id) ON DELETE CASCADE;


--
-- Name: approval_decisions approval_decisions_approval_request_step_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_decisions
    ADD CONSTRAINT approval_decisions_approval_request_step_id_foreign FOREIGN KEY (approval_request_step_id) REFERENCES public.approval_request_steps(id) ON DELETE CASCADE;


--
-- Name: approval_decisions approval_decisions_workspace_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_decisions
    ADD CONSTRAINT approval_decisions_workspace_id_foreign FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: approval_request_steps approval_request_steps_approval_request_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_request_steps
    ADD CONSTRAINT approval_request_steps_approval_request_id_foreign FOREIGN KEY (approval_request_id) REFERENCES public.approval_requests(id) ON DELETE CASCADE;


--
-- Name: approval_request_steps approval_request_steps_workflow_step_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_request_steps
    ADD CONSTRAINT approval_request_steps_workflow_step_id_foreign FOREIGN KEY (workflow_step_id) REFERENCES public.approval_workflow_steps(id) ON DELETE RESTRICT;


--
-- Name: approval_request_steps approval_request_steps_workspace_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_request_steps
    ADD CONSTRAINT approval_request_steps_workspace_id_foreign FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: approval_requests approval_requests_requester_membership_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_requests
    ADD CONSTRAINT approval_requests_requester_membership_id_foreign FOREIGN KEY (requester_membership_id) REFERENCES public.workspace_memberships(id) ON DELETE RESTRICT;


--
-- Name: approval_requests approval_requests_workflow_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_requests
    ADD CONSTRAINT approval_requests_workflow_id_foreign FOREIGN KEY (workflow_id) REFERENCES public.approval_workflows(id) ON DELETE RESTRICT;


--
-- Name: approval_requests approval_requests_workspace_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_requests
    ADD CONSTRAINT approval_requests_workspace_id_foreign FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: approval_workflow_steps approval_workflow_steps_workflow_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_workflow_steps
    ADD CONSTRAINT approval_workflow_steps_workflow_id_foreign FOREIGN KEY (workflow_id) REFERENCES public.approval_workflows(id) ON DELETE CASCADE;


--
-- Name: approval_workflow_steps approval_workflow_steps_workspace_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_workflow_steps
    ADD CONSTRAINT approval_workflow_steps_workspace_id_foreign FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: approval_workflows approval_workflows_workspace_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_workflows
    ADD CONSTRAINT approval_workflows_workspace_id_foreign FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: archival_jobs archival_jobs_retention_policy_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.archival_jobs
    ADD CONSTRAINT archival_jobs_retention_policy_id_fkey FOREIGN KEY (retention_policy_id) REFERENCES public.retention_policies(id) ON DELETE SET NULL;


--
-- Name: archival_jobs archival_jobs_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.archival_jobs
    ADD CONSTRAINT archival_jobs_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: async_jobs async_jobs_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.async_jobs
    ADD CONSTRAINT async_jobs_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: async_jobs async_jobs_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.async_jobs
    ADD CONSTRAINT async_jobs_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: attachments attachments_uploaded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attachments
    ADD CONSTRAINT attachments_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: attachments attachments_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attachments
    ADD CONSTRAINT attachments_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: attendance attendance_adjustment_approved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance
    ADD CONSTRAINT attendance_adjustment_approved_by_fkey FOREIGN KEY (adjustment_approved_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: attendance attendance_shift_assignment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance
    ADD CONSTRAINT attendance_shift_assignment_id_fkey FOREIGN KEY (shift_assignment_id) REFERENCES public.shift_assignments(id) ON DELETE SET NULL;


--
-- Name: attendance attendance_shift_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance
    ADD CONSTRAINT attendance_shift_id_fkey FOREIGN KEY (shift_id) REFERENCES public.shifts(id) ON DELETE SET NULL;


--
-- Name: attendance attendance_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance
    ADD CONSTRAINT attendance_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: attendance attendance_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance
    ADD CONSTRAINT attendance_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: audit_logs audit_logs_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: audit_logs audit_logs_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: automation_logs automation_logs_automation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_logs
    ADD CONSTRAINT automation_logs_automation_id_fkey FOREIGN KEY (automation_id) REFERENCES public.communication_automations(id) ON DELETE CASCADE;


--
-- Name: automation_logs automation_logs_outbound_message_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_logs
    ADD CONSTRAINT automation_logs_outbound_message_id_fkey FOREIGN KEY (outbound_message_id) REFERENCES public.outbound_messages(id) ON DELETE SET NULL;


--
-- Name: automation_logs automation_logs_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_logs
    ADD CONSTRAINT automation_logs_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: bill_of_materials bill_of_materials_final_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bill_of_materials
    ADD CONSTRAINT bill_of_materials_final_product_id_fkey FOREIGN KEY (final_product_id) REFERENCES public.products(id) ON DELETE CASCADE;


--
-- Name: bill_of_materials bill_of_materials_raw_material_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bill_of_materials
    ADD CONSTRAINT bill_of_materials_raw_material_id_fkey FOREIGN KEY (raw_material_id) REFERENCES public.products(id) ON DELETE CASCADE;


--
-- Name: bill_of_materials bill_of_materials_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bill_of_materials
    ADD CONSTRAINT bill_of_materials_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: billing_invoices billing_invoices_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_invoices
    ADD CONSTRAINT billing_invoices_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: billing_payments billing_payments_billing_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_payments
    ADD CONSTRAINT billing_payments_billing_invoice_id_fkey FOREIGN KEY (billing_invoice_id) REFERENCES public.billing_invoices(id) ON DELETE CASCADE;


--
-- Name: billing_payments billing_payments_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_payments
    ADD CONSTRAINT billing_payments_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: billing_snapshots billing_snapshots_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_snapshots
    ADD CONSTRAINT billing_snapshots_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: bookings bookings_assigned_to_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_assigned_to_fkey FOREIGN KEY (assigned_to) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: bookings bookings_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(id) ON DELETE SET NULL;


--
-- Name: bookings bookings_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE SET NULL;


--
-- Name: bookings bookings_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES public.invoices(id) ON DELETE SET NULL;


--
-- Name: bookings bookings_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE SET NULL;


--
-- Name: bookings bookings_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: branches branches_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.branches
    ADD CONSTRAINT branches_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: brand_kits brand_kits_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.brand_kits
    ADD CONSTRAINT brand_kits_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: business_template_custom_fields business_template_custom_fields_business_template_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.business_template_custom_fields
    ADD CONSTRAINT business_template_custom_fields_business_template_id_foreign FOREIGN KEY (business_template_id) REFERENCES public.business_templates(id) ON DELETE CASCADE;


--
-- Name: business_template_modules business_template_modules_business_template_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.business_template_modules
    ADD CONSTRAINT business_template_modules_business_template_id_foreign FOREIGN KEY (business_template_id) REFERENCES public.business_templates(id) ON DELETE CASCADE;


--
-- Name: business_template_roles business_template_roles_business_template_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.business_template_roles
    ADD CONSTRAINT business_template_roles_business_template_id_foreign FOREIGN KEY (business_template_id) REFERENCES public.business_templates(id) ON DELETE CASCADE;


--
-- Name: business_template_workflows business_template_workflows_business_template_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.business_template_workflows
    ADD CONSTRAINT business_template_workflows_business_template_id_foreign FOREIGN KEY (business_template_id) REFERENCES public.business_templates(id) ON DELETE CASCADE;


--
-- Name: campaign_metrics campaign_metrics_campaign_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campaign_metrics
    ADD CONSTRAINT campaign_metrics_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES public.campaigns(id) ON DELETE CASCADE;


--
-- Name: campaigns campaigns_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campaigns
    ADD CONSTRAINT campaigns_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: campaigns campaigns_template_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campaigns
    ADD CONSTRAINT campaigns_template_id_fkey FOREIGN KEY (template_id) REFERENCES public.message_templates(id) ON DELETE SET NULL;


--
-- Name: campaigns campaigns_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campaigns
    ADD CONSTRAINT campaigns_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: cod_collections cod_collections_assignment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cod_collections
    ADD CONSTRAINT cod_collections_assignment_id_fkey FOREIGN KEY (assignment_id) REFERENCES public.delivery_assignments(id) ON DELETE CASCADE;


--
-- Name: cod_collections cod_collections_driver_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cod_collections
    ADD CONSTRAINT cod_collections_driver_id_fkey FOREIGN KEY (driver_id) REFERENCES public.drivers(id) ON DELETE CASCADE;


--
-- Name: cod_collections cod_collections_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cod_collections
    ADD CONSTRAINT cod_collections_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: commission_entries commission_entries_commission_plan_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commission_entries
    ADD CONSTRAINT commission_entries_commission_plan_id_foreign FOREIGN KEY (commission_plan_id) REFERENCES public.commission_plans(id) ON DELETE SET NULL;


--
-- Name: commission_entries commission_entries_commission_rule_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commission_entries
    ADD CONSTRAINT commission_entries_commission_rule_id_foreign FOREIGN KEY (commission_rule_id) REFERENCES public.commission_rules(id) ON DELETE SET NULL;


--
-- Name: commission_entries commission_entries_pipeline_record_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commission_entries
    ADD CONSTRAINT commission_entries_pipeline_record_id_foreign FOREIGN KEY (pipeline_record_id) REFERENCES public.pipeline_records(id) ON DELETE CASCADE;


--
-- Name: commission_entries commission_entries_recipient_membership_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commission_entries
    ADD CONSTRAINT commission_entries_recipient_membership_id_foreign FOREIGN KEY (recipient_membership_id) REFERENCES public.workspace_memberships(id) ON DELETE CASCADE;


--
-- Name: commission_entries commission_entries_source_membership_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commission_entries
    ADD CONSTRAINT commission_entries_source_membership_id_foreign FOREIGN KEY (source_membership_id) REFERENCES public.workspace_memberships(id) ON DELETE SET NULL;


--
-- Name: commission_entries commission_entries_workspace_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commission_entries
    ADD CONSTRAINT commission_entries_workspace_id_foreign FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: commission_plans commission_plans_workspace_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commission_plans
    ADD CONSTRAINT commission_plans_workspace_id_foreign FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: commission_rules commission_rules_commission_plan_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commission_rules
    ADD CONSTRAINT commission_rules_commission_plan_id_foreign FOREIGN KEY (commission_plan_id) REFERENCES public.commission_plans(id) ON DELETE CASCADE;


--
-- Name: commission_rules commission_rules_department_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commission_rules
    ADD CONSTRAINT commission_rules_department_id_foreign FOREIGN KEY (department_id) REFERENCES public.departments(id) ON DELETE SET NULL;


--
-- Name: commission_rules commission_rules_pipeline_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commission_rules
    ADD CONSTRAINT commission_rules_pipeline_id_foreign FOREIGN KEY (pipeline_id) REFERENCES public.pipelines(id) ON DELETE SET NULL;


--
-- Name: commission_rules commission_rules_role_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commission_rules
    ADD CONSTRAINT commission_rules_role_id_foreign FOREIGN KEY (role_id) REFERENCES public.roles(id) ON DELETE SET NULL;


--
-- Name: commission_rules commission_rules_stage_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commission_rules
    ADD CONSTRAINT commission_rules_stage_id_foreign FOREIGN KEY (stage_id) REFERENCES public.pipeline_stages(id) ON DELETE SET NULL;


--
-- Name: commission_rules commission_rules_team_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commission_rules
    ADD CONSTRAINT commission_rules_team_id_foreign FOREIGN KEY (team_id) REFERENCES public.teams(id) ON DELETE SET NULL;


--
-- Name: commission_rules commission_rules_workspace_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commission_rules
    ADD CONSTRAINT commission_rules_workspace_id_foreign FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: communication_automations communication_automations_template_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.communication_automations
    ADD CONSTRAINT communication_automations_template_id_fkey FOREIGN KEY (template_id) REFERENCES public.message_templates(id) ON DELETE CASCADE;


--
-- Name: communication_automations communication_automations_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.communication_automations
    ADD CONSTRAINT communication_automations_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: communication_channels communication_channels_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.communication_channels
    ADD CONSTRAINT communication_channels_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: contacts contacts_assigned_membership_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contacts
    ADD CONSTRAINT contacts_assigned_membership_id_foreign FOREIGN KEY (assigned_membership_id) REFERENCES public.workspace_memberships(id) ON DELETE SET NULL;


--
-- Name: contacts contacts_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contacts
    ADD CONSTRAINT contacts_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: coupons coupons_promotion_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coupons
    ADD CONSTRAINT coupons_promotion_id_fkey FOREIGN KEY (promotion_id) REFERENCES public.promotions(id) ON DELETE CASCADE;


--
-- Name: coupons coupons_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coupons
    ADD CONSTRAINT coupons_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: credit_note_items credit_note_items_credit_note_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_note_items
    ADD CONSTRAINT credit_note_items_credit_note_id_fkey FOREIGN KEY (credit_note_id) REFERENCES public.credit_notes(id) ON DELETE CASCADE;


--
-- Name: credit_note_items credit_note_items_original_invoice_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_note_items
    ADD CONSTRAINT credit_note_items_original_invoice_item_id_fkey FOREIGN KEY (original_invoice_item_id) REFERENCES public.invoice_items(id) ON DELETE SET NULL;


--
-- Name: credit_note_items credit_note_items_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_note_items
    ADD CONSTRAINT credit_note_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE SET NULL;


--
-- Name: credit_note_items credit_note_items_unit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_note_items
    ADD CONSTRAINT credit_note_items_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES public.units_of_measure(id) ON DELETE SET NULL;


--
-- Name: credit_note_items credit_note_items_variant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_note_items
    ADD CONSTRAINT credit_note_items_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.product_variants(id) ON DELETE SET NULL;


--
-- Name: credit_note_items credit_note_items_warehouse_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_note_items
    ADD CONSTRAINT credit_note_items_warehouse_id_fkey FOREIGN KEY (warehouse_id) REFERENCES public.warehouses(id) ON DELETE SET NULL;


--
-- Name: credit_note_items credit_note_items_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_note_items
    ADD CONSTRAINT credit_note_items_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: credit_notes credit_notes_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_notes
    ADD CONSTRAINT credit_notes_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(id) ON DELETE SET NULL;


--
-- Name: credit_notes credit_notes_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_notes
    ADD CONSTRAINT credit_notes_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE SET NULL;


--
-- Name: credit_notes credit_notes_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_notes
    ADD CONSTRAINT credit_notes_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: credit_notes credit_notes_original_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_notes
    ADD CONSTRAINT credit_notes_original_invoice_id_fkey FOREIGN KEY (original_invoice_id) REFERENCES public.invoices(id) ON DELETE RESTRICT;


--
-- Name: credit_notes credit_notes_reversal_journal_entry_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_notes
    ADD CONSTRAINT credit_notes_reversal_journal_entry_id_fkey FOREIGN KEY (reversal_journal_entry_id) REFERENCES public.journal_entries(id) ON DELETE SET NULL;


--
-- Name: credit_notes credit_notes_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_notes
    ADD CONSTRAINT credit_notes_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: crm_activities crm_activities_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_activities
    ADD CONSTRAINT crm_activities_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE SET NULL;


--
-- Name: crm_activities crm_activities_lead_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_activities
    ADD CONSTRAINT crm_activities_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES public.leads(id) ON DELETE CASCADE;


--
-- Name: crm_activities crm_activities_opportunity_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_activities
    ADD CONSTRAINT crm_activities_opportunity_id_fkey FOREIGN KEY (opportunity_id) REFERENCES public.opportunities(id) ON DELETE CASCADE;


--
-- Name: crm_activities crm_activities_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_activities
    ADD CONSTRAINT crm_activities_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: crm_activities crm_activities_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_activities
    ADD CONSTRAINT crm_activities_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: custom_field_values custom_field_values_custom_field_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.custom_field_values
    ADD CONSTRAINT custom_field_values_custom_field_id_foreign FOREIGN KEY (custom_field_id) REFERENCES public.custom_fields(id) ON DELETE CASCADE;


--
-- Name: custom_field_values custom_field_values_workspace_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.custom_field_values
    ADD CONSTRAINT custom_field_values_workspace_id_foreign FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: custom_fields custom_fields_pipeline_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.custom_fields
    ADD CONSTRAINT custom_fields_pipeline_id_foreign FOREIGN KEY (pipeline_id) REFERENCES public.pipelines(id) ON DELETE SET NULL;


--
-- Name: custom_fields custom_fields_workspace_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.custom_fields
    ADD CONSTRAINT custom_fields_workspace_id_foreign FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: customer_credits customer_credits_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_credits
    ADD CONSTRAINT customer_credits_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE CASCADE;


--
-- Name: customer_credits customer_credits_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_credits
    ADD CONSTRAINT customer_credits_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: customer_credits customer_credits_credit_note_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_credits
    ADD CONSTRAINT customer_credits_credit_note_id_fkey FOREIGN KEY (credit_note_id) REFERENCES public.credit_notes(id) ON DELETE SET NULL;


--
-- Name: customer_credits customer_credits_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_credits
    ADD CONSTRAINT customer_credits_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES public.invoices(id) ON DELETE SET NULL;


--
-- Name: customer_credits customer_credits_payment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_credits
    ADD CONSTRAINT customer_credits_payment_id_fkey FOREIGN KEY (payment_id) REFERENCES public.payments(id) ON DELETE SET NULL;


--
-- Name: customer_credits customer_credits_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_credits
    ADD CONSTRAINT customer_credits_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: customer_subscriptions customer_subscriptions_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_subscriptions
    ADD CONSTRAINT customer_subscriptions_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE CASCADE;


--
-- Name: customer_subscriptions customer_subscriptions_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_subscriptions
    ADD CONSTRAINT customer_subscriptions_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE SET NULL;


--
-- Name: customer_subscriptions customer_subscriptions_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_subscriptions
    ADD CONSTRAINT customer_subscriptions_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: delivery_assignments delivery_assignments_driver_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.delivery_assignments
    ADD CONSTRAINT delivery_assignments_driver_id_fkey FOREIGN KEY (driver_id) REFERENCES public.drivers(id) ON DELETE CASCADE;


--
-- Name: delivery_assignments delivery_assignments_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.delivery_assignments
    ADD CONSTRAINT delivery_assignments_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;


--
-- Name: delivery_assignments delivery_assignments_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.delivery_assignments
    ADD CONSTRAINT delivery_assignments_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: delivery_assignments delivery_assignments_zone_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.delivery_assignments
    ADD CONSTRAINT delivery_assignments_zone_id_fkey FOREIGN KEY (zone_id) REFERENCES public.delivery_zones(id) ON DELETE SET NULL;


--
-- Name: delivery_proofs delivery_proofs_assignment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.delivery_proofs
    ADD CONSTRAINT delivery_proofs_assignment_id_fkey FOREIGN KEY (assignment_id) REFERENCES public.delivery_assignments(id) ON DELETE CASCADE;


--
-- Name: delivery_sla_breaches delivery_sla_breaches_assignment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.delivery_sla_breaches
    ADD CONSTRAINT delivery_sla_breaches_assignment_id_fkey FOREIGN KEY (assignment_id) REFERENCES public.delivery_assignments(id) ON DELETE CASCADE;


--
-- Name: delivery_sla_breaches delivery_sla_breaches_zone_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.delivery_sla_breaches
    ADD CONSTRAINT delivery_sla_breaches_zone_id_fkey FOREIGN KEY (zone_id) REFERENCES public.delivery_zones(id) ON DELETE SET NULL;


--
-- Name: delivery_tracking delivery_tracking_assignment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.delivery_tracking
    ADD CONSTRAINT delivery_tracking_assignment_id_fkey FOREIGN KEY (assignment_id) REFERENCES public.delivery_assignments(id) ON DELETE CASCADE;


--
-- Name: delivery_zones delivery_zones_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.delivery_zones
    ADD CONSTRAINT delivery_zones_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: departments departments_manager_membership_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT departments_manager_membership_id_foreign FOREIGN KEY (manager_membership_id) REFERENCES public.workspace_memberships(id) ON DELETE SET NULL;


--
-- Name: departments departments_parent_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT departments_parent_department_id_fkey FOREIGN KEY (parent_department_id) REFERENCES public.departments(id) ON DELETE SET NULL;


--
-- Name: departments departments_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT departments_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: dining_tables dining_tables_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dining_tables
    ADD CONSTRAINT dining_tables_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(id) ON DELETE CASCADE;


--
-- Name: dining_tables dining_tables_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dining_tables
    ADD CONSTRAINT dining_tables_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: discovery_blueprints discovery_blueprints_session_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.discovery_blueprints
    ADD CONSTRAINT discovery_blueprints_session_id_fkey FOREIGN KEY (session_id) REFERENCES public.discovery_sessions(id) ON DELETE CASCADE;


--
-- Name: discovery_blueprints discovery_blueprints_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.discovery_blueprints
    ADD CONSTRAINT discovery_blueprints_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: discovery_messages discovery_messages_session_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.discovery_messages
    ADD CONSTRAINT discovery_messages_session_id_fkey FOREIGN KEY (session_id) REFERENCES public.discovery_sessions(id) ON DELETE CASCADE;


--
-- Name: discovery_messages discovery_messages_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.discovery_messages
    ADD CONSTRAINT discovery_messages_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: discovery_sessions discovery_sessions_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.discovery_sessions
    ADD CONSTRAINT discovery_sessions_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: discovery_sessions discovery_sessions_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.discovery_sessions
    ADD CONSTRAINT discovery_sessions_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: document_checklist_items document_checklist_items_document_checklist_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_checklist_items
    ADD CONSTRAINT document_checklist_items_document_checklist_id_foreign FOREIGN KEY (document_checklist_id) REFERENCES public.document_checklists(id) ON DELETE CASCADE;


--
-- Name: document_checklist_items document_checklist_items_workspace_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_checklist_items
    ADD CONSTRAINT document_checklist_items_workspace_id_foreign FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: document_checklists document_checklists_pipeline_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_checklists
    ADD CONSTRAINT document_checklists_pipeline_id_foreign FOREIGN KEY (pipeline_id) REFERENCES public.pipelines(id) ON DELETE SET NULL;


--
-- Name: document_checklists document_checklists_stage_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_checklists
    ADD CONSTRAINT document_checklists_stage_id_foreign FOREIGN KEY (stage_id) REFERENCES public.pipeline_stages(id) ON DELETE SET NULL;


--
-- Name: document_checklists document_checklists_workspace_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_checklists
    ADD CONSTRAINT document_checklists_workspace_id_foreign FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: document_sequences document_sequences_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_sequences
    ADD CONSTRAINT document_sequences_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: drivers drivers_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.drivers
    ADD CONSTRAINT drivers_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(id) ON DELETE SET NULL;


--
-- Name: drivers drivers_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.drivers
    ADD CONSTRAINT drivers_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: drivers drivers_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.drivers
    ADD CONSTRAINT drivers_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: duplicate_matches duplicate_matches_duplicate_rule_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.duplicate_matches
    ADD CONSTRAINT duplicate_matches_duplicate_rule_id_foreign FOREIGN KEY (duplicate_rule_id) REFERENCES public.duplicate_rules(id) ON DELETE SET NULL;


--
-- Name: duplicate_matches duplicate_matches_resolved_by_membership_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.duplicate_matches
    ADD CONSTRAINT duplicate_matches_resolved_by_membership_id_foreign FOREIGN KEY (resolved_by_membership_id) REFERENCES public.workspace_memberships(id) ON DELETE SET NULL;


--
-- Name: duplicate_matches duplicate_matches_workspace_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.duplicate_matches
    ADD CONSTRAINT duplicate_matches_workspace_id_foreign FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: duplicate_rules duplicate_rules_workspace_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.duplicate_rules
    ADD CONSTRAINT duplicate_rules_workspace_id_foreign FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: email_logs email_logs_actor_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_logs
    ADD CONSTRAINT email_logs_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES public.users(id);


--
-- Name: email_logs email_logs_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_logs
    ADD CONSTRAINT email_logs_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id);


--
-- Name: email_settings email_settings_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_settings
    ADD CONSTRAINT email_settings_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id);


--
-- Name: exchange_rates exchange_rates_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exchange_rates
    ADD CONSTRAINT exchange_rates_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: export_jobs export_jobs_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.export_jobs
    ADD CONSTRAINT export_jobs_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: export_jobs export_jobs_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.export_jobs
    ADD CONSTRAINT export_jobs_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: finance_accounts finance_accounts_workspace_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.finance_accounts
    ADD CONSTRAINT finance_accounts_workspace_id_foreign FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: finance_expenses finance_expenses_finance_transaction_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.finance_expenses
    ADD CONSTRAINT finance_expenses_finance_transaction_id_foreign FOREIGN KEY (finance_transaction_id) REFERENCES public.finance_transactions(id) ON DELETE SET NULL;


--
-- Name: finance_expenses finance_expenses_paid_by_membership_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.finance_expenses
    ADD CONSTRAINT finance_expenses_paid_by_membership_id_foreign FOREIGN KEY (paid_by_membership_id) REFERENCES public.workspace_memberships(id) ON DELETE SET NULL;


--
-- Name: finance_expenses finance_expenses_workspace_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.finance_expenses
    ADD CONSTRAINT finance_expenses_workspace_id_foreign FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: finance_settings finance_settings_workspace_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.finance_settings
    ADD CONSTRAINT finance_settings_workspace_id_foreign FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: finance_transaction_lines finance_transaction_lines_finance_account_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.finance_transaction_lines
    ADD CONSTRAINT finance_transaction_lines_finance_account_id_foreign FOREIGN KEY (finance_account_id) REFERENCES public.finance_accounts(id) ON DELETE RESTRICT;


--
-- Name: finance_transaction_lines finance_transaction_lines_finance_transaction_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.finance_transaction_lines
    ADD CONSTRAINT finance_transaction_lines_finance_transaction_id_foreign FOREIGN KEY (finance_transaction_id) REFERENCES public.finance_transactions(id) ON DELETE CASCADE;


--
-- Name: finance_transaction_lines finance_transaction_lines_workspace_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.finance_transaction_lines
    ADD CONSTRAINT finance_transaction_lines_workspace_id_foreign FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: finance_transactions finance_transactions_posted_by_membership_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.finance_transactions
    ADD CONSTRAINT finance_transactions_posted_by_membership_id_foreign FOREIGN KEY (posted_by_membership_id) REFERENCES public.workspace_memberships(id) ON DELETE SET NULL;


--
-- Name: finance_transactions finance_transactions_workspace_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.finance_transactions
    ADD CONSTRAINT finance_transactions_workspace_id_foreign FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: fiscal_periods fiscal_periods_closed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fiscal_periods
    ADD CONSTRAINT fiscal_periods_closed_by_fkey FOREIGN KEY (closed_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: fiscal_periods fiscal_periods_last_reopened_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fiscal_periods
    ADD CONSTRAINT fiscal_periods_last_reopened_by_fkey FOREIGN KEY (last_reopened_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: fiscal_periods fiscal_periods_locked_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fiscal_periods
    ADD CONSTRAINT fiscal_periods_locked_by_fkey FOREIGN KEY (locked_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: fiscal_periods fiscal_periods_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fiscal_periods
    ADD CONSTRAINT fiscal_periods_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: fixed_assets fixed_assets_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fixed_assets
    ADD CONSTRAINT fixed_assets_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: bill_of_materials fk_bom_unit; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bill_of_materials
    ADD CONSTRAINT fk_bom_unit FOREIGN KEY (unit_id) REFERENCES public.units_of_measure(id) ON DELETE SET NULL;


--
-- Name: campaigns fk_campaigns_segment; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campaigns
    ADD CONSTRAINT fk_campaigns_segment FOREIGN KEY (segment_id) REFERENCES public.segments(id) ON DELETE SET NULL;


--
-- Name: departments fk_department_manager; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT fk_department_manager FOREIGN KEY (manager_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: inventory_levels fk_inventory_variant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_levels
    ADD CONSTRAINT fk_inventory_variant FOREIGN KEY (variant_id) REFERENCES public.product_variants(id) ON DELETE SET NULL;


--
-- Name: invoices fk_invoice_dining_table; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT fk_invoice_dining_table FOREIGN KEY (dining_table_id) REFERENCES public.dining_tables(id) ON DELETE SET NULL;


--
-- Name: invoice_items fk_invoice_item_unit; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_items
    ADD CONSTRAINT fk_invoice_item_unit FOREIGN KEY (unit_id) REFERENCES public.units_of_measure(id) ON DELETE SET NULL;


--
-- Name: invoice_items fk_invoice_item_variant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_items
    ADD CONSTRAINT fk_invoice_item_variant FOREIGN KEY (variant_id) REFERENCES public.product_variants(id) ON DELETE SET NULL;


--
-- Name: orders fk_order_dining_table; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT fk_order_dining_table FOREIGN KEY (dining_table_id) REFERENCES public.dining_tables(id) ON DELETE SET NULL;


--
-- Name: order_items fk_order_item_unit; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT fk_order_item_unit FOREIGN KEY (unit_id) REFERENCES public.units_of_measure(id) ON DELETE SET NULL;


--
-- Name: order_items fk_order_item_variant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT fk_order_item_variant FOREIGN KEY (variant_id) REFERENCES public.product_variants(id) ON DELETE SET NULL;


--
-- Name: products fk_product_unit; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT fk_product_unit FOREIGN KEY (unit_id) REFERENCES public.units_of_measure(id) ON DELETE SET NULL;


--
-- Name: production_orders fk_production_work_center; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.production_orders
    ADD CONSTRAINT fk_production_work_center FOREIGN KEY (work_center_id) REFERENCES public.work_centers(id) ON DELETE SET NULL;


--
-- Name: shipments fk_shipments_return; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shipments
    ADD CONSTRAINT fk_shipments_return FOREIGN KEY (return_id) REFERENCES public.returns(id) ON DELETE SET NULL;


--
-- Name: goods_received_notes goods_received_notes_po_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.goods_received_notes
    ADD CONSTRAINT goods_received_notes_po_id_fkey FOREIGN KEY (po_id) REFERENCES public.purchase_orders(id) ON DELETE RESTRICT;


--
-- Name: goods_received_notes goods_received_notes_received_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.goods_received_notes
    ADD CONSTRAINT goods_received_notes_received_by_fkey FOREIGN KEY (received_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: goods_received_notes goods_received_notes_warehouse_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.goods_received_notes
    ADD CONSTRAINT goods_received_notes_warehouse_id_fkey FOREIGN KEY (warehouse_id) REFERENCES public.warehouses(id) ON DELETE RESTRICT;


--
-- Name: goods_received_notes goods_received_notes_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.goods_received_notes
    ADD CONSTRAINT goods_received_notes_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: grn_items grn_items_grn_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grn_items
    ADD CONSTRAINT grn_items_grn_id_fkey FOREIGN KEY (grn_id) REFERENCES public.goods_received_notes(id) ON DELETE CASCADE;


--
-- Name: grn_items grn_items_po_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grn_items
    ADD CONSTRAINT grn_items_po_item_id_fkey FOREIGN KEY (po_item_id) REFERENCES public.purchase_order_items(id) ON DELETE RESTRICT;


--
-- Name: grn_items grn_items_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grn_items
    ADD CONSTRAINT grn_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE RESTRICT;


--
-- Name: grn_items grn_items_variant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grn_items
    ADD CONSTRAINT grn_items_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.product_variants(id) ON DELETE SET NULL;


--
-- Name: grn_items grn_items_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.grn_items
    ADD CONSTRAINT grn_items_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: idempotency_keys idempotency_keys_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.idempotency_keys
    ADD CONSTRAINT idempotency_keys_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: idempotency_keys idempotency_keys_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.idempotency_keys
    ADD CONSTRAINT idempotency_keys_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: impersonation_sessions impersonation_sessions_platform_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.impersonation_sessions
    ADD CONSTRAINT impersonation_sessions_platform_user_id_fkey FOREIGN KEY (platform_user_id) REFERENCES public.platform_users(id) ON DELETE CASCADE;


--
-- Name: impersonation_sessions impersonation_sessions_target_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.impersonation_sessions
    ADD CONSTRAINT impersonation_sessions_target_user_id_fkey FOREIGN KEY (target_user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: impersonation_sessions impersonation_sessions_target_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.impersonation_sessions
    ADD CONSTRAINT impersonation_sessions_target_workspace_id_fkey FOREIGN KEY (target_workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: import_jobs import_jobs_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_jobs
    ADD CONSTRAINT import_jobs_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: import_jobs import_jobs_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_jobs
    ADD CONSTRAINT import_jobs_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: inbound_messages inbound_messages_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inbound_messages
    ADD CONSTRAINT inbound_messages_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE SET NULL;


--
-- Name: inbound_messages inbound_messages_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inbound_messages
    ADD CONSTRAINT inbound_messages_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: inventory_batches inventory_batches_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_batches
    ADD CONSTRAINT inventory_batches_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE;


--
-- Name: inventory_batches inventory_batches_variant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_batches
    ADD CONSTRAINT inventory_batches_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.product_variants(id) ON DELETE SET NULL;


--
-- Name: inventory_batches inventory_batches_warehouse_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_batches
    ADD CONSTRAINT inventory_batches_warehouse_id_fkey FOREIGN KEY (warehouse_id) REFERENCES public.warehouses(id) ON DELETE CASCADE;


--
-- Name: inventory_batches inventory_batches_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_batches
    ADD CONSTRAINT inventory_batches_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: inventory_levels inventory_levels_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_levels
    ADD CONSTRAINT inventory_levels_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE;


--
-- Name: inventory_levels inventory_levels_warehouse_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_levels
    ADD CONSTRAINT inventory_levels_warehouse_id_fkey FOREIGN KEY (warehouse_id) REFERENCES public.warehouses(id) ON DELETE CASCADE;


--
-- Name: inventory_levels inventory_levels_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_levels
    ADD CONSTRAINT inventory_levels_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: inventory_logs_legacy inventory_logs_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_logs_legacy
    ADD CONSTRAINT inventory_logs_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE;


--
-- Name: inventory_logs_legacy inventory_logs_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_logs_legacy
    ADD CONSTRAINT inventory_logs_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: inventory_logs_legacy inventory_logs_warehouse_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_logs_legacy
    ADD CONSTRAINT inventory_logs_warehouse_id_fkey FOREIGN KEY (warehouse_id) REFERENCES public.warehouses(id);


--
-- Name: inventory_logs_legacy inventory_logs_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_logs_legacy
    ADD CONSTRAINT inventory_logs_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: inventory_movements inventory_movements_batch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_movements
    ADD CONSTRAINT inventory_movements_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES public.inventory_batches(id) ON DELETE SET NULL;


--
-- Name: inventory_movements inventory_movements_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_movements
    ADD CONSTRAINT inventory_movements_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: inventory_movements inventory_movements_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_movements
    ADD CONSTRAINT inventory_movements_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE;


--
-- Name: inventory_movements inventory_movements_variant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_movements
    ADD CONSTRAINT inventory_movements_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.product_variants(id) ON DELETE SET NULL;


--
-- Name: inventory_movements inventory_movements_warehouse_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_movements
    ADD CONSTRAINT inventory_movements_warehouse_id_fkey FOREIGN KEY (warehouse_id) REFERENCES public.warehouses(id) ON DELETE CASCADE;


--
-- Name: inventory_movements inventory_movements_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_movements
    ADD CONSTRAINT inventory_movements_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: invoice_format_rules invoice_format_rules_country_pack_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_format_rules
    ADD CONSTRAINT invoice_format_rules_country_pack_id_fkey FOREIGN KEY (country_pack_id) REFERENCES public.country_packs(id) ON DELETE CASCADE;


--
-- Name: invoice_items invoice_items_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_items
    ADD CONSTRAINT invoice_items_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES public.invoices(id) ON DELETE CASCADE;


--
-- Name: invoice_items invoice_items_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_items
    ADD CONSTRAINT invoice_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id);


--
-- Name: invoice_items invoice_items_warehouse_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_items
    ADD CONSTRAINT invoice_items_warehouse_id_fkey FOREIGN KEY (warehouse_id) REFERENCES public.warehouses(id);


--
-- Name: invoices invoices_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(id) ON DELETE SET NULL;


--
-- Name: invoices invoices_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id);


--
-- Name: invoices invoices_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: invoices invoices_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE SET NULL;


--
-- Name: invoices invoices_parent_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_parent_invoice_id_fkey FOREIGN KEY (parent_invoice_id) REFERENCES public.invoices(id) ON DELETE SET NULL;


--
-- Name: invoices invoices_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: journal_entries journal_entries_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_entries
    ADD CONSTRAINT journal_entries_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: journal_entries journal_entries_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_entries
    ADD CONSTRAINT journal_entries_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: journal_lines journal_lines_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_lines
    ADD CONSTRAINT journal_lines_account_id_fkey FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- Name: journal_lines journal_lines_entry_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.journal_lines
    ADD CONSTRAINT journal_lines_entry_id_fkey FOREIGN KEY (entry_id) REFERENCES public.journal_entries(id) ON DELETE CASCADE;


--
-- Name: leads leads_assigned_to_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leads
    ADD CONSTRAINT leads_assigned_to_fkey FOREIGN KEY (assigned_to) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: leads leads_converted_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leads
    ADD CONSTRAINT leads_converted_contact_id_fkey FOREIGN KEY (converted_contact_id) REFERENCES public.contacts(id) ON DELETE SET NULL;


--
-- Name: leads leads_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leads
    ADD CONSTRAINT leads_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: leave_balances leave_balances_leave_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_balances
    ADD CONSTRAINT leave_balances_leave_type_id_fkey FOREIGN KEY (leave_type_id) REFERENCES public.leave_types(id) ON DELETE CASCADE;


--
-- Name: leave_balances leave_balances_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_balances
    ADD CONSTRAINT leave_balances_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: leave_balances leave_balances_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_balances
    ADD CONSTRAINT leave_balances_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: leave_requests leave_requests_approved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_requests
    ADD CONSTRAINT leave_requests_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: leave_requests leave_requests_cancelled_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_requests
    ADD CONSTRAINT leave_requests_cancelled_by_fkey FOREIGN KEY (cancelled_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: leave_requests leave_requests_leave_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_requests
    ADD CONSTRAINT leave_requests_leave_type_id_fkey FOREIGN KEY (leave_type_id) REFERENCES public.leave_types(id) ON DELETE RESTRICT;


--
-- Name: leave_requests leave_requests_rejected_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_requests
    ADD CONSTRAINT leave_requests_rejected_by_fkey FOREIGN KEY (rejected_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: leave_requests leave_requests_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_requests
    ADD CONSTRAINT leave_requests_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: leave_requests leave_requests_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_requests
    ADD CONSTRAINT leave_requests_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: leave_types leave_types_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_types
    ADD CONSTRAINT leave_types_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: leaves_legacy leaves_leave_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leaves_legacy
    ADD CONSTRAINT leaves_leave_type_id_fkey FOREIGN KEY (leave_type_id) REFERENCES public.leave_types(id) ON DELETE SET NULL;


--
-- Name: leaves_legacy leaves_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leaves_legacy
    ADD CONSTRAINT leaves_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: leaves_legacy leaves_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leaves_legacy
    ADD CONSTRAINT leaves_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: loyalty_accounts loyalty_accounts_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.loyalty_accounts
    ADD CONSTRAINT loyalty_accounts_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE CASCADE;


--
-- Name: loyalty_accounts loyalty_accounts_program_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.loyalty_accounts
    ADD CONSTRAINT loyalty_accounts_program_id_fkey FOREIGN KEY (program_id) REFERENCES public.loyalty_programs(id) ON DELETE CASCADE;


--
-- Name: loyalty_accounts loyalty_accounts_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.loyalty_accounts
    ADD CONSTRAINT loyalty_accounts_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: loyalty_programs loyalty_programs_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.loyalty_programs
    ADD CONSTRAINT loyalty_programs_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: loyalty_transactions loyalty_transactions_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.loyalty_transactions
    ADD CONSTRAINT loyalty_transactions_account_id_fkey FOREIGN KEY (account_id) REFERENCES public.loyalty_accounts(id) ON DELETE CASCADE;


--
-- Name: manual_payments manual_payments_confirmed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.manual_payments
    ADD CONSTRAINT manual_payments_confirmed_by_fkey FOREIGN KEY (confirmed_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: manual_payments manual_payments_plan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.manual_payments
    ADD CONSTRAINT manual_payments_plan_id_fkey FOREIGN KEY (plan_id) REFERENCES public.platform_plans(id) ON DELETE SET NULL;


--
-- Name: manual_payments manual_payments_submitted_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.manual_payments
    ADD CONSTRAINT manual_payments_submitted_by_fkey FOREIGN KEY (submitted_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: manual_payments manual_payments_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.manual_payments
    ADD CONSTRAINT manual_payments_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: media_assets media_assets_approved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.media_assets
    ADD CONSTRAINT media_assets_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: media_assets media_assets_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.media_assets
    ADD CONSTRAINT media_assets_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: media_generation_requests media_generation_requests_brand_kit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.media_generation_requests
    ADD CONSTRAINT media_generation_requests_brand_kit_id_fkey FOREIGN KEY (brand_kit_id) REFERENCES public.brand_kits(id) ON DELETE SET NULL;


--
-- Name: media_generation_requests media_generation_requests_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.media_generation_requests
    ADD CONSTRAINT media_generation_requests_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: media_generation_requests media_generation_requests_result_asset_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.media_generation_requests
    ADD CONSTRAINT media_generation_requests_result_asset_id_fkey FOREIGN KEY (result_asset_id) REFERENCES public.media_assets(id) ON DELETE SET NULL;


--
-- Name: media_generation_requests media_generation_requests_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.media_generation_requests
    ADD CONSTRAINT media_generation_requests_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: membership_roles membership_roles_assigned_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.membership_roles
    ADD CONSTRAINT membership_roles_assigned_by_fkey FOREIGN KEY (assigned_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: membership_roles membership_roles_membership_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.membership_roles
    ADD CONSTRAINT membership_roles_membership_id_fkey FOREIGN KEY (membership_id) REFERENCES public.workspace_memberships(id) ON DELETE CASCADE;


--
-- Name: membership_roles membership_roles_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.membership_roles
    ADD CONSTRAINT membership_roles_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.roles(id) ON DELETE CASCADE;


--
-- Name: membership_roles membership_roles_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.membership_roles
    ADD CONSTRAINT membership_roles_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: message_templates message_templates_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message_templates
    ADD CONSTRAINT message_templates_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: message_threads message_threads_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message_threads
    ADD CONSTRAINT message_threads_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE SET NULL;


--
-- Name: message_threads message_threads_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message_threads
    ADD CONSTRAINT message_threads_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: notifications notifications_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: notifications notifications_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: nurturing_enrollments nurturing_enrollments_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nurturing_enrollments
    ADD CONSTRAINT nurturing_enrollments_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE CASCADE;


--
-- Name: nurturing_enrollments nurturing_enrollments_sequence_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nurturing_enrollments
    ADD CONSTRAINT nurturing_enrollments_sequence_id_fkey FOREIGN KEY (sequence_id) REFERENCES public.nurturing_sequences(id) ON DELETE CASCADE;


--
-- Name: nurturing_sequences nurturing_sequences_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nurturing_sequences
    ADD CONSTRAINT nurturing_sequences_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: opportunities opportunities_assigned_to_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opportunities
    ADD CONSTRAINT opportunities_assigned_to_fkey FOREIGN KEY (assigned_to) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: opportunities opportunities_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opportunities
    ADD CONSTRAINT opportunities_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE SET NULL;


--
-- Name: opportunities opportunities_lead_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opportunities
    ADD CONSTRAINT opportunities_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES public.leads(id) ON DELETE SET NULL;


--
-- Name: opportunities opportunities_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.opportunities
    ADD CONSTRAINT opportunities_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: order_items order_items_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;


--
-- Name: order_items order_items_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id);


--
-- Name: orders orders_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(id) ON DELETE SET NULL;


--
-- Name: orders orders_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id);


--
-- Name: orders orders_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: orders orders_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: outbound_messages outbound_messages_recipient_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.outbound_messages
    ADD CONSTRAINT outbound_messages_recipient_contact_id_fkey FOREIGN KEY (recipient_contact_id) REFERENCES public.contacts(id) ON DELETE SET NULL;


--
-- Name: outbound_messages outbound_messages_recipient_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.outbound_messages
    ADD CONSTRAINT outbound_messages_recipient_user_id_fkey FOREIGN KEY (recipient_user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: outbound_messages outbound_messages_template_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.outbound_messages
    ADD CONSTRAINT outbound_messages_template_id_fkey FOREIGN KEY (template_id) REFERENCES public.message_templates(id) ON DELETE SET NULL;


--
-- Name: outbound_messages outbound_messages_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.outbound_messages
    ADD CONSTRAINT outbound_messages_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: ownership_assignments ownership_assignments_assigned_by_membership_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ownership_assignments
    ADD CONSTRAINT ownership_assignments_assigned_by_membership_id_foreign FOREIGN KEY (assigned_by_membership_id) REFERENCES public.workspace_memberships(id) ON DELETE SET NULL;


--
-- Name: ownership_assignments ownership_assignments_department_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ownership_assignments
    ADD CONSTRAINT ownership_assignments_department_id_foreign FOREIGN KEY (department_id) REFERENCES public.departments(id) ON DELETE SET NULL;


--
-- Name: ownership_assignments ownership_assignments_owner_membership_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ownership_assignments
    ADD CONSTRAINT ownership_assignments_owner_membership_id_foreign FOREIGN KEY (owner_membership_id) REFERENCES public.workspace_memberships(id) ON DELETE CASCADE;


--
-- Name: ownership_assignments ownership_assignments_team_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ownership_assignments
    ADD CONSTRAINT ownership_assignments_team_id_foreign FOREIGN KEY (team_id) REFERENCES public.teams(id) ON DELETE SET NULL;


--
-- Name: ownership_assignments ownership_assignments_workspace_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ownership_assignments
    ADD CONSTRAINT ownership_assignments_workspace_id_foreign FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: ownership_transfer_logs ownership_transfer_logs_from_membership_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ownership_transfer_logs
    ADD CONSTRAINT ownership_transfer_logs_from_membership_id_foreign FOREIGN KEY (from_membership_id) REFERENCES public.workspace_memberships(id) ON DELETE SET NULL;


--
-- Name: ownership_transfer_logs ownership_transfer_logs_ownership_assignment_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ownership_transfer_logs
    ADD CONSTRAINT ownership_transfer_logs_ownership_assignment_id_foreign FOREIGN KEY (ownership_assignment_id) REFERENCES public.ownership_assignments(id) ON DELETE SET NULL;


--
-- Name: ownership_transfer_logs ownership_transfer_logs_to_membership_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ownership_transfer_logs
    ADD CONSTRAINT ownership_transfer_logs_to_membership_id_foreign FOREIGN KEY (to_membership_id) REFERENCES public.workspace_memberships(id) ON DELETE CASCADE;


--
-- Name: ownership_transfer_logs ownership_transfer_logs_transferred_by_membership_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ownership_transfer_logs
    ADD CONSTRAINT ownership_transfer_logs_transferred_by_membership_id_foreign FOREIGN KEY (transferred_by_membership_id) REFERENCES public.workspace_memberships(id) ON DELETE SET NULL;


--
-- Name: ownership_transfer_logs ownership_transfer_logs_workspace_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ownership_transfer_logs
    ADD CONSTRAINT ownership_transfer_logs_workspace_id_foreign FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: payment_transactions payment_transactions_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_transactions
    ADD CONSTRAINT payment_transactions_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: payments payments_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_account_id_fkey FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- Name: payments payments_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: payments payments_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES public.invoices(id) ON DELETE CASCADE;


--
-- Name: payments payments_pos_session_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_pos_session_id_fkey FOREIGN KEY (pos_session_id) REFERENCES public.pos_sessions(id) ON DELETE SET NULL;


--
-- Name: payments payments_reversal_of_payment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_reversal_of_payment_id_fkey FOREIGN KEY (reversal_of_payment_id) REFERENCES public.payments(id) ON DELETE SET NULL;


--
-- Name: payments payments_reversed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_reversed_by_fkey FOREIGN KEY (reversed_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: payments payments_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: payroll_lines payroll_lines_payroll_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_lines
    ADD CONSTRAINT payroll_lines_payroll_id_fkey FOREIGN KEY (payroll_id) REFERENCES public.payroll(id) ON DELETE CASCADE;


--
-- Name: payroll_lines payroll_lines_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_lines
    ADD CONSTRAINT payroll_lines_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: payroll payroll_payroll_run_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll
    ADD CONSTRAINT payroll_payroll_run_id_fkey FOREIGN KEY (payroll_run_id) REFERENCES public.payroll_runs(id) ON DELETE SET NULL;


--
-- Name: payroll_runs payroll_runs_approved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_runs
    ADD CONSTRAINT payroll_runs_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: payroll_runs payroll_runs_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_runs
    ADD CONSTRAINT payroll_runs_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(id) ON DELETE SET NULL;


--
-- Name: payroll_runs payroll_runs_calculated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_runs
    ADD CONSTRAINT payroll_runs_calculated_by_fkey FOREIGN KEY (calculated_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: payroll_runs payroll_runs_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_runs
    ADD CONSTRAINT payroll_runs_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.departments(id) ON DELETE SET NULL;


--
-- Name: payroll_runs payroll_runs_disbursed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_runs
    ADD CONSTRAINT payroll_runs_disbursed_by_fkey FOREIGN KEY (disbursed_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: payroll_runs payroll_runs_journal_entry_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_runs
    ADD CONSTRAINT payroll_runs_journal_entry_id_fkey FOREIGN KEY (journal_entry_id) REFERENCES public.journal_entries(id) ON DELETE SET NULL;


--
-- Name: payroll_runs payroll_runs_locked_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_runs
    ADD CONSTRAINT payroll_runs_locked_by_fkey FOREIGN KEY (locked_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: payroll_runs payroll_runs_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_runs
    ADD CONSTRAINT payroll_runs_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: payroll_statutory_rules payroll_statutory_rules_country_pack_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_statutory_rules
    ADD CONSTRAINT payroll_statutory_rules_country_pack_id_fkey FOREIGN KEY (country_pack_id) REFERENCES public.country_packs(id) ON DELETE CASCADE;


--
-- Name: payroll payroll_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll
    ADD CONSTRAINT payroll_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: payroll payroll_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll
    ADD CONSTRAINT payroll_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: permission_delegation_items permission_delegation_items_delegation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permission_delegation_items
    ADD CONSTRAINT permission_delegation_items_delegation_id_fkey FOREIGN KEY (delegation_id) REFERENCES public.permission_delegations(id) ON DELETE CASCADE;


--
-- Name: permission_delegation_items permission_delegation_items_permission_key_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permission_delegation_items
    ADD CONSTRAINT permission_delegation_items_permission_key_fkey FOREIGN KEY (permission_key) REFERENCES public.permission_definitions(key) ON DELETE CASCADE;


--
-- Name: permission_delegations permission_delegations_delegate_membership_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permission_delegations
    ADD CONSTRAINT permission_delegations_delegate_membership_id_fkey FOREIGN KEY (delegate_membership_id) REFERENCES public.workspace_memberships(id) ON DELETE CASCADE;


--
-- Name: permission_delegations permission_delegations_delegator_membership_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permission_delegations
    ADD CONSTRAINT permission_delegations_delegator_membership_id_fkey FOREIGN KEY (delegator_membership_id) REFERENCES public.workspace_memberships(id) ON DELETE CASCADE;


--
-- Name: permission_delegations permission_delegations_revoked_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permission_delegations
    ADD CONSTRAINT permission_delegations_revoked_by_fkey FOREIGN KEY (revoked_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: permission_delegations permission_delegations_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permission_delegations
    ADD CONSTRAINT permission_delegations_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: pipeline_records pipeline_records_assigned_membership_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pipeline_records
    ADD CONSTRAINT pipeline_records_assigned_membership_id_foreign FOREIGN KEY (assigned_membership_id) REFERENCES public.workspace_memberships(id) ON DELETE SET NULL;


--
-- Name: pipeline_records pipeline_records_contact_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pipeline_records
    ADD CONSTRAINT pipeline_records_contact_id_foreign FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE SET NULL;


--
-- Name: pipeline_records pipeline_records_pipeline_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pipeline_records
    ADD CONSTRAINT pipeline_records_pipeline_id_foreign FOREIGN KEY (pipeline_id) REFERENCES public.pipelines(id) ON DELETE CASCADE;


--
-- Name: pipeline_records pipeline_records_stage_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pipeline_records
    ADD CONSTRAINT pipeline_records_stage_id_foreign FOREIGN KEY (stage_id) REFERENCES public.pipeline_stages(id) ON DELETE CASCADE;


--
-- Name: pipeline_records pipeline_records_workspace_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pipeline_records
    ADD CONSTRAINT pipeline_records_workspace_id_foreign FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: pipeline_stages pipeline_stages_pipeline_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pipeline_stages
    ADD CONSTRAINT pipeline_stages_pipeline_id_foreign FOREIGN KEY (pipeline_id) REFERENCES public.pipelines(id) ON DELETE CASCADE;


--
-- Name: pipeline_stages pipeline_stages_workspace_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pipeline_stages
    ADD CONSTRAINT pipeline_stages_workspace_id_foreign FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: pipelines pipelines_workspace_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pipelines
    ADD CONSTRAINT pipelines_workspace_id_foreign FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: plan_features plan_features_plan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plan_features
    ADD CONSTRAINT plan_features_plan_id_fkey FOREIGN KEY (plan_id) REFERENCES public.platform_plans(id) ON DELETE CASCADE;


--
-- Name: platform_activation_campaigns platform_activation_campaigns_created_by_user_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_activation_campaigns
    ADD CONSTRAINT platform_activation_campaigns_created_by_user_id_foreign FOREIGN KEY (created_by_user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: platform_activation_codes platform_activation_codes_campaign_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_activation_codes
    ADD CONSTRAINT platform_activation_codes_campaign_id_foreign FOREIGN KEY (campaign_id) REFERENCES public.platform_activation_campaigns(id) ON DELETE SET NULL;


--
-- Name: platform_activation_codes platform_activation_codes_used_by_user_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_activation_codes
    ADD CONSTRAINT platform_activation_codes_used_by_user_id_foreign FOREIGN KEY (used_by_user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: platform_activation_codes platform_activation_codes_used_workspace_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_activation_codes
    ADD CONSTRAINT platform_activation_codes_used_workspace_id_foreign FOREIGN KEY (used_workspace_id) REFERENCES public.workspaces(id) ON DELETE SET NULL;


--
-- Name: platform_broadcasts platform_broadcasts_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_broadcasts
    ADD CONSTRAINT platform_broadcasts_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.platform_users(id);


--
-- Name: platform_feature_request_votes platform_feature_request_votes_feature_request_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_feature_request_votes
    ADD CONSTRAINT platform_feature_request_votes_feature_request_id_fkey FOREIGN KEY (feature_request_id) REFERENCES public.platform_feature_requests(id) ON DELETE CASCADE;


--
-- Name: platform_plan_prices platform_plan_prices_plan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_plan_prices
    ADD CONSTRAINT platform_plan_prices_plan_id_fkey FOREIGN KEY (plan_id) REFERENCES public.platform_plans(id) ON DELETE CASCADE;


--
-- Name: platform_settings platform_settings_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_settings
    ADD CONSTRAINT platform_settings_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: platform_survey_responses platform_survey_responses_survey_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_survey_responses
    ADD CONSTRAINT platform_survey_responses_survey_id_fkey FOREIGN KEY (survey_id) REFERENCES public.platform_surveys(id) ON DELETE CASCADE;


--
-- Name: platform_surveys platform_surveys_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_surveys
    ADD CONSTRAINT platform_surveys_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.platform_users(id);


--
-- Name: pos_sessions pos_sessions_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pos_sessions
    ADD CONSTRAINT pos_sessions_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(id) ON DELETE SET NULL;


--
-- Name: pos_sessions pos_sessions_closed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pos_sessions
    ADD CONSTRAINT pos_sessions_closed_by_fkey FOREIGN KEY (closed_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: pos_sessions pos_sessions_terminal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pos_sessions
    ADD CONSTRAINT pos_sessions_terminal_id_fkey FOREIGN KEY (terminal_id) REFERENCES public.pos_terminals(id) ON DELETE CASCADE;


--
-- Name: pos_sessions pos_sessions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pos_sessions
    ADD CONSTRAINT pos_sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: pos_sessions pos_sessions_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pos_sessions
    ADD CONSTRAINT pos_sessions_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: pos_terminals pos_terminals_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pos_terminals
    ADD CONSTRAINT pos_terminals_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(id) ON DELETE CASCADE;


--
-- Name: pos_terminals pos_terminals_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pos_terminals
    ADD CONSTRAINT pos_terminals_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: price_list_items price_list_items_price_list_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.price_list_items
    ADD CONSTRAINT price_list_items_price_list_id_fkey FOREIGN KEY (price_list_id) REFERENCES public.price_lists(id) ON DELETE CASCADE;


--
-- Name: price_list_items price_list_items_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.price_list_items
    ADD CONSTRAINT price_list_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE;


--
-- Name: price_list_items price_list_items_variant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.price_list_items
    ADD CONSTRAINT price_list_items_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.product_variants(id) ON DELETE SET NULL;


--
-- Name: price_lists price_lists_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.price_lists
    ADD CONSTRAINT price_lists_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: product_categories product_categories_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_categories
    ADD CONSTRAINT product_categories_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.product_categories(id) ON DELETE SET NULL;


--
-- Name: product_categories product_categories_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_categories
    ADD CONSTRAINT product_categories_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: product_variants product_variants_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_variants
    ADD CONSTRAINT product_variants_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE;


--
-- Name: production_orders production_orders_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.production_orders
    ADD CONSTRAINT production_orders_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: production_orders production_orders_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.production_orders
    ADD CONSTRAINT production_orders_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE;


--
-- Name: production_orders production_orders_warehouse_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.production_orders
    ADD CONSTRAINT production_orders_warehouse_id_fkey FOREIGN KEY (warehouse_id) REFERENCES public.warehouses(id) ON DELETE SET NULL;


--
-- Name: production_orders production_orders_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.production_orders
    ADD CONSTRAINT production_orders_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: products products_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.product_categories(id) ON DELETE SET NULL;


--
-- Name: products products_tax_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_tax_id_fkey FOREIGN KEY (tax_id) REFERENCES public.taxes(id) ON DELETE SET NULL;


--
-- Name: products products_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: projects projects_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT projects_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE SET NULL;


--
-- Name: projects projects_manager_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT projects_manager_id_fkey FOREIGN KEY (manager_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: projects projects_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT projects_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: promotions promotions_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promotions
    ADD CONSTRAINT promotions_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: provisioning_entity_bindings provisioning_entity_bindings_last_blueprint_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provisioning_entity_bindings
    ADD CONSTRAINT provisioning_entity_bindings_last_blueprint_id_foreign FOREIGN KEY (last_blueprint_id) REFERENCES public.discovery_blueprints(id) ON DELETE CASCADE;


--
-- Name: provisioning_entity_bindings provisioning_entity_bindings_last_provisioning_run_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provisioning_entity_bindings
    ADD CONSTRAINT provisioning_entity_bindings_last_provisioning_run_id_foreign FOREIGN KEY (last_provisioning_run_id) REFERENCES public.provisioning_runs(id) ON DELETE CASCADE;


--
-- Name: provisioning_entity_bindings provisioning_entity_bindings_workspace_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provisioning_entity_bindings
    ADD CONSTRAINT provisioning_entity_bindings_workspace_id_foreign FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: provisioning_runs provisioning_runs_applied_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provisioning_runs
    ADD CONSTRAINT provisioning_runs_applied_by_fkey FOREIGN KEY (applied_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: provisioning_runs provisioning_runs_blueprint_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provisioning_runs
    ADD CONSTRAINT provisioning_runs_blueprint_id_fkey FOREIGN KEY (blueprint_id) REFERENCES public.discovery_blueprints(id) ON DELETE CASCADE;


--
-- Name: provisioning_runs provisioning_runs_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provisioning_runs
    ADD CONSTRAINT provisioning_runs_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: purchase_order_items purchase_order_items_po_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_order_items
    ADD CONSTRAINT purchase_order_items_po_id_fkey FOREIGN KEY (po_id) REFERENCES public.purchase_orders(id) ON DELETE CASCADE;


--
-- Name: purchase_order_items purchase_order_items_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_order_items
    ADD CONSTRAINT purchase_order_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE RESTRICT;


--
-- Name: purchase_order_items purchase_order_items_unit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_order_items
    ADD CONSTRAINT purchase_order_items_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES public.units_of_measure(id) ON DELETE SET NULL;


--
-- Name: purchase_order_items purchase_order_items_variant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_order_items
    ADD CONSTRAINT purchase_order_items_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.product_variants(id) ON DELETE SET NULL;


--
-- Name: purchase_order_items purchase_order_items_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_order_items
    ADD CONSTRAINT purchase_order_items_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: purchase_orders purchase_orders_approved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_orders
    ADD CONSTRAINT purchase_orders_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: purchase_orders purchase_orders_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_orders
    ADD CONSTRAINT purchase_orders_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(id) ON DELETE SET NULL;


--
-- Name: purchase_orders purchase_orders_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_orders
    ADD CONSTRAINT purchase_orders_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: purchase_orders purchase_orders_supplier_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_orders
    ADD CONSTRAINT purchase_orders_supplier_contact_id_fkey FOREIGN KEY (supplier_contact_id) REFERENCES public.contacts(id) ON DELETE RESTRICT;


--
-- Name: purchase_orders purchase_orders_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchase_orders
    ADD CONSTRAINT purchase_orders_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: record_documents record_documents_document_checklist_item_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.record_documents
    ADD CONSTRAINT record_documents_document_checklist_item_id_foreign FOREIGN KEY (document_checklist_item_id) REFERENCES public.document_checklist_items(id) ON DELETE SET NULL;


--
-- Name: record_documents record_documents_pipeline_record_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.record_documents
    ADD CONSTRAINT record_documents_pipeline_record_id_foreign FOREIGN KEY (pipeline_record_id) REFERENCES public.pipeline_records(id) ON DELETE CASCADE;


--
-- Name: record_documents record_documents_uploaded_by_membership_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.record_documents
    ADD CONSTRAINT record_documents_uploaded_by_membership_id_foreign FOREIGN KEY (uploaded_by_membership_id) REFERENCES public.workspace_memberships(id) ON DELETE SET NULL;


--
-- Name: record_documents record_documents_workspace_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.record_documents
    ADD CONSTRAINT record_documents_workspace_id_foreign FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: recurring_expenses recurring_expenses_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recurring_expenses
    ADD CONSTRAINT recurring_expenses_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: referral_programs referral_programs_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.referral_programs
    ADD CONSTRAINT referral_programs_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: referrals referrals_program_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.referrals
    ADD CONSTRAINT referrals_program_id_fkey FOREIGN KEY (program_id) REFERENCES public.referral_programs(id) ON DELETE CASCADE;


--
-- Name: referrals referrals_referee_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.referrals
    ADD CONSTRAINT referrals_referee_contact_id_fkey FOREIGN KEY (referee_contact_id) REFERENCES public.contacts(id) ON DELETE SET NULL;


--
-- Name: referrals referrals_referrer_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.referrals
    ADD CONSTRAINT referrals_referrer_contact_id_fkey FOREIGN KEY (referrer_contact_id) REFERENCES public.contacts(id) ON DELETE CASCADE;


--
-- Name: referrals referrals_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.referrals
    ADD CONSTRAINT referrals_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: report_runs report_runs_report_template_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.report_runs
    ADD CONSTRAINT report_runs_report_template_id_foreign FOREIGN KEY (report_template_id) REFERENCES public.report_templates(id) ON DELETE SET NULL;


--
-- Name: report_runs report_runs_run_by_membership_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.report_runs
    ADD CONSTRAINT report_runs_run_by_membership_id_foreign FOREIGN KEY (run_by_membership_id) REFERENCES public.workspace_memberships(id) ON DELETE SET NULL;


--
-- Name: report_runs report_runs_workspace_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.report_runs
    ADD CONSTRAINT report_runs_workspace_id_foreign FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: report_templates report_templates_created_by_membership_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.report_templates
    ADD CONSTRAINT report_templates_created_by_membership_id_foreign FOREIGN KEY (created_by_membership_id) REFERENCES public.workspace_memberships(id) ON DELETE SET NULL;


--
-- Name: report_templates report_templates_workspace_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.report_templates
    ADD CONSTRAINT report_templates_workspace_id_foreign FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: retention_policies retention_policies_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.retention_policies
    ADD CONSTRAINT retention_policies_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: return_items return_items_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.return_items
    ADD CONSTRAINT return_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE RESTRICT;


--
-- Name: return_items return_items_restocked_warehouse_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.return_items
    ADD CONSTRAINT return_items_restocked_warehouse_id_fkey FOREIGN KEY (restocked_warehouse_id) REFERENCES public.warehouses(id) ON DELETE SET NULL;


--
-- Name: return_items return_items_return_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.return_items
    ADD CONSTRAINT return_items_return_id_fkey FOREIGN KEY (return_id) REFERENCES public.returns(id) ON DELETE CASCADE;


--
-- Name: return_items return_items_variant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.return_items
    ADD CONSTRAINT return_items_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.product_variants(id) ON DELETE SET NULL;


--
-- Name: return_items return_items_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.return_items
    ADD CONSTRAINT return_items_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: returns returns_approved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.returns
    ADD CONSTRAINT returns_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: returns returns_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.returns
    ADD CONSTRAINT returns_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE RESTRICT;


--
-- Name: returns returns_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.returns
    ADD CONSTRAINT returns_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: returns returns_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.returns
    ADD CONSTRAINT returns_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES public.invoices(id) ON DELETE SET NULL;


--
-- Name: returns returns_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.returns
    ADD CONSTRAINT returns_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE SET NULL;


--
-- Name: returns returns_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.returns
    ADD CONSTRAINT returns_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: roles roles_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: segment_contacts segment_contacts_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.segment_contacts
    ADD CONSTRAINT segment_contacts_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id) ON DELETE CASCADE;


--
-- Name: segment_contacts segment_contacts_segment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.segment_contacts
    ADD CONSTRAINT segment_contacts_segment_id_fkey FOREIGN KEY (segment_id) REFERENCES public.segments(id) ON DELETE CASCADE;


--
-- Name: segments segments_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.segments
    ADD CONSTRAINT segments_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: shift_assignments shift_assignments_assigned_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shift_assignments
    ADD CONSTRAINT shift_assignments_assigned_by_fkey FOREIGN KEY (assigned_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: shift_assignments shift_assignments_shift_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shift_assignments
    ADD CONSTRAINT shift_assignments_shift_id_fkey FOREIGN KEY (shift_id) REFERENCES public.shifts(id) ON DELETE CASCADE;


--
-- Name: shift_assignments shift_assignments_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shift_assignments
    ADD CONSTRAINT shift_assignments_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: shift_assignments shift_assignments_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shift_assignments
    ADD CONSTRAINT shift_assignments_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: shifts shifts_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shifts
    ADD CONSTRAINT shifts_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: shipment_items shipment_items_batch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shipment_items
    ADD CONSTRAINT shipment_items_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES public.inventory_batches(id) ON DELETE SET NULL;


--
-- Name: shipment_items shipment_items_order_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shipment_items
    ADD CONSTRAINT shipment_items_order_item_id_fkey FOREIGN KEY (order_item_id) REFERENCES public.order_items(id) ON DELETE SET NULL;


--
-- Name: shipment_items shipment_items_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shipment_items
    ADD CONSTRAINT shipment_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE RESTRICT;


--
-- Name: shipment_items shipment_items_reservation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shipment_items
    ADD CONSTRAINT shipment_items_reservation_id_fkey FOREIGN KEY (reservation_id) REFERENCES public.stock_reservations(id) ON DELETE SET NULL;


--
-- Name: shipment_items shipment_items_shipment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shipment_items
    ADD CONSTRAINT shipment_items_shipment_id_fkey FOREIGN KEY (shipment_id) REFERENCES public.shipments(id) ON DELETE CASCADE;


--
-- Name: shipment_items shipment_items_variant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shipment_items
    ADD CONSTRAINT shipment_items_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.product_variants(id) ON DELETE SET NULL;


--
-- Name: shipment_items shipment_items_warehouse_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shipment_items
    ADD CONSTRAINT shipment_items_warehouse_id_fkey FOREIGN KEY (warehouse_id) REFERENCES public.warehouses(id) ON DELETE RESTRICT;


--
-- Name: shipment_items shipment_items_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shipment_items
    ADD CONSTRAINT shipment_items_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: shipments shipments_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shipments
    ADD CONSTRAINT shipments_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id);


--
-- Name: shipments shipments_delivery_driver_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shipments
    ADD CONSTRAINT shipments_delivery_driver_id_fkey FOREIGN KEY (delivery_driver_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: shipments shipments_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shipments
    ADD CONSTRAINT shipments_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES public.invoices(id);


--
-- Name: shipments shipments_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shipments
    ADD CONSTRAINT shipments_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE SET NULL;


--
-- Name: shipments shipments_warehouse_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shipments
    ADD CONSTRAINT shipments_warehouse_id_fkey FOREIGN KEY (warehouse_id) REFERENCES public.warehouses(id) ON DELETE SET NULL;


--
-- Name: shipments shipments_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shipments
    ADD CONSTRAINT shipments_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: stock_reservations stock_reservations_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_reservations
    ADD CONSTRAINT stock_reservations_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;


--
-- Name: stock_reservations stock_reservations_order_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_reservations
    ADD CONSTRAINT stock_reservations_order_item_id_fkey FOREIGN KEY (order_item_id) REFERENCES public.order_items(id) ON DELETE CASCADE;


--
-- Name: stock_reservations stock_reservations_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_reservations
    ADD CONSTRAINT stock_reservations_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE;


--
-- Name: stock_reservations stock_reservations_variant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_reservations
    ADD CONSTRAINT stock_reservations_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.product_variants(id) ON DELETE SET NULL;


--
-- Name: stock_reservations stock_reservations_warehouse_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_reservations
    ADD CONSTRAINT stock_reservations_warehouse_id_fkey FOREIGN KEY (warehouse_id) REFERENCES public.warehouses(id) ON DELETE CASCADE;


--
-- Name: stock_reservations stock_reservations_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_reservations
    ADD CONSTRAINT stock_reservations_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: stock_transfer_items stock_transfer_items_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_transfer_items
    ADD CONSTRAINT stock_transfer_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE;


--
-- Name: stock_transfer_items stock_transfer_items_transfer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_transfer_items
    ADD CONSTRAINT stock_transfer_items_transfer_id_fkey FOREIGN KEY (transfer_id) REFERENCES public.stock_transfers(id) ON DELETE CASCADE;


--
-- Name: stock_transfer_items stock_transfer_items_variant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_transfer_items
    ADD CONSTRAINT stock_transfer_items_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.product_variants(id) ON DELETE SET NULL;


--
-- Name: stock_transfers stock_transfers_approved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_transfers
    ADD CONSTRAINT stock_transfers_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: stock_transfers stock_transfers_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_transfers
    ADD CONSTRAINT stock_transfers_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: stock_transfers stock_transfers_from_warehouse_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_transfers
    ADD CONSTRAINT stock_transfers_from_warehouse_id_fkey FOREIGN KEY (from_warehouse_id) REFERENCES public.warehouses(id) ON DELETE CASCADE;


--
-- Name: stock_transfers stock_transfers_to_warehouse_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_transfers
    ADD CONSTRAINT stock_transfers_to_warehouse_id_fkey FOREIGN KEY (to_warehouse_id) REFERENCES public.warehouses(id) ON DELETE CASCADE;


--
-- Name: stock_transfers stock_transfers_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_transfers
    ADD CONSTRAINT stock_transfers_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: sync_logs sync_logs_integration_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sync_logs
    ADD CONSTRAINT sync_logs_integration_id_fkey FOREIGN KEY (integration_id) REFERENCES public.workspace_integrations(id) ON DELETE CASCADE;


--
-- Name: sync_logs sync_logs_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sync_logs
    ADD CONSTRAINT sync_logs_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: tasks tasks_assigned_to_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT tasks_assigned_to_fkey FOREIGN KEY (assigned_to) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: tasks tasks_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT tasks_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE;


--
-- Name: tasks tasks_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT tasks_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: tax_rules tax_rules_country_pack_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tax_rules
    ADD CONSTRAINT tax_rules_country_pack_id_fkey FOREIGN KEY (country_pack_id) REFERENCES public.country_packs(id) ON DELETE SET NULL;


--
-- Name: tax_rules tax_rules_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tax_rules
    ADD CONSTRAINT tax_rules_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: taxes taxes_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taxes
    ADD CONSTRAINT taxes_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: teams teams_department_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teams
    ADD CONSTRAINT teams_department_id_foreign FOREIGN KEY (department_id) REFERENCES public.departments(id) ON DELETE SET NULL;


--
-- Name: teams teams_manager_membership_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teams
    ADD CONSTRAINT teams_manager_membership_id_foreign FOREIGN KEY (manager_membership_id) REFERENCES public.workspace_memberships(id) ON DELETE SET NULL;


--
-- Name: teams teams_workspace_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teams
    ADD CONSTRAINT teams_workspace_id_foreign FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: transactions transactions_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transactions
    ADD CONSTRAINT transactions_account_id_fkey FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- Name: transactions transactions_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transactions
    ADD CONSTRAINT transactions_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id);


--
-- Name: transactions transactions_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transactions
    ADD CONSTRAINT transactions_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: transactions transactions_from_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transactions
    ADD CONSTRAINT transactions_from_account_id_fkey FOREIGN KEY (from_account_id) REFERENCES public.accounts(id);


--
-- Name: transactions transactions_to_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transactions
    ADD CONSTRAINT transactions_to_account_id_fkey FOREIGN KEY (to_account_id) REFERENCES public.accounts(id);


--
-- Name: transactions transactions_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transactions
    ADD CONSTRAINT transactions_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: units_of_measure units_of_measure_base_unit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.units_of_measure
    ADD CONSTRAINT units_of_measure_base_unit_id_fkey FOREIGN KEY (base_unit_id) REFERENCES public.units_of_measure(id) ON DELETE SET NULL;


--
-- Name: units_of_measure units_of_measure_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.units_of_measure
    ADD CONSTRAINT units_of_measure_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: user_permission_overrides user_permission_overrides_granted_by_membership_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_permission_overrides
    ADD CONSTRAINT user_permission_overrides_granted_by_membership_id_fkey FOREIGN KEY (granted_by_membership_id) REFERENCES public.workspace_memberships(id) ON DELETE CASCADE;


--
-- Name: user_permission_overrides user_permission_overrides_membership_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_permission_overrides
    ADD CONSTRAINT user_permission_overrides_membership_id_fkey FOREIGN KEY (membership_id) REFERENCES public.workspace_memberships(id) ON DELETE CASCADE;


--
-- Name: user_permission_overrides user_permission_overrides_permission_key_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_permission_overrides
    ADD CONSTRAINT user_permission_overrides_permission_key_fkey FOREIGN KEY (permission_key) REFERENCES public.permission_definitions(key) ON DELETE CASCADE;


--
-- Name: user_permission_overrides user_permission_overrides_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_permission_overrides
    ADD CONSTRAINT user_permission_overrides_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: users users_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_branch_id_fkey FOREIGN KEY (branch_id_deprecated) REFERENCES public.branches(id) ON DELETE SET NULL;


--
-- Name: users users_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_department_id_fkey FOREIGN KEY (department_id_deprecated) REFERENCES public.departments(id) ON DELETE SET NULL;


--
-- Name: users users_manager_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_manager_id_fkey FOREIGN KEY (manager_id_deprecated) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: users users_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_role_id_fkey FOREIGN KEY (role_id_deprecated) REFERENCES public.roles(id) ON DELETE SET NULL;


--
-- Name: users users_shift_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_shift_id_fkey FOREIGN KEY (shift_id_deprecated) REFERENCES public.shifts(id) ON DELETE SET NULL;


--
-- Name: users users_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_workspace_id_fkey FOREIGN KEY (workspace_id_deprecated) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: warehouses warehouses_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.warehouses
    ADD CONSTRAINT warehouses_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(id) ON DELETE SET NULL;


--
-- Name: warehouses warehouses_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.warehouses
    ADD CONSTRAINT warehouses_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: webhook_deliveries webhook_deliveries_subscription_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_deliveries
    ADD CONSTRAINT webhook_deliveries_subscription_id_fkey FOREIGN KEY (subscription_id) REFERENCES public.webhook_subscriptions(id) ON DELETE CASCADE;


--
-- Name: webhook_subscriptions webhook_subscriptions_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_subscriptions
    ADD CONSTRAINT webhook_subscriptions_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: work_centers work_centers_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_centers
    ADD CONSTRAINT work_centers_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: workspace_configurations workspace_configurations_provisioning_run_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_configurations
    ADD CONSTRAINT workspace_configurations_provisioning_run_id_fkey FOREIGN KEY (provisioning_run_id) REFERENCES public.provisioning_runs(id) ON DELETE SET NULL;


--
-- Name: workspace_configurations workspace_configurations_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_configurations
    ADD CONSTRAINT workspace_configurations_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: workspace_country_packs workspace_country_packs_country_pack_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_country_packs
    ADD CONSTRAINT workspace_country_packs_country_pack_id_fkey FOREIGN KEY (country_pack_id) REFERENCES public.country_packs(id) ON DELETE RESTRICT;


--
-- Name: workspace_country_packs workspace_country_packs_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_country_packs
    ADD CONSTRAINT workspace_country_packs_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: workspace_feature_flags workspace_feature_flags_set_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_feature_flags
    ADD CONSTRAINT workspace_feature_flags_set_by_fkey FOREIGN KEY (set_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: workspace_feature_flags workspace_feature_flags_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_feature_flags
    ADD CONSTRAINT workspace_feature_flags_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: workspace_integrations workspace_integrations_provider_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_integrations
    ADD CONSTRAINT workspace_integrations_provider_id_fkey FOREIGN KEY (provider_id) REFERENCES public.integration_providers(id) ON DELETE RESTRICT;


--
-- Name: workspace_integrations workspace_integrations_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_integrations
    ADD CONSTRAINT workspace_integrations_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: workspace_invitation_roles workspace_invitation_roles_role_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_invitation_roles
    ADD CONSTRAINT workspace_invitation_roles_role_id_foreign FOREIGN KEY (role_id) REFERENCES public.roles(id) ON DELETE CASCADE;


--
-- Name: workspace_invitation_roles workspace_invitation_roles_workspace_invitation_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_invitation_roles
    ADD CONSTRAINT workspace_invitation_roles_workspace_invitation_id_foreign FOREIGN KEY (workspace_invitation_id) REFERENCES public.workspace_invitations(id) ON DELETE CASCADE;


--
-- Name: workspace_invitations workspace_invitations_accepted_user_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_invitations
    ADD CONSTRAINT workspace_invitations_accepted_user_id_foreign FOREIGN KEY (accepted_user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: workspace_invitations workspace_invitations_department_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_invitations
    ADD CONSTRAINT workspace_invitations_department_id_foreign FOREIGN KEY (department_id) REFERENCES public.departments(id) ON DELETE SET NULL;


--
-- Name: workspace_invitations workspace_invitations_invited_by_user_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_invitations
    ADD CONSTRAINT workspace_invitations_invited_by_user_id_foreign FOREIGN KEY (invited_by_user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: workspace_invitations workspace_invitations_role_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_invitations
    ADD CONSTRAINT workspace_invitations_role_id_foreign FOREIGN KEY (role_id) REFERENCES public.roles(id) ON DELETE SET NULL;


--
-- Name: workspace_invitations workspace_invitations_team_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_invitations
    ADD CONSTRAINT workspace_invitations_team_id_foreign FOREIGN KEY (team_id) REFERENCES public.teams(id) ON DELETE SET NULL;


--
-- Name: workspace_invitations workspace_invitations_workspace_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_invitations
    ADD CONSTRAINT workspace_invitations_workspace_id_foreign FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: workspace_memberships workspace_memberships_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_memberships
    ADD CONSTRAINT workspace_memberships_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(id) ON DELETE SET NULL;


--
-- Name: workspace_memberships workspace_memberships_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_memberships
    ADD CONSTRAINT workspace_memberships_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.departments(id) ON DELETE SET NULL;


--
-- Name: workspace_memberships workspace_memberships_manager_membership_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_memberships
    ADD CONSTRAINT workspace_memberships_manager_membership_id_fkey FOREIGN KEY (manager_membership_id) REFERENCES public.workspace_memberships(id) ON DELETE SET NULL;


--
-- Name: workspace_memberships workspace_memberships_shift_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_memberships
    ADD CONSTRAINT workspace_memberships_shift_id_fkey FOREIGN KEY (shift_id) REFERENCES public.shifts(id) ON DELETE SET NULL;


--
-- Name: workspace_memberships workspace_memberships_team_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_memberships
    ADD CONSTRAINT workspace_memberships_team_id_foreign FOREIGN KEY (team_id) REFERENCES public.teams(id) ON DELETE SET NULL;


--
-- Name: workspace_memberships workspace_memberships_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_memberships
    ADD CONSTRAINT workspace_memberships_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: workspace_memberships workspace_memberships_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_memberships
    ADD CONSTRAINT workspace_memberships_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: workspace_subscriptions workspace_subscriptions_plan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_subscriptions
    ADD CONSTRAINT workspace_subscriptions_plan_id_fkey FOREIGN KEY (plan_id) REFERENCES public.platform_plans(id);


--
-- Name: workspace_subscriptions workspace_subscriptions_plan_price_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_subscriptions
    ADD CONSTRAINT workspace_subscriptions_plan_price_id_fkey FOREIGN KEY (plan_price_id) REFERENCES public.platform_plan_prices(id);


--
-- Name: workspace_subscriptions workspace_subscriptions_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_subscriptions
    ADD CONSTRAINT workspace_subscriptions_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: workspace_template_applications workspace_template_applications_business_template_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_template_applications
    ADD CONSTRAINT workspace_template_applications_business_template_id_foreign FOREIGN KEY (business_template_id) REFERENCES public.business_templates(id) ON DELETE RESTRICT;


--
-- Name: workspace_template_applications workspace_template_applications_workspace_id_foreign; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workspace_template_applications
    ADD CONSTRAINT workspace_template_applications_workspace_id_foreign FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE CASCADE;


--
-- Name: accounts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.accounts ENABLE ROW LEVEL SECURITY;

--
-- Name: ai_change_requests; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.ai_change_requests ENABLE ROW LEVEL SECURITY;

--
-- Name: ai_change_requests ai_change_requests_tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ai_change_requests_tenant_isolation ON public.ai_change_requests USING ((workspace_id = (NULLIF(current_setting('app.workspace_id'::text, true), ''::text))::uuid)) WITH CHECK ((workspace_id = (NULLIF(current_setting('app.workspace_id'::text, true), ''::text))::uuid));


--
-- Name: ai_conversations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.ai_conversations ENABLE ROW LEVEL SECURITY;

--
-- Name: ai_conversations ai_conversations_tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ai_conversations_tenant_isolation ON public.ai_conversations USING ((workspace_id = (NULLIF(current_setting('app.workspace_id'::text, true), ''::text))::uuid)) WITH CHECK ((workspace_id = (NULLIF(current_setting('app.workspace_id'::text, true), ''::text))::uuid));


--
-- Name: ai_execution_plans; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.ai_execution_plans ENABLE ROW LEVEL SECURITY;

--
-- Name: ai_execution_plans ai_execution_plans_tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ai_execution_plans_tenant_isolation ON public.ai_execution_plans USING ((workspace_id = (NULLIF(current_setting('app.workspace_id'::text, true), ''::text))::uuid)) WITH CHECK ((workspace_id = (NULLIF(current_setting('app.workspace_id'::text, true), ''::text))::uuid));


--
-- Name: ai_insights; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.ai_insights ENABLE ROW LEVEL SECURITY;

--
-- Name: ai_insights ai_insights_tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ai_insights_tenant_isolation ON public.ai_insights USING ((workspace_id = (NULLIF(current_setting('app.workspace_id'::text, true), ''::text))::uuid)) WITH CHECK ((workspace_id = (NULLIF(current_setting('app.workspace_id'::text, true), ''::text))::uuid));


--
-- Name: ai_memory; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.ai_memory ENABLE ROW LEVEL SECURITY;

--
-- Name: ai_memory ai_memory_tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ai_memory_tenant_isolation ON public.ai_memory USING ((workspace_id = (NULLIF(current_setting('app.workspace_id'::text, true), ''::text))::uuid)) WITH CHECK ((workspace_id = (NULLIF(current_setting('app.workspace_id'::text, true), ''::text))::uuid));


--
-- Name: ai_messages; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.ai_messages ENABLE ROW LEVEL SECURITY;

--
-- Name: ai_messages ai_messages_tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ai_messages_tenant_isolation ON public.ai_messages USING ((workspace_id = (NULLIF(current_setting('app.workspace_id'::text, true), ''::text))::uuid)) WITH CHECK ((workspace_id = (NULLIF(current_setting('app.workspace_id'::text, true), ''::text))::uuid));


--
-- Name: ai_recommendations ai_rec_workspace_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ai_rec_workspace_isolation ON public.ai_recommendations USING ((workspace_id = (current_setting('app.workspace_id'::text))::uuid));


--
-- Name: ai_recommendations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.ai_recommendations ENABLE ROW LEVEL SECURITY;

--
-- Name: ai_usage_logs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.ai_usage_logs ENABLE ROW LEVEL SECURITY;

--
-- Name: ai_usage_logs ai_usage_logs_tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ai_usage_logs_tenant_isolation ON public.ai_usage_logs USING ((workspace_id = (NULLIF(current_setting('app.workspace_id'::text, true), ''::text))::uuid)) WITH CHECK ((workspace_id = (NULLIF(current_setting('app.workspace_id'::text, true), ''::text))::uuid));


--
-- Name: ai_workspace_settings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.ai_workspace_settings ENABLE ROW LEVEL SECURITY;

--
-- Name: ai_workspace_settings ai_workspace_settings_tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ai_workspace_settings_tenant_isolation ON public.ai_workspace_settings USING ((workspace_id = (NULLIF(current_setting('app.workspace_id'::text, true), ''::text))::uuid)) WITH CHECK ((workspace_id = (NULLIF(current_setting('app.workspace_id'::text, true), ''::text))::uuid));


--
-- Name: archival_jobs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.archival_jobs ENABLE ROW LEVEL SECURITY;

--
-- Name: async_jobs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.async_jobs ENABLE ROW LEVEL SECURITY;

--
-- Name: attachments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.attachments ENABLE ROW LEVEL SECURITY;

--
-- Name: attendance; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.attendance ENABLE ROW LEVEL SECURITY;

--
-- Name: audit_logs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

--
-- Name: automation_logs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.automation_logs ENABLE ROW LEVEL SECURITY;

--
-- Name: bill_of_materials; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.bill_of_materials ENABLE ROW LEVEL SECURITY;

--
-- Name: billing_invoices; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.billing_invoices ENABLE ROW LEVEL SECURITY;

--
-- Name: billing_payments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.billing_payments ENABLE ROW LEVEL SECURITY;

--
-- Name: bookings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.bookings ENABLE ROW LEVEL SECURITY;

--
-- Name: branches; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.branches ENABLE ROW LEVEL SECURITY;

--
-- Name: brand_kits; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.brand_kits ENABLE ROW LEVEL SECURITY;

--
-- Name: campaigns; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.campaigns ENABLE ROW LEVEL SECURITY;

--
-- Name: cod_collections; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.cod_collections ENABLE ROW LEVEL SECURITY;

--
-- Name: communication_automations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.communication_automations ENABLE ROW LEVEL SECURITY;

--
-- Name: communication_channels; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.communication_channels ENABLE ROW LEVEL SECURITY;

--
-- Name: contacts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.contacts ENABLE ROW LEVEL SECURITY;

--
-- Name: coupons; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.coupons ENABLE ROW LEVEL SECURITY;

--
-- Name: credit_note_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.credit_note_items ENABLE ROW LEVEL SECURITY;

--
-- Name: credit_notes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.credit_notes ENABLE ROW LEVEL SECURITY;

--
-- Name: crm_activities; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.crm_activities ENABLE ROW LEVEL SECURITY;

--
-- Name: customer_credits; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.customer_credits ENABLE ROW LEVEL SECURITY;

--
-- Name: customer_subscriptions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.customer_subscriptions ENABLE ROW LEVEL SECURITY;

--
-- Name: delivery_assignments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.delivery_assignments ENABLE ROW LEVEL SECURITY;

--
-- Name: delivery_zones; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.delivery_zones ENABLE ROW LEVEL SECURITY;

--
-- Name: departments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.departments ENABLE ROW LEVEL SECURITY;

--
-- Name: dining_tables; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.dining_tables ENABLE ROW LEVEL SECURITY;

--
-- Name: discovery_blueprints; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.discovery_blueprints ENABLE ROW LEVEL SECURITY;

--
-- Name: discovery_blueprints discovery_blueprints_workspace_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY discovery_blueprints_workspace_isolation ON public.discovery_blueprints USING ((workspace_id = (NULLIF(current_setting('app.workspace_id'::text, true), ''::text))::uuid)) WITH CHECK ((workspace_id = (NULLIF(current_setting('app.workspace_id'::text, true), ''::text))::uuid));


--
-- Name: discovery_messages; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.discovery_messages ENABLE ROW LEVEL SECURITY;

--
-- Name: discovery_messages discovery_messages_workspace_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY discovery_messages_workspace_isolation ON public.discovery_messages USING ((workspace_id = (NULLIF(current_setting('app.workspace_id'::text, true), ''::text))::uuid)) WITH CHECK ((workspace_id = (NULLIF(current_setting('app.workspace_id'::text, true), ''::text))::uuid));


--
-- Name: discovery_sessions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.discovery_sessions ENABLE ROW LEVEL SECURITY;

--
-- Name: discovery_sessions discovery_sessions_workspace_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY discovery_sessions_workspace_isolation ON public.discovery_sessions USING ((workspace_id = (NULLIF(current_setting('app.workspace_id'::text, true), ''::text))::uuid)) WITH CHECK ((workspace_id = (NULLIF(current_setting('app.workspace_id'::text, true), ''::text))::uuid));


--
-- Name: document_sequences; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.document_sequences ENABLE ROW LEVEL SECURITY;

--
-- Name: drivers; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.drivers ENABLE ROW LEVEL SECURITY;

--
-- Name: email_logs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.email_logs ENABLE ROW LEVEL SECURITY;

--
-- Name: email_logs email_logs_workspace_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY email_logs_workspace_isolation ON public.email_logs USING ((workspace_id = (current_setting('app.workspace_id'::text))::uuid));


--
-- Name: email_settings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.email_settings ENABLE ROW LEVEL SECURITY;

--
-- Name: email_settings email_settings_workspace_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY email_settings_workspace_isolation ON public.email_settings USING ((workspace_id = (current_setting('app.workspace_id'::text))::uuid));


--
-- Name: exchange_rates; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.exchange_rates ENABLE ROW LEVEL SECURITY;

--
-- Name: export_jobs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;

--
-- Name: fiscal_periods; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.fiscal_periods ENABLE ROW LEVEL SECURITY;

--
-- Name: fixed_assets; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.fixed_assets ENABLE ROW LEVEL SECURITY;

--
-- Name: goods_received_notes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.goods_received_notes ENABLE ROW LEVEL SECURITY;

--
-- Name: grn_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.grn_items ENABLE ROW LEVEL SECURITY;

--
-- Name: idempotency_keys; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.idempotency_keys ENABLE ROW LEVEL SECURITY;

--
-- Name: import_jobs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.import_jobs ENABLE ROW LEVEL SECURITY;

--
-- Name: inbound_messages; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.inbound_messages ENABLE ROW LEVEL SECURITY;

--
-- Name: inventory_batches; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.inventory_batches ENABLE ROW LEVEL SECURITY;

--
-- Name: inventory_levels; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.inventory_levels ENABLE ROW LEVEL SECURITY;

--
-- Name: inventory_logs_legacy; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.inventory_logs_legacy ENABLE ROW LEVEL SECURITY;

--
-- Name: inventory_movements; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.inventory_movements ENABLE ROW LEVEL SECURITY;

--
-- Name: invoices; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.invoices ENABLE ROW LEVEL SECURITY;

--
-- Name: journal_entries; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.journal_entries ENABLE ROW LEVEL SECURITY;

--
-- Name: leads; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.leads ENABLE ROW LEVEL SECURITY;

--
-- Name: leave_balances; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.leave_balances ENABLE ROW LEVEL SECURITY;

--
-- Name: leave_requests; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.leave_requests ENABLE ROW LEVEL SECURITY;

--
-- Name: leave_types; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.leave_types ENABLE ROW LEVEL SECURITY;

--
-- Name: leaves_legacy; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.leaves_legacy ENABLE ROW LEVEL SECURITY;

--
-- Name: loyalty_accounts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.loyalty_accounts ENABLE ROW LEVEL SECURITY;

--
-- Name: loyalty_programs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.loyalty_programs ENABLE ROW LEVEL SECURITY;

--
-- Name: manual_payments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.manual_payments ENABLE ROW LEVEL SECURITY;

--
-- Name: media_assets; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.media_assets ENABLE ROW LEVEL SECURITY;

--
-- Name: media_generation_requests; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.media_generation_requests ENABLE ROW LEVEL SECURITY;

--
-- Name: membership_roles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.membership_roles ENABLE ROW LEVEL SECURITY;

--
-- Name: message_templates; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.message_templates ENABLE ROW LEVEL SECURITY;

--
-- Name: message_threads; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.message_threads ENABLE ROW LEVEL SECURITY;

--
-- Name: notifications; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

--
-- Name: nurturing_sequences; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.nurturing_sequences ENABLE ROW LEVEL SECURITY;

--
-- Name: opportunities; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.opportunities ENABLE ROW LEVEL SECURITY;

--
-- Name: orders; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

--
-- Name: outbound_messages; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.outbound_messages ENABLE ROW LEVEL SECURITY;

--
-- Name: payments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;

--
-- Name: payroll; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payroll ENABLE ROW LEVEL SECURITY;

--
-- Name: payroll_lines; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payroll_lines ENABLE ROW LEVEL SECURITY;

--
-- Name: payroll_runs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payroll_runs ENABLE ROW LEVEL SECURITY;

--
-- Name: permission_delegations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.permission_delegations ENABLE ROW LEVEL SECURITY;

--
-- Name: pos_sessions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.pos_sessions ENABLE ROW LEVEL SECURITY;

--
-- Name: pos_terminals; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.pos_terminals ENABLE ROW LEVEL SECURITY;

--
-- Name: price_lists; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.price_lists ENABLE ROW LEVEL SECURITY;

--
-- Name: product_categories; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.product_categories ENABLE ROW LEVEL SECURITY;

--
-- Name: production_orders; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.production_orders ENABLE ROW LEVEL SECURITY;

--
-- Name: products; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

--
-- Name: projects; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.projects ENABLE ROW LEVEL SECURITY;

--
-- Name: promotions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.promotions ENABLE ROW LEVEL SECURITY;

--
-- Name: provisioning_runs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.provisioning_runs ENABLE ROW LEVEL SECURITY;

--
-- Name: purchase_order_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.purchase_order_items ENABLE ROW LEVEL SECURITY;

--
-- Name: purchase_orders; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;

--
-- Name: recurring_expenses; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.recurring_expenses ENABLE ROW LEVEL SECURITY;

--
-- Name: referral_programs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.referral_programs ENABLE ROW LEVEL SECURITY;

--
-- Name: referrals; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.referrals ENABLE ROW LEVEL SECURITY;

--
-- Name: retention_policies; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.retention_policies ENABLE ROW LEVEL SECURITY;

--
-- Name: return_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.return_items ENABLE ROW LEVEL SECURITY;

--
-- Name: returns; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.returns ENABLE ROW LEVEL SECURITY;

--
-- Name: roles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.roles ENABLE ROW LEVEL SECURITY;

--
-- Name: segments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.segments ENABLE ROW LEVEL SECURITY;

--
-- Name: shift_assignments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.shift_assignments ENABLE ROW LEVEL SECURITY;

--
-- Name: shifts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.shifts ENABLE ROW LEVEL SECURITY;

--
-- Name: shipment_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.shipment_items ENABLE ROW LEVEL SECURITY;

--
-- Name: shipments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.shipments ENABLE ROW LEVEL SECURITY;

--
-- Name: stock_reservations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.stock_reservations ENABLE ROW LEVEL SECURITY;

--
-- Name: stock_transfers; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.stock_transfers ENABLE ROW LEVEL SECURITY;

--
-- Name: sync_logs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sync_logs ENABLE ROW LEVEL SECURITY;

--
-- Name: tasks; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;

--
-- Name: tax_rules; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tax_rules ENABLE ROW LEVEL SECURITY;

--
-- Name: taxes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.taxes ENABLE ROW LEVEL SECURITY;

--
-- Name: transactions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;

--
-- Name: units_of_measure; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.units_of_measure ENABLE ROW LEVEL SECURITY;

--
-- Name: user_permission_overrides; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.user_permission_overrides ENABLE ROW LEVEL SECURITY;

--
-- Name: users; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

--
-- Name: warehouses; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.warehouses ENABLE ROW LEVEL SECURITY;

--
-- Name: webhook_subscriptions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.webhook_subscriptions ENABLE ROW LEVEL SECURITY;

--
-- Name: work_centers; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.work_centers ENABLE ROW LEVEL SECURITY;

--
-- Name: workspace_configurations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.workspace_configurations ENABLE ROW LEVEL SECURITY;

--
-- Name: workspace_country_packs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.workspace_country_packs ENABLE ROW LEVEL SECURITY;

--
-- Name: workspace_integrations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.workspace_integrations ENABLE ROW LEVEL SECURITY;

--
-- Name: workspace_memberships; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.workspace_memberships ENABLE ROW LEVEL SECURITY;

--
-- Name: accounts ws_accounts; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_accounts ON public.accounts USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: ai_change_requests ws_ai_change_requests; Type: POLICY; Schema: public; Owner: -
--



--
-- Name: ai_conversations ws_ai_conversations; Type: POLICY; Schema: public; Owner: -
--



--
-- Name: ai_execution_plans ws_ai_execution_plans; Type: POLICY; Schema: public; Owner: -
--



--
-- Name: ai_insights ws_ai_insights; Type: POLICY; Schema: public; Owner: -
--



--
-- Name: ai_memory ws_ai_memory; Type: POLICY; Schema: public; Owner: -
--



--
-- Name: archival_jobs ws_archival_jobs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_archival_jobs ON public.archival_jobs USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: async_jobs ws_async_jobs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_async_jobs ON public.async_jobs USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: attachments ws_attachments; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_attachments ON public.attachments USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: attendance ws_attendance; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_attendance ON public.attendance USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: audit_logs ws_audit_logs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_audit_logs ON public.audit_logs USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: automation_logs ws_automation_logs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_automation_logs ON public.automation_logs USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: inventory_batches ws_batches; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_batches ON public.inventory_batches USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: bill_of_materials ws_bill_of_materials; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_bill_of_materials ON public.bill_of_materials USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: billing_invoices ws_billing_invoices; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_billing_invoices ON public.billing_invoices USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: billing_payments ws_billing_payments; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_billing_payments ON public.billing_payments USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: bookings ws_bookings; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_bookings ON public.bookings USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: branches ws_branches; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_branches ON public.branches USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: brand_kits ws_brand_kits; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_brand_kits ON public.brand_kits USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: campaigns ws_campaigns; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_campaigns ON public.campaigns USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: cod_collections ws_cod_collections; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_cod_collections ON public.cod_collections USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: communication_automations ws_communication_automations; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_communication_automations ON public.communication_automations USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: communication_channels ws_communication_channels; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_communication_channels ON public.communication_channels USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: contacts ws_contacts; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_contacts ON public.contacts USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: coupons ws_coupons; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_coupons ON public.coupons USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: credit_note_items ws_credit_note_items; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_credit_note_items ON public.credit_note_items USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: credit_notes ws_credit_notes; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_credit_notes ON public.credit_notes USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: crm_activities ws_crm; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_crm ON public.crm_activities USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: customer_credits ws_customer_credits; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_customer_credits ON public.customer_credits USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: permission_delegations ws_delegations; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_delegations ON public.permission_delegations USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: delivery_assignments ws_delivery_assignments; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_delivery_assignments ON public.delivery_assignments USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: delivery_zones ws_delivery_zones; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_delivery_zones ON public.delivery_zones USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: departments ws_departments; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_departments ON public.departments USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: document_sequences ws_document_sequences; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_document_sequences ON public.document_sequences USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: drivers ws_drivers; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_drivers ON public.drivers USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: exchange_rates ws_exchange_rates; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_exchange_rates ON public.exchange_rates USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: export_jobs ws_export_jobs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_export_jobs ON public.export_jobs USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: fiscal_periods ws_fiscal_periods; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_fiscal_periods ON public.fiscal_periods USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: fixed_assets ws_fixed_assets; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_fixed_assets ON public.fixed_assets USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: goods_received_notes ws_grn; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_grn ON public.goods_received_notes USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: grn_items ws_grn_items; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_grn_items ON public.grn_items USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: idempotency_keys ws_idempotency_keys; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_idempotency_keys ON public.idempotency_keys USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: import_jobs ws_import_jobs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_import_jobs ON public.import_jobs USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: inbound_messages ws_inbound_messages; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_inbound_messages ON public.inbound_messages USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: inventory_logs_legacy ws_inv_logs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_inv_logs ON public.inventory_logs_legacy USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: inventory_levels ws_inventory_levels; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_inventory_levels ON public.inventory_levels USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: inventory_movements ws_inventory_movements; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_inventory_movements ON public.inventory_movements USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: invoices ws_invoices; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_invoices ON public.invoices USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: POLICY ws_invoices ON invoices; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON POLICY ws_invoices ON public.invoices IS 'RLS: tenant isolation via app.workspace_id session variable (009).';


--
-- Name: journal_entries ws_journal_entries; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_journal_entries ON public.journal_entries USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: leads ws_leads; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_leads ON public.leads USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: leave_balances ws_leave_balances; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_leave_balances ON public.leave_balances USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: leave_requests ws_leave_requests; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_leave_requests ON public.leave_requests USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: leave_types ws_leave_types; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_leave_types ON public.leave_types USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: leaves_legacy ws_leaves; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_leaves ON public.leaves_legacy USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: loyalty_accounts ws_loyalty_accounts; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_loyalty_accounts ON public.loyalty_accounts USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: loyalty_programs ws_loyalty_programs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_loyalty_programs ON public.loyalty_programs USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: manual_payments ws_manual_payments; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_manual_payments ON public.manual_payments USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: media_assets ws_media_assets; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_media_assets ON public.media_assets USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: media_generation_requests ws_media_generation_requests; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_media_generation_requests ON public.media_generation_requests USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: membership_roles ws_membership_roles; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_membership_roles ON public.membership_roles USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: workspace_memberships ws_memberships; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_memberships ON public.workspace_memberships USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: message_templates ws_message_templates; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_message_templates ON public.message_templates USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: message_threads ws_message_threads; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_message_threads ON public.message_threads USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: notifications ws_notifications; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_notifications ON public.notifications USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: nurturing_sequences ws_nurturing_sequences; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_nurturing_sequences ON public.nurturing_sequences USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: opportunities ws_opportunities; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_opportunities ON public.opportunities USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: orders ws_orders; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_orders ON public.orders USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: POLICY ws_orders ON orders; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON POLICY ws_orders ON public.orders IS 'RLS: tenant isolation via app.workspace_id session variable (009).';


--
-- Name: outbound_messages ws_outbound_messages; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_outbound_messages ON public.outbound_messages USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: user_permission_overrides ws_overrides; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_overrides ON public.user_permission_overrides USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: payments ws_payments; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_payments ON public.payments USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: POLICY ws_payments ON payments; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON POLICY ws_payments ON public.payments IS 'RLS: tenant isolation via app.workspace_id session variable (009).';


--
-- Name: payroll ws_payroll; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_payroll ON public.payroll USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: payroll_lines ws_payroll_lines; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_payroll_lines ON public.payroll_lines USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: payroll_runs ws_payroll_runs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_payroll_runs ON public.payroll_runs USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: purchase_order_items ws_po_items; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_po_items ON public.purchase_order_items USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: pos_sessions ws_pos_sessions; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_pos_sessions ON public.pos_sessions USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: pos_terminals ws_pos_terminals; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_pos_terminals ON public.pos_terminals USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: price_lists ws_price_lists; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_price_lists ON public.price_lists USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: product_categories ws_product_categories; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_product_categories ON public.product_categories USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: production_orders ws_production_orders; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_production_orders ON public.production_orders USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: products ws_products; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_products ON public.products USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: projects ws_projects; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_projects ON public.projects USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: promotions ws_promotions; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_promotions ON public.promotions USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: provisioning_runs ws_provisioning_runs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_provisioning_runs ON public.provisioning_runs USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: purchase_orders ws_purchase_orders; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_purchase_orders ON public.purchase_orders USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: recurring_expenses ws_recurring_expenses; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_recurring_expenses ON public.recurring_expenses USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: referral_programs ws_referral_programs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_referral_programs ON public.referral_programs USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: referrals ws_referrals; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_referrals ON public.referrals USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: retention_policies ws_retention_policies; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_retention_policies ON public.retention_policies USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: return_items ws_return_items; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_return_items ON public.return_items USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: returns ws_returns; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_returns ON public.returns USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: roles ws_roles; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_roles ON public.roles USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: segments ws_segments; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_segments ON public.segments USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: shift_assignments ws_shift_assignments; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_shift_assignments ON public.shift_assignments USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: shifts ws_shifts; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_shifts ON public.shifts USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: shipment_items ws_shipment_items; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_shipment_items ON public.shipment_items USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: shipments ws_shipments; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_shipments ON public.shipments USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: stock_reservations ws_stock_reservations; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_stock_reservations ON public.stock_reservations USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: customer_subscriptions ws_subscriptions; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_subscriptions ON public.customer_subscriptions USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: sync_logs ws_sync_logs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_sync_logs ON public.sync_logs USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: dining_tables ws_tables; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_tables ON public.dining_tables USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: tasks ws_tasks; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_tasks ON public.tasks USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: tax_rules ws_tax_rules; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_tax_rules ON public.tax_rules USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: taxes ws_taxes; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_taxes ON public.taxes USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: transactions ws_transactions; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_transactions ON public.transactions USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: stock_transfers ws_transfers; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_transfers ON public.stock_transfers USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: units_of_measure ws_units; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_units ON public.units_of_measure USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: users ws_users; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_users ON public.users USING ((workspace_id_deprecated = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id_deprecated = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: users ws_users_via_membership; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_users_via_membership ON public.users USING ((id IN ( SELECT workspace_memberships.user_id
   FROM public.workspace_memberships
  WHERE ((workspace_memberships.workspace_id = (current_setting('app.workspace_id'::text, true))::uuid) AND ((workspace_memberships.status)::text = ANY (ARRAY[('active'::character varying)::text, ('pending'::character varying)::text]))))));


--
-- Name: POLICY ws_users_via_membership ON users; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON POLICY ws_users_via_membership ON public.users IS 'Multi-workspace identity policy. Makes a user visible in any workspace where they have an active or pending workspace_membership. Works alongside the legacy ws_users policy (OR semantics). Auth login uses a service-role connection that bypasses RLS entirely — this policy is for in-app queries only.';


--
-- Name: warehouses ws_warehouses; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_warehouses ON public.warehouses USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: webhook_subscriptions ws_webhook_subscriptions; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_webhook_subscriptions ON public.webhook_subscriptions USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: work_centers ws_work_centers; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_work_centers ON public.work_centers USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: workspace_configurations ws_workspace_configurations; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_workspace_configurations ON public.workspace_configurations USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: workspace_country_packs ws_workspace_country_packs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_workspace_country_packs ON public.workspace_country_packs USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- Name: workspace_integrations ws_workspace_integrations; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ws_workspace_integrations ON public.workspace_integrations USING ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid)) WITH CHECK ((workspace_id = (current_setting('app.workspace_id'::text, true))::uuid));


--
-- SmartBiz baseline migration metadata
-- These rows mark the migrations already represented by this schema snapshot.
--
INSERT INTO public.migrations (migration, batch) VALUES
    ('022_email_communication', 1),
    ('023_ai_advisor', 1),
    ('024_business_templates', 1),
    ('025_workspace_invitations', 1),
    ('026_role_permission_management', 1),
    ('027_org_structure', 1),
    ('028_pipelines_custom_fields', 1),
    ('029_document_checklists', 1),
    ('030_commission_rules', 1),
    ('031_duplicate_ownership_rules', 1),
    ('032_report_templates', 1),
    ('033_finance_integration', 1),
    ('034_platform_activation_codes', 1),
    ('035_ai_foundation', 1),
    ('036_ai_tool_calls', 1),
    ('037_approval_engine', 1),
    ('037b_approval_requests_remediation', 1),
    ('038_discovery_provisioning', 1),
    ('039_discovery_state', 1),
    ('2026_07_13_200000_add_assigned_membership_id_to_contacts', 1),
    ('2026_07_16_170000_provisioning_status_extension', 1),
    ('2026_07_17_010000_create_provisioning_entity_bindings', 1),
    ('2026_07_17_020000_add_metadata_to_branches', 1),
    ('2026_07_17_030000_harden_provisioning_entity_bindings', 1),
    ('2026_07_17_050000_add_onboarding_complete_to_provisioning_runs_status', 1),
    ('2026_07_20_220000_enhance_workspace_invitations', 1);
SELECT pg_catalog.setval('public.migrations_id_seq', (SELECT COALESCE(MAX(id), 1) FROM public.migrations), true);
--
-- PostgreSQL database dump complete
--
