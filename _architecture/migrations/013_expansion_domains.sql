-- ==========================================
-- Migration 013: Expansion Domains
-- SmartBiz AI — Universal Business Operating System Extensions
-- ==========================================
--
-- Scope:
--   §1  Communications & Messaging (7 tables)
--   §2  Marketing & Growth (11 tables)
--   §3  Delivery / Fleet / Last-Mile (7 tables)
--   §4  Compliance / Localization (7 tables)
--   §5  Media / Content AI Layer (3 tables)
--   §6  Integration Hub (7 tables)
--   §7  Row Level Security
--   §8  Indexes
--   §9  Triggers
--   §10 Verification checklist
--
-- Dependencies: migrations 001–012
-- Idempotency: all CREATE TABLE use IF NOT EXISTS
-- Total new entities: 42 workspace-scoped + 6 platform-scoped = 48
--

-- ==========================================
-- §1. COMMUNICATIONS & MESSAGING [Core v1]
-- ==========================================

-- Channel provider configurations (email, SMS, WhatsApp, push) per workspace
CREATE TABLE IF NOT EXISTS communication_channels (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    type VARCHAR(50) NOT NULL CHECK (type IN ('email', 'sms', 'whatsapp', 'push')),
    provider_name VARCHAR(100) NOT NULL,        -- e.g. 'sendgrid', 'mailgun', 'twilio'
    provider_config JSONB NOT NULL DEFAULT '{}', -- encrypted credentials + settings
    is_default BOOLEAN NOT NULL DEFAULT FALSE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(workspace_id, type, provider_name)
);
COMMENT ON TABLE communication_channels IS 'Workspace channel provider registry. Each workspace configures its own email/SMS/push providers.';

-- Reusable message templates with variable interpolation
CREATE TABLE IF NOT EXISTS message_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    channel_type VARCHAR(50) NOT NULL CHECK (channel_type IN ('email', 'sms', 'whatsapp', 'push')),
    name VARCHAR(255) NOT NULL,
    subject VARCHAR(500),                        -- for email only
    body TEXT NOT NULL,                           -- supports {{variable}} interpolation
    variables JSONB NOT NULL DEFAULT '[]',        -- declared variables: [{key, label, default}]
    locale VARCHAR(10) DEFAULT 'en',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(workspace_id, channel_type, name, locale)
);
COMMENT ON TABLE message_templates IS 'Reusable message templates per channel. Variables are interpolated at send time.';

-- Outbound message dispatch log
CREATE TABLE IF NOT EXISTS outbound_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    channel_type VARCHAR(50) NOT NULL CHECK (channel_type IN ('email', 'sms', 'whatsapp', 'push')),
    template_id UUID REFERENCES message_templates(id) ON DELETE SET NULL,
    recipient_contact_id UUID REFERENCES contacts(id) ON DELETE SET NULL,
    recipient_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    recipient_address VARCHAR(500) NOT NULL,      -- email address or phone number
    subject VARCHAR(500),
    body TEXT NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'sending', 'sent', 'delivered', 'failed', 'bounced')),
    provider_message_id VARCHAR(255),
    error_message TEXT,
    attempts INT NOT NULL DEFAULT 0,
    sent_at TIMESTAMPTZ,
    delivered_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE outbound_messages IS 'Outbound message dispatch log. Tracks every message sent across all channels.';

-- Inbound message storage (replies, support messages) [Expansion Pack]
CREATE TABLE IF NOT EXISTS inbound_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    channel_type VARCHAR(50) NOT NULL CHECK (channel_type IN ('email', 'sms', 'whatsapp')),
    from_address VARCHAR(500) NOT NULL,
    thread_id UUID,
    contact_id UUID REFERENCES contacts(id) ON DELETE SET NULL,
    entity_type VARCHAR(100),                     -- linked entity (e.g. 'invoice', 'order')
    entity_id UUID,
    body TEXT NOT NULL,
    received_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE inbound_messages IS '[Expansion Pack] Inbound message threading. Associates replies with contacts and business entities.';

-- Conversation threads linking inbound/outbound [Expansion Pack]
CREATE TABLE IF NOT EXISTS message_threads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    contact_id UUID REFERENCES contacts(id) ON DELETE SET NULL,
    subject VARCHAR(500),
    last_message_at TIMESTAMPTZ,
    status VARCHAR(50) NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'closed')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE message_threads IS '[Expansion Pack] Conversation threads grouping inbound + outbound messages per contact.';

-- Event-triggered messaging automations
CREATE TABLE IF NOT EXISTS communication_automations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    trigger_event VARCHAR(255) NOT NULL,          -- e.g. 'invoice.overdue', 'leave.approved'
    conditions JSONB NOT NULL DEFAULT '{}',        -- filtering conditions
    template_id UUID NOT NULL REFERENCES message_templates(id) ON DELETE CASCADE,
    channel_type VARCHAR(50) NOT NULL CHECK (channel_type IN ('email', 'sms', 'whatsapp', 'push')),
    delay_minutes INT NOT NULL DEFAULT 0,          -- delay after trigger before sending
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(workspace_id, name)
);
COMMENT ON TABLE communication_automations IS 'Event-triggered messaging rules. Fires template-based messages when business events occur.';

