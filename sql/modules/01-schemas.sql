-- ============================================================================
-- SCHEMAS MODULE
-- Create separate schemas for different domains
-- ============================================================================

-- Drop schemas if they exist (for clean rebuilds)
DROP SCHEMA IF EXISTS app_auth CASCADE;  -- Renamed from auth to avoid conflict with Supabase
DROP SCHEMA IF EXISTS content CASCADE;
DROP SCHEMA IF EXISTS contact CASCADE;
DROP SCHEMA IF EXISTS launch CASCADE;
DROP SCHEMA IF EXISTS system CASCADE;
DROP SCHEMA IF EXISTS api CASCADE;

-- Create schemas
CREATE SCHEMA app_auth AUTHORIZATION postgres;  -- Renamed from auth to avoid conflict with Supabase
COMMENT ON SCHEMA app_auth IS 'Application authentication and authorization (separate from Supabase auth)';

CREATE SCHEMA content AUTHORIZATION postgres;
COMMENT ON SCHEMA content IS 'Content management system';

CREATE SCHEMA contact AUTHORIZATION postgres;
COMMENT ON SCHEMA contact IS 'Contact and inquiry management';

CREATE SCHEMA launch AUTHORIZATION postgres;
COMMENT ON SCHEMA launch IS 'Launch campaigns and notifications';

CREATE SCHEMA system AUTHORIZATION postgres;
COMMENT ON SCHEMA system IS 'System configuration and logging';

CREATE SCHEMA api AUTHORIZATION postgres;
COMMENT ON SCHEMA api IS 'API views and functions';

-- Set search path to include all schemas
ALTER DATABASE dink_house SET search_path TO public, app_auth, content, contact, launch, system, api;

-- Grant usage on schemas
GRANT USAGE ON SCHEMA app_auth TO postgres;
GRANT USAGE ON SCHEMA content TO postgres;
GRANT USAGE ON SCHEMA contact TO postgres;
GRANT USAGE ON SCHEMA launch TO postgres;
GRANT USAGE ON SCHEMA system TO postgres;
GRANT USAGE ON SCHEMA api TO postgres;

-- Grant create on schemas to postgres
GRANT CREATE ON SCHEMA app_auth TO postgres;
GRANT CREATE ON SCHEMA content TO postgres;
GRANT CREATE ON SCHEMA contact TO postgres;
GRANT CREATE ON SCHEMA launch TO postgres;
GRANT CREATE ON SCHEMA system TO postgres;
GRANT CREATE ON SCHEMA api TO postgres;