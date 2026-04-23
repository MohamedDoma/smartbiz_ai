-- ============================================================
-- Migration 020: AI Chat schema extensions
-- ============================================================

-- 1. Create ai_conversation_messages table for chat history
CREATE TABLE IF NOT EXISTS ai_conversation_messages (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES ai_conversations(id) ON DELETE CASCADE,
    role            VARCHAR(20) NOT NULL CHECK (role IN ('system', 'user', 'assistant', 'tool')),
    content         TEXT NOT NULL,
    metadata        JSONB NOT NULL DEFAULT '{}',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_ai_conv_msgs_conv ON ai_conversation_messages(conversation_id, created_at);

-- 2. Enable RLS
ALTER TABLE ai_conversation_messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS ws_ai_conversation_messages ON ai_conversation_messages;
CREATE POLICY ws_ai_conversation_messages ON ai_conversation_messages
    USING (
        conversation_id IN (
            SELECT id FROM ai_conversations
            WHERE workspace_id = current_setting('app.workspace_id', true)::uuid
        )
    );

-- 3. Expand ai_request_logs.request_type CHECK constraint
ALTER TABLE ai_request_logs DROP CONSTRAINT IF EXISTS ai_request_logs_request_type_check;
ALTER TABLE ai_request_logs ADD CONSTRAINT ai_request_logs_request_type_check
    CHECK (request_type IN (
        'onboarding', 'change_request', 'advisory', 'analytics', 'unsupported',
        'ai_chat', 'ai_read', 'ai_action', 'ai_discovery'
    ));

-- 4. Expand ai_conversations.mode if needed (add 'chat' if not in constraint)
-- Check if constraint exists first; if so, drop and recreate
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ai_conversations_mode_check'
    ) THEN
        ALTER TABLE ai_conversations DROP CONSTRAINT ai_conversations_mode_check;
    END IF;
END $$;
ALTER TABLE ai_conversations ADD CONSTRAINT ai_conversations_mode_check
    CHECK (mode IN ('discovery', 'chat', 'advisory', 'general'));