-- Automation execution log
CREATE TABLE IF NOT EXISTS automation_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    automation_id UUID NOT NULL REFERENCES communication_automations(id) ON DELETE CASCADE,
    outbound_message_id UUID REFERENCES outbound_messages(id) ON DELETE SET NULL,
    triggered_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    entity_type VARCHAR(100),
    entity_id UUID
);
COMMENT ON TABLE automation_logs IS 'Execution log for communication automations. Links trigger events to sent messages.';


-- ==========================================
-- §2. MARKETING & GROWTH [Mixed: Core v1 + Expansion Pack]
-- ==========================================

-- Marketing campaigns [Expansion Pack]
CREATE TABLE IF NOT EXISTS campaigns (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    type VARCHAR(50) NOT NULL CHECK (type IN ('email', 'sms', 'multi_channel')),
    status VARCHAR(50) NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'active', 'paused', 'completed', 'archived')),
    segment_id UUID,                              -- FK added after segments table
    template_id UUID REFERENCES message_templates(id) ON DELETE SET NULL,
    budget DECIMAL(12, 2),
    spent DECIMAL(12, 2) DEFAULT 0,
    scheduled_at TIMESTAMPTZ,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE campaigns IS '[Expansion Pack] Marketing campaign lifecycle management.';

-- Campaign performance metrics [Expansion Pack]
CREATE TABLE IF NOT EXISTS campaign_metrics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    campaign_id UUID NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
    sent_count INT NOT NULL DEFAULT 0,
    delivered_count INT NOT NULL DEFAULT 0,
    opened_count INT NOT NULL DEFAULT 0,
    clicked_count INT NOT NULL DEFAULT 0,
    converted_count INT NOT NULL DEFAULT 0,
    unsubscribed_count INT NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE campaign_metrics IS '[Expansion Pack] Aggregated campaign performance counters.';

-- Customer segments (rule-based groups) [Core v1]
CREATE TABLE IF NOT EXISTS segments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    rules JSONB NOT NULL DEFAULT '[]',             -- [{field, operator, value}]
    contact_count INT NOT NULL DEFAULT 0,
    is_dynamic BOOLEAN NOT NULL DEFAULT TRUE,
    recalculated_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(workspace_id, name)
);
COMMENT ON TABLE segments IS '[Core v1] Rule-based customer segmentation. Dynamic segments auto-recalculate.';

-- Add FK from campaigns to segments (deferred to avoid ordering issues)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'fk_campaigns_segment'
    ) THEN
        ALTER TABLE campaigns ADD CONSTRAINT fk_campaigns_segment
            FOREIGN KEY (segment_id) REFERENCES segments(id) ON DELETE SET NULL;
    END IF;
END $$;

-- Segment-contact membership (materialized for performance)
CREATE TABLE IF NOT EXISTS segment_contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    segment_id UUID NOT NULL REFERENCES segments(id) ON DELETE CASCADE,
    contact_id UUID NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
    added_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(segment_id, contact_id)
);
COMMENT ON TABLE segment_contacts IS 'Materialized segment membership. Refreshed by async recalculation job.';

-- Loyalty programs [Core v1]
CREATE TABLE IF NOT EXISTS loyalty_programs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    earn_rules JSONB NOT NULL DEFAULT '[]',        -- [{type: 'per_dollar', rate: 1}, ...]
    burn_rules JSONB NOT NULL DEFAULT '[]',        -- [{points: 100, discount: 5.00}, ...]
    tiers JSONB NOT NULL DEFAULT '[]',             -- [{name, min_points, benefits}]
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(workspace_id, name)
);
COMMENT ON TABLE loyalty_programs IS '[Core v1] Customer loyalty programs with points earn/burn rules and tier definitions.';

-- Per-customer loyalty account [Core v1]
CREATE TABLE IF NOT EXISTS loyalty_accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    contact_id UUID NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
    program_id UUID NOT NULL REFERENCES loyalty_programs(id) ON DELETE CASCADE,
    points_balance INT NOT NULL DEFAULT 0 CHECK (points_balance >= 0),
    lifetime_points INT NOT NULL DEFAULT 0 CHECK (lifetime_points >= 0),
    current_tier VARCHAR(100),
    tier_updated_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(workspace_id, contact_id, program_id)
);
COMMENT ON TABLE loyalty_accounts IS '[Core v1] Individual customer loyalty balances and tier status.';

