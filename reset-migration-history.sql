-- Reset Supabase Migration History
-- Run this in Supabase Dashboard SQL Editor:
-- https://supabase.com/dashboard/project/wchxzbuuwssrnaxshseu/sql

-- Clear all existing migration history
TRUNCATE TABLE supabase_migrations.schema_migrations;

-- Add the new baseline migration
INSERT INTO supabase_migrations.schema_migrations (version, name, statements)
VALUES ('20251008', 'baseline_from_modules', ARRAY['-- Baseline from sql/modules/']);

-- Verify
SELECT * FROM supabase_migrations.schema_migrations;
