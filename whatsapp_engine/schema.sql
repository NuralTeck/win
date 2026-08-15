-- ==============================================================================
-- SUPABASE POSTGRESQL SCHEMA FOR HIGH-TRAFFIC WHATSAPP LOGGING ENGINE
-- ==============================================================================

-- 1. Create table for WhatsApp Entries
CREATE TABLE IF NOT EXISTS public.whatsapp_entries (
    id BIGSERIAL PRIMARY KEY,
    sender VARCHAR(64) NOT NULL,
    sender_name VARCHAR(128) DEFAULT NULL,
    message_text TEXT NOT NULL,
    message_timestamp BIGINT DEFAULT NULL,
    raw_payload JSONB DEFAULT NULL,
    status VARCHAR(32) DEFAULT 'pending',
    created_at TIMESTAMPTZ NOT NULL DEFAULT TIMEZONE('utc'::text, NOW())
);

-- 2. Performance Indexes for 1000+ entries/min throughput
CREATE INDEX IF NOT EXISTS idx_whatsapp_entries_created_at ON public.whatsapp_entries (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_whatsapp_entries_sender ON public.whatsapp_entries (sender);
CREATE INDEX IF NOT EXISTS idx_whatsapp_entries_status ON public.whatsapp_entries (status);

-- 3. Enable Row Level Security (RLS)
ALTER TABLE public.whatsapp_entries ENABLE ROW LEVEL SECURITY;

-- 4. RLS Policies: Allow authenticated and service_role to insert & read
CREATE POLICY "Allow public read/insert with anon key" ON public.whatsapp_entries
    FOR ALL
    TO anon, authenticated, service_role
    USING (true)
    WITH CHECK (true);

-- 5. Comments
COMMENT ON TABLE public.whatsapp_entries IS 'High-throughput stream table for raw WhatsApp incoming booking messages';

-- ==============================================================================
-- 6. UNPARSED MESSAGES TABLE (For messages that failed standard parsing)
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.unparsed_messages (
    id BIGSERIAL PRIMARY KEY,
    raw_text TEXT NOT NULL,
    sender_phone VARCHAR(64) NOT NULL,
    sender_name VARCHAR(128) DEFAULT NULL,
    status VARCHAR(32) DEFAULT 'pending', -- 'pending' | 'resolved' | 'ignored'
    received_at TIMESTAMPTZ NOT NULL DEFAULT TIMEZONE('utc'::text, NOW()),
    resolved_at TIMESTAMPTZ DEFAULT NULL
);

CREATE INDEX IF NOT EXISTS idx_unparsed_messages_status ON public.unparsed_messages (status);
CREATE INDEX IF NOT EXISTS idx_unparsed_messages_received_at ON public.unparsed_messages (received_at DESC);

ALTER TABLE public.unparsed_messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow all on unparsed_messages" ON public.unparsed_messages
    FOR ALL TO anon, authenticated, service_role
    USING (true) WITH CHECK (true);

-- ==============================================================================
-- 7. LEARNED PATTERNS TABLE (Dynamic Bot Regex Rules learned by operator)
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.learned_patterns (
    id BIGSERIAL PRIMARY KEY,
    pattern_name VARCHAR(128) NOT NULL,
    regex_pattern TEXT NOT NULL,
    series_group_index INT DEFAULT 1,
    ticket_group_index INT DEFAULT 2,
    qty_group_index INT DEFAULT 3,
    sample_text TEXT DEFAULT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT TIMEZONE('utc'::text, NOW())
);

CREATE INDEX IF NOT EXISTS idx_learned_patterns_created_at ON public.learned_patterns (created_at DESC);

ALTER TABLE public.learned_patterns ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow all on learned_patterns" ON public.learned_patterns
    FOR ALL TO anon, authenticated, service_role
    USING (true) WITH CHECK (true);