-- Loyalty point transaction ledger [Core v1]
CREATE TABLE IF NOT EXISTS loyalty_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id UUID NOT NULL REFERENCES loyalty_accounts(id) ON DELETE CASCADE,
    type VARCHAR(50) NOT NULL CHECK (type IN ('earn', 'burn', 'adjust', 'expire')),
    points INT NOT NULL,
    reason VARCHAR(500),
    reference_entity_type VARCHAR(100),            -- e.g. 'order', 'manual'
    reference_entity_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE loyalty_transactions IS '[Core v1] Immutable ledger of loyalty point movements.';

-- Referral programs [Expansion Pack]
CREATE TABLE IF NOT EXISTS referral_programs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    referrer_reward JSONB NOT NULL DEFAULT '{}',    -- {type: 'credit', amount: 50}
    referee_reward JSONB NOT NULL DEFAULT '{}',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(workspace_id, name)
);
COMMENT ON TABLE referral_programs IS '[Expansion Pack] Customer referral program definitions.';

-- Individual referral tracking [Expansion Pack]
CREATE TABLE IF NOT EXISTS referrals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    program_id UUID NOT NULL REFERENCES referral_programs(id) ON DELETE CASCADE,
    referrer_contact_id UUID NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
    referee_contact_id UUID REFERENCES contacts(id) ON DELETE SET NULL,
    referral_code VARCHAR(50) NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'converted', 'expired', 'cancelled')),
    converted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(workspace_id, referral_code)
);
COMMENT ON TABLE referrals IS '[Expansion Pack] Individual referral tracking with attribution.';

-- Lead nurturing sequences [Expansion Pack]
CREATE TABLE IF NOT EXISTS nurturing_sequences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    trigger_event VARCHAR(255) NOT NULL,           -- e.g. 'lead.created', 'lead.qualified'
    steps JSONB NOT NULL DEFAULT '[]',             -- [{delay_days, template_id, channel}]
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(workspace_id, name)
);
COMMENT ON TABLE nurturing_sequences IS '[Expansion Pack] Multi-step lead nurturing automation.';

-- Nurturing enrollment tracking [Expansion Pack]
CREATE TABLE IF NOT EXISTS nurturing_enrollments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sequence_id UUID NOT NULL REFERENCES nurturing_sequences(id) ON DELETE CASCADE,
    contact_id UUID NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
    current_step INT NOT NULL DEFAULT 0,
    status VARCHAR(50) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'completed', 'paused', 'exited')),
    last_step_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(sequence_id, contact_id)
);
COMMENT ON TABLE nurturing_enrollments IS '[Expansion Pack] Per-contact enrollment in nurturing sequences.';


-- ==========================================
-- §3. DELIVERY / FLEET / LAST-MILE [Core v1]
-- ==========================================

-- Driver/rider profiles
CREATE TABLE IF NOT EXISTS drivers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    vehicle_type VARCHAR(50) CHECK (vehicle_type IN ('motorcycle', 'car', 'van', 'truck', 'bicycle', 'other')),
    vehicle_plate VARCHAR(50),
    license_number VARCHAR(100),
    zone_ids JSONB NOT NULL DEFAULT '[]',          -- assigned delivery zone UUIDs
    status VARCHAR(50) NOT NULL DEFAULT 'offline' CHECK (status IN ('available', 'busy', 'offline', 'suspended')),
    branch_id UUID REFERENCES branches(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(workspace_id, user_id)
);
COMMENT ON TABLE drivers IS '[Core v1] Delivery driver/rider profiles with vehicle info and zone assignments.';

-- Delivery zones with SLA targets
CREATE TABLE IF NOT EXISTS delivery_zones (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    boundary_geojson JSONB,                        -- GeoJSON polygon for zone boundary
    sla_minutes INT,                               -- target delivery time
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(workspace_id, name)
);
COMMENT ON TABLE delivery_zones IS '[Core v1] Delivery zones with optional GeoJSON boundaries and SLA targets.';

-- Order-to-driver assignments
CREATE TABLE IF NOT EXISTS delivery_assignments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    driver_id UUID NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
    zone_id UUID REFERENCES delivery_zones(id) ON DELETE SET NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'pending' CHECK (status IN (
        'pending', 'accepted', 'rejected', 'picked_up', 'in_transit', 'delivered', 'failed', 'returned'
    )),
    assigned_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    accepted_at TIMESTAMPTZ,
    picked_up_at TIMESTAMPTZ,
    delivered_at TIMESTAMPTZ,
    failed_reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE delivery_assignments IS '[Core v1] Order-to-driver assignment lifecycle. Strict FSM: pending→accepted→picked_up→in_transit→delivered|failed.';

-- GPS tracking points [Expansion Pack]
CREATE TABLE IF NOT EXISTS delivery_tracking (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assignment_id UUID NOT NULL REFERENCES delivery_assignments(id) ON DELETE CASCADE,
    latitude DECIMAL(10, 7) NOT NULL,
    longitude DECIMAL(10, 7) NOT NULL,
    captured_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    event_type VARCHAR(50) DEFAULT 'location_update' CHECK (event_type IN ('location_update', 'status_change'))
);
COMMENT ON TABLE delivery_tracking IS '[Expansion Pack] Real-time GPS tracking points for active deliveries.';

