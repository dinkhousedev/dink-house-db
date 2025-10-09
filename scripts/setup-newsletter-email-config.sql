-- Setup Newsletter Email Configuration
-- Run this script to configure the database settings needed for newsletter emails

-- IMPORTANT: Replace these values with your actual Supabase project details
-- You can find these in your Supabase Dashboard > Settings > API

-- Set Supabase URL (replace with your project URL)
ALTER DATABASE postgres SET app.supabase_url = 'https://wchxzbuuwssrnaxshseu.supabase.co';

-- Set Service Role Key (replace with your service role key)
-- WARNING: Keep this key secure! It has full database access.
ALTER DATABASE postgres SET app.supabase_service_role_key = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndjaHh6YnV1d3Nzcm5heHNoc2V1Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc1ODk5MDg3NywiZXhwIjoyMDc0NTY2ODc3fQ.6u66CMI4K4xb1R3-xbEHkW5TeQ9tXeA420WyMnW-d5I';

-- Verify settings were applied
SELECT
    'app.supabase_url' as setting,
    current_setting('app.supabase_url', true) as value
UNION ALL
SELECT
    'app.supabase_service_role_key' as setting,
    CASE
        WHEN current_setting('app.supabase_service_role_key', true) IS NOT NULL
        THEN '***configured***'
        ELSE 'NOT SET'
    END as value;

-- Test that pg_net extension is available
SELECT
    extname,
    extversion
FROM pg_extension
WHERE extname = 'pg_net';

-- If you see 'pg_net' in the results above, you're good to go!
-- If not, run: CREATE EXTENSION pg_net;

COMMENT ON DATABASE postgres IS 'Newsletter email configuration applied. Remember to keep service role key secure!';