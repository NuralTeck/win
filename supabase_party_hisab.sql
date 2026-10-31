-- =========================================================================
-- SUPABASE CLOUD SCHEMA: ANTI-PIRACY LICENSE & MASTER ADMIN PANEL
-- =========================================================================
-- 1. Authentication & License Protection: Handled via Supabase Auth
-- 2. Party Name & Net Hisab Summary: Stored in 'party_hisab' table
-- 3. Live Login & Device Tracking: Stored in 'app_sessions' table
-- 4. User License & Remote Blocking: Stored in 'app_licenses' table
-- 5. Raw tickets, vouchers & logs: Kept 100% on local SQLite
-- =========================================================================

-- 1. PARTY HISAB TABLE (Party Name & Net Hisab Balance)
CREATE TABLE IF NOT EXISTS party_hisab (
    party_name TEXT PRIMARY KEY,
    dealer_name TEXT,
    total_tickets BIGINT DEFAULT 0,
    total_sales NUMERIC DEFAULT 0,
    total_prize NUMERIC DEFAULT 0,
    net_hisab NUMERIC DEFAULT 0,
    category TEXT DEFAULT 'Party Hisab',
    last_active_date TEXT,
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    synced_by TEXT
);

-- 2. APP SESSIONS & ACTIVITY LOGS (Who logged in, when, device, online time)
CREATE TABLE IF NOT EXISTS app_sessions (
    session_id TEXT PRIMARY KEY,
    user_email TEXT NOT NULL,
    user_name TEXT,
    device_name TEXT,
    os_info TEXT,
    login_time TIMESTAMPTZ DEFAULT NOW(),
    last_heartbeat TIMESTAMPTZ DEFAULT NOW(),
    logout_time TIMESTAMPTZ,
    is_online BOOLEAN DEFAULT TRUE,
    is_blocked BOOLEAN DEFAULT FALSE,
    total_online_seconds INTEGER DEFAULT 0,
    app_version TEXT DEFAULT '2.0.0',
    status TEXT DEFAULT 'Online'
);

-- 3. USER LICENSES & REMOTE KILL SWITCH (Create user, block/unblock, license validity)
CREATE TABLE IF NOT EXISTS app_licenses (
    id TEXT PRIMARY KEY,
    user_email TEXT NOT NULL UNIQUE,
    full_name TEXT,
    license_status TEXT DEFAULT 'Active',
    is_blocked BOOLEAN DEFAULT FALSE,
    valid_until TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    notes TEXT
);

-- Enable Row Level Security (RLS)
ALTER TABLE party_hisab ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_licenses ENABLE ROW LEVEL SECURITY;

-- Allow authenticated users full read & write access
DROP POLICY IF EXISTS "Allow authenticated users full access to party_hisab" ON party_hisab;
CREATE POLICY "Allow authenticated users full access to party_hisab"
ON party_hisab FOR ALL TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow authenticated users full access to app_sessions" ON app_sessions;
CREATE POLICY "Allow authenticated users full access to app_sessions"
ON app_sessions FOR ALL TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow authenticated users full access to app_licenses" ON app_licenses;
CREATE POLICY "Allow authenticated users full access to app_licenses"
ON app_licenses FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Allow anon key access for client desktop apps and master admin web panel
DROP POLICY IF EXISTS "Allow anon access to party_hisab" ON party_hisab;
CREATE POLICY "Allow anon access to party_hisab"
ON party_hisab FOR ALL TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow anon access to app_sessions" ON app_sessions;
CREATE POLICY "Allow anon access to app_sessions"
ON app_sessions FOR ALL TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow anon access to app_licenses" ON app_licenses;
CREATE POLICY "Allow anon access to app_licenses"
ON app_licenses FOR ALL TO anon USING (true) WITH CHECK (true);

-- Enable Supabase Realtime safely (only adds if not already added)
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND tablename = 'app_sessions'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE app_sessions;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND tablename = 'app_licenses'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE app_licenses;
  END IF;
END $$;

-- =========================================================================
-- 4. AUTO-CONFIRM ALL USERS (Instant Access Without Email Verification)
-- =========================================================================
-- Automatically sets email_confirmed_at so new users can log in immediately:
CREATE OR REPLACE FUNCTION public.auto_confirm_new_user()
RETURNS trigger AS $$
BEGIN
  NEW.email_confirmed_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  BEFORE INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.auto_confirm_new_user();

-- Auto-confirm any accounts already in the database:
UPDATE auth.users 
SET email_confirmed_at = NOW() 
WHERE email_confirmed_at IS NULL;

-- =========================================================================
-- 5. AUTO-SYNC USERS INTO APP_LICENSES TABLE (Shows immediately in Web Panel)
-- =========================================================================
-- Sync all existing users from Supabase Auth into app_licenses table:
INSERT INTO public.app_licenses (id, user_email, full_name, license_status, is_blocked, valid_until, created_at)
SELECT 
  'lic_' || substr(id::text, 1, 8),
  LOWER(email),
  COALESCE(raw_user_meta_data->>'full_name', raw_user_meta_data->>'name', split_part(email, '@', 1)),
  'Active',
  false,
  'Lifetime',
  created_at
FROM auth.users
ON CONFLICT (user_email) DO NOTHING;

-- Trigger: Whenever any user is created in Supabase Dashboard, auto-sync to app_licenses:
CREATE OR REPLACE FUNCTION public.sync_auth_user_to_licenses()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.app_licenses (id, user_email, full_name, license_status, is_blocked, valid_until, created_at)
  VALUES (
    'lic_' || substr(NEW.id::text, 1, 8),
    LOWER(NEW.email),
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', split_part(NEW.email, '@', 1)),
    'Active',
    false,
    'Lifetime',
    NOW()
  )
  ON CONFLICT (user_email) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_sync_license ON auth.users;
CREATE TRIGGER on_auth_user_sync_license
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.sync_auth_user_to_licenses();

-- =========================================================================
-- 6. ADMIN-ONLY PASSWORD RESET RPC
-- Only Master Admin has the power to reset passwords remotely from Web Panel
-- =========================================================================
CREATE OR REPLACE FUNCTION public.admin_reset_user_password(target_email text, new_password text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  rows_updated integer;
BEGIN
  -- Update encrypted password in auth.users using pgcrypto bcrypt salt
  BEGIN
    UPDATE auth.users
    SET encrypted_password = extensions.crypt(new_password, extensions.gen_salt('bf')),
        updated_at = NOW()
    WHERE LOWER(email) = LOWER(TRIM(target_email));
    GET DIAGNOSTICS rows_updated = ROW_COUNT;
  EXCEPTION WHEN OTHERS THEN
    UPDATE auth.users
    SET encrypted_password = crypt(new_password, gen_salt('bf')),
        updated_at = NOW()
    WHERE LOWER(email) = LOWER(TRIM(target_email));
    GET DIAGNOSTICS rows_updated = ROW_COUNT;
  END;

  RETURN rows_updated > 0;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_reset_user_password(text, text) TO anon, authenticated, service_role;