-- Proof of delivery evidence
CREATE TABLE IF NOT EXISTS delivery_proofs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assignment_id UUID NOT NULL REFERENCES delivery_assignments(id) ON DELETE CASCADE,
    photo_path VARCHAR(500),
    signature_path VARCHAR(500),
    pin_code VARCHAR(10),
    receiver_name VARCHAR(255),
    captured_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(assignment_id)
);
COMMENT ON TABLE delivery_proofs IS '[Core v1] Proof of delivery: photo, signature, and/or PIN. One proof per assignment.';

-- Cash-on-delivery tracking
CREATE TABLE IF NOT EXISTS cod_collections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    assignment_id UUID NOT NULL REFERENCES delivery_assignments(id) ON DELETE CASCADE,
    driver_id UUID NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
    amount_expected DECIMAL(12, 2) NOT NULL CHECK (amount_expected >= 0),
    amount_collected DECIMAL(12, 2) CHECK (amount_collected >= 0),
    variance DECIMAL(12, 2) GENERATED ALWAYS AS (COALESCE(amount_collected, 0) - amount_expected) STORED,
    settled BOOLEAN NOT NULL DEFAULT FALSE,
    settled_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(assignment_id)
);
COMMENT ON TABLE cod_collections IS '[Core v1] Cash-on-delivery collection tracking per assignment with variance detection.';

-- Delivery SLA breach tracking [Expansion Pack]
CREATE TABLE IF NOT EXISTS delivery_sla_breaches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assignment_id UUID NOT NULL REFERENCES delivery_assignments(id) ON DELETE CASCADE,
    zone_id UUID REFERENCES delivery_zones(id) ON DELETE SET NULL,
    target_minutes INT NOT NULL,
    actual_minutes INT NOT NULL,
    breached_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE delivery_sla_breaches IS '[Expansion Pack] Delivery SLA breach records for performance analysis.';


-- ==========================================
-- §4. COMPLIANCE / LOCALIZATION [Core v1 framework, Expansion Pack per-country]
-- ==========================================

-- Platform-level country pack catalog
CREATE TABLE IF NOT EXISTS country_packs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    country_code VARCHAR(3) NOT NULL UNIQUE,       -- ISO 3166 alpha-2 or alpha-3
    name VARCHAR(255) NOT NULL,
    version VARCHAR(20) NOT NULL DEFAULT '1.0.0',
    tax_config JSONB NOT NULL DEFAULT '{}',        -- default tax rules for this country
    payroll_config JSONB NOT NULL DEFAULT '{}',    -- statutory deductions, brackets
    invoice_config JSONB NOT NULL DEFAULT '{}',    -- format requirements, QR, e-invoicing
    constants JSONB NOT NULL DEFAULT '{}',         -- regulatory constants (min wage, etc.)
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE country_packs IS '[Core v1 framework] Platform-scoped country configuration bundles. Not workspace-scoped — no RLS.';

-- Workspace country pack installations
CREATE TABLE IF NOT EXISTS workspace_country_packs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    country_pack_id UUID NOT NULL REFERENCES country_packs(id) ON DELETE RESTRICT,
    installed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    config_overrides JSONB NOT NULL DEFAULT '{}',  -- workspace-specific overrides
    UNIQUE(workspace_id, country_pack_id)
);
COMMENT ON TABLE workspace_country_packs IS '[Core v1 framework] Links workspaces to installed country packs.';

-- Country-specific tax rules (effective-dated)
CREATE TABLE IF NOT EXISTS tax_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    country_pack_id UUID REFERENCES country_packs(id) ON DELETE SET NULL,
    rule_type VARCHAR(50) NOT NULL CHECK (rule_type IN (
        'standard', 'reduced', 'zero', 'exempt', 'reverse_charge', 'withholding'
    )),
    rate DECIMAL(6, 4) NOT NULL CHECK (rate >= 0 AND rate <= 1),  -- 0.15 = 15%
    conditions JSONB NOT NULL DEFAULT '{}',        -- product type, threshold, etc.
    effective_from DATE NOT NULL,
    effective_to DATE,                             -- NULL = still active
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (effective_to IS NULL OR effective_to > effective_from)
);
COMMENT ON TABLE tax_rules IS '[Core v1] Country-specific tax rules. Effective-dated — never deleted, only superseded.';

