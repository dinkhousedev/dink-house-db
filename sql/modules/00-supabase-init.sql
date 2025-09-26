-- ============================================================================
-- SUPABASE INITIALIZATION MODULE
-- Creates required schemas and tables for Supabase services
-- This must run BEFORE other modules to avoid conflicts
-- ============================================================================

-- Create required extensions first
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
-- Note: pgjwt is optional and may not be available in Alpine
-- CREATE EXTENSION IF NOT EXISTS "pgjwt";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";

-- ============================================================================
-- AUTH SCHEMA (for Supabase GoTrue)
-- ============================================================================
-- Note: This is separate from our custom app_auth schema

-- The auth schema is created automatically by GoTrue, but we ensure it exists
CREATE SCHEMA IF NOT EXISTS auth;

-- Grant necessary permissions
GRANT USAGE ON SCHEMA auth TO postgres;
GRANT CREATE ON SCHEMA auth TO postgres;
GRANT ALL ON SCHEMA auth TO postgres;

-- ============================================================================
-- STORAGE SCHEMA (for Supabase Storage)
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS storage;
GRANT ALL ON SCHEMA storage TO postgres;

-- Create storage tables
CREATE TABLE IF NOT EXISTS storage.buckets (
    id text NOT NULL PRIMARY KEY,
    name text UNIQUE NOT NULL,
    owner uuid,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    public boolean DEFAULT false,
    avif_autodetection boolean DEFAULT false,
    file_size_limit bigint,
    allowed_mime_types text[]
);

CREATE TABLE IF NOT EXISTS storage.objects (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    bucket_id text,
    name text,
    owner uuid,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    last_accessed_at timestamptz DEFAULT now(),
    metadata jsonb,
    -- path_tokens column will be added by storage service migration if needed
    CONSTRAINT objects_bucketid_fkey FOREIGN KEY (bucket_id) REFERENCES storage.buckets(id),
    UNIQUE(bucket_id, name)
);

CREATE TABLE IF NOT EXISTS storage.migrations (
    id integer PRIMARY KEY,
    name varchar(100) UNIQUE NOT NULL,
    hash varchar(40) NOT NULL,
    executed_at timestamp DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for storage
CREATE INDEX IF NOT EXISTS idx_objects_bucket_id ON storage.objects(bucket_id);
CREATE INDEX IF NOT EXISTS idx_objects_owner ON storage.objects(owner);
CREATE INDEX IF NOT EXISTS idx_objects_created_at ON storage.objects(created_at);
CREATE INDEX IF NOT EXISTS idx_objects_updated_at ON storage.objects(updated_at);
CREATE INDEX IF NOT EXISTS idx_objects_last_accessed_at ON storage.objects(last_accessed_at);
-- Note: idx_objects_path_tokens will be created by storage service when it adds the path_tokens column

-- ============================================================================
-- REALTIME SCHEMA
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS realtime;
GRANT USAGE ON SCHEMA realtime TO postgres;

-- Create publication for realtime
CREATE PUBLICATION supabase_realtime FOR ALL TABLES;

-- ============================================================================
-- EXTENSIONS SCHEMA
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS extensions;
GRANT USAGE ON SCHEMA extensions TO postgres;
GRANT CREATE ON SCHEMA extensions TO postgres;

-- ============================================================================
-- ROLES FOR SUPABASE
-- ============================================================================

-- Create roles if they don't exist
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
        CREATE ROLE anon NOLOGIN NOINHERIT;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
        CREATE ROLE authenticated NOLOGIN NOINHERIT;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
        CREATE ROLE service_role NOLOGIN NOINHERIT BYPASSRLS;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_admin') THEN
        CREATE ROLE supabase_admin NOLOGIN CREATEDB CREATEROLE REPLICATION BYPASSRLS;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_auth_admin') THEN
        CREATE ROLE supabase_auth_admin NOLOGIN NOINHERIT CREATEROLE;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_storage_admin') THEN
        CREATE ROLE supabase_storage_admin NOLOGIN NOINHERIT;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_realtime_admin') THEN
        CREATE ROLE supabase_realtime_admin NOLOGIN NOINHERIT;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_anon') THEN
        CREATE ROLE app_anon NOLOGIN NOINHERIT;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_authenticated') THEN
        CREATE ROLE app_authenticated NOLOGIN NOINHERIT;
    END IF;
END
$$;

-- Grant permissions to roles
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA extensions TO anon, authenticated, service_role;

-- Grant auth permissions
GRANT ALL ON SCHEMA auth TO supabase_auth_admin;
GRANT ALL ON ALL TABLES IN SCHEMA auth TO supabase_auth_admin;
GRANT ALL ON ALL SEQUENCES IN SCHEMA auth TO supabase_auth_admin;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_auth_admin IN SCHEMA auth GRANT ALL ON TABLES TO supabase_auth_admin;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_auth_admin IN SCHEMA auth GRANT ALL ON SEQUENCES TO supabase_auth_admin;

-- Grant storage permissions
GRANT ALL ON SCHEMA storage TO supabase_storage_admin;
GRANT ALL ON ALL TABLES IN SCHEMA storage TO supabase_storage_admin;
GRANT ALL ON ALL SEQUENCES IN SCHEMA storage TO supabase_storage_admin;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_storage_admin IN SCHEMA storage GRANT ALL ON TABLES TO supabase_storage_admin;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_storage_admin IN SCHEMA storage GRANT ALL ON SEQUENCES TO supabase_storage_admin;

-- Grant realtime permissions
GRANT ALL ON SCHEMA realtime TO supabase_realtime_admin;
GRANT ALL ON ALL TABLES IN SCHEMA realtime TO supabase_realtime_admin;
GRANT ALL ON ALL SEQUENCES IN SCHEMA realtime TO supabase_realtime_admin;

-- Grant postgres user necessary permissions
GRANT anon, authenticated, service_role, supabase_admin, supabase_auth_admin, supabase_storage_admin, supabase_realtime_admin TO postgres;

-- ============================================================================
-- HELPER FUNCTIONS FOR SUPABASE
-- ============================================================================

-- JWT functions that auth service expects
CREATE OR REPLACE FUNCTION auth.uid()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

CREATE OR REPLACE FUNCTION auth.role()
RETURNS text
LANGUAGE sql
STABLE
AS $$
  SELECT NULLIF(current_setting('request.jwt.claim.role', true), '')::text;
$$;

CREATE OR REPLACE FUNCTION auth.email()
RETURNS text
LANGUAGE sql
STABLE
AS $$
  SELECT NULLIF(current_setting('request.jwt.claim.email', true), '')::text;
$$;

-- ============================================================================
-- INITIAL STORAGE BUCKETS
-- ============================================================================

-- Create default storage buckets
INSERT INTO storage.buckets (id, name, public)
VALUES
    ('avatars', 'avatars', true),
    ('public', 'public', true),
    ('private', 'private', false)
ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- SET DATABASE CONFIGURATION
-- ============================================================================

-- Set the JWT secret (this will be overridden by environment variables)
ALTER DATABASE dink_house SET "app.jwt_secret" TO 'your-super-secret-jwt-key-change-in-production';

-- Set statement timeout
ALTER DATABASE dink_house SET statement_timeout TO '60s';

-- Enable RLS
ALTER DATABASE dink_house SET row_security TO 'on';

COMMENT ON SCHEMA storage IS 'Supabase Storage schema for managing file uploads';
COMMENT ON SCHEMA auth IS 'Supabase Auth schema for GoTrue authentication service';
COMMENT ON SCHEMA realtime IS 'Supabase Realtime schema for websocket functionality';