-- Payroll statutory deduction rules [Expansion Pack per-country]
CREATE TABLE IF NOT EXISTS payroll_statutory_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    country_pack_id UUID NOT NULL REFERENCES country_packs(id) ON DELETE CASCADE,
    deduction_type VARCHAR(100) NOT NULL,           -- e.g. 'social_insurance', 'income_tax'
    calculation_method VARCHAR(50) NOT NULL CHECK (calculation_method IN ('flat', 'percentage', 'bracket')),
    brackets JSONB NOT NULL DEFAULT '[]',           -- [{min, max, rate}] for bracket method
    effective_from DATE NOT NULL,
    effective_to DATE,
    CHECK (effective_to IS NULL OR effective_to > effective_from)
);
COMMENT ON TABLE payroll_statutory_rules IS '[Expansion Pack] Per-country payroll statutory deduction definitions. Platform-scoped.';

-- Invoice format requirements per country [Expansion Pack per-country]
CREATE TABLE IF NOT EXISTS invoice_format_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    country_pack_id UUID NOT NULL REFERENCES country_packs(id) ON DELETE CASCADE,
    field_requirements JSONB NOT NULL DEFAULT '{}', -- required fields per country
    qr_code_required BOOLEAN NOT NULL DEFAULT FALSE,
    digital_signature_required BOOLEAN NOT NULL DEFAULT FALSE,
    format_template TEXT,                           -- template name or path
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE invoice_format_rules IS '[Expansion Pack] Country-specific invoice format requirements (e.g. ZATCA QR, Egypt ETA).';

-- Data retention policies
CREATE TABLE IF NOT EXISTS retention_policies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    entity_type VARCHAR(100) NOT NULL,              -- e.g. 'contacts', 'audit_logs', 'invoices'
    retention_years INT NOT NULL CHECK (retention_years >= 1),
    action VARCHAR(50) NOT NULL DEFAULT 'archive' CHECK (action IN ('archive', 'anonymize', 'delete')),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(workspace_id, entity_type)
);
COMMENT ON TABLE retention_policies IS '[Expansion Pack] Per-entity data retention policies with configurable action.';

-- Archival job log
CREATE TABLE IF NOT EXISTS archival_jobs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    entity_type VARCHAR(100) NOT NULL,
    records_archived INT NOT NULL DEFAULT 0,
    retention_policy_id UUID REFERENCES retention_policies(id) ON DELETE SET NULL,
    archived_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE archival_jobs IS '[Expansion Pack] Archival execution log. Tracks how many records were processed per run.';


-- ==========================================
-- §5. MEDIA / CONTENT AI LAYER [Core v1 basic, Expansion Pack generation]
-- ==========================================

-- Workspace brand identity kit
CREATE TABLE IF NOT EXISTS brand_kits (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    primary_color VARCHAR(9),                      -- hex color, e.g. '#FF5733'
    secondary_color VARCHAR(9),
    accent_color VARCHAR(9),
    font_family VARCHAR(100),
    logo_path VARCHAR(500),
    tone_description TEXT,                          -- 'Professional and friendly'
    guidelines JSONB NOT NULL DEFAULT '{}',         -- extended brand guidelines
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(workspace_id)                            -- singleton per workspace
);
COMMENT ON TABLE brand_kits IS '[Core v1] Workspace brand identity. Singleton per workspace. AI uses this for content generation context.';

-- Media asset library
CREATE TABLE IF NOT EXISTS media_assets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    file_path VARCHAR(500) NOT NULL,
    mime_type VARCHAR(100) NOT NULL,
    file_size INT,
    tags JSONB NOT NULL DEFAULT '[]',
    folder VARCHAR(255),
    source VARCHAR(50) NOT NULL DEFAULT 'upload' CHECK (source IN ('upload', 'ai_generated')),
    status VARCHAR(50) NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'approved', 'archived')),
    approved_by UUID REFERENCES users(id) ON DELETE SET NULL,
    approved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE media_assets IS '[Core v1] Centralized media asset library with approval workflow. Sources: upload or AI-generated.';

-- AI content generation requests [Expansion Pack]
CREATE TABLE IF NOT EXISTS media_generation_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    prompt TEXT NOT NULL,
    brand_kit_id UUID REFERENCES brand_kits(id) ON DELETE SET NULL,
    ai_model VARCHAR(100),
    status VARCHAR(50) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
    result_asset_id UUID REFERENCES media_assets(id) ON DELETE SET NULL,
    tokens_used INT DEFAULT 0,
    error_message TEXT,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE media_generation_requests IS '[Expansion Pack] AI content generation request tracking. Consumes AI token quota.';


-- ==========================================
-- §6. INTEGRATION HUB [Core v1]
-- ==========================================

-- Platform-level integration provider catalog
CREATE TABLE IF NOT EXISTS integration_providers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    type VARCHAR(50) NOT NULL CHECK (type IN ('payment', 'email', 'sms', 'ecommerce', 'accounting', 'storage', 'other')),
    name VARCHAR(100) NOT NULL UNIQUE,
    adapter_class VARCHAR(255) NOT NULL,            -- Laravel class path for the adapter
    config_schema JSONB NOT NULL DEFAULT '{}',      -- JSON Schema for credential fields
    is_available BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE integration_providers IS '[Core v1] Platform-scoped integration provider catalog. Not workspace-scoped — no RLS.';

-- Workspace integration connections
CREATE TABLE IF NOT EXISTS workspace_integrations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    provider_id UUID NOT NULL REFERENCES integration_providers(id) ON DELETE RESTRICT,
    credentials JSONB NOT NULL DEFAULT '{}',        -- encrypted at rest by application layer
    status VARCHAR(50) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'active', 'error', 'disconnected')),
    last_sync_at TIMESTAMPTZ,
    error_message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(workspace_id, provider_id)
);
COMMENT ON TABLE workspace_integrations IS '[Core v1] Per-workspace integration connections with encrypted credentials.';

-- Outbound webhook subscriptions
CREATE TABLE IF NOT EXISTS webhook_subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    event_type VARCHAR(255) NOT NULL,               -- e.g. 'order.confirmed', 'payment.received'
    target_url VARCHAR(1000) NOT NULL,
    secret VARCHAR(255),                             -- HMAC signing secret
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    failure_count INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE webhook_subscriptions IS '[Core v1] Outbound webhook event subscriptions with signing secrets.';

-- Webhook delivery log
CREATE TABLE IF NOT EXISTS webhook_deliveries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subscription_id UUID NOT NULL REFERENCES webhook_subscriptions(id) ON DELETE CASCADE,
    event_type VARCHAR(255) NOT NULL,
    payload JSONB NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'delivered', 'failed')),
    attempts INT NOT NULL DEFAULT 0,
    last_attempted_at TIMESTAMPTZ,
    response_code INT,
    response_body TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE webhook_deliveries IS '[Core v1] Webhook delivery attempts with retry tracking.';

-- Bulk import jobs
CREATE TABLE IF NOT EXISTS import_jobs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    entity_type VARCHAR(100) NOT NULL,              -- e.g. 'products', 'contacts', 'accounts'
    file_path VARCHAR(500) NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'uploaded' CHECK (status IN (
        'uploaded', 'validating', 'preview', 'applying', 'completed', 'failed'
    )),
    total_rows INT,
    valid_rows INT,
    error_rows INT,
    errors JSONB,                                   -- [{row, column, message}]
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE import_jobs IS '[Core v1] Bulk data import pipeline with validation and preview.';

-- Bulk export jobs
CREATE TABLE IF NOT EXISTS export_jobs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    entity_type VARCHAR(100) NOT NULL,
    format VARCHAR(20) NOT NULL DEFAULT 'csv' CHECK (format IN ('csv', 'xlsx', 'xml', 'json')),
    filters JSONB NOT NULL DEFAULT '{}',
    status VARCHAR(50) NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'processing', 'completed', 'failed')),
    file_path VARCHAR(500),
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE export_jobs IS '[Core v1] Bulk data export pipeline with format and filter options.';

-- Integration sync activity log
CREATE TABLE IF NOT EXISTS sync_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    integration_id UUID NOT NULL REFERENCES workspace_integrations(id) ON DELETE CASCADE,
    direction VARCHAR(10) NOT NULL CHECK (direction IN ('inbound', 'outbound')),
    entity_type VARCHAR(100) NOT NULL,
    entity_id UUID,
    status VARCHAR(50) NOT NULL CHECK (status IN ('success', 'conflict', 'error')),
    details JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE sync_logs IS '[Core v1] Integration sync activity log for debugging and audit.';


-- ==========================================
-- §7. ROW LEVEL SECURITY
-- ==========================================
-- All workspace-scoped tables get RLS. Platform-scoped tables (country_packs,
-- integration_providers, payroll_statutory_rules, invoice_format_rules) do NOT.

-- Communications
ALTER TABLE communication_channels ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_communication_channels ON communication_channels
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

ALTER TABLE message_templates ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_message_templates ON message_templates
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

ALTER TABLE outbound_messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_outbound_messages ON outbound_messages
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

ALTER TABLE inbound_messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_inbound_messages ON inbound_messages
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

ALTER TABLE message_threads ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_message_threads ON message_threads
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

ALTER TABLE communication_automations ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_communication_automations ON communication_automations
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

ALTER TABLE automation_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_automation_logs ON automation_logs
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

-- Marketing
ALTER TABLE campaigns ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_campaigns ON campaigns
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

ALTER TABLE segments ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_segments ON segments
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

ALTER TABLE loyalty_programs ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_loyalty_programs ON loyalty_programs
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

ALTER TABLE loyalty_accounts ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_loyalty_accounts ON loyalty_accounts
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

ALTER TABLE referral_programs ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_referral_programs ON referral_programs
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

ALTER TABLE referrals ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_referrals ON referrals
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

ALTER TABLE nurturing_sequences ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_nurturing_sequences ON nurturing_sequences
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

-- Delivery
ALTER TABLE drivers ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_drivers ON drivers
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

ALTER TABLE delivery_zones ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_delivery_zones ON delivery_zones
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

ALTER TABLE delivery_assignments ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_delivery_assignments ON delivery_assignments
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

ALTER TABLE cod_collections ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_cod_collections ON cod_collections
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

-- Compliance (workspace-scoped only)
ALTER TABLE workspace_country_packs ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_workspace_country_packs ON workspace_country_packs
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

ALTER TABLE tax_rules ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_tax_rules ON tax_rules
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

ALTER TABLE retention_policies ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_retention_policies ON retention_policies
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

ALTER TABLE archival_jobs ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_archival_jobs ON archival_jobs
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

-- Media (workspace-scoped)
ALTER TABLE brand_kits ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_brand_kits ON brand_kits
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

ALTER TABLE media_assets ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_media_assets ON media_assets
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

ALTER TABLE media_generation_requests ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_media_generation_requests ON media_generation_requests
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

-- Integration Hub (workspace-scoped)
ALTER TABLE workspace_integrations ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_workspace_integrations ON workspace_integrations
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

ALTER TABLE webhook_subscriptions ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_webhook_subscriptions ON webhook_subscriptions
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

ALTER TABLE import_jobs ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_import_jobs ON import_jobs
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

ALTER TABLE export_jobs ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_export_jobs ON export_jobs
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

ALTER TABLE sync_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_sync_logs ON sync_logs
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

-- Note: platform-scoped tables do NOT get RLS:
-- country_packs, integration_providers, payroll_statutory_rules, invoice_format_rules
-- These are managed by platform admins and readable by all authenticated users.

-- Child tables inheriting RLS from parent (no workspace_id):
-- campaign_metrics → campaigns
-- segment_contacts → segments
-- loyalty_transactions → loyalty_accounts
-- nurturing_enrollments → nurturing_sequences
-- delivery_tracking → delivery_assignments
-- delivery_proofs → delivery_assignments
-- delivery_sla_breaches → delivery_assignments
-- webhook_deliveries → webhook_subscriptions


-- ==========================================
-- §8. INDEXES
-- ==========================================

-- Communications
CREATE INDEX IF NOT EXISTS idx_outbound_messages_ws_status ON outbound_messages(workspace_id, status);
CREATE INDEX IF NOT EXISTS idx_outbound_messages_contact ON outbound_messages(recipient_contact_id);
CREATE INDEX IF NOT EXISTS idx_outbound_messages_sent ON outbound_messages(sent_at) WHERE sent_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_automation_logs_ws ON automation_logs(workspace_id, triggered_at);

-- Marketing
CREATE INDEX IF NOT EXISTS idx_campaigns_ws_status ON campaigns(workspace_id, status);
CREATE INDEX IF NOT EXISTS idx_segments_ws ON segments(workspace_id);
CREATE INDEX IF NOT EXISTS idx_segment_contacts_segment ON segment_contacts(segment_id);
CREATE INDEX IF NOT EXISTS idx_loyalty_accounts_ws_contact ON loyalty_accounts(workspace_id, contact_id);
CREATE INDEX IF NOT EXISTS idx_loyalty_transactions_account ON loyalty_transactions(account_id, created_at);
CREATE INDEX IF NOT EXISTS idx_referrals_ws_code ON referrals(workspace_id, referral_code);

-- Delivery
CREATE INDEX IF NOT EXISTS idx_drivers_ws_status ON drivers(workspace_id, status);
CREATE INDEX IF NOT EXISTS idx_delivery_assignments_ws_status ON delivery_assignments(workspace_id, status);
CREATE INDEX IF NOT EXISTS idx_delivery_assignments_driver ON delivery_assignments(driver_id, status);
CREATE INDEX IF NOT EXISTS idx_delivery_assignments_order ON delivery_assignments(order_id);
CREATE INDEX IF NOT EXISTS idx_delivery_tracking_assign ON delivery_tracking(assignment_id, captured_at);
CREATE INDEX IF NOT EXISTS idx_cod_collections_ws_settled ON cod_collections(workspace_id, settled);

-- Compliance
CREATE INDEX IF NOT EXISTS idx_tax_rules_ws_effective ON tax_rules(workspace_id, effective_from, effective_to);
CREATE INDEX IF NOT EXISTS idx_workspace_country_packs_ws ON workspace_country_packs(workspace_id);

-- Media
CREATE INDEX IF NOT EXISTS idx_media_assets_ws_status ON media_assets(workspace_id, status);
CREATE INDEX IF NOT EXISTS idx_media_assets_ws_folder ON media_assets(workspace_id, folder);
CREATE INDEX IF NOT EXISTS idx_media_gen_ws_status ON media_generation_requests(workspace_id, status);

-- Integration Hub
CREATE INDEX IF NOT EXISTS idx_workspace_integrations_ws ON workspace_integrations(workspace_id);
CREATE INDEX IF NOT EXISTS idx_webhook_subscriptions_ws_event ON webhook_subscriptions(workspace_id, event_type);
CREATE INDEX IF NOT EXISTS idx_webhook_deliveries_sub_status ON webhook_deliveries(subscription_id, status);
CREATE INDEX IF NOT EXISTS idx_import_jobs_ws_status ON import_jobs(workspace_id, status);
CREATE INDEX IF NOT EXISTS idx_export_jobs_ws_status ON export_jobs(workspace_id, status);
CREATE INDEX IF NOT EXISTS idx_sync_logs_ws_integration ON sync_logs(workspace_id, integration_id, created_at);


-- ==========================================
-- §9. TRIGGERS (updated_at auto-update)
-- ==========================================
-- Uses the set_updated_at() function created in the base schema.

DO $$
DECLARE
    tbl TEXT;
BEGIN
    FOREACH tbl IN ARRAY ARRAY[
        'communication_channels', 'message_templates', 'outbound_messages',
        'message_threads', 'communication_automations',
        'campaigns', 'segments', 'loyalty_programs', 'loyalty_accounts',
        'referral_programs', 'nurturing_sequences', 'nurturing_enrollments',
        'drivers', 'delivery_zones', 'delivery_assignments',
        'workspace_country_packs', 'retention_policies',
        'brand_kits', 'media_assets', 'media_generation_requests',
        'workspace_integrations', 'webhook_subscriptions',
        'import_jobs', 'export_jobs',
        'country_packs', 'integration_providers'
    ] LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_trigger
            WHERE tgname = 'trg_' || tbl || '_updated'
        ) THEN
            EXECUTE format(
                'CREATE TRIGGER trg_%I_updated BEFORE UPDATE ON %I FOR EACH ROW EXECUTE FUNCTION set_updated_at()',
                tbl, tbl
            );
        END IF;
    END LOOP;
END $$;


-- ==========================================
-- §10. VERIFICATION CHECKLIST
-- ==========================================
-- After running this migration, verify:
--
-- Communications (7 tables):
--   [ ] communication_channels exists with RLS
--   [ ] message_templates exists with RLS
--   [ ] outbound_messages exists with RLS
--   [ ] inbound_messages exists with RLS
--   [ ] message_threads exists with RLS
--   [ ] communication_automations exists with RLS
--   [ ] automation_logs exists with RLS
--
-- Marketing (11 tables):
--   [ ] campaigns exists with RLS
--   [ ] campaign_metrics exists (child — no RLS)
--   [ ] segments exists with RLS
--   [ ] segment_contacts exists (child — no RLS)
--   [ ] loyalty_programs exists with RLS
--   [ ] loyalty_accounts exists with RLS + points_balance >= 0
--   [ ] loyalty_transactions exists (child — no RLS)
--   [ ] referral_programs exists with RLS
--   [ ] referrals exists with RLS
--   [ ] nurturing_sequences exists with RLS
--   [ ] nurturing_enrollments exists (child — no RLS)
--
-- Delivery (7 tables):
--   [ ] drivers exists with RLS + status CHECK
--   [ ] delivery_zones exists with RLS
--   [ ] delivery_assignments exists with RLS + status FSM CHECK
--   [ ] delivery_tracking exists (child — no RLS)
--   [ ] delivery_proofs exists (child — no RLS, UNIQUE assignment_id)
--   [ ] cod_collections exists with RLS + computed variance
--   [ ] delivery_sla_breaches exists (child — no RLS)
--
-- Compliance (7 tables):
--   [ ] country_packs exists (platform — no RLS)
--   [ ] workspace_country_packs exists with RLS
--   [ ] tax_rules exists with RLS + effective dates
--   [ ] payroll_statutory_rules exists (platform — no RLS)
--   [ ] invoice_format_rules exists (platform — no RLS)
--   [ ] retention_policies exists with RLS
--   [ ] archival_jobs exists with RLS
--
-- Media (3 tables):
--   [ ] brand_kits exists with RLS + UNIQUE(workspace_id)
--   [ ] media_assets exists with RLS + status CHECK
--   [ ] media_generation_requests exists with RLS
--
-- Integration Hub (7 tables):
--   [ ] integration_providers exists (platform — no RLS)
--   [ ] workspace_integrations exists with RLS
--   [ ] webhook_subscriptions exists with RLS
--   [ ] webhook_deliveries exists (child — no RLS)
--   [ ] import_jobs exists with RLS + status FSM
--   [ ] export_jobs exists with RLS
--   [ ] sync_logs exists with RLS
--
-- Totals:
--   42 workspace-scoped tables (RLS enabled)
--   6 platform-scoped tables (no RLS)
--   8 child tables (inherit RLS from parent)
--   28 indexes created
--   26 updated_at triggers created
