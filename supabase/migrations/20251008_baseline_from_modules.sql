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

-- Create publication for realtime (if not exists)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        CREATE PUBLICATION supabase_realtime FOR ALL TABLES;
    END IF;
END
$$;

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
COMMENT ON SCHEMA realtime IS 'Supabase Realtime schema for websocket functionality';-- ============================================================================
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
GRANT CREATE ON SCHEMA api TO postgres;-- ============================================================================
-- EXTENSIONS MODULE
-- Enable required PostgreSQL extensions in public schema
-- ============================================================================

-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" SCHEMA public;

-- Enable cryptographic functions for password hashing
CREATE EXTENSION IF NOT EXISTS "pgcrypto" SCHEMA public;

-- Enable case-insensitive text
CREATE EXTENSION IF NOT EXISTS "citext" SCHEMA public;-- ============================================================================
-- APPLICATION AUTHENTICATION MODULE
-- Multi-persona authentication schema (admin, player, guest)
-- Note: This is separate from Supabase's auth schema
-- ============================================================================

SET search_path TO app_auth, public;

-- --------------------------------------------------------------------------
-- Shared enum types (created idempotently for repeated migrations)
-- --------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_type t
        JOIN pg_namespace n ON t.typnamespace = n.oid
        WHERE t.typname = 'user_type' AND n.nspname = 'app_auth'
    ) THEN
        CREATE TYPE app_auth.user_type AS ENUM ('admin', 'player', 'guest');
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_type t
        JOIN pg_namespace n ON t.typnamespace = n.oid
        WHERE t.typname = 'admin_role' AND n.nspname = 'app_auth'
    ) THEN
        CREATE TYPE app_auth.admin_role AS ENUM ('super_admin', 'admin', 'manager', 'coach', 'editor', 'viewer');
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_type t
        JOIN pg_namespace n ON t.typnamespace = n.oid
        WHERE t.typname = 'membership_level' AND n.nspname = 'app_auth'
    ) THEN
        CREATE TYPE app_auth.membership_level AS ENUM ('guest', 'basic', 'premium', 'vip');
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_type t
        JOIN pg_namespace n ON t.typnamespace = n.oid
        WHERE t.typname = 'skill_level' AND n.nspname = 'app_auth'
    ) THEN
        CREATE TYPE app_auth.skill_level AS ENUM ('beginner', 'intermediate', 'advanced', 'pro');
    END IF;
END;
$$;

-- --------------------------------------------------------------------------
-- Canonical account table shared by admins, players, and guests
-- --------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS app_auth.user_accounts (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    email public.CITEXT NOT NULL,
    password_hash TEXT NOT NULL,
    user_type app_auth.user_type NOT NULL,
    is_active BOOLEAN DEFAULT true,
    is_verified BOOLEAN DEFAULT false,
    verification_token TEXT,
    password_reset_token TEXT,
    password_reset_expires TIMESTAMP WITH TIME ZONE,
    last_login TIMESTAMP WITH TIME ZONE,
    failed_login_attempts INT DEFAULT 0,
    locked_until TIMESTAMP WITH TIME ZONE,
    temporary_expires_at TIMESTAMP WITH TIME ZONE,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_user_accounts_email UNIQUE (email),
    CONSTRAINT chk_guest_temporary_expiry
        CHECK (
            (user_type = 'guest' AND temporary_expires_at IS NOT NULL)
            OR (user_type <> 'guest' AND temporary_expires_at IS NULL)
            OR temporary_expires_at IS NULL
        )
);

-- --------------------------------------------------------------------------
-- Admin/staff profile data (1:1 with user_accounts)
-- --------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS app_auth.admin_users (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    account_id UUID NOT NULL UNIQUE REFERENCES app_auth.user_accounts(id) ON DELETE CASCADE,
    username public.CITEXT UNIQUE NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    role app_auth.admin_role NOT NULL DEFAULT 'viewer',
    department TEXT,
    phone TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- --------------------------------------------------------------------------
-- Player/member profile data (1:1 with user_accounts)
-- --------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS app_auth.players (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    account_id UUID NOT NULL UNIQUE REFERENCES app_auth.user_accounts(id) ON DELETE CASCADE,
    first_name TEXT NOT NULL,
    last_name TEXT NOT NULL,
    display_name TEXT,
    phone TEXT,
    street_address TEXT,
    city TEXT,
    state TEXT,
    date_of_birth DATE,
    membership_level app_auth.membership_level DEFAULT 'guest',
    membership_started_on DATE,
    membership_expires_on DATE,
    skill_level app_auth.skill_level,
    dupr_rating NUMERIC(3, 2),
    dupr_rating_updated_at TIMESTAMP WITH TIME ZONE,
    club_id UUID,
    stripe_customer_id TEXT UNIQUE,
    profile JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- --------------------------------------------------------------------------
-- Guest/temporary access profile (1:1 with user_accounts)
-- --------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS app_auth.guest_users (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    account_id UUID NOT NULL UNIQUE REFERENCES app_auth.user_accounts(id) ON DELETE CASCADE,
    display_name TEXT,
    email public.CITEXT,
    phone TEXT,
    invited_by_admin UUID REFERENCES app_auth.admin_users(id) ON DELETE SET NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT (CURRENT_TIMESTAMP + INTERVAL '48 hours'),
    converted_to_player_at TIMESTAMP WITH TIME ZONE,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_guest_expiry_future CHECK (expires_at > created_at)
);

-- --------------------------------------------------------------------------
-- Sessions / refresh tokens / API keys reference user_accounts
-- --------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS app_auth.sessions (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    account_id UUID NOT NULL REFERENCES app_auth.user_accounts(id) ON DELETE CASCADE,
    token_hash TEXT UNIQUE NOT NULL,
    user_type app_auth.user_type NOT NULL,
    ip_address INET,
    user_agent TEXT,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS app_auth.refresh_tokens (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    account_id UUID NOT NULL REFERENCES app_auth.user_accounts(id) ON DELETE CASCADE,
    token_hash TEXT UNIQUE NOT NULL,
    user_type app_auth.user_type NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    revoked_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS app_auth.api_keys (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    account_id UUID NOT NULL REFERENCES app_auth.user_accounts(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    key_hash TEXT UNIQUE NOT NULL,
    permissions JSONB DEFAULT '[]'::jsonb,
    last_used_at TIMESTAMP WITH TIME ZONE,
    expires_at TIMESTAMP WITH TIME ZONE,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- --------------------------------------------------------------------------
-- Useful indexes
-- --------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_user_accounts_email ON app_auth.user_accounts(email);
CREATE INDEX IF NOT EXISTS idx_user_accounts_user_type ON app_auth.user_accounts(user_type);
CREATE INDEX IF NOT EXISTS idx_user_accounts_temp_expiry ON app_auth.user_accounts(temporary_expires_at) WHERE temporary_expires_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_admin_users_role ON app_auth.admin_users(role);
CREATE INDEX IF NOT EXISTS idx_admin_users_name ON app_auth.admin_users(last_name, first_name);

CREATE INDEX IF NOT EXISTS idx_players_membership ON app_auth.players(membership_level);
CREATE INDEX IF NOT EXISTS idx_players_skill_level ON app_auth.players(skill_level);
CREATE INDEX IF NOT EXISTS idx_players_dupr_rating ON app_auth.players(dupr_rating);
CREATE INDEX IF NOT EXISTS idx_players_name ON app_auth.players(last_name, first_name);

CREATE INDEX IF NOT EXISTS idx_guest_users_expiry ON app_auth.guest_users(expires_at);
CREATE UNIQUE INDEX IF NOT EXISTS uq_guest_users_active_email
    ON app_auth.guest_users(email)
    WHERE converted_to_player_at IS NULL AND email IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_sessions_token_hash ON app_auth.sessions(token_hash);
CREATE INDEX IF NOT EXISTS idx_sessions_account_id ON app_auth.sessions(account_id);
CREATE INDEX IF NOT EXISTS idx_sessions_user_type ON app_auth.sessions(user_type);
CREATE INDEX IF NOT EXISTS idx_sessions_expires_at ON app_auth.sessions(expires_at);

CREATE INDEX IF NOT EXISTS idx_refresh_tokens_token_hash ON app_auth.refresh_tokens(token_hash);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_account_id ON app_auth.refresh_tokens(account_id);

CREATE INDEX IF NOT EXISTS idx_api_keys_key_hash ON app_auth.api_keys(key_hash);
CREATE INDEX IF NOT EXISTS idx_api_keys_account_id ON app_auth.api_keys(account_id);
-- ============================================================================
-- CONTENT MANAGEMENT MODULE
-- Pages, categories, and media management in content schema
-- ============================================================================

-- Switch to content schema
SET search_path TO content, public;

-- Content categories
CREATE TABLE IF NOT EXISTS content.categories (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(255) UNIQUE NOT NULL,
    description TEXT,
    parent_id UUID REFERENCES content.categories(id) ON DELETE CASCADE,
    sort_order INT DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    meta_data JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Content pages
CREATE TABLE IF NOT EXISTS content.pages (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    title VARCHAR(255) NOT NULL,
    slug VARCHAR(255) UNIQUE NOT NULL,
    content TEXT,
    excerpt TEXT,
    featured_image VARCHAR(500),
    meta_title VARCHAR(255),
    meta_description TEXT,
    meta_keywords TEXT[],
    category_id UUID REFERENCES content.categories(id) ON DELETE SET NULL,
    status VARCHAR(50) DEFAULT 'draft'
        CHECK (status IN ('draft', 'published', 'scheduled', 'archived')),
    visibility VARCHAR(50) DEFAULT 'public'
        CHECK (visibility IN ('public', 'private', 'password_protected')),
    password_hash VARCHAR(255),
    author_id UUID NOT NULL REFERENCES app_auth.admin_users(id) ON DELETE RESTRICT,
    editor_id UUID REFERENCES app_auth.admin_users(id) ON DELETE SET NULL,
    published_at TIMESTAMP WITH TIME ZONE,
    scheduled_at TIMESTAMP WITH TIME ZONE,
    views_count INT DEFAULT 0,
    custom_data JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Media files
CREATE TABLE IF NOT EXISTS content.media_files (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    filename VARCHAR(255) NOT NULL,
    original_filename VARCHAR(255) NOT NULL,
    file_path VARCHAR(500) NOT NULL,
    file_url VARCHAR(500),
    file_size BIGINT NOT NULL,
    mime_type VARCHAR(100) NOT NULL,
    file_extension VARCHAR(20),
    width INT,
    height INT,
    duration INT, -- For video/audio files in seconds
    alt_text VARCHAR(255),
    caption TEXT,
    folder_path VARCHAR(500) DEFAULT '/',
    tags TEXT[],
    metadata JSONB DEFAULT '{}',
    uploaded_by UUID NOT NULL REFERENCES app_auth.admin_users(id) ON DELETE RESTRICT,
    is_public BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Content revisions for version control
CREATE TABLE IF NOT EXISTS content.revisions (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    page_id UUID NOT NULL REFERENCES content.pages(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    content TEXT,
    excerpt TEXT,
    meta_data JSONB,
    revision_number INT NOT NULL,
    revision_message TEXT,
    created_by UUID NOT NULL REFERENCES app_auth.admin_users(id) ON DELETE RESTRICT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for content tables
CREATE INDEX idx_categories_slug ON content.categories(slug);
CREATE INDEX idx_categories_parent_id ON content.categories(parent_id);
CREATE INDEX idx_pages_slug ON content.pages(slug);
CREATE INDEX idx_pages_status ON content.pages(status);
CREATE INDEX idx_pages_author_id ON content.pages(author_id);
CREATE INDEX idx_pages_category_id ON content.pages(category_id);
CREATE INDEX idx_pages_published_at ON content.pages(published_at);
CREATE INDEX idx_media_files_mime_type ON content.media_files(mime_type);
CREATE INDEX idx_media_files_uploaded_by ON content.media_files(uploaded_by);
CREATE INDEX idx_media_files_folder_path ON content.media_files(folder_path);
CREATE INDEX idx_revisions_page_id ON content.revisions(page_id);
-- ============================================================================
-- CONTACT MANAGEMENT MODULE
-- Contact form submissions and inquiry management
-- ============================================================================

-- Set search path for contact schema
SET search_path TO contact, public;

-- Contact form configurations
CREATE TABLE IF NOT EXISTS contact.contact_forms (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(255) UNIQUE NOT NULL,
    description TEXT,
    fields JSONB NOT NULL DEFAULT '[]',
    email_recipients TEXT[],
    success_message TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Contact inquiries
CREATE TABLE IF NOT EXISTS contact.contact_inquiries (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    form_id UUID REFERENCES contact.contact_forms(id) ON DELETE SET NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email public.CITEXT NOT NULL,
    phone VARCHAR(30),
    company VARCHAR(255),
    job_title VARCHAR(255),
    subject VARCHAR(255),
    message TEXT NOT NULL,
    custom_fields JSONB DEFAULT '{}',
    source VARCHAR(100) DEFAULT 'website'
        CHECK (source IN ('website', 'landing_page', 'referral', 'social_media', 'email', 'phone', 'other')),
    source_details JSONB DEFAULT '{}',
    status VARCHAR(50) DEFAULT 'new'
        CHECK (status IN ('new', 'in_progress', 'responded', 'resolved', 'closed', 'spam')),
    priority VARCHAR(20) DEFAULT 'medium'
        CHECK (priority IN ('low', 'medium', 'high', 'urgent')),
    tags TEXT[],
    assigned_to UUID REFERENCES app_auth.admin_users(id) ON DELETE SET NULL,
    responded_at TIMESTAMP WITH TIME ZONE,
    resolved_at TIMESTAMP WITH TIME ZONE,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Contact inquiry responses
CREATE TABLE IF NOT EXISTS contact.contact_responses (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    inquiry_id UUID NOT NULL REFERENCES contact.contact_inquiries(id) ON DELETE CASCADE,
    responder_id UUID NOT NULL REFERENCES app_auth.admin_users(id) ON DELETE RESTRICT,
    response_type VARCHAR(50) DEFAULT 'email'
        CHECK (response_type IN ('email', 'phone', 'internal_note')),
    subject VARCHAR(255),
    message TEXT NOT NULL,
    is_internal BOOLEAN DEFAULT false,
    sent_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Contact blacklist for spam prevention
CREATE TABLE IF NOT EXISTS contact.contact_blacklist (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    email public.CITEXT,
    ip_address INET,
    reason TEXT,
    expires_at TIMESTAMP WITH TIME ZONE,
    created_by UUID REFERENCES app_auth.admin_users(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for contact tables
CREATE INDEX inquiries_email ON contact.contact_inquiries(email);
CREATE INDEX inquiries_status ON contact.contact_inquiries(status);
CREATE INDEX inquiries_priority ON contact.contact_inquiries(priority);
CREATE INDEX inquiries_assigned_to ON contact.contact_inquiries(assigned_to);
CREATE INDEX inquiries_created_at ON contact.contact_inquiries(created_at);
CREATE INDEX responses_inquiry_id ON contact.contact_responses(inquiry_id);
CREATE INDEX blacklist_email ON contact.contact_blacklist(email);
CREATE INDEX blacklist_ip_address ON contact.contact_blacklist(ip_address);
-- ============================================================================
-- LAUNCH & NOTIFICATION MODULE
-- Campaign management and subscriber notifications
-- ============================================================================

-- Set search path for launch schema
SET search_path TO launch, public;

-- Launch campaigns
CREATE TABLE IF NOT EXISTS launch.launch_campaigns (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(255) UNIQUE NOT NULL,
    description TEXT,
    campaign_type VARCHAR(50) DEFAULT 'product_launch'
        CHECK (campaign_type IN ('product_launch', 'feature_release', 'announcement', 'newsletter', 'event')),
    launch_date TIMESTAMP WITH TIME ZONE,
    end_date TIMESTAMP WITH TIME ZONE,
    status VARCHAR(50) DEFAULT 'draft'
        CHECK (status IN ('draft', 'scheduled', 'active', 'paused', 'completed', 'cancelled')),
    target_audience JSONB DEFAULT '{}',
    goals JSONB DEFAULT '{}',
    metadata JSONB DEFAULT '{}',
    created_by UUID NOT NULL REFERENCES app_auth.admin_users(id) ON DELETE RESTRICT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Launch subscribers
CREATE TABLE IF NOT EXISTS launch.launch_subscribers (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    email public.CITEXT UNIQUE NOT NULL,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    phone VARCHAR(30),
    company VARCHAR(255),
    job_title VARCHAR(255),
    interests TEXT[],
    preferences JSONB DEFAULT '{}',
    source VARCHAR(100) DEFAULT 'website',
    source_campaign VARCHAR(255),
    referrer_url TEXT,
    subscription_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    verification_token VARCHAR(255),
    verified_at TIMESTAMP WITH TIME ZONE,
    is_active BOOLEAN DEFAULT true,
    unsubscribed_at TIMESTAMP WITH TIME ZONE,
    bounce_count INT DEFAULT 0,
    complaint_count INT DEFAULT 0,
    engagement_score DECIMAL(5,2) DEFAULT 0,
    tags TEXT[],
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Campaign subscribers (many-to-many relationship)
CREATE TABLE IF NOT EXISTS launch.launch_campaign_subscribers (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    campaign_id UUID NOT NULL REFERENCES launch.launch_campaigns(id) ON DELETE CASCADE,
    subscriber_id UUID NOT NULL REFERENCES launch.launch_subscribers(id) ON DELETE CASCADE,
    added_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(campaign_id, subscriber_id)
);

-- Notification templates (created first as it's referenced by launch_notifications)
CREATE TABLE IF NOT EXISTS launch.notification_templates (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(255) UNIQUE NOT NULL,
    template_type VARCHAR(50) NOT NULL
        CHECK (template_type IN ('email', 'sms', 'push', 'in_app')),
    category VARCHAR(100) NOT NULL
        CHECK (category IN ('launch_notification', 'welcome', 'confirmation', 'reminder', 'follow_up', 'newsletter', 'transactional')),
    subject VARCHAR(255),
    html_content TEXT,
    text_content TEXT,
    variables JSONB DEFAULT '{}',
    is_active BOOLEAN DEFAULT true,
    created_by UUID NOT NULL REFERENCES app_auth.admin_users(id) ON DELETE RESTRICT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Launch notifications
CREATE TABLE IF NOT EXISTS launch.launch_notifications (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    campaign_id UUID NOT NULL REFERENCES launch.launch_campaigns(id) ON DELETE CASCADE,
    subscriber_id UUID NOT NULL REFERENCES launch.launch_subscribers(id) ON DELETE CASCADE,
    notification_type VARCHAR(50) NOT NULL
        CHECK (notification_type IN ('email', 'sms', 'push', 'in_app')),
    template_id UUID REFERENCES launch.notification_templates(id) ON DELETE SET NULL,
    subject VARCHAR(255),
    content TEXT,
    status VARCHAR(50) DEFAULT 'pending'
        CHECK (status IN ('pending', 'queued', 'sending', 'sent', 'delivered', 'opened', 'clicked', 'failed', 'bounced', 'complained')),
    scheduled_for TIMESTAMP WITH TIME ZONE,
    sent_at TIMESTAMP WITH TIME ZONE,
    delivered_at TIMESTAMP WITH TIME ZONE,
    opened_at TIMESTAMP WITH TIME ZONE,
    clicked_at TIMESTAMP WITH TIME ZONE,
    failed_at TIMESTAMP WITH TIME ZONE,
    error_message TEXT,
    retry_count INT DEFAULT 0,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Subscriber segments for targeted campaigns
CREATE TABLE IF NOT EXISTS launch.launch_segments (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    criteria JSONB NOT NULL,
    is_dynamic BOOLEAN DEFAULT true,
    subscriber_count INT DEFAULT 0,
    created_by UUID NOT NULL REFERENCES app_auth.admin_users(id) ON DELETE RESTRICT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Segment subscribers (for static segments)
CREATE TABLE IF NOT EXISTS launch.launch_segment_subscribers (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    segment_id UUID NOT NULL REFERENCES launch.launch_segments(id) ON DELETE CASCADE,
    subscriber_id UUID NOT NULL REFERENCES launch.launch_subscribers(id) ON DELETE CASCADE,
    added_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(segment_id, subscriber_id)
);

-- Create indexes for launch tables
CREATE INDEX campaigns_status ON launch.launch_campaigns(status);
CREATE INDEX campaigns_launch_date ON launch.launch_campaigns(launch_date);
CREATE INDEX subscribers_email ON launch.launch_subscribers(email);
CREATE INDEX subscribers_is_active ON launch.launch_subscribers(is_active);
CREATE INDEX campaign_subscribers_campaign_id ON launch.launch_campaign_subscribers(campaign_id);
CREATE INDEX campaign_subscribers_subscriber_id ON launch.launch_campaign_subscribers(subscriber_id);
CREATE INDEX notifications_campaign_id ON launch.launch_notifications(campaign_id);
CREATE INDEX notifications_subscriber_id ON launch.launch_notifications(subscriber_id);
CREATE INDEX notifications_status ON launch.launch_notifications(status);
CREATE INDEX notifications_scheduled_for ON launch.launch_notifications(scheduled_for);
CREATE INDEX templates_slug ON launch.notification_templates(slug);
CREATE INDEX templates_category ON launch.notification_templates(category);
-- ============================================================================
-- SYSTEM MODULE
-- System settings, logs, and administrative functions
-- ============================================================================

-- Set search path for system schema
SET search_path TO system, public;

-- System settings
CREATE TABLE IF NOT EXISTS system.system_settings (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    setting_key VARCHAR(255) UNIQUE NOT NULL,
    setting_value TEXT,
    setting_type VARCHAR(50) DEFAULT 'string'
        CHECK (setting_type IN ('string', 'number', 'boolean', 'json', 'array')),
    category VARCHAR(100) DEFAULT 'general',
    description TEXT,
    is_public BOOLEAN DEFAULT false,
    is_encrypted BOOLEAN DEFAULT false,
    validation_rules JSONB,
    updated_by UUID REFERENCES app_auth.admin_users(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Activity logs
CREATE TABLE IF NOT EXISTS system.activity_logs (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    user_id UUID REFERENCES app_auth.admin_users(id) ON DELETE SET NULL,
    action VARCHAR(100) NOT NULL,
    entity_type VARCHAR(100) NOT NULL,
    entity_id UUID,
    old_values JSONB,
    new_values JSONB,
    details JSONB,
    ip_address INET,
    user_agent TEXT,
    session_id UUID REFERENCES app_auth.sessions(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- System jobs/tasks queue
CREATE TABLE IF NOT EXISTS system.system_jobs (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    job_type VARCHAR(100) NOT NULL,
    job_name VARCHAR(255) NOT NULL,
    payload JSONB DEFAULT '{}',
    status VARCHAR(50) DEFAULT 'pending'
        CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'cancelled')),
    priority INT DEFAULT 5 CHECK (priority BETWEEN 1 AND 10),
    max_retries INT DEFAULT 3,
    retry_count INT DEFAULT 0,
    scheduled_at TIMESTAMP WITH TIME ZONE,
    started_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,
    failed_at TIMESTAMP WITH TIME ZONE,
    error_message TEXT,
    result JSONB,
    created_by UUID REFERENCES app_auth.admin_users(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Email queue for async sending
CREATE TABLE IF NOT EXISTS system.email_queue (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    to_email TEXT[] NOT NULL,
    cc_email TEXT[],
    bcc_email TEXT[],
    from_email VARCHAR(255),
    reply_to VARCHAR(255),
    subject VARCHAR(255) NOT NULL,
    html_body TEXT,
    text_body TEXT,
    attachments JSONB DEFAULT '[]',
    headers JSONB DEFAULT '{}',
    priority INT DEFAULT 5 CHECK (priority BETWEEN 1 AND 10),
    template_id UUID REFERENCES launch.notification_templates(id) ON DELETE SET NULL,
    template_data JSONB,
    status VARCHAR(50) DEFAULT 'queued'
        CHECK (status IN ('queued', 'sending', 'sent', 'failed', 'bounced')),
    attempts INT DEFAULT 0,
    sent_at TIMESTAMP WITH TIME ZONE,
    failed_at TIMESTAMP WITH TIME ZONE,
    error_message TEXT,
    provider_message_id VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Audit trail for compliance
CREATE TABLE IF NOT EXISTS system.audit_trail (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    table_name VARCHAR(100) NOT NULL,
    record_id UUID NOT NULL,
    operation VARCHAR(20) NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
    user_id UUID REFERENCES app_auth.admin_users(id) ON DELETE SET NULL,
    old_data JSONB,
    new_data JSONB,
    changed_fields TEXT[],
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Feature flags for gradual rollouts
CREATE TABLE IF NOT EXISTS system.feature_flags (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    flag_key VARCHAR(255) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    is_enabled BOOLEAN DEFAULT false,
    rollout_percentage INT DEFAULT 0 CHECK (rollout_percentage BETWEEN 0 AND 100),
    conditions JSONB DEFAULT '{}',
    allowed_users UUID[],
    blocked_users UUID[],
    metadata JSONB DEFAULT '{}',
    created_by UUID REFERENCES app_auth.admin_users(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for system tables
CREATE INDEX settings_key ON system.system_settings(setting_key);
CREATE INDEX settings_category ON system.system_settings(category);
CREATE INDEX activity_logs_user_id ON system.activity_logs(user_id);
CREATE INDEX activity_logs_entity_type ON system.activity_logs(entity_type);
CREATE INDEX activity_logs_entity_id ON system.activity_logs(entity_id);
CREATE INDEX activity_logs_created_at ON system.activity_logs(created_at);
CREATE INDEX jobs_status ON system.system_jobs(status);
CREATE INDEX jobs_job_type ON system.system_jobs(job_type);
CREATE INDEX jobs_scheduled_at ON system.system_jobs(scheduled_at);
CREATE INDEX email_queue_status ON system.email_queue(status);
CREATE INDEX email_queue_created_at ON system.email_queue(created_at);
CREATE INDEX audit_trail_table_name ON system.audit_trail(table_name);
CREATE INDEX audit_trail_record_id ON system.audit_trail(record_id);
CREATE INDEX audit_trail_user_id ON system.audit_trail(user_id);
CREATE INDEX audit_trail_created_at ON system.audit_trail(created_at);
CREATE INDEX feature_flags_flag_key ON system.feature_flags(flag_key);
-- ============================================================================
-- FUNCTIONS & TRIGGERS MODULE
-- Utility functions and automated triggers
-- ============================================================================

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Function to generate a slug from text
CREATE OR REPLACE FUNCTION generate_slug(input_text TEXT)
RETURNS TEXT AS $$
BEGIN
    RETURN LOWER(
        REGEXP_REPLACE(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    TRIM(input_text),
                    '[^a-zA-Z0-9\s-]', '', 'g'
                ),
                '\s+', '-', 'g'
            ),
            '-+', '-', 'g'
        )
    );
END;
$$ LANGUAGE plpgsql;

-- Function to hash passwords (for development only)
CREATE OR REPLACE FUNCTION hash_password(password TEXT)
RETURNS TEXT AS $$
BEGIN
    RETURN crypt(password, gen_salt('bf', 8));
END;
$$ LANGUAGE plpgsql;

-- Function to verify passwords
CREATE OR REPLACE FUNCTION verify_password(password TEXT, password_hash TEXT)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN password_hash = crypt(password, password_hash);
END;
$$ LANGUAGE plpgsql;

-- Function to clean expired sessions
CREATE OR REPLACE FUNCTION clean_expired_sessions()
RETURNS void AS $$
BEGIN
    DELETE FROM app_auth.sessions WHERE expires_at < CURRENT_TIMESTAMP;
    DELETE FROM app_auth.refresh_tokens WHERE expires_at < CURRENT_TIMESTAMP AND revoked_at IS NULL;
END;
$$ LANGUAGE plpgsql;

-- Function to calculate subscriber engagement score
CREATE OR REPLACE FUNCTION calculate_engagement_score(subscriber_id UUID)
RETURNS DECIMAL AS $$
DECLARE
    score DECIMAL(5,2);
    opens_count INT;
    clicks_count INT;
    total_sent INT;
BEGIN
    SELECT
        COUNT(CASE WHEN opened_at IS NOT NULL THEN 1 END),
        COUNT(CASE WHEN clicked_at IS NOT NULL THEN 1 END),
        COUNT(*)
    INTO opens_count, clicks_count, total_sent
    FROM launch.launch_notifications
    WHERE subscriber_id = calculate_engagement_score.subscriber_id
        AND status = 'delivered';

    IF total_sent = 0 THEN
        RETURN 0;
    END IF;

    score := ((opens_count * 1.0 + clicks_count * 2.0) / (total_sent * 3.0)) * 100;
    RETURN LEAST(score, 100);
END;
$$ LANGUAGE plpgsql;

-- Function for audit logging
CREATE OR REPLACE FUNCTION create_audit_log()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO system.audit_trail(table_name, record_id, operation, new_data)
        VALUES (TG_TABLE_NAME, NEW.id, TG_OP, to_jsonb(NEW));
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO system.audit_trail(table_name, record_id, operation, old_data, new_data)
        VALUES (TG_TABLE_NAME, NEW.id, TG_OP, to_jsonb(OLD), to_jsonb(NEW));
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO system.audit_trail(table_name, record_id, operation, old_data)
        VALUES (TG_TABLE_NAME, OLD.id, TG_OP, to_jsonb(OLD));
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Updated_at triggers for all tables with updated_at column
CREATE TRIGGER update_user_accounts_updated_at
    BEFORE UPDATE ON app_auth.user_accounts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_admin_users_updated_at
    BEFORE UPDATE ON app_auth.admin_users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_players_updated_at
    BEFORE UPDATE ON app_auth.players
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_guest_users_updated_at
    BEFORE UPDATE ON app_auth.guest_users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_api_keys_updated_at
    BEFORE UPDATE ON app_auth.api_keys
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_categories_updated_at
    BEFORE UPDATE ON content.categories
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_pages_updated_at
    BEFORE UPDATE ON content.pages
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_forms_updated_at
    BEFORE UPDATE ON contact.contact_forms
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_inquiries_updated_at
    BEFORE UPDATE ON contact.contact_inquiries
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_campaigns_updated_at
    BEFORE UPDATE ON launch.launch_campaigns
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_subscribers_updated_at
    BEFORE UPDATE ON launch.launch_subscribers
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_segments_updated_at
    BEFORE UPDATE ON launch.launch_segments
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_templates_updated_at
    BEFORE UPDATE ON launch.notification_templates
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_settings_updated_at
    BEFORE UPDATE ON system.system_settings
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_jobs_updated_at
    BEFORE UPDATE ON system.system_jobs
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_flags_updated_at
    BEFORE UPDATE ON system.feature_flags
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Audit triggers (optional - enable for specific tables as needed)
-- Example: Enable audit for app_auth.user_accounts table
-- CREATE TRIGGER audit_user_accounts
--     AFTER INSERT OR UPDATE OR DELETE ON app_auth.user_accounts
--     FOR EACH ROW EXECUTE FUNCTION create_audit_log();
-- ============================================================================
-- PERMISSIONS AND ROLES MODULE
-- Database roles and schema permissions for security
-- ============================================================================

-- Create database roles
DO $$
BEGIN
    -- Application roles
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_anon') THEN
        CREATE ROLE app_anon NOLOGIN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_user') THEN
        CREATE ROLE app_user NOLOGIN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_admin') THEN
        CREATE ROLE app_admin NOLOGIN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_service') THEN
        CREATE ROLE app_service NOLOGIN;
    END IF;
END
$$;

-- Grant schema usage permissions
-- Anonymous users (public access)
GRANT USAGE ON SCHEMA public TO app_anon;
GRANT USAGE ON SCHEMA api TO app_anon;
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA api TO anon;

-- Authenticated users
GRANT USAGE ON SCHEMA public TO app_user;
GRANT USAGE ON SCHEMA auth TO app_user;
GRANT USAGE ON SCHEMA content TO app_user;
GRANT USAGE ON SCHEMA contact TO app_user;
GRANT USAGE ON SCHEMA launch TO app_user;
GRANT USAGE ON SCHEMA api TO app_user;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA auth TO authenticated;
GRANT USAGE ON SCHEMA content TO authenticated;
GRANT USAGE ON SCHEMA contact TO authenticated;
GRANT USAGE ON SCHEMA launch TO authenticated;
GRANT USAGE ON SCHEMA api TO authenticated;

-- Admin users
GRANT USAGE ON SCHEMA public TO app_admin;
GRANT USAGE ON SCHEMA auth TO app_admin;
GRANT USAGE ON SCHEMA content TO app_admin;
GRANT USAGE ON SCHEMA contact TO app_admin;
GRANT USAGE ON SCHEMA launch TO app_admin;
GRANT USAGE ON SCHEMA system TO app_admin;
GRANT USAGE ON SCHEMA api TO app_admin;
GRANT USAGE ON SCHEMA public TO service_role;
GRANT USAGE ON SCHEMA auth TO service_role;
GRANT USAGE ON SCHEMA content TO service_role;
GRANT USAGE ON SCHEMA contact TO service_role;
GRANT USAGE ON SCHEMA launch TO service_role;
GRANT USAGE ON SCHEMA system TO service_role;
GRANT USAGE ON SCHEMA api TO service_role;

-- Service accounts (full access)
GRANT ALL ON SCHEMA public TO app_service;
GRANT ALL ON SCHEMA auth TO app_service;
GRANT ALL ON SCHEMA content TO app_service;
GRANT ALL ON SCHEMA contact TO app_service;
GRANT ALL ON SCHEMA launch TO app_service;
GRANT ALL ON SCHEMA system TO app_service;
GRANT ALL ON SCHEMA api TO app_service;

-- ============================================================================
-- TABLE PERMISSIONS
-- ============================================================================

-- Auth schema permissions
GRANT SELECT ON ALL TABLES IN SCHEMA auth TO app_anon;  -- Limited read for verification
GRANT ALL ON ALL TABLES IN SCHEMA auth TO app_user;     -- Users can manage their own data
GRANT ALL ON ALL TABLES IN SCHEMA auth TO app_admin;    -- Admins have full access
GRANT ALL ON ALL TABLES IN SCHEMA auth TO app_service;  -- Services have full access

-- Content schema permissions
GRANT SELECT ON ALL TABLES IN SCHEMA content TO app_anon;  -- Anonymous can read public content
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA content TO app_user;  -- Users can create content
GRANT ALL ON ALL TABLES IN SCHEMA content TO app_admin;     -- Admins have full access
GRANT ALL ON ALL TABLES IN SCHEMA content TO app_service;   -- Services have full access

-- Contact schema permissions
GRANT INSERT ON contact.contact_inquiries TO app_anon;      -- Anonymous can submit forms
GRANT SELECT ON contact.contact_forms TO app_anon;          -- Anonymous can view forms
GRANT ALL ON ALL TABLES IN SCHEMA contact TO app_user;      -- Users have full access
GRANT ALL ON ALL TABLES IN SCHEMA contact TO app_admin;     -- Admins have full access
GRANT ALL ON ALL TABLES IN SCHEMA contact TO app_service;   -- Services have full access

-- Launch schema permissions
GRANT SELECT ON launch.launch_campaigns TO app_anon;        -- Anonymous can view campaigns
GRANT INSERT ON launch.launch_subscribers TO app_anon;      -- Anonymous can subscribe
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA launch TO app_user;  -- Users can manage subscriptions
GRANT ALL ON ALL TABLES IN SCHEMA launch TO app_admin;      -- Admins have full access
GRANT ALL ON ALL TABLES IN SCHEMA launch TO app_service;    -- Services have full access

-- System schema permissions (restricted)
-- No access for anonymous users
-- No access for regular users
GRANT ALL ON ALL TABLES IN SCHEMA system TO app_admin;      -- Admins have full access
GRANT ALL ON ALL TABLES IN SCHEMA system TO app_service;    -- Services have full access

-- ============================================================================
-- SEQUENCE PERMISSIONS
-- ============================================================================

GRANT USAGE ON ALL SEQUENCES IN SCHEMA auth TO app_user, app_admin, app_service;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA content TO app_user, app_admin, app_service;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA contact TO app_anon, app_user, app_admin, app_service;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA launch TO app_anon, app_user, app_admin, app_service;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA system TO app_admin, app_service;

-- ============================================================================
-- FUNCTION PERMISSIONS
-- ============================================================================

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO app_anon, app_user, app_admin, app_service;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA auth TO app_user, app_admin, app_service;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO app_anon, app_user, app_admin, app_service;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO anon, authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA auth TO authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO anon, authenticated, service_role;

-- ============================================================================
-- DEFAULT PRIVILEGES
-- Set default permissions for future objects
-- ============================================================================

-- For tables created by postgres user
ALTER DEFAULT PRIVILEGES IN SCHEMA auth
    GRANT ALL ON TABLES TO app_admin, app_service;
ALTER DEFAULT PRIVILEGES IN SCHEMA auth
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_user;

ALTER DEFAULT PRIVILEGES IN SCHEMA content
    GRANT ALL ON TABLES TO app_admin, app_service;
ALTER DEFAULT PRIVILEGES IN SCHEMA content
    GRANT SELECT ON TABLES TO app_anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA content
    GRANT SELECT, INSERT, UPDATE ON TABLES TO app_user;

ALTER DEFAULT PRIVILEGES IN SCHEMA contact
    GRANT ALL ON TABLES TO app_admin, app_service, app_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA contact
    GRANT INSERT ON TABLES TO app_anon;

ALTER DEFAULT PRIVILEGES IN SCHEMA launch
    GRANT ALL ON TABLES TO app_admin, app_service;
ALTER DEFAULT PRIVILEGES IN SCHEMA launch
    GRANT SELECT, INSERT, UPDATE ON TABLES TO app_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA launch
    GRANT SELECT ON TABLES TO app_anon;

ALTER DEFAULT PRIVILEGES IN SCHEMA system
    GRANT ALL ON TABLES TO app_admin, app_service;

-- For sequences
ALTER DEFAULT PRIVILEGES IN SCHEMA auth
    GRANT USAGE ON SEQUENCES TO app_user, app_admin, app_service;

ALTER DEFAULT PRIVILEGES IN SCHEMA content
    GRANT USAGE ON SEQUENCES TO app_user, app_admin, app_service;

ALTER DEFAULT PRIVILEGES IN SCHEMA contact
    GRANT USAGE ON SEQUENCES TO app_anon, app_user, app_admin, app_service;

ALTER DEFAULT PRIVILEGES IN SCHEMA launch
    GRANT USAGE ON SEQUENCES TO app_anon, app_user, app_admin, app_service;

ALTER DEFAULT PRIVILEGES IN SCHEMA system
    GRANT USAGE ON SEQUENCES TO app_admin, app_service;

-- ============================================================================
-- ROW LEVEL SECURITY (RLS)
-- Definitive policies are maintained in sql/modules/11-rls-policies.sql
ALTER TABLE app_auth.user_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_auth.admin_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_auth.players ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_auth.guest_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_auth.sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE content.pages ENABLE ROW LEVEL SECURITY;
ALTER TABLE contact.contact_inquiries ENABLE ROW LEVEL SECURITY;
ALTER TABLE system.system_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY settings_admin_all ON system.system_settings
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM app_auth.admin_users au
            WHERE au.id = current_setting('app.current_user_id', true)::uuid
            AND au.role IN ('admin', 'super_admin')
        )
    );

-- Grant role memberships
GRANT app_anon TO postgres;
GRANT app_user TO postgres;
GRANT app_admin TO postgres;
GRANT app_service TO postgres;

-- ============================================================================
-- NOTES
-- ============================================================================
-- To use these roles in your application:
-- 1. Create database users and assign them to appropriate roles:
--    CREATE USER my_app_user WITH PASSWORD 'password';
--    GRANT app_user TO my_app_user;
--
-- 2. Set session variables for RLS:
--    SET app.current_user_id = 'user-uuid';
--    SET app.current_user_email = 'user@example.com';
--
-- 3. Switch roles in your application based on authentication:
--    SET ROLE app_anon;    -- For unauthenticated requests
--    SET ROLE app_user;    -- For authenticated users
--    SET ROLE app_admin;   -- For admin users
--    SET ROLE app_service; -- For service accounts
-- ============================================================================
-- API VIEWS MODULE
-- Create views for REST API endpoints in api schema
-- ============================================================================

-- Switch to api schema
SET search_path TO api, auth, content, contact, launch, system, public;

-- ============================================================================
-- USER VIEWS
-- ============================================================================

-- Public user profile view
CREATE OR REPLACE VIEW api.users_public AS
SELECT
    au.id,
    au.username,
    au.first_name,
    au.last_name,
    au.role,
    ua.is_active,
    ua.is_verified,
    ua.created_at
FROM app_auth.admin_users au
JOIN app_auth.user_accounts ua ON ua.id = au.account_id
WHERE ua.is_active = true
  AND ua.is_verified = true;

COMMENT ON VIEW api.users_public IS 'Public user profiles for API access';

-- User profile with stats
CREATE OR REPLACE VIEW api.user_profiles AS
SELECT
    au.id,
    au.username,
    ua.email,
    au.first_name,
    au.last_name,
    au.role,
    ua.is_active,
    ua.is_verified,
    ua.last_login,
    ua.created_at,
    ua.updated_at,
    COUNT(DISTINCT p.id) AS total_pages,
    COUNT(DISTINCT ci.id) AS assigned_inquiries
FROM app_auth.admin_users au
JOIN app_auth.user_accounts ua ON ua.id = au.account_id
LEFT JOIN content.pages p ON p.author_id = au.id
LEFT JOIN contact.contact_inquiries ci ON ci.assigned_to = au.id
GROUP BY au.id, au.username, ua.email, au.first_name, au.last_name, au.role,
         ua.is_active, ua.is_verified, ua.last_login, ua.created_at, ua.updated_at;

COMMENT ON VIEW api.user_profiles IS 'User profiles with statistics';

-- ============================================================================
-- CONTENT VIEWS
-- ============================================================================

-- Published content view
CREATE OR REPLACE VIEW api.content_published AS
SELECT
    p.id,
    p.slug,
    p.title,
    p.content,
    p.excerpt,
    p.featured_image,
    p.status,
    p.published_at,
    p.views_count,
    p.meta_title,
    p.meta_description,
    p.meta_keywords,
    c.id AS category_id,
    c.name AS category_name,
    c.slug AS category_slug,
    u.id AS author_id,
    u.username AS author_username,
    u.first_name AS author_first_name,
    u.last_name AS author_last_name,
    p.created_at,
    p.updated_at
FROM content.pages p
LEFT JOIN content.categories c ON p.category_id = c.id
LEFT JOIN app_auth.admin_users u ON p.author_id = u.id
WHERE p.status = 'published'
  AND p.published_at <= CURRENT_TIMESTAMP;

COMMENT ON VIEW api.content_published IS 'Published content for public API access';

-- Content categories with counts
CREATE OR REPLACE VIEW api.categories_with_counts AS
SELECT
    c.id,
    c.name,
    c.slug,
    c.description,
    c.parent_id,
    c.is_active,
    COUNT(DISTINCT p.id) AS page_count,
    c.created_at,
    c.updated_at
FROM content.categories c
LEFT JOIN content.pages p ON p.category_id = c.id AND p.status = 'published'
WHERE c.is_active = true
GROUP BY c.id;

COMMENT ON VIEW api.categories_with_counts IS 'Categories with page counts';

-- Media files view
CREATE OR REPLACE VIEW api.media_files AS
SELECT
    m.id,
    m.filename,
    m.original_filename,
    m.mime_type,
    m.file_size,
    m.file_path,
    m.file_url,
    m.alt_text,
    m.caption,
    m.is_public,
    u.username AS uploaded_by_username,
    m.created_at
FROM content.media_files m
LEFT JOIN app_auth.admin_users u ON m.uploaded_by = u.id
WHERE m.is_public = true;

COMMENT ON VIEW api.media_files IS 'Public media files';

-- ============================================================================
-- CONTACT VIEWS
-- ============================================================================

-- Public contact forms
CREATE OR REPLACE VIEW api.contact_forms_public AS
SELECT
    cf.id,
    cf.name,
    cf.slug,
    cf.description,
    cf.fields,
    cf.success_message,
    cf.is_active
FROM contact.contact_forms cf
WHERE cf.is_active = true;

COMMENT ON VIEW api.contact_forms_public IS 'Public contact forms for submissions';

-- Contact inquiries summary (admin view)
CREATE OR REPLACE VIEW api.contact_inquiries_summary AS
SELECT
    ci.id,
    ci.form_id,
    cf.name AS form_name,
    CONCAT(ci.first_name, ' ', ci.last_name) AS name,
    ci.email,
    ci.subject,
    ci.status,
    ci.priority,
    ci.assigned_to,
    u.username AS assigned_to_username,
    ci.created_at,
    ci.updated_at
FROM contact.contact_inquiries ci
LEFT JOIN contact.contact_forms cf ON ci.form_id = cf.id
LEFT JOIN app_auth.admin_users u ON ci.assigned_to = u.id;

COMMENT ON VIEW api.contact_inquiries_summary IS 'Contact inquiries summary for admin API';

-- ============================================================================
-- LAUNCH CAMPAIGN VIEWS
-- ============================================================================

-- Active launch campaigns
CREATE OR REPLACE VIEW api.launch_campaigns_active AS
SELECT
    lc.id,
    lc.name,
    lc.slug,
    lc.description,
    lc.campaign_type,
    lc.launch_date,
    lc.end_date,
    lc.status,
    lc.target_audience,
    lc.goals,
    lc.metadata,
    COUNT(DISTINCT lcs.subscriber_id) AS subscriber_count
FROM launch.launch_campaigns lc
LEFT JOIN launch.launch_campaign_subscribers lcs ON lcs.campaign_id = lc.id
WHERE lc.status = 'active'
  AND (lc.launch_date IS NULL OR lc.launch_date <= CURRENT_TIMESTAMP)
  AND (lc.end_date IS NULL OR lc.end_date >= CURRENT_TIMESTAMP)
GROUP BY lc.id;

COMMENT ON VIEW api.launch_campaigns_active IS 'Active launch campaigns for public API';

-- Launch subscriber stats
CREATE OR REPLACE VIEW api.launch_subscriber_stats AS
SELECT
    DATE(created_at) AS signup_date,
    COUNT(*) AS total_signups,
    COUNT(CASE WHEN verified_at IS NOT NULL THEN 1 END) AS verified_signups,
    COUNT(CASE WHEN source_campaign IS NOT NULL THEN 1 END) AS referred_signups
FROM launch.launch_subscribers
GROUP BY DATE(created_at)
ORDER BY signup_date DESC;

COMMENT ON VIEW api.launch_subscriber_stats IS 'Launch subscriber statistics by date';

-- ============================================================================
-- SYSTEM VIEWS
-- ============================================================================

-- System settings (public)
CREATE OR REPLACE VIEW api.system_settings_public AS
SELECT
    ss.setting_key AS key,
    ss.setting_value AS value,
    ss.description
FROM system.system_settings ss
WHERE ss.is_public = true;

COMMENT ON VIEW api.system_settings_public IS 'Public system settings';

-- Feature flags
CREATE OR REPLACE VIEW api.feature_flags_active AS
SELECT
    ff.flag_key AS key,
    ff.name,
    ff.description,
    ff.is_enabled
FROM system.feature_flags ff
WHERE ff.is_enabled = true;

COMMENT ON VIEW api.feature_flags_active IS 'Active feature flags';

-- Activity logs summary (admin view)
CREATE OR REPLACE VIEW api.activity_logs_summary AS
SELECT
    DATE(al.created_at) AS activity_date,
    al.action,
    al.entity_type,
    COUNT(*) AS action_count,
    COUNT(DISTINCT al.user_id) AS unique_users
FROM system.activity_logs al
GROUP BY DATE(al.created_at), al.action, al.entity_type
ORDER BY activity_date DESC, action_count DESC;

COMMENT ON VIEW api.activity_logs_summary IS 'Activity logs summary for analytics';

-- ============================================================================
-- DASHBOARD VIEWS
-- ============================================================================

-- Admin dashboard stats
CREATE OR REPLACE VIEW api.dashboard_stats AS
SELECT
    (SELECT COUNT(*) FROM app_auth.user_accounts WHERE is_active = true) AS total_users,
    (SELECT COUNT(*) FROM app_auth.user_accounts WHERE is_verified = true) AS verified_users,
    (SELECT COUNT(*) FROM content.pages WHERE status = 'published') AS published_pages,
    (SELECT COUNT(*) FROM content.pages WHERE status = 'draft') AS draft_pages,
    (SELECT COUNT(*) FROM contact.contact_inquiries WHERE status = 'new') AS new_inquiries,
    (SELECT COUNT(*) FROM contact.contact_inquiries WHERE status = 'in_progress') AS inquiries_in_progress,
    (SELECT COUNT(*) FROM launch.launch_subscribers WHERE verified_at IS NOT NULL) AS verified_subscribers,
    (SELECT COUNT(*) FROM launch.launch_campaign_subscribers lcs JOIN launch.launch_campaigns lc ON lc.id = lcs.campaign_id WHERE lc.status = 'active') AS total_campaign_subscribers,
    (SELECT COUNT(*) FROM content.media_files) AS total_media_files,
    (SELECT COUNT(*) FROM system.activity_logs WHERE created_at >= CURRENT_DATE) AS today_activities;

COMMENT ON VIEW api.dashboard_stats IS 'Dashboard statistics for admin panel';

-- Recent activities
CREATE OR REPLACE VIEW api.recent_activities AS
SELECT
    al.id,
    al.user_id,
    u.username,
    u.first_name,
    u.last_name,
    al.action,
    al.entity_type,
    al.entity_id,
    al.details,
    al.ip_address,
    al.created_at
FROM system.activity_logs al
LEFT JOIN app_auth.admin_users u ON al.user_id = u.id
ORDER BY al.created_at DESC
LIMIT 100;

COMMENT ON VIEW api.recent_activities IS 'Recent system activities';

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

-- Grant SELECT on all views to authenticated users
GRANT SELECT ON ALL TABLES IN SCHEMA api TO authenticated;

-- Grant SELECT on public views to anonymous users
GRANT SELECT ON api.users_public TO anon;
GRANT SELECT ON api.content_published TO anon;
GRANT SELECT ON api.categories_with_counts TO anon;
GRANT SELECT ON api.media_files TO anon;
GRANT SELECT ON api.contact_forms_public TO anon;
GRANT SELECT ON api.launch_campaigns_active TO anon;
GRANT SELECT ON api.system_settings_public TO anon;
GRANT SELECT ON api.feature_flags_active TO anon;
-- ============================================================================
-- ROW LEVEL SECURITY POLICIES MODULE
-- Implement RLS policies for all tables using new multi-persona auth model
-- ============================================================================

-- Enable RLS on key tables (idempotent guards)
ALTER TABLE IF EXISTS app_auth.user_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS app_auth.admin_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS app_auth.players ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS app_auth.guest_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS app_auth.sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS app_auth.refresh_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS app_auth.api_keys ENABLE ROW LEVEL SECURITY;

ALTER TABLE IF EXISTS content.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS content.pages ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS content.revisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS content.media_files ENABLE ROW LEVEL SECURITY;

ALTER TABLE IF EXISTS contact.contact_forms ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS contact.contact_inquiries ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS contact.contact_responses ENABLE ROW LEVEL SECURITY;

ALTER TABLE IF EXISTS launch.launch_campaigns ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS launch.launch_subscribers ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS launch.launch_waitlist ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS launch.launch_referrals ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS launch.notification_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS launch.notification_queue ENABLE ROW LEVEL SECURITY;

ALTER TABLE IF EXISTS system.system_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS system.activity_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS system.system_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS system.feature_flags ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- AUTH SCHEMA POLICIES
-- ============================================================================

-- user_accounts: user can read/update their own account; admins and service role have full access
DROP POLICY IF EXISTS user_accounts_self_read ON app_auth.user_accounts;
CREATE POLICY user_accounts_self_read ON app_auth.user_accounts
    FOR SELECT
    TO authenticated
    USING (id = auth.uid());

DROP POLICY IF EXISTS user_accounts_self_update ON app_auth.user_accounts;
CREATE POLICY user_accounts_self_update ON app_auth.user_accounts
    FOR UPDATE
    TO authenticated
    USING (id = auth.uid())
    WITH CHECK (id = auth.uid() AND user_type <> 'guest');

DROP POLICY IF EXISTS user_accounts_admin_manage ON app_auth.user_accounts;
CREATE POLICY user_accounts_admin_manage ON app_auth.user_accounts
    FOR ALL
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('admin', 'super_admin')
    )
    WITH CHECK (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('admin', 'super_admin')
    );

DROP POLICY IF EXISTS user_accounts_service_full ON app_auth.user_accounts;
CREATE POLICY user_accounts_service_full ON app_auth.user_accounts
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- admin_users: admins can see/manage their own profile, super admins/admins can manage everyone
DROP POLICY IF EXISTS admin_users_self_read ON app_auth.admin_users;
CREATE POLICY admin_users_self_read ON app_auth.admin_users
    FOR SELECT
    TO authenticated
    USING (account_id = auth.uid());

DROP POLICY IF EXISTS admin_users_self_update ON app_auth.admin_users;
CREATE POLICY admin_users_self_update ON app_auth.admin_users
    FOR UPDATE
    TO authenticated
    USING (account_id = auth.uid())
    WITH CHECK (account_id = auth.uid());

DROP POLICY IF EXISTS admin_users_admin_manage ON app_auth.admin_users;
CREATE POLICY admin_users_admin_manage ON app_auth.admin_users
    FOR ALL
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('admin', 'super_admin')
    )
    WITH CHECK (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('admin', 'super_admin')
    );

DROP POLICY IF EXISTS admin_users_service_full ON app_auth.admin_users;
CREATE POLICY admin_users_service_full ON app_auth.admin_users
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- players: players can see/update their own record; service role full access
DROP POLICY IF EXISTS players_self_read ON app_auth.players;
CREATE POLICY players_self_read ON app_auth.players
    FOR SELECT
    TO authenticated
    USING (account_id = auth.uid());

DROP POLICY IF EXISTS players_self_update ON app_auth.players;
CREATE POLICY players_self_update ON app_auth.players
    FOR UPDATE
    TO authenticated
    USING (account_id = auth.uid())
    WITH CHECK (account_id = auth.uid());

DROP POLICY IF EXISTS players_admin_manage ON app_auth.players;
CREATE POLICY players_admin_manage ON app_auth.players
    FOR ALL
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('admin', 'super_admin', 'manager', 'coach')
    )
    WITH CHECK (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('admin', 'super_admin', 'manager', 'coach')
    );

DROP POLICY IF EXISTS players_service_full ON app_auth.players;
CREATE POLICY players_service_full ON app_auth.players
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- guest_users: guests can read their own record, but cannot modify; admins/service manage
DROP POLICY IF EXISTS guest_users_self_read ON app_auth.guest_users;
CREATE POLICY guest_users_self_read ON app_auth.guest_users
    FOR SELECT
    TO authenticated
    USING (account_id = auth.uid());

DROP POLICY IF EXISTS guest_users_admin_manage ON app_auth.guest_users;
CREATE POLICY guest_users_admin_manage ON app_auth.guest_users
    FOR ALL
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('admin', 'super_admin', 'manager')
    )
    WITH CHECK (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('admin', 'super_admin', 'manager')
    );

DROP POLICY IF EXISTS guest_users_service_full ON app_auth.guest_users;
CREATE POLICY guest_users_service_full ON app_auth.guest_users
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- sessions: account owners can view/delete their sessions; service role full access
DROP POLICY IF EXISTS sessions_own_read ON app_auth.sessions;
CREATE POLICY sessions_own_read ON app_auth.sessions
    FOR SELECT
    TO authenticated
    USING (account_id = auth.uid());

DROP POLICY IF EXISTS sessions_own_delete ON app_auth.sessions;
CREATE POLICY sessions_own_delete ON app_auth.sessions
    FOR DELETE
    TO authenticated
    USING (account_id = auth.uid());

DROP POLICY IF EXISTS sessions_service_all ON app_auth.sessions;
CREATE POLICY sessions_service_all ON app_auth.sessions
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- refresh tokens
DROP POLICY IF EXISTS refresh_tokens_own ON app_auth.refresh_tokens;
CREATE POLICY refresh_tokens_own ON app_auth.refresh_tokens
    FOR ALL
    TO authenticated
    USING (account_id = auth.uid());

DROP POLICY IF EXISTS refresh_tokens_service ON app_auth.refresh_tokens;
CREATE POLICY refresh_tokens_service ON app_auth.refresh_tokens
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- API keys restricted to admins
DROP POLICY IF EXISTS api_keys_admin_read ON app_auth.api_keys;
CREATE POLICY api_keys_admin_read ON app_auth.api_keys
    FOR SELECT
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND account_id = auth.uid()
    );

DROP POLICY IF EXISTS api_keys_admin_all ON app_auth.api_keys;
CREATE POLICY api_keys_admin_all ON app_auth.api_keys
    FOR ALL
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('admin', 'super_admin')
    )
    WITH CHECK (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('admin', 'super_admin')
    );

DROP POLICY IF EXISTS api_keys_service_all ON app_auth.api_keys;
CREATE POLICY api_keys_service_all ON app_auth.api_keys
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- ============================================================================
-- CONTENT POLICIES (admin-only management)
-- ============================================================================

-- Helper predicate usage: JWT must carry user_type/admin_role claims
DROP POLICY IF EXISTS categories_public_read ON content.categories;
CREATE POLICY categories_public_read ON content.categories
    FOR SELECT
    TO anon, authenticated
    USING (is_active = true);

DROP POLICY IF EXISTS categories_editor_insert ON content.categories;
CREATE POLICY categories_editor_insert ON content.categories
    FOR INSERT
    TO authenticated
    WITH CHECK (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('editor', 'admin', 'super_admin')
    );

DROP POLICY IF EXISTS categories_editor_update ON content.categories;
CREATE POLICY categories_editor_update ON content.categories
    FOR UPDATE
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('editor', 'admin', 'super_admin')
    )
    WITH CHECK (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('editor', 'admin', 'super_admin')
    );

DROP POLICY IF EXISTS categories_admin_delete ON content.categories;
CREATE POLICY categories_admin_delete ON content.categories
    FOR DELETE
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('admin', 'super_admin')
    );

-- Pages policies
DROP POLICY IF EXISTS pages_published_read ON content.pages;
CREATE POLICY pages_published_read ON content.pages
    FOR SELECT
    TO anon, authenticated
    USING (status = 'published' AND published_at <= CURRENT_TIMESTAMP);

DROP POLICY IF EXISTS pages_own_drafts_read ON content.pages;
CREATE POLICY pages_own_drafts_read ON content.pages
    FOR SELECT
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND author_id = auth.uid()
        AND status = 'draft'
    );

DROP POLICY IF EXISTS pages_editor_read ON content.pages;
CREATE POLICY pages_editor_read ON content.pages
    FOR SELECT
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('editor', 'admin', 'super_admin')
    );

DROP POLICY IF EXISTS pages_author_insert ON content.pages;
CREATE POLICY pages_author_insert ON content.pages
    FOR INSERT
    TO authenticated
    WITH CHECK (
        auth.jwt() ->> 'user_type' = 'admin'
        AND (
            author_id = auth.uid()
            AND (
                status = 'draft'
                OR auth.jwt() ->> 'admin_role' IN ('editor', 'admin', 'super_admin')
            )
        )
    );

DROP POLICY IF EXISTS pages_author_update ON content.pages;
CREATE POLICY pages_author_update ON content.pages
    FOR UPDATE
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND (author_id = auth.uid() OR auth.jwt() ->> 'admin_role' IN ('editor', 'admin', 'super_admin'))
    )
    WITH CHECK (
        auth.jwt() ->> 'user_type' = 'admin'
        AND (author_id = auth.uid() OR auth.jwt() ->> 'admin_role' IN ('editor', 'admin', 'super_admin'))
    );

DROP POLICY IF EXISTS pages_editor_delete ON content.pages;
CREATE POLICY pages_editor_delete ON content.pages
    FOR DELETE
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('editor', 'admin', 'super_admin')
    );

-- Page revisions
DROP POLICY IF EXISTS revisions_page_author_read ON content.revisions;
CREATE POLICY revisions_page_author_read ON content.revisions
    FOR SELECT
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND EXISTS (
            SELECT 1 FROM content.pages p
            WHERE p.id = page_id
              AND (p.author_id = auth.uid() OR auth.jwt() ->> 'admin_role' IN ('editor', 'admin', 'super_admin'))
        )
    );

DROP POLICY IF EXISTS revisions_insert ON content.revisions;
CREATE POLICY revisions_insert ON content.revisions
    FOR INSERT
    TO authenticated
    WITH CHECK (
        auth.jwt() ->> 'user_type' = 'admin'
        AND EXISTS (
            SELECT 1 FROM content.pages p
            WHERE p.id = page_id
              AND (p.author_id = auth.uid() OR auth.jwt() ->> 'admin_role' IN ('editor', 'admin', 'super_admin'))
        )
    );

-- Media files
DROP POLICY IF EXISTS media_public_read ON content.media_files;
CREATE POLICY media_public_read ON content.media_files
    FOR SELECT
    TO anon, authenticated
    USING (is_public = true);

DROP POLICY IF EXISTS media_own_read ON content.media_files;
CREATE POLICY media_own_read ON content.media_files
    FOR SELECT
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND uploaded_by = auth.uid()
    );

DROP POLICY IF EXISTS media_own_insert ON content.media_files;
CREATE POLICY media_own_insert ON content.media_files
    FOR INSERT
    TO authenticated
    WITH CHECK (
        auth.jwt() ->> 'user_type' = 'admin'
        AND uploaded_by = auth.uid()
    );

DROP POLICY IF EXISTS media_own_update ON content.media_files;
CREATE POLICY media_own_update ON content.media_files
    FOR UPDATE
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND uploaded_by = auth.uid()
    )
    WITH CHECK (
        auth.jwt() ->> 'user_type' = 'admin'
        AND uploaded_by = auth.uid()
    );

DROP POLICY IF EXISTS media_editor_delete ON content.media_files;
CREATE POLICY media_editor_delete ON content.media_files
    FOR DELETE
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('editor', 'admin', 'super_admin')
    );

-- ============================================================================
-- CONTACT POLICIES
-- ============================================================================

DROP POLICY IF EXISTS inquiries_insert_anon ON contact.contact_inquiries;
CREATE POLICY inquiries_insert_anon ON contact.contact_inquiries
    FOR INSERT
    TO anon, authenticated
    WITH CHECK (true);

DROP POLICY IF EXISTS inquiries_view_admin ON contact.contact_inquiries;
CREATE POLICY inquiries_view_admin ON contact.contact_inquiries
    FOR SELECT
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('manager', 'admin', 'super_admin', 'coach', 'editor')
    );

DROP POLICY IF EXISTS inquiries_self_view ON contact.contact_inquiries;
CREATE POLICY inquiries_self_view ON contact.contact_inquiries
    FOR SELECT
    TO authenticated
    USING (
        (email = auth.jwt() ->> 'email')
        OR (
            auth.jwt() ->> 'user_type' = 'admin'
            AND assigned_to = auth.uid()
        )
    );

DROP POLICY IF EXISTS inquiries_admin_update ON contact.contact_inquiries;
CREATE POLICY inquiries_admin_update ON contact.contact_inquiries
    FOR UPDATE
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('manager', 'admin', 'super_admin', 'coach')
    )
    WITH CHECK (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('manager', 'admin', 'super_admin', 'coach')
    );

DROP POLICY IF EXISTS responses_admin_manage ON contact.contact_responses;
CREATE POLICY responses_admin_manage ON contact.contact_responses
    FOR ALL
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('manager', 'admin', 'super_admin', 'coach', 'editor')
    )
    WITH CHECK (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('manager', 'admin', 'super_admin', 'coach', 'editor')
    );

-- ============================================================================
-- LAUNCH / SYSTEM POLICIES
-- ============================================================================

-- For brevity, allow admins (manager+) and service role full access
DROP POLICY IF EXISTS launch_admin_all ON launch.launch_campaigns;
CREATE POLICY launch_admin_all ON launch.launch_campaigns
    FOR ALL
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('manager', 'admin', 'super_admin', 'coach', 'editor')
    )
    WITH CHECK (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('manager', 'admin', 'super_admin', 'coach', 'editor')
    );

DROP POLICY IF EXISTS launch_service_all ON launch.launch_campaigns;
CREATE POLICY launch_service_all ON launch.launch_campaigns
    FOR ALL TO service_role USING (true) WITH CHECK (true);

-- Subscribers can self-manage entries via email match
DROP POLICY IF EXISTS launch_subscribers_self_manage ON launch.launch_subscribers;
CREATE POLICY launch_subscribers_self_manage ON launch.launch_subscribers
    FOR SELECT
    TO authenticated
    USING (email = auth.jwt() ->> 'email');

DROP POLICY IF EXISTS launch_subscribers_insert_public ON launch.launch_subscribers;
CREATE POLICY launch_subscribers_insert_public ON launch.launch_subscribers
    FOR INSERT
    TO anon, authenticated
    WITH CHECK (true);

DROP POLICY IF EXISTS launch_subscribers_admin_manage ON launch.launch_subscribers;
CREATE POLICY launch_subscribers_admin_manage ON launch.launch_subscribers
    FOR ALL
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('manager', 'admin', 'super_admin', 'coach', 'editor')
    )
    WITH CHECK (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('manager', 'admin', 'super_admin', 'coach', 'editor')
    );

-- System schema: only admin (admin role) and service role
DROP POLICY IF EXISTS system_settings_public_read ON system.system_settings;
CREATE POLICY system_settings_public_read ON system.system_settings
    FOR SELECT
    TO anon, authenticated
    USING (is_public = true);

DROP POLICY IF EXISTS system_settings_admin_all ON system.system_settings;
CREATE POLICY system_settings_admin_all ON system.system_settings
    FOR ALL
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('admin', 'super_admin')
    )
    WITH CHECK (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('admin', 'super_admin')
    );

DROP POLICY IF EXISTS system_settings_service_all ON system.system_settings;
CREATE POLICY system_settings_service_all ON system.system_settings
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- Activity logs (read-only for admins; service full)
DROP POLICY IF EXISTS activity_logs_admin_read ON system.activity_logs;
CREATE POLICY activity_logs_admin_read ON system.activity_logs
    FOR SELECT
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('manager', 'admin', 'super_admin')
    );

DROP POLICY IF EXISTS activity_logs_service_all ON system.activity_logs;
CREATE POLICY activity_logs_service_all ON system.activity_logs
    FOR ALL TO service_role USING (true) WITH CHECK (true);

-- Jobs / feature flags reserved for admins & service
DROP POLICY IF EXISTS system_jobs_admin_manage ON system.system_jobs;
CREATE POLICY system_jobs_admin_manage ON system.system_jobs
    FOR ALL
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('admin', 'super_admin')
    )
    WITH CHECK (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('admin', 'super_admin')
    );

DROP POLICY IF EXISTS system_jobs_service_all ON system.system_jobs;
CREATE POLICY system_jobs_service_all ON system.system_jobs
    FOR ALL TO service_role USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS feature_flags_admin_manage ON system.feature_flags;
CREATE POLICY feature_flags_admin_manage ON system.feature_flags
    FOR ALL
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('admin', 'super_admin')
    )
    WITH CHECK (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('admin', 'super_admin')
    );

DROP POLICY IF EXISTS feature_flags_service_all ON system.feature_flags;
CREATE POLICY feature_flags_service_all ON system.feature_flags
    FOR ALL TO service_role USING (true) WITH CHECK (true);

-- ============================================================================
-- NOTES
-- ============================================================================
-- Policies assume JWT claims include:
--   user_type  -> 'admin' | 'player' | 'guest'
--   admin_role -> enum value for admin personas when user_type = 'admin'
--   email      -> primary email address for the account
-- Adjust application auth middleware to populate these claims accordingly.
-- ============================================================================
-- API FUNCTIONS MODULE
-- Create database functions for API operations
-- ============================================================================

SET search_path TO api, auth, content, contact, launch, system, public;

-- ============================================================================
-- AUTHENTICATION FUNCTIONS
-- ============================================================================

-- Track failed login attempt (returns true if account is now locked)
CREATE OR REPLACE FUNCTION api.track_failed_login(p_identifier TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_account RECORD;
    v_failed_attempts INT;
    v_locked_until TIMESTAMP WITH TIME ZONE;
BEGIN
    -- Locate account by email or admin username
    SELECT ua.*, au.username AS admin_username
    INTO v_account
    FROM app_auth.user_accounts ua
    LEFT JOIN app_auth.admin_users au ON au.account_id = ua.id
    WHERE ua.email = lower(p_identifier)
       OR (au.username = lower(p_identifier))
    LIMIT 1;

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'User not found');
    END IF;

    UPDATE app_auth.user_accounts
    SET failed_login_attempts = failed_login_attempts + 1,
        locked_until = CASE
            WHEN failed_login_attempts >= 4 THEN CURRENT_TIMESTAMP + INTERVAL '15 minutes'
            ELSE locked_until
        END
    WHERE id = v_account.id
    RETURNING failed_login_attempts, locked_until
    INTO v_failed_attempts, v_locked_until;

    RETURN json_build_object(
        'success', true,
        'failed_attempts', v_failed_attempts,
        'is_locked', v_locked_until IS NOT NULL AND v_locked_until > CURRENT_TIMESTAMP,
        'locked_until', v_locked_until
    );
END;
$$;

-- Login function that returns JSON instead of raising exceptions
CREATE OR REPLACE FUNCTION api.login_safe(
    email TEXT,
    password TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_account app_auth.user_accounts%ROWTYPE;
    v_admin app_auth.admin_users%ROWTYPE;
    v_player app_auth.players%ROWTYPE;
    v_guest app_auth.guest_users%ROWTYPE;
    v_user_profile JSONB;
    v_session_id UUID;
    v_token VARCHAR(255);
    v_refresh_token VARCHAR(255);
    v_session_ttl INTERVAL := INTERVAL '24 hours';
    v_refresh_ttl INTERVAL := INTERVAL '7 days';
    v_input_email TEXT := email;
    v_input_password TEXT := password;
BEGIN
    -- Find account by email or admin username
    SELECT ua.*
    INTO v_account
    FROM app_auth.user_accounts ua
    LEFT JOIN app_auth.admin_users au ON au.account_id = ua.id
    WHERE ua.email = lower(v_input_email)
       OR (au.username = lower(v_input_email))
    ORDER BY ua.created_at DESC
    LIMIT 1;

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Account does not exist');
    END IF;

    -- Check if player is trying to access admin platform
    IF v_account.user_type = 'player' THEN
        RETURN json_build_object('success', false, 'error', 'Players cannot access the admin platform');
    END IF;

    -- Check if guest is trying to access admin platform
    IF v_account.user_type = 'guest' THEN
        RETURN json_build_object('success', false, 'error', 'Guest accounts cannot access the admin platform');
    END IF;

    -- Load persona profile details
    IF v_account.user_type = 'admin' THEN
        SELECT * INTO v_admin
        FROM app_auth.admin_users
        WHERE account_id = v_account.id;

        IF v_admin IS NULL THEN
            RETURN json_build_object('success', false, 'error', 'Admin profile not found');
        END IF;

        v_user_profile := jsonb_build_object(
            'id', v_admin.id,
            'username', v_admin.username,
            'first_name', v_admin.first_name,
            'last_name', v_admin.last_name,
            'role', v_admin.role
        );
    END IF;

    -- Check if account is locked
    IF v_account.locked_until IS NOT NULL AND v_account.locked_until > CURRENT_TIMESTAMP THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Account is locked. Please try again later.',
            'locked_until', v_account.locked_until
        );
    END IF;

    -- Verify password
    IF NOT verify_password(v_input_password, v_account.password_hash) THEN
        PERFORM api.track_failed_login(v_input_email);
        RETURN json_build_object('success', false, 'error', 'Invalid credentials');
    END IF;

    -- Check if account is active
    IF NOT v_account.is_active THEN
        RETURN json_build_object('success', false, 'error', 'Account is inactive');
    END IF;

    -- Check if account is verified (admin accounts must be verified)
    IF NOT v_account.is_verified THEN
        RETURN json_build_object('success', false, 'error', 'Please verify your email address');
    END IF;

    -- Generate tokens
    v_token := encode(public.gen_random_bytes(32), 'hex');
    v_refresh_token := encode(public.gen_random_bytes(32), 'hex');

    -- Create session
    INSERT INTO app_auth.sessions (
        account_id,
        user_type,
        token_hash,
        expires_at
    ) VALUES (
        v_account.id,
        v_account.user_type,
        encode(public.digest(v_token, 'sha256'), 'hex'),
        CURRENT_TIMESTAMP + v_session_ttl
    ) RETURNING id INTO v_session_id;

    -- Create refresh token
    INSERT INTO app_auth.refresh_tokens (
        account_id,
        user_type,
        token_hash,
        expires_at
    ) VALUES (
        v_account.id,
        v_account.user_type,
        encode(public.digest(v_refresh_token, 'sha256'), 'hex'),
        CURRENT_TIMESTAMP + v_refresh_ttl
    );

    -- Update account metadata
    UPDATE app_auth.user_accounts
    SET last_login = CURRENT_TIMESTAMP,
        failed_login_attempts = 0,
        locked_until = NULL
    WHERE id = v_account.id;

    -- Log activity for admins only (activity_logs FK is admin-scoped)
    IF v_account.user_type = 'admin' AND v_admin IS NOT NULL THEN
        INSERT INTO system.activity_logs (
            user_id,
            action,
            entity_type,
            entity_id,
            details
        ) VALUES (
            v_admin.id,
            'user_login',
            'session',
            v_session_id,
            jsonb_build_object('method', 'password')
        );
    END IF;

    RETURN json_build_object(
        'success', true,
        'user', jsonb_build_object(
            'account_id', v_account.id,
            'user_type', v_account.user_type,
            'email', v_account.email,
            'profile', v_user_profile
        ),
        'session_token', v_token,
        'refresh_token', v_refresh_token,
        'expires_at', (CURRENT_TIMESTAMP + v_session_ttl)
    );
END;
$$;

-- Register new admin user (invite-only)
CREATE OR REPLACE FUNCTION api.register_user(
    p_email TEXT,
    p_username TEXT,
    p_password TEXT,
    p_first_name TEXT,
    p_last_name TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_account_id UUID;
    v_verification_token VARCHAR(255);
    v_password_hash VARCHAR(255);
BEGIN
    IF EXISTS (SELECT 1 FROM app_auth.user_accounts WHERE email = lower(p_email)) THEN
        RAISE EXCEPTION 'Email already registered';
    END IF;

    IF EXISTS (
        SELECT 1 FROM app_auth.admin_users WHERE username = lower(p_username)
    ) THEN
        RAISE EXCEPTION 'Username already taken';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM app_auth.allowed_emails
        WHERE email = lower(p_email)
          AND is_active = true
    ) THEN
        RAISE EXCEPTION 'Email is not authorized for admin signup';
    END IF;

    v_password_hash := hash_password(p_password);
    -- Players are auto-verified for now; keep token nullable for future email verification rollout
    v_verification_token := NULL;

    INSERT INTO app_auth.user_accounts (
        email,
        password_hash,
        user_type,
        is_active,
        is_verified,
        verification_token
    ) VALUES (
        lower(p_email),
        v_password_hash,
        'admin',
        true,
        false,
        v_verification_token
    ) RETURNING id INTO v_account_id;

    INSERT INTO app_auth.admin_users (
        id,
        account_id,
        username,
        first_name,
        last_name,
        role
    ) VALUES (
        v_account_id,
        v_account_id,
        lower(p_username),
        p_first_name,
        p_last_name,
        'viewer'
    );

    UPDATE app_auth.allowed_emails
    SET used_at = CURRENT_TIMESTAMP,
        used_by = v_account_id
    WHERE email = lower(p_email);

RETURN json_build_object(
        'success', true,
        'user_id', v_account_id,
        'verification_token', v_verification_token,
        'message', 'Registration successful. Please verify your email.'
    );
END;
$$;

-- Player signup (public)
CREATE OR REPLACE FUNCTION api.player_signup(
    p_email TEXT,
    p_password TEXT,
    p_first_name TEXT,
    p_last_name TEXT,
    p_display_name TEXT DEFAULT NULL,
    p_phone TEXT DEFAULT NULL,
    p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_account_id UUID;
    v_password_hash TEXT;
    v_verification_token TEXT;
BEGIN
    IF p_email IS NULL OR position('@' IN p_email) = 0 THEN
        RAISE EXCEPTION 'Invalid email address';
    END IF;

    IF EXISTS (SELECT 1 FROM app_auth.user_accounts WHERE email = lower(p_email)) THEN
        RAISE EXCEPTION 'Email already registered';
    END IF;

    v_password_hash := hash_password(p_password);
    v_verification_token := NULL;

    INSERT INTO app_auth.user_accounts (
        email,
        password_hash,
        user_type,
        is_active,
        is_verified,
        verification_token,
        metadata
    ) VALUES (
        lower(p_email),
        v_password_hash,
        'player',
        true,
        true,
        v_verification_token,
        COALESCE(p_metadata, '{}'::jsonb)
    ) RETURNING id INTO v_account_id;

    INSERT INTO app_auth.players (
        id,
        account_id,
        first_name,
        last_name,
        display_name,
        phone
    ) VALUES (
        v_account_id,
        v_account_id,
        p_first_name,
        p_last_name,
        COALESCE(p_display_name, CONCAT_WS(' ', p_first_name, p_last_name)),
        p_phone
    );

    RETURN json_build_object(
        'success', true,
        'user_id', v_account_id,
        'user_type', 'player',
        'verification_token', v_verification_token,
        'message', 'Registration successful. Please verify your email.'
    );
END;
$$;

-- Guest check-in / lightweight signup
CREATE OR REPLACE FUNCTION api.guest_check_in(
    p_display_name TEXT,
    p_email TEXT DEFAULT NULL,
    p_phone TEXT DEFAULT NULL,
    p_metadata JSONB DEFAULT '{}'::jsonb,
    p_invited_by UUID DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_account RECORD;
    v_guest RECORD;
    v_account_id UUID;
    v_password_hash TEXT;
    v_session_token TEXT;
    v_refresh_token TEXT;
    v_session_ttl INTERVAL := INTERVAL '6 hours';
    v_refresh_ttl INTERVAL := INTERVAL '12 hours';
    v_expiration TIMESTAMPTZ := CURRENT_TIMESTAMP + INTERVAL '48 hours';
    v_admin_user_id UUID;
BEGIN
    IF COALESCE(TRIM(p_display_name), '') = '' THEN
        RAISE EXCEPTION 'Display name is required';
    END IF;

    -- Attempt to reuse existing guest account by email
    IF p_email IS NOT NULL THEN
        SELECT ua.*
        INTO v_account
        FROM app_auth.user_accounts ua
        JOIN app_auth.guest_users gu ON gu.account_id = ua.id
        WHERE ua.email = lower(p_email)
          AND ua.user_type = 'guest'
        LIMIT 1;

        IF FOUND THEN
            SELECT gu.*
            INTO v_guest
            FROM app_auth.guest_users gu
            WHERE gu.account_id = v_account.id;
        END IF;
    END IF;

    IF FOUND THEN
        -- Ensure guest is still valid
        IF v_account.temporary_expires_at IS NULL OR v_guest.expires_at < CURRENT_TIMESTAMP THEN
            -- Treat as expired, force creation of a new account
            v_account := NULL;
        ELSE
            v_account_id := v_account.id;
            UPDATE app_auth.user_accounts
            SET temporary_expires_at = v_expiration,
                metadata = COALESCE(p_metadata, '{}'::jsonb)
            WHERE id = v_account_id;

            UPDATE app_auth.guest_users
            SET display_name = p_display_name,
                email = COALESCE(lower(p_email), email),
                phone = COALESCE(p_phone, phone),
                metadata = COALESCE(p_metadata, metadata),
                expires_at = v_expiration
            WHERE account_id = v_account_id
            RETURNING * INTO v_guest;
        END IF;
    END IF;

    IF v_account_id IS NULL THEN
        v_password_hash := hash_password(encode(public.gen_random_bytes(32), 'hex'));

        INSERT INTO app_auth.user_accounts (
            email,
            password_hash,
            user_type,
            is_active,
            is_verified,
            temporary_expires_at,
            metadata
        ) VALUES (
            CASE WHEN p_email IS NOT NULL THEN lower(p_email) ELSE NULL END,
            v_password_hash,
            'guest',
            true,
            false,
            v_expiration,
            COALESCE(p_metadata, '{}'::jsonb)
        ) RETURNING id INTO v_account_id;

        IF p_invited_by IS NOT NULL THEN
            SELECT id INTO v_admin_user_id
            FROM app_auth.admin_users
            WHERE id = p_invited_by OR account_id = p_invited_by;
        END IF;

        INSERT INTO app_auth.guest_users (
            id,
            account_id,
            display_name,
            email,
            phone,
            invited_by_admin,
            expires_at,
            metadata
        ) VALUES (
            v_account_id,
            v_account_id,
            p_display_name,
            CASE WHEN p_email IS NOT NULL THEN lower(p_email) ELSE NULL END,
            p_phone,
            v_admin_user_id,
            v_expiration,
            COALESCE(p_metadata, '{}'::jsonb)
        ) RETURNING * INTO v_guest;
    END IF;

    -- Generate session + refresh tokens for guest access
    v_session_token := encode(public.gen_random_bytes(32), 'hex');
    v_refresh_token := encode(public.gen_random_bytes(32), 'hex');

    INSERT INTO app_auth.sessions (
        account_id,
        user_type,
        token_hash,
        expires_at
    ) VALUES (
        v_account_id,
        'guest',
        encode(public.digest(v_session_token, 'sha256'), 'hex'),
        CURRENT_TIMESTAMP + v_session_ttl
    );

    INSERT INTO app_auth.refresh_tokens (
        account_id,
        user_type,
        token_hash,
        expires_at
    ) VALUES (
        v_account_id,
        'guest',
        encode(public.digest(v_refresh_token, 'sha256'), 'hex'),
        CURRENT_TIMESTAMP + v_refresh_ttl
    );

    UPDATE app_auth.user_accounts
    SET last_login = CURRENT_TIMESTAMP,
        temporary_expires_at = v_expiration
    WHERE id = v_account_id;

    RETURN json_build_object(
        'success', true,
        'user_id', v_account_id,
        'user_type', 'guest',
        'guest', jsonb_build_object(
            'display_name', v_guest.display_name,
            'email', v_guest.email,
            'expires_at', v_guest.expires_at
        ),
        'session_token', v_session_token,
        'refresh_token', v_refresh_token,
        'expires_at', (CURRENT_TIMESTAMP + v_session_ttl)
    );
END;
$$;

-- Login user
CREATE OR REPLACE FUNCTION api.login(
    email TEXT,
    password TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSON;
    v_success BOOLEAN;
    v_error TEXT;
BEGIN
    v_result := api.login_safe(email, password);
    v_success := COALESCE((v_result ->> 'success')::BOOLEAN, false);

    IF NOT v_success THEN
        v_error := COALESCE(v_result ->> 'error', 'Invalid credentials');
        RAISE EXCEPTION '%', v_error;
    END IF;

    RETURN v_result;
END;
$$;

-- Validate session token
CREATE OR REPLACE FUNCTION api.validate_session(
    p_session_token TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_session RECORD;
    v_account RECORD;
    v_admin RECORD;
BEGIN
    -- Find session by token
    SELECT s.*, ua.*, au.*
    INTO v_session
    FROM app_auth.sessions s
    JOIN app_auth.user_accounts ua ON ua.id = s.account_id
    LEFT JOIN app_auth.admin_users au ON au.account_id = ua.id
    WHERE s.token_hash = encode(public.digest(p_session_token, 'sha256'), 'hex')
      AND s.expires_at > CURRENT_TIMESTAMP;

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Invalid or expired session');
    END IF;

    -- Only allow admin accounts
    IF v_session.user_type != 'admin' THEN
        RETURN json_build_object('success', false, 'error', 'Access denied');
    END IF;

    -- Get admin profile
    SELECT * INTO v_admin
    FROM app_auth.admin_users
    WHERE account_id = v_session.account_id;

    IF v_admin IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'Admin profile not found');
    END IF;

    RETURN json_build_object(
        'success', true,
        'user', jsonb_build_object(
            'account_id', v_session.account_id,
            'user_type', v_session.user_type,
            'email', (SELECT email FROM app_auth.user_accounts WHERE id = v_session.account_id),
            'profile', jsonb_build_object(
                'id', v_admin.id,
                'username', v_admin.username,
                'first_name', v_admin.first_name,
                'last_name', v_admin.last_name,
                'role', v_admin.role
            )
        )
    );
END;
$$;

-- Logout user
CREATE OR REPLACE FUNCTION api.logout(
    p_session_token TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_session_id UUID;
    v_account_id UUID;
    v_user_type app_auth.user_type;
    v_admin_user_id UUID;
BEGIN
    -- Find and delete session
    DELETE FROM app_auth.sessions
    WHERE token_hash = encode(public.digest(p_session_token, 'sha256'), 'hex')
    RETURNING id, account_id, user_type
    INTO v_session_id, v_account_id, v_user_type;

    IF v_session_id IS NULL THEN
        RAISE EXCEPTION 'Invalid session';
    END IF;

    -- Log activity for admin personas only
    IF v_user_type = 'admin' THEN
        SELECT id INTO v_admin_user_id
        FROM app_auth.admin_users
        WHERE account_id = v_account_id;

        IF v_admin_user_id IS NOT NULL THEN
            INSERT INTO system.activity_logs (
                user_id,
                action,
                entity_type,
                entity_id
            ) VALUES (
                v_admin_user_id,
                'user_logout',
                'session',
                v_session_id
            );
        END IF;
    END IF;

    RETURN json_build_object(
        'success', true,
        'message', 'Logged out successfully'
    );
END;
$$;

-- Refresh access token
CREATE OR REPLACE FUNCTION api.refresh_token(
    p_refresh_token TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_account_id UUID;
    v_user_type app_auth.user_type;
    v_account RECORD;
    v_guest RECORD;
    v_new_token VARCHAR(255);
    v_new_refresh_token VARCHAR(255);
    v_session_ttl INTERVAL := INTERVAL '24 hours';
    v_refresh_ttl INTERVAL := INTERVAL '7 days';
    v_admin_user_id UUID;
BEGIN
    -- Verify refresh token and retrieve account context
    SELECT account_id, user_type
    INTO v_account_id, v_user_type
    FROM app_auth.refresh_tokens
    WHERE token_hash = encode(public.digest(p_refresh_token, 'sha256'), 'hex')
        AND expires_at > CURRENT_TIMESTAMP
        AND revoked_at IS NULL;

    IF v_account_id IS NULL THEN
        RAISE EXCEPTION 'Invalid refresh token';
    END IF;

    SELECT * INTO v_account
    FROM app_auth.user_accounts
    WHERE id = v_account_id;

    IF v_account IS NULL OR NOT v_account.is_active THEN
        RAISE EXCEPTION 'Account is inactive';
    END IF;

    IF v_account.user_type <> 'guest' AND NOT v_account.is_verified THEN
        RAISE EXCEPTION 'Please verify your email address';
    END IF;

    IF v_account.user_type = 'guest' THEN
        SELECT * INTO v_guest
        FROM app_auth.guest_users
        WHERE account_id = v_account_id;

        IF v_account.temporary_expires_at IS NULL
            OR v_account.temporary_expires_at < CURRENT_TIMESTAMP
            OR v_guest.expires_at < CURRENT_TIMESTAMP THEN
            RAISE EXCEPTION 'Guest access has expired';
        END IF;

        v_session_ttl := INTERVAL '6 hours';
        v_refresh_ttl := INTERVAL '12 hours';
    END IF;

    -- Revoke old refresh token
    UPDATE app_auth.refresh_tokens
    SET revoked_at = CURRENT_TIMESTAMP
    WHERE token_hash = encode(public.digest(p_refresh_token, 'sha256'), 'hex');

    -- Generate new tokens
    v_new_token := encode(public.gen_random_bytes(32), 'hex');
    v_new_refresh_token := encode(public.gen_random_bytes(32), 'hex');

    -- Create new session
    INSERT INTO app_auth.sessions (
        account_id,
        user_type,
        token_hash,
        expires_at
    ) VALUES (
        v_account_id,
        v_user_type,
        encode(public.digest(v_new_token, 'sha256'), 'hex'),
        CURRENT_TIMESTAMP + v_session_ttl
    );

    -- Create new refresh token
    INSERT INTO app_auth.refresh_tokens (
        account_id,
        user_type,
        token_hash,
        expires_at
    ) VALUES (
        v_account_id,
        v_user_type,
        encode(public.digest(v_new_refresh_token, 'sha256'), 'hex'),
        CURRENT_TIMESTAMP + v_refresh_ttl
    );

    -- Update login timestamp
    UPDATE app_auth.user_accounts
    SET last_login = CURRENT_TIMESTAMP
    WHERE id = v_account_id;

    -- Log activity for admins
    IF v_user_type = 'admin' THEN
        SELECT id INTO v_admin_user_id
        FROM app_auth.admin_users
        WHERE account_id = v_account_id;

        IF v_admin_user_id IS NOT NULL THEN
            INSERT INTO system.activity_logs (
                user_id,
                action,
                entity_type,
                entity_id,
                details
            ) VALUES (
                v_admin_user_id,
                'token_refreshed',
                'session',
                NULL,
                jsonb_build_object('method', 'refresh_token')
            );
        END IF;
    END IF;

    RETURN json_build_object(
        'success', true,
        'session_token', v_new_token,
        'refresh_token', v_new_refresh_token,
        'expires_at', (CURRENT_TIMESTAMP + v_session_ttl)
    );
END;
$$;

-- ============================================================================
-- CONTENT FUNCTIONS
-- ============================================================================

-- Get published content with filters
CREATE OR REPLACE FUNCTION api.get_published_content(
    p_category_id UUID DEFAULT NULL,
    p_search TEXT DEFAULT NULL,
    p_limit INT DEFAULT 20,
    p_offset INT DEFAULT 0
)
RETURNS JSON
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_result JSON;
    v_total INT;
BEGIN
    -- Get total count
    SELECT COUNT(*)
    INTO v_total
    FROM content.pages p
    WHERE p.status = 'published'
        AND p.published_at <= CURRENT_TIMESTAMP
        AND (p_category_id IS NULL OR p.category_id = p_category_id)
        AND (p_search IS NULL OR (
            p.title ILIKE '%' || p_search || '%'
            OR p.content ILIKE '%' || p_search || '%'
            OR p.excerpt ILIKE '%' || p_search || '%'
        ));

    -- Get paginated results
    SELECT json_build_object(
        'total', v_total,
        'limit', p_limit,
        'offset', p_offset,
        'data', COALESCE(json_agg(
            json_build_object(
                'id', p.id,
                'slug', p.slug,
                'title', p.title,
                'excerpt', p.excerpt,
                'featured_image', p.featured_image,
                'published_at', p.published_at,
                'view_count', p.view_count,
                'category', CASE
                    WHEN c.id IS NOT NULL THEN json_build_object(
                        'id', c.id,
                        'name', c.name,
                        'slug', c.slug
                    )
                    ELSE NULL
                END,
                'author', json_build_object(
                    'id', u.id,
                    'username', u.username,
                    'first_name', u.first_name,
                    'last_name', u.last_name
                )
            ) ORDER BY p.published_at DESC
        ), '[]'::json)
    )
    INTO v_result
    FROM content.pages p
    LEFT JOIN content.categories c ON p.category_id = c.id
    LEFT JOIN app_auth.admin_users u ON p.author_id = u.id
    WHERE p.status = 'published'
        AND p.published_at <= CURRENT_TIMESTAMP
        AND (p_category_id IS NULL OR p.category_id = p_category_id)
        AND (p_search IS NULL OR (
            p.title ILIKE '%' || p_search || '%'
            OR p.content ILIKE '%' || p_search || '%'
            OR p.excerpt ILIKE '%' || p_search || '%'
        ))
    LIMIT p_limit
    OFFSET p_offset;

    RETURN v_result;
END;
$$;

-- Create or update content
CREATE OR REPLACE FUNCTION api.upsert_content(
    p_id UUID DEFAULT NULL,
    p_title TEXT DEFAULT NULL,
    p_slug TEXT DEFAULT NULL,
    p_content TEXT DEFAULT NULL,
    p_excerpt TEXT DEFAULT NULL,
    p_category_id UUID DEFAULT NULL,
    p_featured_image TEXT DEFAULT NULL,
    p_status TEXT DEFAULT 'draft',
    p_published_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    p_seo_title TEXT DEFAULT NULL,
    p_seo_description TEXT DEFAULT NULL,
    p_seo_keywords TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_page_id UUID;
    v_author_id UUID;
    v_is_new BOOLEAN;
BEGIN
    -- Get current user
    v_author_id := auth.uid();

    IF v_author_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    -- Check if this is an update
    v_is_new := (p_id IS NULL);

    IF v_is_new THEN
        -- Create new page
        INSERT INTO content.pages (
            title,
            slug,
            content,
            excerpt,
            category_id,
            author_id,
            featured_image,
            status,
            published_at,
            seo_title,
            seo_description,
            seo_keywords
        ) VALUES (
            p_title,
            COALESCE(p_slug, regexp_replace(lower(p_title), '[^a-z0-9]+', '-', 'g')),
            p_content,
            p_excerpt,
            p_category_id,
            v_author_id,
            p_featured_image,
            p_status,
            CASE WHEN p_status = 'published' THEN COALESCE(p_published_at, CURRENT_TIMESTAMP) ELSE NULL END,
            p_seo_title,
            p_seo_description,
            p_seo_keywords
        ) RETURNING id INTO v_page_id;

        -- Log activity
        INSERT INTO system.activity_logs (
            user_id,
            action,
            entity_type,
            entity_id,
            details
        ) VALUES (
            v_author_id,
            'content_created',
            'page',
            v_page_id,
            jsonb_build_object('title', p_title, 'status', p_status)
        );
    ELSE
        -- Update existing page
        UPDATE content.pages
        SET title = COALESCE(p_title, title),
            slug = COALESCE(p_slug, slug),
            content = COALESCE(p_content, content),
            excerpt = COALESCE(p_excerpt, excerpt),
            category_id = COALESCE(p_category_id, category_id),
            featured_image = COALESCE(p_featured_image, featured_image),
            status = COALESCE(p_status, status),
            published_at = CASE
                WHEN p_status = 'published' AND status != 'published' THEN COALESCE(p_published_at, CURRENT_TIMESTAMP)
                WHEN p_status = 'published' THEN COALESCE(p_published_at, published_at)
                ELSE published_at
            END,
            seo_title = COALESCE(p_seo_title, seo_title),
            seo_description = COALESCE(p_seo_description, seo_description),
            seo_keywords = COALESCE(p_seo_keywords, seo_keywords),
            updated_at = CURRENT_TIMESTAMP
        WHERE id = p_id
        RETURNING id INTO v_page_id;

        -- Create revision
        INSERT INTO content.page_revisions (
            page_id,
            title,
            content,
            excerpt,
            revision_by
        )
        SELECT id, title, content, excerpt, v_author_id
        FROM content.pages
        WHERE id = v_page_id;

        -- Log activity
        INSERT INTO system.activity_logs (
            user_id,
            action,
            entity_type,
            entity_id,
            details
        ) VALUES (
            v_author_id,
            'content_updated',
            'page',
            v_page_id,
            jsonb_build_object('status', p_status)
        );
    END IF;

    RETURN json_build_object(
        'success', true,
        'page_id', v_page_id,
        'is_new', v_is_new,
        'message', CASE WHEN v_is_new THEN 'Content created successfully' ELSE 'Content updated successfully' END
    );
END;
$$;

-- ============================================================================
-- CONTACT FUNCTIONS
-- ============================================================================

-- Submit contact form
CREATE OR REPLACE FUNCTION api.submit_contact_form(
    p_form_id UUID,
    p_name TEXT,
    p_email TEXT,
    p_message TEXT,
    p_subject TEXT DEFAULT NULL,
    p_data JSONB DEFAULT '{}'::jsonb
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_inquiry_id UUID;
    v_form RECORD;
BEGIN
    -- Get form details
    SELECT * INTO v_form
    FROM contact.contact_forms
    WHERE id = p_form_id AND is_active = true;

    IF v_form IS NULL THEN
        RAISE EXCEPTION 'Form not found or inactive';
    END IF;

    -- Create inquiry
    INSERT INTO contact.contact_inquiries (
        form_id,
        name,
        email,
        subject,
        message,
        data,
        status,
        priority
    ) VALUES (
        p_form_id,
        p_name,
        lower(p_email),
        COALESCE(p_subject, 'Contact Form Submission'),
        p_message,
        p_data,
        'new',
        'normal'
    ) RETURNING id INTO v_inquiry_id;

    -- Log activity
    INSERT INTO system.activity_logs (
        action,
        entity_type,
        entity_id,
        details
    ) VALUES (
        'contact_form_submitted',
        'inquiry',
        v_inquiry_id,
        jsonb_build_object(
            'form_name', v_form.name,
            'email', p_email
        )
    );

    -- Add to notification queue if configured
    IF v_form.notification_email IS NOT NULL THEN
        INSERT INTO launch.notification_queue (
            template_id,
            recipient_email,
            subject,
            variables,
            priority
        ) VALUES (
            (SELECT id FROM launch.notification_templates WHERE code = 'contact_form_notification' LIMIT 1),
            v_form.notification_email,
            'New Contact Form Submission: ' || COALESCE(p_subject, v_form.name),
            jsonb_build_object(
                'inquiry_id', v_inquiry_id,
                'form_name', v_form.name,
                'name', p_name,
                'email', p_email,
                'subject', p_subject,
                'message', p_message
            ),
            'high'
        );
    END IF;

    RETURN json_build_object(
        'success', true,
        'inquiry_id', v_inquiry_id,
        'message', COALESCE(v_form.success_message, 'Thank you for your submission. We will get back to you soon.')
    );
END;
$$;

-- ============================================================================
-- LAUNCH FUNCTIONS
-- ============================================================================

-- Subscribe to campaign
CREATE OR REPLACE FUNCTION api.subscribe_to_campaign(
    p_campaign_id UUID,
    p_email TEXT,
    p_first_name TEXT DEFAULT NULL,
    p_last_name TEXT DEFAULT NULL,
    p_referral_code TEXT DEFAULT NULL,
    p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_subscriber_id UUID;
    v_campaign RECORD;
    v_verification_token VARCHAR(255);
    v_referrer_id UUID;
BEGIN
    -- Get campaign details
    SELECT * INTO v_campaign
    FROM launch.launch_campaigns
    WHERE id = p_campaign_id
        AND is_active = true
        AND status = 'active'
        AND (start_date IS NULL OR start_date <= CURRENT_TIMESTAMP)
        AND (end_date IS NULL OR end_date >= CURRENT_TIMESTAMP);

    IF v_campaign IS NULL THEN
        RAISE EXCEPTION 'Campaign not found or inactive';
    END IF;

    -- Check if already subscribed
    IF EXISTS (
        SELECT 1 FROM launch.launch_subscribers
        WHERE campaign_id = p_campaign_id AND email = lower(p_email)
    ) THEN
        RAISE EXCEPTION 'Already subscribed to this campaign';
    END IF;

    -- Find referrer if code provided
    IF p_referral_code IS NOT NULL THEN
        SELECT id INTO v_referrer_id
        FROM launch.launch_subscribers
        WHERE referral_code = p_referral_code
            AND campaign_id = p_campaign_id;
    END IF;

    -- Generate verification token
    v_verification_token := encode(public.gen_random_bytes(32), 'hex');

    -- Create subscriber
    INSERT INTO launch.launch_subscribers (
        campaign_id,
        email,
        first_name,
        last_name,
        verification_token,
        referral_code,
        metadata,
        referral_source
    ) VALUES (
        p_campaign_id,
        lower(p_email),
        p_first_name,
        p_last_name,
        v_verification_token,
        encode(public.gen_random_bytes(16), 'hex'),
        p_metadata,
        p_referral_code
    ) RETURNING id INTO v_subscriber_id;

    -- Create referral record if applicable
    IF v_referrer_id IS NOT NULL THEN
        INSERT INTO launch.launch_referrals (
            referrer_id,
            referee_id,
            campaign_id,
            status
        ) VALUES (
            v_referrer_id,
            v_subscriber_id,
            p_campaign_id,
            'pending'
        );

        -- Update referrer's referral count
        UPDATE launch.launch_subscribers
        SET referral_count = referral_count + 1
        WHERE id = v_referrer_id;
    END IF;

    -- Update campaign subscriber count
    UPDATE launch.launch_campaigns
    SET current_subscribers = current_subscribers + 1
    WHERE id = p_campaign_id;

    -- Log activity
    INSERT INTO system.activity_logs (
        action,
        entity_type,
        entity_id,
        details
    ) VALUES (
        'campaign_subscription',
        'subscriber',
        v_subscriber_id,
        jsonb_build_object(
            'campaign_name', v_campaign.name,
            'email', p_email,
            'referred_by', p_referral_code
        )
    );

    -- Add to notification queue
    INSERT INTO launch.notification_queue (
        template_id,
        recipient_email,
        subject,
        variables
    ) VALUES (
        (SELECT id FROM launch.notification_templates WHERE code = 'subscription_confirmation' LIMIT 1),
        p_email,
        'Please confirm your subscription',
        jsonb_build_object(
            'campaign_name', v_campaign.name,
            'verification_token', v_verification_token,
            'first_name', p_first_name
        )
    );

    RETURN json_build_object(
        'success', true,
        'subscriber_id', v_subscriber_id,
        'verification_token', v_verification_token,
        'referral_code', (SELECT referral_code FROM launch.launch_subscribers WHERE id = v_subscriber_id),
        'message', 'Successfully subscribed! Please check your email to verify your subscription.'
    );
END;
$$;

-- Unsubscribe from campaign
CREATE OR REPLACE FUNCTION api.unsubscribe(
    p_token TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_subscriber RECORD;
BEGIN
    -- Find subscriber by unsubscribe token
    SELECT * INTO v_subscriber
    FROM launch.launch_subscribers
    WHERE unsubscribe_token = p_token;

    IF v_subscriber IS NULL THEN
        RAISE EXCEPTION 'Invalid unsubscribe token';
    END IF;

    -- Update subscriber status
    UPDATE launch.launch_subscribers
    SET is_subscribed = false,
        unsubscribed_at = CURRENT_TIMESTAMP
    WHERE id = v_subscriber.id;

    -- Update campaign subscriber count
    UPDATE launch.launch_campaigns
    SET current_subscribers = GREATEST(0, current_subscribers - 1)
    WHERE id = v_subscriber.campaign_id;

    -- Log activity
    INSERT INTO system.activity_logs (
        action,
        entity_type,
        entity_id,
        details
    ) VALUES (
        'campaign_unsubscribe',
        'subscriber',
        v_subscriber.id,
        jsonb_build_object('email', v_subscriber.email)
    );

    RETURN json_build_object(
        'success', true,
        'message', 'Successfully unsubscribed'
    );
END;
$$;

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

-- Search across multiple entities
CREATE OR REPLACE FUNCTION api.global_search(
    p_query TEXT,
    p_limit INT DEFAULT 10
)
RETURNS JSON
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_results JSON;
BEGIN
    SELECT json_build_object(
        'pages', (
            SELECT COALESCE(json_agg(
                json_build_object(
                    'type', 'page',
                    'id', id,
                    'title', title,
                    'slug', slug,
                    'excerpt', excerpt
                )
            ), '[]'::json)
            FROM content.pages
            WHERE status = 'published'
                AND (
                    title ILIKE '%' || p_query || '%'
                    OR content ILIKE '%' || p_query || '%'
                    OR excerpt ILIKE '%' || p_query || '%'
                )
            LIMIT p_limit
        ),
        'categories', (
            SELECT COALESCE(json_agg(
                json_build_object(
                    'type', 'category',
                    'id', id,
                    'name', name,
                    'slug', slug,
                    'description', description
                )
            ), '[]'::json)
            FROM content.categories
            WHERE is_active = true
                AND (
                    name ILIKE '%' || p_query || '%'
                    OR description ILIKE '%' || p_query || '%'
                )
            LIMIT p_limit
        ),
        'users', (
            SELECT COALESCE(json_agg(
                json_build_object(
                    'type', 'user',
                    'id', au.id,
                    'username', au.username,
                    'first_name', au.first_name,
                    'last_name', au.last_name,
                    'email', ua.email
                )
            ), '[]'::json)
            FROM app_auth.admin_users au
            JOIN app_auth.user_accounts ua ON ua.id = au.account_id
            WHERE ua.is_active = true AND ua.is_verified = true
                AND (
                    au.username ILIKE '%' || p_query || '%'
                    OR au.first_name ILIKE '%' || p_query || '%'
                    OR au.last_name ILIKE '%' || p_query || '%'
                    OR ua.email ILIKE '%' || p_query || '%'
                )
            LIMIT p_limit
        )
    )
    INTO v_results;

    RETURN v_results;
END;
$$;

-- Get system statistics
CREATE OR REPLACE FUNCTION api.get_system_stats()
RETURNS JSON
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
    v_stats JSON;
BEGIN
    SELECT json_build_object(
        'users', json_build_object(
            'total', (SELECT COUNT(*) FROM app_auth.user_accounts),
            'active', (SELECT COUNT(*) FROM app_auth.user_accounts WHERE is_active = true),
            'verified', (SELECT COUNT(*) FROM app_auth.user_accounts WHERE is_verified = true),
            'new_today', (SELECT COUNT(*) FROM app_auth.user_accounts WHERE created_at >= CURRENT_DATE)
        ),
        'content', json_build_object(
            'total_pages', (SELECT COUNT(*) FROM content.pages),
            'published', (SELECT COUNT(*) FROM content.pages WHERE status = 'published'),
            'drafts', (SELECT COUNT(*) FROM content.pages WHERE status = 'draft'),
            'categories', (SELECT COUNT(*) FROM content.categories WHERE is_active = true),
            'media_files', (SELECT COUNT(*) FROM content.media_files)
        ),
        'contact', json_build_object(
            'total_inquiries', (SELECT COUNT(*) FROM contact.contact_inquiries),
            'new', (SELECT COUNT(*) FROM contact.contact_inquiries WHERE status = 'new'),
            'in_progress', (SELECT COUNT(*) FROM contact.contact_inquiries WHERE status = 'in_progress'),
            'resolved', (SELECT COUNT(*) FROM contact.contact_inquiries WHERE status = 'resolved')
        ),
        'campaigns', json_build_object(
            'active', (SELECT COUNT(*) FROM launch.launch_campaigns WHERE is_active = true),
            'total_subscribers', (SELECT COUNT(*) FROM launch.launch_subscribers),
            'verified_subscribers', (SELECT COUNT(*) FROM launch.launch_subscribers WHERE is_verified = true),
            'total_referrals', (SELECT COUNT(*) FROM launch.launch_referrals)
        ),
        'system', json_build_object(
            'activities_today', (SELECT COUNT(*) FROM system.activity_logs WHERE created_at >= CURRENT_DATE),
            'pending_jobs', (SELECT COUNT(*) FROM system.system_jobs WHERE status = 'pending'),
            'enabled_features', (SELECT COUNT(*) FROM system.feature_flags WHERE is_enabled = true)
        ),
        'generated_at', CURRENT_TIMESTAMP
    )
    INTO v_stats;

    RETURN v_stats;
END;
$$;

-- ============================================================================
-- GRANT EXECUTE PERMISSIONS
-- ============================================================================

-- Public functions (accessible by anonymous users)
GRANT EXECUTE ON FUNCTION api.register_user TO authenticated;
GRANT EXECUTE ON FUNCTION api.register_user TO service_role;
GRANT EXECUTE ON FUNCTION api.player_signup TO anon;
GRANT EXECUTE ON FUNCTION api.guest_check_in TO anon;
GRANT EXECUTE ON FUNCTION api.login TO anon;
GRANT EXECUTE ON FUNCTION api.get_published_content TO anon;
GRANT EXECUTE ON FUNCTION api.submit_contact_form TO anon;
GRANT EXECUTE ON FUNCTION api.subscribe_to_campaign TO anon;
GRANT EXECUTE ON FUNCTION api.unsubscribe TO anon;
GRANT EXECUTE ON FUNCTION api.global_search TO anon;

-- Authenticated functions
GRANT EXECUTE ON FUNCTION api.logout TO authenticated;
GRANT EXECUTE ON FUNCTION api.refresh_token TO authenticated;
GRANT EXECUTE ON FUNCTION api.refresh_token TO service_role;
GRANT EXECUTE ON FUNCTION api.validate_session TO authenticated;
GRANT EXECUTE ON FUNCTION api.validate_session TO service_role;
GRANT EXECUTE ON FUNCTION api.upsert_content TO authenticated;

-- Admin functions
GRANT EXECUTE ON FUNCTION api.get_system_stats TO authenticated;
-- ============================================================================
-- REALTIME CONFIGURATION MODULE
-- Enable real-time subscriptions for tables
-- ============================================================================

-- Create publication for real-time
DROP PUBLICATION IF EXISTS supabase_realtime CASCADE;
CREATE PUBLICATION supabase_realtime;

-- ============================================================================
-- ENABLE REALTIME FOR TABLES
-- ============================================================================

-- Authentication tables
ALTER PUBLICATION supabase_realtime ADD TABLE app_auth.user_accounts;
ALTER PUBLICATION supabase_realtime ADD TABLE app_auth.admin_users;
ALTER PUBLICATION supabase_realtime ADD TABLE app_auth.players;
ALTER PUBLICATION supabase_realtime ADD TABLE app_auth.guest_users;
ALTER PUBLICATION supabase_realtime ADD TABLE app_auth.sessions;

-- Content tables
ALTER PUBLICATION supabase_realtime ADD TABLE content.pages;
ALTER PUBLICATION supabase_realtime ADD TABLE content.categories;
ALTER PUBLICATION supabase_realtime ADD TABLE content.media_files;

-- Contact tables
ALTER PUBLICATION supabase_realtime ADD TABLE contact.contact_inquiries;
ALTER PUBLICATION supabase_realtime ADD TABLE contact.contact_responses;

-- Launch campaign tables
ALTER PUBLICATION supabase_realtime ADD TABLE launch.launch_campaigns;
ALTER PUBLICATION supabase_realtime ADD TABLE launch.launch_subscribers;
-- notification_queue table doesn't exist, using launch_notifications instead
ALTER PUBLICATION supabase_realtime ADD TABLE launch.launch_notifications;

-- System tables
ALTER PUBLICATION supabase_realtime ADD TABLE system.activity_logs;
ALTER PUBLICATION supabase_realtime ADD TABLE system.system_jobs;
ALTER PUBLICATION supabase_realtime ADD TABLE system.feature_flags;

-- ============================================================================
-- REALTIME TRIGGERS
-- ============================================================================

-- Function to notify channel on data changes
CREATE OR REPLACE FUNCTION notify_channel()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    channel_name TEXT;
    payload JSONB;
BEGIN
    -- Determine channel name based on table
    channel_name := TG_TABLE_SCHEMA || '_' || TG_TABLE_NAME || '_changes';

    -- Build payload
    payload := jsonb_build_object(
        'table', TG_TABLE_NAME,
        'schema', TG_TABLE_SCHEMA,
        'action', TG_OP,
        'new', to_jsonb(NEW),
        'old', to_jsonb(OLD),
        'timestamp', CURRENT_TIMESTAMP
    );

    -- Send notification
    PERFORM pg_notify(channel_name, payload::text);

    RETURN NEW;
END;
$$;

-- Create triggers for important tables

-- Content updates trigger
CREATE TRIGGER content_pages_notify
AFTER INSERT OR UPDATE OR DELETE ON content.pages
FOR EACH ROW
EXECUTE FUNCTION notify_channel();

-- Contact form submissions trigger
CREATE TRIGGER contact_inquiries_notify
AFTER INSERT ON contact.contact_inquiries
FOR EACH ROW
EXECUTE FUNCTION notify_channel();

-- Campaign subscription trigger
CREATE TRIGGER launch_subscribers_notify
AFTER INSERT OR UPDATE ON launch.launch_subscribers
FOR EACH ROW
EXECUTE FUNCTION notify_channel();

-- System activity trigger
CREATE TRIGGER activity_logs_notify
AFTER INSERT ON system.activity_logs
FOR EACH ROW
EXECUTE FUNCTION notify_channel();

-- ============================================================================
-- REALTIME FILTERS
-- ============================================================================

-- Function to filter realtime data based on user role
CREATE OR REPLACE FUNCTION realtime_filter(
    p_table_name TEXT,
    p_user_id UUID,
    p_user_role TEXT,
    p_record JSONB
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Admin and super_admin can see everything
    IF p_user_role IN ('admin', 'super_admin') THEN
        RETURN TRUE;
    END IF;

    -- Table-specific filters
    CASE p_table_name
        WHEN 'pages' THEN
            -- Users can see published pages or their own
            RETURN (p_record->>'status' = 'published') OR
                   (p_record->>'author_id' = p_user_id::text);

        WHEN 'contact_inquiries' THEN
            -- Users can see inquiries they submitted or are assigned to
            RETURN (p_record->>'submitted_by' = p_user_id::text) OR
                   (p_record->>'assigned_to' = p_user_id::text);

        WHEN 'launch_subscribers' THEN
            -- Users can only see their own subscriptions
            RETURN (p_record->>'user_id' = p_user_id::text);

        WHEN 'activity_logs' THEN
            -- Users can see their own activity
            RETURN (p_record->>'user_id' = p_user_id::text);

        ELSE
            -- Default: no access
            RETURN FALSE;
    END CASE;
END;
$$;

-- ============================================================================
-- BROADCAST CHANNELS
-- ============================================================================

-- System broadcast channel for announcements
CREATE OR REPLACE FUNCTION broadcast_system_message(
    p_type TEXT,
    p_title TEXT,
    p_message TEXT,
    p_data JSONB DEFAULT '{}'::jsonb
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_payload JSONB;
BEGIN
    v_payload := jsonb_build_object(
        'type', p_type,
        'title', p_title,
        'message', p_message,
        'data', p_data,
        'timestamp', CURRENT_TIMESTAMP
    );

    PERFORM pg_notify('system_broadcast', v_payload::text);
END;
$$;

-- Content update broadcast
CREATE OR REPLACE FUNCTION broadcast_content_update(
    p_page_id UUID,
    p_action TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_page RECORD;
    v_payload JSONB;
BEGIN
    SELECT p.*, u.username
    INTO v_page
    FROM content.pages p
    LEFT JOIN app_auth.admin_users u ON p.author_id = u.id
    WHERE p.id = p_page_id;

    v_payload := jsonb_build_object(
        'action', p_action,
        'page', jsonb_build_object(
            'id', v_page.id,
            'title', v_page.title,
            'slug', v_page.slug,
            'status', v_page.status,
            'author', v_page.username
        ),
        'timestamp', CURRENT_TIMESTAMP
    );

    PERFORM pg_notify('content_updates', v_payload::text);
END;
$$;

-- ============================================================================
-- PRESENCE TRACKING
-- ============================================================================

-- Table for tracking user presence
CREATE TABLE IF NOT EXISTS realtime.presence (
    user_id UUID REFERENCES app_auth.user_accounts(id) ON DELETE CASCADE,
    channel TEXT NOT NULL,
    status TEXT DEFAULT 'online',
    last_seen TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    metadata JSONB DEFAULT '{}'::jsonb,
    PRIMARY KEY (user_id, channel)
);

-- Function to update user presence
CREATE OR REPLACE FUNCTION update_presence(
    p_user_id UUID,
    p_channel TEXT,
    p_status TEXT DEFAULT 'online',
    p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    INSERT INTO realtime.presence (
        user_id,
        channel,
        status,
        metadata,
        last_seen
    ) VALUES (
        p_user_id,
        p_channel,
        p_status,
        p_metadata,
        CURRENT_TIMESTAMP
    )
    ON CONFLICT (user_id, channel)
    DO UPDATE SET
        status = EXCLUDED.status,
        metadata = EXCLUDED.metadata,
        last_seen = CURRENT_TIMESTAMP;
END;
$$;

-- Function to clean up old presence records
CREATE OR REPLACE FUNCTION cleanup_presence()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Remove presence records older than 5 minutes
    DELETE FROM realtime.presence
    WHERE last_seen < CURRENT_TIMESTAMP - INTERVAL '5 minutes';
END;
$$;

-- ============================================================================
-- METRICS AND MONITORING
-- ============================================================================

-- Table for tracking realtime metrics
CREATE TABLE IF NOT EXISTS realtime.metrics (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    channel TEXT NOT NULL,
    event_type TEXT NOT NULL,
    user_id UUID REFERENCES app_auth.user_accounts(id),
    payload_size INT,
    success BOOLEAN DEFAULT true,
    error_message TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Function to log realtime metrics
CREATE OR REPLACE FUNCTION log_realtime_metric(
    p_channel TEXT,
    p_event_type TEXT,
    p_user_id UUID DEFAULT NULL,
    p_payload_size INT DEFAULT 0,
    p_success BOOLEAN DEFAULT true,
    p_error_message TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    INSERT INTO realtime.metrics (
        channel,
        event_type,
        user_id,
        payload_size,
        success,
        error_message
    ) VALUES (
        p_channel,
        p_event_type,
        p_user_id,
        p_payload_size,
        p_success,
        p_error_message
    );

    -- Clean up old metrics (keep only last 7 days)
    DELETE FROM realtime.metrics
    WHERE created_at < CURRENT_TIMESTAMP - INTERVAL '7 days';
END;
$$;

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

-- Grant permissions for realtime functions
GRANT EXECUTE ON FUNCTION notify_channel() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION realtime_filter TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION broadcast_system_message TO authenticated;
GRANT EXECUTE ON FUNCTION broadcast_content_update TO authenticated;
GRANT EXECUTE ON FUNCTION update_presence TO authenticated;
GRANT EXECUTE ON FUNCTION cleanup_presence TO service_role;
GRANT EXECUTE ON FUNCTION log_realtime_metric TO authenticated, service_role;

-- Grant permissions for presence tracking
GRANT SELECT, INSERT, UPDATE, DELETE ON realtime.presence TO authenticated;
GRANT SELECT ON realtime.metrics TO authenticated;
GRANT INSERT ON realtime.metrics TO service_role;
-- ============================================================================
-- CONTACT NOTIFICATION TABLE
-- Simple table for waitlist and notification signups
-- ============================================================================

-- Set search path for contact schema
SET search_path TO contact, public;

-- Create contact_notification table
CREATE TABLE IF NOT EXISTS contact.contact_notification (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email public.CITEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create index on email for faster lookups
CREATE INDEX IF NOT EXISTS idx_contact_notification_email ON contact.contact_notification(email);

-- Create index on created_at for sorting
CREATE INDEX IF NOT EXISTS idx_contact_notification_created_at ON contact.contact_notification(created_at DESC);

-- Add comment to table
COMMENT ON TABLE contact.contact_notification IS 'Stores waitlist and notification signup information';
COMMENT ON COLUMN contact.contact_notification.id IS 'Unique identifier for the notification signup';
COMMENT ON COLUMN contact.contact_notification.first_name IS 'First name of the person signing up';
COMMENT ON COLUMN contact.contact_notification.last_name IS 'Last name of the person signing up';
COMMENT ON COLUMN contact.contact_notification.email IS 'Email address for notifications';
COMMENT ON COLUMN contact.contact_notification.created_at IS 'Timestamp when the signup occurred';-- ============================================================================
-- ALLOWED EMAILS MODULE (PUBLIC SCHEMA)
-- Manage pre-authorized email addresses for sign-up
-- Using public schema since auth schema is managed by Supabase
-- ============================================================================

-- Use public schema
SET search_path TO public;

-- Drop the auth schema table if it exists (cleanup)
DROP TABLE IF EXISTS app_auth.allowed_emails CASCADE;

-- Table for storing allowed email addresses for sign-up
CREATE TABLE IF NOT EXISTS public.allowed_emails (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email CITEXT UNIQUE NOT NULL,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    role VARCHAR(50) DEFAULT 'viewer'
        CHECK (role IN ('super_admin', 'admin', 'editor', 'viewer', 'manager', 'coach')),
    added_by UUID,
    notes TEXT,
    is_active BOOLEAN DEFAULT true,
    used_at TIMESTAMP WITH TIME ZONE,
    used_by UUID,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_allowed_emails_email ON public.allowed_emails(email);
CREATE INDEX IF NOT EXISTS idx_allowed_emails_is_active ON public.allowed_emails(is_active);
CREATE INDEX IF NOT EXISTS idx_allowed_emails_created_at ON public.allowed_emails(created_at DESC);

-- Add comment on table
COMMENT ON TABLE public.allowed_emails IS 'Pre-authorized email addresses that are allowed to sign up';
COMMENT ON COLUMN public.allowed_emails.email IS 'The email address that is allowed to sign up';
COMMENT ON COLUMN public.allowed_emails.role IS 'The default role to assign when this email signs up';
COMMENT ON COLUMN public.allowed_emails.added_by IS 'The user who added this email to the allowed list';
COMMENT ON COLUMN public.allowed_emails.used_at IS 'When this email was used to sign up';
COMMENT ON COLUMN public.allowed_emails.used_by IS 'The user ID created when this email signed up';

-- Function to check if an email is allowed to sign up
CREATE OR REPLACE FUNCTION public.is_email_allowed(check_email TEXT)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1
        FROM public.allowed_emails
        WHERE email = LOWER(check_email)
        AND is_active = true
        AND used_at IS NULL
    );
END;
$$ LANGUAGE plpgsql;

-- Function to mark an allowed email as used
CREATE OR REPLACE FUNCTION public.mark_email_used(
    used_email TEXT,
    user_id UUID
)
RETURNS VOID AS $$
BEGIN
    UPDATE public.allowed_emails
    SET
        used_at = CURRENT_TIMESTAMP,
        used_by = user_id,
        updated_at = CURRENT_TIMESTAMP
    WHERE email = LOWER(used_email);
END;
$$ LANGUAGE plpgsql;

-- Enable RLS (Row Level Security)
ALTER TABLE public.allowed_emails ENABLE ROW LEVEL SECURITY;

-- Create policies for public access (adjust as needed)
-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Enable read access for all users" ON public.allowed_emails;
DROP POLICY IF EXISTS "Enable insert for authenticated users" ON public.allowed_emails;
DROP POLICY IF EXISTS "Enable update for authenticated users" ON public.allowed_emails;
DROP POLICY IF EXISTS "Enable delete for authenticated users" ON public.allowed_emails;

-- Create policies
CREATE POLICY "Enable read access for all users" ON public.allowed_emails
    FOR SELECT USING (true);

CREATE POLICY "Enable insert for authenticated users" ON public.allowed_emails
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Enable update for authenticated users" ON public.allowed_emails
    FOR UPDATE USING (true);

CREATE POLICY "Enable delete for authenticated users" ON public.allowed_emails
    FOR DELETE USING (true);-- ============================================================================
-- ALLOWED EMAILS MODULE
-- Manage pre-authorized email addresses for sign-up
-- ============================================================================

-- Switch to app_auth schema
SET search_path TO app_auth, public;

-- Table for storing allowed email addresses for sign-up
CREATE TABLE IF NOT EXISTS app_auth.allowed_emails (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    email public.CITEXT UNIQUE NOT NULL,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    role VARCHAR(50) DEFAULT 'viewer'
        CHECK (role IN ('super_admin', 'admin', 'editor', 'viewer', 'manager', 'coach')),
    added_by UUID REFERENCES app_auth.admin_users(id),
    notes TEXT,
    is_active BOOLEAN DEFAULT true,
    used_at TIMESTAMP WITH TIME ZONE,
    used_by UUID REFERENCES app_auth.admin_users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for performance
CREATE INDEX idx_allowed_emails_email ON app_auth.allowed_emails(email);
CREATE INDEX idx_allowed_emails_is_active ON app_auth.allowed_emails(is_active);
CREATE INDEX idx_allowed_emails_created_at ON app_auth.allowed_emails(created_at DESC);

-- Add comment on table
COMMENT ON TABLE app_auth.allowed_emails IS 'Pre-authorized email addresses that are allowed to sign up';
COMMENT ON COLUMN app_auth.allowed_emails.email IS 'The email address that is allowed to sign up';
COMMENT ON COLUMN app_auth.allowed_emails.role IS 'The default role to assign when this email signs up';
COMMENT ON COLUMN app_auth.allowed_emails.added_by IS 'The user who added this email to the allowed list';
COMMENT ON COLUMN app_auth.allowed_emails.used_at IS 'When this email was used to sign up';
COMMENT ON COLUMN app_auth.allowed_emails.used_by IS 'The user ID created when this email signed up';

-- Function to check if an email is allowed to sign up
CREATE OR REPLACE FUNCTION app_auth.is_email_allowed(check_email TEXT)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1
        FROM app_auth.allowed_emails
        WHERE email = LOWER(check_email)
        AND is_active = true
        AND used_at IS NULL
    );
END;
$$ LANGUAGE plpgsql;

-- Function to mark an allowed email as used
CREATE OR REPLACE FUNCTION app_auth.mark_email_used(
    used_email TEXT,
    user_id UUID
)
RETURNS VOID AS $$
BEGIN
    UPDATE app_auth.allowed_emails
    SET
        used_at = CURRENT_TIMESTAMP,
        used_by = user_id,
        updated_at = CURRENT_TIMESTAMP
    WHERE email = LOWER(used_email);
END;
$$ LANGUAGE plpgsql;

-- Grant necessary permissions
GRANT SELECT ON app_auth.allowed_emails TO anon;
GRANT SELECT, INSERT, UPDATE ON app_auth.allowed_emails TO authenticated;
GRANT ALL ON app_auth.allowed_emails TO service_role;
-- ============================================================================
-- EMAIL SYSTEM MODULE
-- Email templates, logs, and asset management
-- ============================================================================

-- Note: uuid-ossp extension should already be installed in Supabase Cloud

-- Create system schema if not exists
CREATE SCHEMA IF NOT EXISTS system;

-- Set search path
SET search_path TO system, public;

-- Email templates table
CREATE TABLE IF NOT EXISTS system.email_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    template_key VARCHAR(100) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    subject VARCHAR(255) NOT NULL,
    html_body TEXT NOT NULL,
    text_body TEXT,
    variables JSONB DEFAULT '[]',
    category VARCHAR(50) DEFAULT 'general',
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Email logs table
CREATE TABLE IF NOT EXISTS system.email_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    template_key VARCHAR(100) REFERENCES system.email_templates(template_key) ON DELETE SET NULL,
    to_email TEXT NOT NULL,
    from_email TEXT NOT NULL,
    subject VARCHAR(255),
    status VARCHAR(50) DEFAULT 'pending'
        CHECK (status IN ('pending', 'sent', 'failed', 'bounced', 'opened', 'clicked')),
    provider VARCHAR(50) DEFAULT 'sendgrid',
    provider_message_id VARCHAR(255),
    metadata JSONB DEFAULT '{}',
    error_message TEXT,
    sent_at TIMESTAMP WITH TIME ZONE,
    opened_at TIMESTAMP WITH TIME ZONE,
    clicked_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Email attachments table
CREATE TABLE IF NOT EXISTS system.email_attachments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email_log_id UUID REFERENCES system.email_logs(id) ON DELETE CASCADE,
    filename VARCHAR(255) NOT NULL,
    content_type VARCHAR(100),
    size_bytes INTEGER,
    storage_path TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes
CREATE INDEX email_logs_to_email ON system.email_logs(to_email);
CREATE INDEX email_logs_status ON system.email_logs(status);
CREATE INDEX email_logs_created_at ON system.email_logs(created_at);
CREATE INDEX email_logs_template_key ON system.email_logs(template_key);

-- Insert default email templates
INSERT INTO system.email_templates (template_key, name, subject, html_body, text_body, category, variables) VALUES
(
    'contact_form_thank_you',
    'Contact Form - Thank You',
    'Thank you for contacting The Dink House',
    '<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; line-height: 1.6; color: #333; margin: 0; padding: 0; }
        .container { max-width: 600px; margin: 0 auto; padding: 20px; }
        .header { background: linear-gradient(135deg, #CDFE00 0%, #9BCF00 100%); padding: 40px 20px; text-align: center; border-radius: 8px 8px 0 0; }
        .logo { max-width: 200px; height: auto; margin-bottom: 20px; }
        .content { background: #ffffff; padding: 40px 30px; border: 1px solid #e0e0e0; border-top: none; border-radius: 0 0 8px 8px; }
        .button { display: inline-block; background: #CDFE00; color: #000; padding: 14px 30px; text-decoration: none; border-radius: 4px; font-weight: 600; margin-top: 20px; }
        .footer { text-align: center; padding: 30px; color: #666; font-size: 14px; }
        .social-links { margin-top: 20px; }
        .social-links a { margin: 0 10px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <img src="{{logo_url}}" alt="The Dink House" class="logo" />
            <h1 style="color: white; margin: 0; font-size: 28px;">Thank You for Reaching Out!</h1>
        </div>
        <div class="content">
            <p style="font-size: 16px;">Hi {{first_name}},</p>

            <p>Thank you for contacting The Dink House! We''ve received your message and truly appreciate you taking the time to reach out to us.</p>

            <p>Our team is reviewing your inquiry and will get back to you within 24-48 hours. We''re excited to connect with you and discuss how we can help with your pickleball needs!</p>

            <p>In the meantime, feel free to:</p>
            <ul>
                <li>Check out our latest updates on social media</li>
                <li>Browse our facilities and programs on our website</li>
                <li>Join our community of pickleball enthusiasts</li>
            </ul>

            <center>
                <a href="{{site_url}}" class="button">Visit Our Website</a>
            </center>

            <p style="margin-top: 30px;">If you have any urgent questions, feel free to call us at (555) 123-4567.</p>

            <p>Looking forward to connecting with you soon!</p>

            <p><strong>Best regards,<br>The Dink House Team</strong></p>
        </div>
        <div class="footer">
            <p>The Dink House - Where Pickleball Lives</p>
            <div class="social-links">
                <a href="#">Facebook</a> |
                <a href="#">Instagram</a> |
                <a href="#">Twitter</a>
            </div>
            <p style="font-size: 12px; margin-top: 20px;">
                © 2025 The Dink House. All rights reserved.<br>
                123 Pickleball Lane, Your City, ST 12345
            </p>
        </div>
    </div>
</body>
</html>',
    'Hi {{first_name}},

Thank you for contacting The Dink House! We''ve received your message and truly appreciate you taking the time to reach out to us.

Our team is reviewing your inquiry and will get back to you within 24-48 hours. We''re excited to connect with you and discuss how we can help with your pickleball needs!

If you have any urgent questions, feel free to call us at (555) 123-4567.

Looking forward to connecting with you soon!

Best regards,
The Dink House Team

--
The Dink House - Where Pickleball Lives
Visit us at: {{site_url}}',
    'contact',
    '["first_name", "site_url", "logo_url"]'::jsonb
),
(
    'contact_form_admin',
    'Contact Form - Admin Notification',
    'New Contact Form Submission - {{subject}}',
    '<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; line-height: 1.6; color: #333; margin: 0; padding: 0; }
        .container { max-width: 700px; margin: 0 auto; padding: 20px; }
        .header { background: linear-gradient(135deg, #CDFE00 0%, #9BCF00 100%); padding: 30px; border-radius: 8px 8px 0 0; }
        .content { background: #f9f9f9; padding: 30px; border: 1px solid #e0e0e0; border-top: none; border-radius: 0 0 8px 8px; }
        .field { margin-bottom: 25px; background: white; padding: 15px; border-radius: 4px; border: 1px solid #e0e0e0; }
        .label { font-weight: 600; color: #666; margin-bottom: 8px; font-size: 12px; text-transform: uppercase; letter-spacing: 0.5px; }
        .value { color: #333; font-size: 15px; }
        .message-box { background: white; padding: 20px; border-radius: 4px; border: 1px solid #e0e0e0; white-space: pre-wrap; }
        .metadata { margin-top: 30px; padding-top: 20px; border-top: 2px solid #e0e0e0; }
        .button { display: inline-block; background: #CDFE00; color: #000; padding: 12px 24px; text-decoration: none; border-radius: 4px; font-weight: 600; margin-right: 10px; }
        .button-secondary { background: #f0f0f0; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h2 style="color: white; margin: 0;">New Contact Form Submission</h2>
            <p style="color: rgba(255,255,255,0.9); margin: 10px 0 0 0;">Received at {{submitted_at}}</p>
        </div>
        <div class="content">
            <div class="field">
                <div class="label">Name</div>
                <div class="value">{{first_name}} {{last_name}}</div>
            </div>

            <div class="field">
                <div class="label">Email</div>
                <div class="value"><a href="mailto:{{email}}">{{email}}</a></div>
            </div>

            {{#if phone}}
            <div class="field">
                <div class="label">Phone</div>
                <div class="value">{{phone}}</div>
            </div>
            {{/if}}

            {{#if company}}
            <div class="field">
                <div class="label">Company</div>
                <div class="value">{{company}}</div>
            </div>
            {{/if}}

            {{#if subject}}
            <div class="field">
                <div class="label">Subject</div>
                <div class="value">{{subject}}</div>
            </div>
            {{/if}}

            <div class="field">
                <div class="label">Message</div>
                <div class="message-box">{{message}}</div>
            </div>

            <div style="margin-top: 30px;">
                <a href="{{admin_url}}" class="button">View in Admin</a>
                <a href="mailto:{{email}}" class="button button-secondary">Reply via Email</a>
            </div>

            <div class="metadata">
                <p style="color: #999; font-size: 13px;">
                    <strong>Submission ID:</strong> {{submission_id}}<br>
                    <strong>Form Type:</strong> {{form_type}}<br>
                    <strong>Submitted:</strong> {{submitted_at}}
                </p>
            </div>
        </div>
    </div>
</body>
</html>',
    'New Contact Form Submission

Name: {{first_name}} {{last_name}}
Email: {{email}}
Phone: {{phone}}
Company: {{company}}
Subject: {{subject}}

Message:
{{message}}

--
Submission ID: {{submission_id}}
Submitted: {{submitted_at}}
View in Admin: {{admin_url}}',
    'contact',
    '["first_name", "last_name", "email", "phone", "company", "subject", "message", "submission_id", "submitted_at", "admin_url", "form_type"]'::jsonb
),
(
    'welcome_email',
    'Welcome Email',
    'Welcome to The Dink House Community!',
    '<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; line-height: 1.6; color: #333; margin: 0; padding: 0; }
        .container { max-width: 600px; margin: 0 auto; padding: 20px; }
        .header { background: linear-gradient(135deg, #CDFE00 0%, #9BCF00 100%); padding: 50px 20px; text-align: center; border-radius: 8px 8px 0 0; }
        .logo { max-width: 250px; height: auto; margin-bottom: 20px; }
        .content { background: #ffffff; padding: 40px 30px; border: 1px solid #e0e0e0; border-top: none; border-radius: 0 0 8px 8px; }
        .button { display: inline-block; background: #CDFE00; color: #000; padding: 16px 40px; text-decoration: none; border-radius: 4px; font-weight: 600; margin-top: 20px; font-size: 16px; }
        .features { margin: 30px 0; }
        .feature { padding: 15px; margin: 10px 0; background: #f8f8f8; border-radius: 4px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <img src="{{logo_url}}" alt="The Dink House" class="logo" />
            <h1 style="color: white; margin: 0; font-size: 32px;">Welcome to The Dink House!</h1>
        </div>
        <div class="content">
            <p style="font-size: 18px;">Hi {{first_name}},</p>

            <p style="font-size: 16px;">Welcome to The Dink House community! We''re thrilled to have you join our growing family of pickleball enthusiasts.</p>

            <div class="features">
                <h3>Here''s what you can look forward to:</h3>
                <div class="feature">
                    <strong>🏓 World-Class Facilities</strong><br>
                    Professional courts, equipment, and amenities
                </div>
                <div class="feature">
                    <strong>👥 Vibrant Community</strong><br>
                    Connect with players of all skill levels
                </div>
                <div class="feature">
                    <strong>📅 Events & Tournaments</strong><br>
                    Regular competitions and social events
                </div>
                <div class="feature">
                    <strong>🎓 Professional Coaching</strong><br>
                    Improve your game with expert instruction
                </div>
            </div>

            <center>
                <a href="{{site_url}}/get-started" class="button">Get Started</a>
            </center>

            <p style="margin-top: 40px;">If you have any questions, our team is here to help. Just reply to this email or give us a call.</p>

            <p><strong>See you on the courts!<br>The Dink House Team</strong></p>
        </div>
    </div>
</body>
</html>',
    'Hi {{first_name}},

Welcome to The Dink House community! We''re thrilled to have you join our growing family of pickleball enthusiasts.

Here''s what you can look forward to:

🏓 World-Class Facilities - Professional courts, equipment, and amenities
👥 Vibrant Community - Connect with players of all skill levels
📅 Events & Tournaments - Regular competitions and social events
🎓 Professional Coaching - Improve your game with expert instruction

Get started at: {{site_url}}/get-started

If you have any questions, our team is here to help. Just reply to this email or give us a call.

See you on the courts!
The Dink House Team',
    'user',
    '["first_name", "site_url", "logo_url"]'::jsonb
),
(
    'newsletter_welcome',
    'Newsletter Welcome Email',
    'Welcome to The Dink House Newsletter!',
    '<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; line-height: 1.6; color: #333; margin: 0; padding: 0; }
        .container { max-width: 600px; margin: 0 auto; padding: 20px; }
        .header { background: linear-gradient(135deg, #B3FF00 0%, #9BCF00 100%); padding: 50px 20px; text-align: center; border-radius: 8px 8px 0 0; }
        .logo { max-width: 200px; height: auto; margin-bottom: 20px; }
        .content { background: #ffffff; padding: 40px 30px; border: 1px solid #e0e0e0; border-top: none; border-radius: 0 0 8px 8px; }
        .button { display: inline-block; background: #B3FF00; color: #000; padding: 16px 40px; text-decoration: none; border-radius: 4px; font-weight: 600; margin-top: 20px; font-size: 16px; }
        .benefits { margin: 30px 0; }
        .benefit { padding: 15px; margin: 10px 0; background: #f8f8f8; border-radius: 4px; border-left: 4px solid #B3FF00; }
        .footer { text-align: center; padding: 30px; color: #666; font-size: 14px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <img src="https://wchxzbuuwssrnaxshseu.supabase.co/storage/v1/object/public/dink-files/dinklogo.jpg" alt="The Dink House" class="logo" />
            <h1 style="color: white; margin: 0; font-size: 32px;">You''re In!</h1>
        </div>
        <div class="content">
            <p style="font-size: 18px;">Hi {{first_name}},</p>

            <p style="font-size: 16px;">Thank you for subscribing to The Dink House newsletter! You''re now part of an exclusive community of pickleball enthusiasts who get first access to:</p>

            <div class="benefits">
                <div class="benefit">
                    <strong>🏓 Early Access</strong><br>
                    Be the first to know about court bookings and new facilities
                </div>
                <div class="benefit">
                    <strong>🎉 Exclusive Events</strong><br>
                    VIP invitations to tournaments, clinics, and social gatherings
                </div>
                <div class="benefit">
                    <strong>💡 Pro Tips & Insights</strong><br>
                    Expert advice to improve your game from our coaches
                </div>
                <div class="benefit">
                    <strong>🎁 Special Offers</strong><br>
                    Member-only discounts on bookings, gear, and programs
                </div>
            </div>

            <p>We''re working hard to create the ultimate pickleball destination, and we can''t wait to share our progress with you!</p>

            <center>
                <a href="{{site_url}}" class="button">Visit The Dink House</a>
            </center>

            <p style="margin-top: 40px; font-size: 14px; color: #666;">
                PS: Keep an eye on your inbox - we have some exciting announcements coming soon!
            </p>

            <p><strong>See you soon,<br>The Dink House Team</strong></p>
        </div>
        <div class="footer">
            <p>The Dink House - Where Pickleball Lives</p>
            <p style="font-size: 12px; margin-top: 20px; color: #999;">
                You''re receiving this because you subscribed to our newsletter at {{site_url}}
            </p>
        </div>
    </div>
</body>
</html>',
    'Hi {{first_name}},

Thank you for subscribing to The Dink House newsletter! You''re now part of an exclusive community of pickleball enthusiasts.

You''ll be the first to know about:
🏓 Early Access - Court bookings and new facilities
🎉 Exclusive Events - Tournaments, clinics, and social gatherings
💡 Pro Tips - Expert advice from our coaches
🎁 Special Offers - Member-only discounts

We''re working hard to create the ultimate pickleball destination, and we can''t wait to share our progress with you!

Visit us at: {{site_url}}

See you soon,
The Dink House Team

--
The Dink House - Where Pickleball Lives
You''re receiving this because you subscribed to our newsletter.',
    'newsletter',
    '["first_name", "email", "site_url", "logo_url"]'::jsonb
),
(
    'contribution_thank_you',
    'Contribution Thank You with Receipt',
    'Thank You for Your Contribution to The Dink House! 🎉',
    '<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; line-height: 1.6; color: #333; margin: 0; padding: 0; background-color: #f5f5f5; }
        .container { max-width: 650px; margin: 0 auto; background-color: #ffffff; }
        .header { background: linear-gradient(135deg, #B3FF00 0%, #9BCF00 100%); padding: 40px 30px; text-align: center; }
        .logo { max-width: 200px; height: auto; margin-bottom: 15px; }
        .header h1 { color: #1a1a1a; margin: 0; font-size: 28px; font-weight: 700; }
        .content { padding: 40px 35px; }
        .greeting { font-size: 18px; margin-bottom: 20px; }

        .section { margin: 30px 0; padding: 25px; background: #f9f9f9; border-radius: 8px; border-left: 4px solid #B3FF00; }
        .section-title { font-size: 20px; font-weight: 700; color: #1a1a1a; margin: 0 0 15px 0; display: flex; align-items: center; }
        .section-title .icon { margin-right: 10px; font-size: 24px; }

        .receipt-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 15px; margin-top: 15px; }
        .receipt-item { }
        .receipt-label { font-size: 12px; text-transform: uppercase; color: #666; font-weight: 600; letter-spacing: 0.5px; margin-bottom: 5px; }
        .receipt-value { font-size: 16px; color: #1a1a1a; font-weight: 600; }
        .receipt-value.amount { font-size: 24px; color: #B3FF00; text-shadow: 1px 1px 2px rgba(0,0,0,0.1); background: linear-gradient(135deg, #B3FF00 0%, #9BCF00 100%); -webkit-background-clip: text; -webkit-text-fill-color: transparent; background-clip: text; }

        .benefits-list { margin-top: 15px; }
        .benefit-item { background: white; padding: 15px; margin: 10px 0; border-radius: 6px; border: 1px solid #e0e0e0; display: flex; align-items: start; }
        .benefit-item .checkmark { color: #B3FF00; font-size: 20px; margin-right: 12px; font-weight: bold; flex-shrink: 0; }
        .benefit-content { flex: 1; }
        .benefit-name { font-weight: 600; color: #1a1a1a; font-size: 15px; margin-bottom: 3px; }
        .benefit-details { font-size: 13px; color: #666; }
        .benefit-quantity { display: inline-block; background: #B3FF00; color: #1a1a1a; padding: 2px 8px; border-radius: 12px; font-size: 12px; font-weight: 600; margin-left: 8px; }

        .recognition-box { background: linear-gradient(135deg, #B3FF00 0%, #9BCF00 100%); padding: 20px; border-radius: 8px; text-align: center; margin: 20px 0; }
        .recognition-box h3 { margin: 0 0 10px 0; color: #1a1a1a; font-size: 18px; }
        .recognition-box p { margin: 0; color: #1a1a1a; font-size: 14px; }

        .cta-box { text-align: center; margin: 30px 0; }
        .button { display: inline-block; background: #B3FF00; color: #1a1a1a; padding: 14px 32px; text-decoration: none; border-radius: 6px; font-weight: 700; font-size: 16px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }
        .button:hover { background: #9BCF00; }

        .help-text { background: #f0f0f0; padding: 20px; border-radius: 6px; margin: 25px 0; font-size: 14px; color: #666; }

        .footer { background: #1a1a1a; color: #ffffff; padding: 30px 35px; text-align: center; font-size: 14px; }
        .footer a { color: #B3FF00; text-decoration: none; }
        .footer .social-links { margin: 15px 0; }
        .footer .contact { margin-top: 20px; font-size: 13px; color: #999; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <img src="https://wchxzbuuwssrnaxshseu.supabase.co/storage/v1/object/public/dink-files/dinklogo.jpg" alt="The Dink House" class="logo" />
            <h1>Thank You for Your Contribution!</h1>
        </div>

        <div class="content">
            <p class="greeting">Hi {{first_name}},</p>

            <p style="font-size: 16px; line-height: 1.8;">
                🎉 <strong>Wow!</strong> We are absolutely thrilled and grateful for your generous contribution to The Dink House.
                You''re not just supporting a pickleball facility—you''re helping build a community where players of all levels can thrive, learn, and connect.
            </p>

            <!-- Receipt Section -->
            <div class="section">
                <h2 class="section-title">
                    <span class="icon">📄</span>
                    Your Receipt
                </h2>
                <div class="receipt-grid">
                    <div class="receipt-item">
                        <div class="receipt-label">Contribution Amount</div>
                        <div class="receipt-value amount">${{amount}}</div>
                    </div>
                    <div class="receipt-item">
                        <div class="receipt-label">Contribution Tier</div>
                        <div class="receipt-value">{{tier_name}}</div>
                    </div>
                    <div class="receipt-item">
                        <div class="receipt-label">Date</div>
                        <div class="receipt-value">{{contribution_date}}</div>
                    </div>
                    <div class="receipt-item">
                        <div class="receipt-label">Transaction ID</div>
                        <div class="receipt-value" style="font-size: 13px;">{{contribution_id}}</div>
                    </div>
                    <div class="receipt-item">
                        <div class="receipt-label">Payment Method</div>
                        <div class="receipt-value">{{payment_method}}</div>
                    </div>
                    <div class="receipt-item">
                        <div class="receipt-label">Stripe Charge ID</div>
                        <div class="receipt-value" style="font-size: 12px;">{{stripe_charge_id}}</div>
                    </div>
                </div>
            </div>

            <!-- Rewards Section -->
            <div class="section">
                <h2 class="section-title">
                    <span class="icon">🎁</span>
                    Your Rewards & Benefits
                </h2>
                <p style="margin-top: 0; color: #666;">As a valued contributor, you''re receiving the following benefits:</p>
                <div class="benefits-list">
                    {{benefits_html}}
                </div>
            </div>

            <!-- Founders Wall Recognition -->
            {{#if on_founders_wall}}
            <div class="recognition-box">
                <h3>🌟 You''re on the Founders Wall!</h3>
                <p>Your name will be displayed as: <strong>{{display_name}}</strong></p>
                <p style="margin-top: 8px;">{{founders_wall_message}}</p>
            </div>
            {{/if}}

            <!-- Next Steps -->
            <div class="help-text">
                <strong>📋 Next Steps:</strong><br>
                • Keep this email for your records - it serves as your official receipt<br>
                • Benefits will be available once The Dink House opens<br>
                • Watch your email for facility updates and opening announcements<br>
                • Questions? Reply to this email or call us at (254) 123-4567
            </div>

            <div class="cta-box">
                <a href="{{site_url}}" class="button">Visit The Dink House</a>
            </div>

            <p style="font-size: 16px; margin-top: 40px;">
                Your support means the world to us. Together, we''re creating something special for the pickleball community in Bell County!
            </p>

            <p style="font-size: 16px; font-weight: 600;">
                With gratitude,<br>
                The Dink House Team
            </p>
        </div>

        <div class="footer">
            <p><strong>The Dink House</strong> - Where Pickleball Lives</p>
            <div class="social-links">
                <a href="#">Facebook</a> | <a href="#">Instagram</a> | <a href="#">Twitter</a>
            </div>
            <div class="contact">
                Questions? Contact us at support@thedinkhouse.com or (254) 123-4567<br>
                <span style="font-size: 11px; margin-top: 10px; display: block;">
                    This is a receipt for your contribution. Please keep for your records.<br>
                    The Dink House is a project of [Organization Name]. Contributions may be tax-deductible - consult your tax advisor.
                </span>
            </div>
        </div>
    </div>
</body>
</html>',
    'Hi {{first_name}},

🎉 THANK YOU FOR YOUR CONTRIBUTION! 🎉

We are absolutely thrilled and grateful for your generous contribution to The Dink House. You''re not just supporting a pickleball facility—you''re helping build a community where players of all levels can thrive, learn, and connect.

=====================================
YOUR RECEIPT
=====================================

Contribution Amount: ${{amount}}
Contribution Tier: {{tier_name}}
Date: {{contribution_date}}
Transaction ID: {{contribution_id}}
Payment Method: {{payment_method}}
Stripe Charge ID: {{stripe_charge_id}}

=====================================
YOUR REWARDS & BENEFITS
=====================================

As a valued contributor, you''re receiving:

{{benefits_text}}

{{#if on_founders_wall}}
=====================================
🌟 FOUNDERS WALL RECOGNITION
=====================================

Your name will be displayed as: {{display_name}}
{{founders_wall_message}}
{{/if}}

=====================================
NEXT STEPS
=====================================

• Keep this email for your records - it serves as your official receipt
• Benefits will be available once The Dink House opens
• Watch your email for facility updates and opening announcements
• Questions? Reply to this email or call us at (254) 123-4567

Visit us at: {{site_url}}

Your support means the world to us. Together, we''re creating something special for the pickleball community in Bell County!

With gratitude,
The Dink House Team

--
The Dink House - Where Pickleball Lives
Questions? Contact us at support@thedinkhouse.com or (254) 123-4567

This is a receipt for your contribution. Please keep for your records.
The Dink House is a project of [Organization Name]. Contributions may be tax-deductible - consult your tax advisor.',
    'crowdfunding',
    '["first_name", "amount", "tier_name", "contribution_date", "contribution_id", "payment_method", "stripe_charge_id", "benefits_html", "benefits_text", "on_founders_wall", "display_name", "founders_wall_message", "site_url"]'::jsonb
)
ON CONFLICT (template_key) DO UPDATE SET
    subject = EXCLUDED.subject,
    html_body = EXCLUDED.html_body,
    text_body = EXCLUDED.text_body,
    variables = EXCLUDED.variables,
    updated_at = CURRENT_TIMESTAMP;

-- Function to log emails
CREATE OR REPLACE FUNCTION system.log_email(
    p_template_key VARCHAR(100),
    p_to_email TEXT,
    p_from_email TEXT,
    p_subject VARCHAR(255),
    p_status VARCHAR(50),
    p_metadata JSONB DEFAULT '{}'
) RETURNS UUID AS $$
DECLARE
    v_log_id UUID;
BEGIN
    INSERT INTO system.email_logs (
        template_key,
        to_email,
        from_email,
        subject,
        status,
        metadata,
        sent_at
    ) VALUES (
        p_template_key,
        p_to_email,
        p_from_email,
        p_subject,
        p_status,
        p_metadata,
        CASE WHEN p_status = 'sent' THEN CURRENT_TIMESTAMP ELSE NULL END
    ) RETURNING id INTO v_log_id;

    RETURN v_log_id;
END;
$$ LANGUAGE plpgsql;

-- Grant permissions
-- Note: Supabase Cloud uses different role names (authenticator, authenticated, service_role, etc.)
-- Adjust these grants based on your Supabase project's role configuration if needed
-- GRANT USAGE ON SCHEMA system TO authenticated, service_role;
-- GRANT SELECT ON system.email_templates TO authenticated, service_role;
-- GRANT ALL ON system.email_logs TO service_role;
-- GRANT EXECUTE ON FUNCTION system.log_email TO authenticated, service_role;-- ============================================================================
-- EVENTS MODULE
-- Calendar event management for pickleball sessions
-- ============================================================================

-- Drop schema if exists for clean rebuilds
DROP SCHEMA IF EXISTS events CASCADE;

-- Create events schema
CREATE SCHEMA events AUTHORIZATION postgres;
COMMENT ON SCHEMA events IS 'Calendar event management and court scheduling';

-- Grant usage on schema
GRANT USAGE ON SCHEMA events TO postgres;
GRANT CREATE ON SCHEMA events TO postgres;
GRANT USAGE ON SCHEMA events TO service_role;
GRANT USAGE ON SCHEMA events TO authenticated;
GRANT USAGE ON SCHEMA events TO anon;

-- ============================================================================
-- ENUMS AND TYPES
-- ============================================================================

CREATE TYPE events.event_type AS ENUM (
    'event_scramble',
    'dupr_open_play',
    'dupr_tournament',
    'non_dupr_tournament',
    'league',
    'clinic',
    'private_booking'
);

CREATE TYPE events.court_surface AS ENUM (
    'hard',
    'clay',
    'grass',
    'indoor'
);

CREATE TYPE events.court_environment AS ENUM (
    'indoor',
    'outdoor'
);

CREATE TYPE events.court_status AS ENUM (
    'available',
    'maintenance',
    'reserved',
    'closed'
);

CREATE TYPE events.skill_level AS ENUM (
    '2.0', '2.5', '3.0', '3.5', '4.0', '4.5', '5.0', '5.0+'
);

CREATE TYPE events.recurrence_frequency AS ENUM (
    'daily',
    'weekly',
    'biweekly',
    'monthly',
    'custom'
);

CREATE TYPE events.registration_status AS ENUM (
    'registered',
    'waitlisted',
    'cancelled',
    'no_show'
);

-- ============================================================================
-- COURTS TABLE
-- ============================================================================

CREATE TABLE events.courts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    court_number INTEGER NOT NULL UNIQUE,
    name VARCHAR(100) NOT NULL,
    surface_type events.court_surface DEFAULT 'hard',
    environment events.court_environment NOT NULL DEFAULT 'indoor',
    status events.court_status DEFAULT 'available',
    location VARCHAR(100),
    features JSONB DEFAULT '[]'::jsonb, -- lights, covered, etc.
    max_capacity INTEGER DEFAULT 4,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE events.courts IS 'Physical courts available for booking';

-- Create indexes
CREATE INDEX idx_courts_status ON events.courts(status);
CREATE INDEX idx_courts_number ON events.courts(court_number);
CREATE INDEX idx_courts_environment ON events.courts(environment);

-- ============================================================================
-- DUPR BRACKETS TABLE
-- ============================================================================

CREATE TABLE events.dupr_brackets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    label VARCHAR(100) NOT NULL UNIQUE,
    min_rating NUMERIC(3, 2),
    min_inclusive BOOLEAN DEFAULT true,
    max_rating NUMERIC(3, 2),
    max_inclusive BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT dupr_bracket_presence CHECK (
        min_rating IS NOT NULL OR max_rating IS NOT NULL
    ),
    CONSTRAINT dupr_bracket_bounds CHECK (
        max_rating IS NULL OR min_rating IS NULL OR max_rating >= min_rating
    )
);

COMMENT ON TABLE events.dupr_brackets IS 'Standard DUPR rating brackets available for event configuration';

-- Create indexes
CREATE INDEX idx_dupr_brackets_min_rating ON events.dupr_brackets(min_rating);
CREATE INDEX idx_dupr_brackets_max_rating ON events.dupr_brackets(max_rating);

GRANT SELECT ON events.dupr_brackets TO service_role;
GRANT SELECT ON events.dupr_brackets TO authenticated;

-- ============================================================================
-- EVENT TEMPLATES TABLE
-- ============================================================================

CREATE TABLE events.event_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(200) NOT NULL,
    description TEXT,
    event_type events.event_type NOT NULL,
    duration_minutes INTEGER NOT NULL DEFAULT 120,
    max_capacity INTEGER DEFAULT 16,
    min_capacity INTEGER DEFAULT 4,
    skill_levels events.skill_level[] DEFAULT ARRAY['2.0', '2.5', '3.0', '3.5', '4.0', '4.5', '5.0']::events.skill_level[],
    price_member DECIMAL(10, 2) DEFAULT 0,
    price_guest DECIMAL(10, 2) DEFAULT 0,
    court_preferences JSONB DEFAULT '{"count": 2}'::jsonb,
    dupr_bracket_id UUID REFERENCES events.dupr_brackets(id),
    dupr_range_label VARCHAR(100),
    dupr_min_rating NUMERIC(3, 2),
    dupr_max_rating NUMERIC(3, 2),
    dupr_open_ended BOOLEAN DEFAULT false,
    dupr_min_inclusive BOOLEAN DEFAULT true,
    dupr_max_inclusive BOOLEAN DEFAULT true,
    equipment_provided BOOLEAN DEFAULT false,
    settings JSONB DEFAULT '{}'::jsonb,
    is_active BOOLEAN DEFAULT true,
    created_by UUID REFERENCES app_auth.admin_users(id),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT template_dupr_fields CHECK (
        CASE WHEN event_type IN ('dupr_open_play', 'dupr_tournament') THEN
            (
                (dupr_bracket_id IS NOT NULL)
                OR (dupr_range_label IS NOT NULL AND dupr_min_rating IS NOT NULL)
            )
            AND (dupr_open_ended = true OR dupr_max_rating IS NOT NULL)
        ELSE
            dupr_bracket_id IS NULL
            AND dupr_range_label IS NULL
            AND dupr_min_rating IS NULL
            AND dupr_max_rating IS NULL
            AND dupr_open_ended = false
            AND dupr_min_inclusive = true
            AND dupr_max_inclusive = true
        END
    ),
    CONSTRAINT template_dupr_bounds CHECK (
        dupr_max_rating IS NULL OR dupr_min_rating IS NULL OR dupr_max_rating >= dupr_min_rating
    ),
    CONSTRAINT template_dupr_open_ended CHECK (
        dupr_open_ended = false OR dupr_max_rating IS NULL
    )
);

COMMENT ON TABLE events.event_templates IS 'Reusable event configurations';

-- Create indexes
CREATE INDEX idx_event_templates_active ON events.event_templates(is_active);
CREATE INDEX idx_event_templates_type ON events.event_templates(event_type);
CREATE INDEX idx_event_templates_dupr_bracket ON events.event_templates(dupr_bracket_id);

-- ============================================================================
-- EVENTS TABLE
-- ============================================================================

CREATE TABLE events.events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title VARCHAR(200) NOT NULL,
    description TEXT,
    event_type events.event_type NOT NULL,
    template_id UUID REFERENCES events.event_templates(id) ON DELETE SET NULL,

    -- Scheduling
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    check_in_time TIMESTAMPTZ,

    -- Capacity
    max_capacity INTEGER DEFAULT 16,
    min_capacity INTEGER DEFAULT 4,
    current_registrations INTEGER DEFAULT 0,
    waitlist_capacity INTEGER DEFAULT 5,

    -- Requirements
    skill_levels events.skill_level[] DEFAULT ARRAY['2.0', '2.5', '3.0', '3.5', '4.0', '4.5', '5.0']::events.skill_level[],
    dupr_bracket_id UUID REFERENCES events.dupr_brackets(id),
    dupr_range_label VARCHAR(100),
    dupr_min_rating NUMERIC(3, 2),
    dupr_max_rating NUMERIC(3, 2),
    dupr_open_ended BOOLEAN DEFAULT false,
    dupr_min_inclusive BOOLEAN DEFAULT true,
    dupr_max_inclusive BOOLEAN DEFAULT true,
    member_only BOOLEAN DEFAULT false,

    -- Pricing
    price_member DECIMAL(10, 2) DEFAULT 0,
    price_guest DECIMAL(10, 2) DEFAULT 0,

    -- Status
    is_published BOOLEAN DEFAULT true,
    is_cancelled BOOLEAN DEFAULT false,
    cancellation_reason TEXT,

    -- Metadata
    equipment_provided BOOLEAN DEFAULT false,
    special_instructions TEXT,
    settings JSONB DEFAULT '{}'::jsonb,

    -- Tracking
    created_by UUID REFERENCES app_auth.admin_users(id),
    updated_by UUID REFERENCES app_auth.admin_users(id),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
    CONSTRAINT valid_time_range CHECK (end_time > start_time),
    CONSTRAINT valid_capacity CHECK (max_capacity >= min_capacity),
    CONSTRAINT valid_registrations CHECK (current_registrations >= 0),
    CONSTRAINT dupr_fields_required CHECK (
        CASE WHEN event_type IN ('dupr_open_play', 'dupr_tournament') THEN
            (
                (dupr_bracket_id IS NOT NULL)
                OR (dupr_range_label IS NOT NULL AND dupr_min_rating IS NOT NULL)
            )
            AND (dupr_open_ended = true OR dupr_max_rating IS NOT NULL)
        ELSE
            dupr_bracket_id IS NULL
            AND dupr_range_label IS NULL
            AND dupr_min_rating IS NULL
            AND dupr_max_rating IS NULL
            AND dupr_open_ended = false
            AND dupr_min_inclusive = true
            AND dupr_max_inclusive = true
        END
    ),
    CONSTRAINT dupr_bounds CHECK (
        dupr_max_rating IS NULL OR dupr_min_rating IS NULL OR dupr_max_rating >= dupr_min_rating
    ),
    CONSTRAINT dupr_open_ended CHECK (
        dupr_open_ended = false OR dupr_max_rating IS NULL
    )
);

COMMENT ON TABLE events.events IS 'Calendar events and sessions';

-- Create indexes
CREATE INDEX idx_events_start_time ON events.events(start_time);
CREATE INDEX idx_events_end_time ON events.events(end_time);
CREATE INDEX idx_events_type ON events.events(event_type);
CREATE INDEX idx_events_published ON events.events(is_published);
CREATE INDEX idx_events_cancelled ON events.events(is_cancelled);
CREATE INDEX idx_events_date_range ON events.events(start_time, end_time);
CREATE INDEX idx_events_dupr_bracket ON events.events(dupr_bracket_id);

-- ============================================================================
-- EVENT COURTS TABLE (Many-to-Many)
-- ============================================================================

CREATE TABLE events.event_courts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL REFERENCES events.events(id) ON DELETE CASCADE,
    court_id UUID NOT NULL REFERENCES events.courts(id) ON DELETE CASCADE,
    is_primary BOOLEAN DEFAULT false,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT unique_event_court UNIQUE(event_id, court_id)
);

COMMENT ON TABLE events.event_courts IS 'Courts assigned to events';

-- Create indexes
CREATE INDEX idx_event_courts_event ON events.event_courts(event_id);
CREATE INDEX idx_event_courts_court ON events.event_courts(court_id);

-- Composite index for time-based court availability queries
CREATE INDEX idx_event_courts_time_range ON events.event_courts(court_id, event_id)
    INCLUDE (is_primary);

-- Additional index to optimize court booking conflict detection
CREATE INDEX idx_events_time_overlap ON events.events(start_time, end_time)
    WHERE is_cancelled = false;

-- ============================================================================
-- RECURRENCE PATTERNS TABLE
-- ============================================================================

CREATE TABLE events.recurrence_patterns (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL REFERENCES events.events(id) ON DELETE CASCADE,
    frequency events.recurrence_frequency NOT NULL,
    interval_count INTEGER DEFAULT 1, -- every N days/weeks/months

    -- Weekly options
    days_of_week INTEGER[], -- 0=Sunday, 6=Saturday

    -- Monthly options
    day_of_month INTEGER, -- 1-31
    week_of_month INTEGER, -- 1-5 (5=last)

    -- Series info
    series_start_date DATE NOT NULL,
    series_end_date DATE,
    occurrences_count INTEGER,

    -- Metadata
    timezone VARCHAR(100) DEFAULT 'America/New_York',
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE events.recurrence_patterns IS 'Recurring event patterns';

-- Create indexes
CREATE INDEX idx_recurrence_event ON events.recurrence_patterns(event_id);
CREATE INDEX idx_recurrence_dates ON events.recurrence_patterns(series_start_date, series_end_date);

-- ============================================================================
-- EVENT SERIES TABLE
-- ============================================================================

CREATE TABLE events.event_series (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    series_name VARCHAR(200) NOT NULL,
    parent_event_id UUID REFERENCES events.events(id) ON DELETE SET NULL,
    recurrence_pattern_id UUID REFERENCES events.recurrence_patterns(id) ON DELETE CASCADE,
    created_by UUID REFERENCES app_auth.admin_users(id),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE events.event_series IS 'Groups of recurring events';

-- ============================================================================
-- EVENT SERIES INSTANCES TABLE
-- ============================================================================

CREATE TABLE events.event_series_instances (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    series_id UUID NOT NULL REFERENCES events.event_series(id) ON DELETE CASCADE,
    event_id UUID NOT NULL REFERENCES events.events(id) ON DELETE CASCADE,
    original_start_time TIMESTAMPTZ NOT NULL,
    is_exception BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT unique_series_event UNIQUE(series_id, event_id)
);

COMMENT ON TABLE events.event_series_instances IS 'Individual instances of recurring events';

-- Create indexes
CREATE INDEX idx_series_instances_series ON events.event_series_instances(series_id);
CREATE INDEX idx_series_instances_event ON events.event_series_instances(event_id);

-- ============================================================================
-- EVENT EXCEPTIONS TABLE
-- ============================================================================

CREATE TABLE events.event_exceptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recurrence_pattern_id UUID NOT NULL REFERENCES events.recurrence_patterns(id) ON DELETE CASCADE,
    exception_date DATE NOT NULL,
    reason TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT unique_pattern_exception UNIQUE(recurrence_pattern_id, exception_date)
);

COMMENT ON TABLE events.event_exceptions IS 'Dates to skip in recurring patterns';

-- Create indexes
CREATE INDEX idx_exceptions_pattern ON events.event_exceptions(recurrence_pattern_id);
CREATE INDEX idx_exceptions_date ON events.event_exceptions(exception_date);

-- ============================================================================
-- EVENT REGISTRATIONS TABLE
-- ============================================================================

CREATE TABLE events.event_registrations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL REFERENCES events.events(id) ON DELETE CASCADE,
    user_id UUID REFERENCES app_auth.players(id) ON DELETE SET NULL,

    -- Player info (for guests)
    player_name VARCHAR(200),
    player_email VARCHAR(255),
    player_phone VARCHAR(50),
    skill_level events.skill_level,
    dupr_rating NUMERIC(3, 2),

    -- Registration details
    status events.registration_status DEFAULT 'registered',
    registration_time TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    check_in_time TIMESTAMPTZ,

    -- Payment
    amount_paid DECIMAL(10, 2) DEFAULT 0,
    payment_method VARCHAR(50),
    payment_reference VARCHAR(200),

    -- Notes
    notes TEXT,
    special_requests TEXT,

    -- Metadata
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT unique_event_user UNIQUE(event_id, user_id),
    CONSTRAINT player_info_required CHECK (
        user_id IS NOT NULL OR
        (player_name IS NOT NULL AND player_email IS NOT NULL)
    )
);

COMMENT ON TABLE events.event_registrations IS 'Player registrations for events';

-- Create indexes
CREATE INDEX idx_registrations_event ON events.event_registrations(event_id);
CREATE INDEX idx_registrations_user ON events.event_registrations(user_id);
CREATE INDEX idx_registrations_status ON events.event_registrations(status);
CREATE INDEX idx_registrations_time ON events.event_registrations(registration_time);

-- ============================================================================
-- COURT AVAILABILITY TABLE
-- ============================================================================

CREATE TABLE events.court_availability (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    court_id UUID NOT NULL REFERENCES events.courts(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    is_available BOOLEAN DEFAULT true,
    reason VARCHAR(200),
    created_by UUID REFERENCES app_auth.admin_users(id),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT valid_availability_time CHECK (end_time > start_time),
    CONSTRAINT unique_court_availability UNIQUE(court_id, date, start_time, end_time)
);

COMMENT ON TABLE events.court_availability IS 'Court availability schedule';

-- Create indexes
CREATE INDEX idx_availability_court ON events.court_availability(court_id);
CREATE INDEX idx_availability_date ON events.court_availability(date);
CREATE INDEX idx_availability_available ON events.court_availability(is_available);

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Update timestamp trigger
CREATE OR REPLACE FUNCTION events.update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply update trigger to relevant tables
CREATE TRIGGER update_courts_updated_at
    BEFORE UPDATE ON events.courts
    FOR EACH ROW EXECUTE FUNCTION events.update_updated_at();

CREATE TRIGGER update_dupr_brackets_updated_at
    BEFORE UPDATE ON events.dupr_brackets
    FOR EACH ROW EXECUTE FUNCTION events.update_updated_at();

CREATE TRIGGER update_templates_updated_at
    BEFORE UPDATE ON events.event_templates
    FOR EACH ROW EXECUTE FUNCTION events.update_updated_at();

CREATE TRIGGER update_events_updated_at
    BEFORE UPDATE ON events.events
    FOR EACH ROW EXECUTE FUNCTION events.update_updated_at();

CREATE TRIGGER update_registrations_updated_at
    BEFORE UPDATE ON events.event_registrations
    FOR EACH ROW EXECUTE FUNCTION events.update_updated_at();

-- Update registration count trigger
CREATE OR REPLACE FUNCTION events.update_registration_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' AND NEW.status = 'registered' THEN
        UPDATE events.events
        SET current_registrations = current_registrations + 1
        WHERE id = NEW.event_id;
    ELSIF TG_OP = 'DELETE' AND OLD.status = 'registered' THEN
        UPDATE events.events
        SET current_registrations = current_registrations - 1
        WHERE id = OLD.event_id;
    ELSIF TG_OP = 'UPDATE' THEN
        IF OLD.status = 'registered' AND NEW.status != 'registered' THEN
            UPDATE events.events
            SET current_registrations = current_registrations - 1
            WHERE id = NEW.event_id;
        ELSIF OLD.status != 'registered' AND NEW.status = 'registered' THEN
            UPDATE events.events
            SET current_registrations = current_registrations + 1
            WHERE id = NEW.event_id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_event_registration_count
    AFTER INSERT OR UPDATE OR DELETE ON events.event_registrations
    FOR EACH ROW EXECUTE FUNCTION events.update_registration_count();
-- ============================================================================
-- STORAGE SETUP MODULE
-- Creates storage buckets for email assets and other media
-- ============================================================================

-- Note: This SQL creates the storage policies.
-- The actual bucket creation needs to be done via Supabase dashboard or CLI

-- Create storage schema if not exists
CREATE SCHEMA IF NOT EXISTS storage;

-- Storage bucket policies for email-assets
DO $$
BEGIN
    -- Check if storage.buckets table exists (Supabase environment)
    IF EXISTS (
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = 'storage'
        AND table_name = 'buckets'
    ) THEN
        -- Insert email-assets bucket if not exists
        INSERT INTO storage.buckets (id, name, public, avif_autodetection, file_size_limit, allowed_mime_types)
        VALUES (
            'email-assets',
            'email-assets',
            true,  -- Public bucket for email images
            false,
            5242880,  -- 5MB limit
            ARRAY['image/jpeg', 'image/png', 'image/gif', 'image/svg+xml', 'image/webp']
        )
        ON CONFLICT (id) DO NOTHING;

        -- Insert general media bucket if not exists
        INSERT INTO storage.buckets (id, name, public, avif_autodetection, file_size_limit, allowed_mime_types)
        VALUES (
            'media',
            'media',
            true,  -- Public bucket for general media
            false,
            52428800,  -- 50MB limit
            ARRAY['image/jpeg', 'image/png', 'image/gif', 'image/svg+xml', 'image/webp', 'video/mp4', 'video/quicktime', 'application/pdf']
        )
        ON CONFLICT (id) DO NOTHING;
    END IF;
END $$;

-- Create RLS policies for storage (if in Supabase environment)
DO $$
BEGIN
    -- Check if storage.objects table exists
    IF EXISTS (
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = 'storage'
        AND table_name = 'objects'
    ) THEN
        -- Drop existing policies if they exist
        DROP POLICY IF EXISTS "Email assets are publicly accessible" ON storage.objects;
        DROP POLICY IF EXISTS "Admins can upload email assets" ON storage.objects;
        DROP POLICY IF EXISTS "Admins can update email assets" ON storage.objects;
        DROP POLICY IF EXISTS "Admins can delete email assets" ON storage.objects;

        -- Public read access for email-assets bucket
        CREATE POLICY "Email assets are publicly accessible"
        ON storage.objects FOR SELECT
        USING (bucket_id = 'email-assets');

        -- Admin upload access for email-assets bucket
        CREATE POLICY "Admins can upload email assets"
        ON storage.objects FOR INSERT
        WITH CHECK (
            bucket_id = 'email-assets'
            AND auth.role() IN ('app_admin', 'app_service')
        );

        -- Admin update access for email-assets bucket
        CREATE POLICY "Admins can update email assets"
        ON storage.objects FOR UPDATE
        USING (
            bucket_id = 'email-assets'
            AND auth.role() IN ('app_admin', 'app_service')
        );

        -- Admin delete access for email-assets bucket
        CREATE POLICY "Admins can delete email assets"
        ON storage.objects FOR DELETE
        USING (
            bucket_id = 'email-assets'
            AND auth.role() IN ('app_admin', 'app_service')
        );
    END IF;
END $$;

-- Create a tracking table for uploaded assets
CREATE TABLE IF NOT EXISTS system.uploaded_assets (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    bucket_id VARCHAR(255) NOT NULL,
    object_path TEXT NOT NULL,
    filename VARCHAR(255) NOT NULL,
    content_type VARCHAR(100),
    size_bytes BIGINT,
    public_url TEXT,
    metadata JSONB DEFAULT '{}',
    uploaded_by UUID REFERENCES app_auth.admin_users(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(bucket_id, object_path)
);

-- Create index for asset lookups
CREATE INDEX uploaded_assets_bucket_path ON system.uploaded_assets(bucket_id, object_path);

-- Function to track uploaded assets
CREATE OR REPLACE FUNCTION system.track_uploaded_asset(
    p_bucket_id VARCHAR(255),
    p_object_path TEXT,
    p_filename VARCHAR(255),
    p_content_type VARCHAR(100),
    p_size_bytes BIGINT,
    p_public_url TEXT,
    p_metadata JSONB DEFAULT '{}'
) RETURNS UUID AS $$
DECLARE
    v_asset_id UUID;
BEGIN
    INSERT INTO system.uploaded_assets (
        bucket_id,
        object_path,
        filename,
        content_type,
        size_bytes,
        public_url,
        metadata
    ) VALUES (
        p_bucket_id,
        p_object_path,
        p_filename,
        p_content_type,
        p_size_bytes,
        p_public_url,
        p_metadata
    )
    ON CONFLICT (bucket_id, object_path)
    DO UPDATE SET
        filename = EXCLUDED.filename,
        content_type = EXCLUDED.content_type,
        size_bytes = EXCLUDED.size_bytes,
        public_url = EXCLUDED.public_url,
        metadata = EXCLUDED.metadata,
        created_at = CURRENT_TIMESTAMP
    RETURNING id INTO v_asset_id;

    RETURN v_asset_id;
END;
$$ LANGUAGE plpgsql;

-- Insert default logo reference
INSERT INTO system.uploaded_assets (bucket_id, object_path, filename, content_type, public_url, metadata)
VALUES (
    'email-assets',
    'dink-house-logo.png',
    'dink-house-logo.png',
    'image/png',
    '{{SUPABASE_URL}}/storage/v1/object/public/email-assets/dink-house-logo.png',
    '{"description": "The Dink House official logo for emails", "dimensions": "300x100"}'::jsonb
)
ON CONFLICT (bucket_id, object_path) DO NOTHING;-- ============================================================================
-- EVENTS API VIEWS MODULE
-- API views for the events system
-- ============================================================================

-- ============================================================================
-- CALENDAR VIEW
-- Main view for displaying events on the calendar
-- ============================================================================

CREATE OR REPLACE VIEW api.events_calendar_view AS
SELECT
    e.id,
    e.title,
    e.description,
    e.event_type,
    e.start_time,
    e.end_time,
    e.check_in_time,
    e.max_capacity,
    e.min_capacity,
    e.current_registrations,
    e.waitlist_capacity,
    e.skill_levels,
    e.member_only,
    e.price_member,
    e.price_guest,
    e.is_published,
    e.is_cancelled,
    e.cancellation_reason,
    e.equipment_provided,
    e.special_instructions,
    e.dupr_bracket_id,
    e.dupr_range_label,
    e.dupr_min_rating,
    e.dupr_max_rating,
    e.dupr_open_ended,
    e.dupr_min_inclusive,
    e.dupr_max_inclusive,
    CASE
        WHEN e.event_type IN ('dupr_open_play', 'dupr_tournament') THEN
            jsonb_build_object(
                'source', CASE WHEN e.dupr_bracket_id IS NOT NULL THEN 'catalog' ELSE 'custom' END,
                'label', COALESCE(e.dupr_range_label, db.label),
                'min_rating', COALESCE(db.min_rating, e.dupr_min_rating),
                'max_rating', COALESCE(db.max_rating, e.dupr_max_rating),
                'min_inclusive', COALESCE(db.min_inclusive, e.dupr_min_inclusive),
                'max_inclusive', COALESCE(db.max_inclusive, e.dupr_max_inclusive),
                'open_ended', CASE
                    WHEN e.dupr_bracket_id IS NOT NULL THEN (db.max_rating IS NULL)
                    ELSE e.dupr_open_ended
                END
            )
        ELSE NULL
    END AS dupr_range,

    -- Template info
    et.name AS template_name,

    -- Court information
    COALESCE(
        json_agg(
            json_build_object(
                'id', c.id,
                'court_number', c.court_number,
                'name', c.name,
                'surface_type', c.surface_type,
                'environment', c.environment,
                'is_primary', ec.is_primary
            ) ORDER BY ec.is_primary DESC, c.court_number
        ) FILTER (WHERE c.id IS NOT NULL),
        '[]'::json
    ) AS courts,

    -- Registration status
    CASE
        WHEN e.current_registrations >= e.max_capacity THEN 'full'
        WHEN e.current_registrations >= e.max_capacity * 0.8 THEN 'almost_full'
        WHEN e.current_registrations < e.min_capacity THEN 'needs_players'
        ELSE 'open'
    END AS registration_status,

    -- Series information
    esi.series_id,
    es.series_name,
    rp.frequency AS recurrence_frequency,

    -- Metadata
    e.created_by,
    e.created_at,
    e.updated_at
FROM
    events.events e
    LEFT JOIN events.event_templates et ON e.template_id = et.id
    LEFT JOIN events.event_courts ec ON e.id = ec.event_id
    LEFT JOIN events.courts c ON ec.court_id = c.id
    LEFT JOIN events.event_series_instances esi ON e.id = esi.event_id
    LEFT JOIN events.event_series es ON esi.series_id = es.id
    LEFT JOIN events.recurrence_patterns rp ON es.recurrence_pattern_id = rp.id
    LEFT JOIN events.dupr_brackets db ON e.dupr_bracket_id = db.id
GROUP BY
    e.id, et.name, esi.series_id, es.series_name, rp.frequency, db.label, db.min_rating, db.max_rating, db.min_inclusive, db.max_inclusive;

COMMENT ON VIEW api.events_calendar_view IS 'Main calendar view with event details and court assignments';

-- ============================================================================
-- COURT AVAILABILITY VIEW
-- Shows court availability for scheduling
-- ============================================================================

CREATE OR REPLACE VIEW api.court_availability_view AS
WITH court_bookings AS (
    SELECT
        ec.court_id,
        e.start_time,
        e.end_time,
        e.title AS event_title,
        e.event_type
    FROM
        events.event_courts ec
        INNER JOIN events.events e ON ec.event_id = e.id
    WHERE
        e.is_cancelled = false
)
SELECT
    c.id,
    c.court_number,
    c.name,
    c.surface_type,
    c.environment,
    c.status,
    c.location,
    c.features,
    c.max_capacity,

    -- Current bookings
    COALESCE(
        json_agg(
            json_build_object(
                'start_time', cb.start_time,
                'end_time', cb.end_time,
                'event_title', cb.event_title,
                'event_type', cb.event_type
            ) ORDER BY cb.start_time
        ) FILTER (WHERE cb.court_id IS NOT NULL),
        '[]'::json
    ) AS bookings,

    -- Availability overrides
    COALESCE(
        json_agg(
            json_build_object(
                'date', ca.date,
                'start_time', ca.start_time,
                'end_time', ca.end_time,
                'is_available', ca.is_available,
                'reason', ca.reason
            ) ORDER BY ca.date, ca.start_time
        ) FILTER (WHERE ca.court_id IS NOT NULL),
        '[]'::json
    ) AS availability_schedule
FROM
    events.courts c
    LEFT JOIN court_bookings cb ON c.id = cb.court_id
    LEFT JOIN events.court_availability ca ON c.id = ca.court_id
GROUP BY
    c.id;

COMMENT ON VIEW api.court_availability_view IS 'Court availability with current bookings';

-- ============================================================================
-- EVENT TEMPLATES VIEW
-- Available templates for quick event creation
-- ============================================================================

CREATE OR REPLACE VIEW api.event_templates_view AS
SELECT
    et.id,
    et.name,
    et.description,
    et.event_type,
    et.duration_minutes,
    et.max_capacity,
    et.min_capacity,
    et.skill_levels,
    et.price_member,
    et.price_guest,
    et.court_preferences,
    et.dupr_bracket_id,
    et.dupr_range_label,
    et.dupr_min_rating,
    et.dupr_max_rating,
    et.dupr_open_ended,
    et.dupr_min_inclusive,
    et.dupr_max_inclusive,
    et.equipment_provided,
    et.settings,
    et.is_active,

    -- Usage statistics
    COUNT(e.id) AS times_used,
    MAX(e.created_at) AS last_used,

    et.created_by,
    et.created_at,
    et.updated_at
FROM
    events.event_templates et
    LEFT JOIN events.events e ON et.id = e.template_id
WHERE
    et.is_active = true
GROUP BY
    et.id
ORDER BY
    COUNT(e.id) DESC, et.name;

COMMENT ON VIEW api.event_templates_view IS 'Active event templates with usage stats';

-- ============================================================================
-- EVENT REGISTRATIONS VIEW
-- Player registrations with details
-- ============================================================================

CREATE OR REPLACE VIEW api.event_registrations_view AS
SELECT
    er.id,
    er.event_id,
    er.user_id,
    er.player_name,
    er.player_email,
    er.player_phone,
    er.skill_level,
    er.dupr_rating,
    er.status,
    er.registration_time,
    er.check_in_time,
    er.amount_paid,
    er.payment_method,
    er.notes,
    er.special_requests,

    -- Event details
    e.title AS event_title,
    e.event_type,
    e.start_time AS event_start_time,
    e.end_time AS event_end_time,

    -- Player details (if registered user)
    COALESCE(ua.email, er.player_email) AS user_email,
    COALESCE(p.first_name || ' ' || p.last_name, er.player_name) AS user_full_name,

    er.created_at,
    er.updated_at
FROM
    events.event_registrations er
    INNER JOIN events.events e ON er.event_id = e.id
    LEFT JOIN app_auth.players p ON er.user_id = p.id
    LEFT JOIN app_auth.user_accounts ua ON ua.id = p.account_id
ORDER BY
    er.registration_time DESC;

COMMENT ON VIEW api.event_registrations_view IS 'Event registrations with player and event details';

-- ============================================================================
-- COURT SCHEDULE VIEW
-- Timeline view of court usage
-- ============================================================================

CREATE OR REPLACE VIEW api.court_schedule_view AS
SELECT
    c.id AS court_id,
    c.court_number,
    c.name AS court_name,
    e.id AS event_id,
    e.title AS event_title,
    e.event_type,
    e.start_time,
    e.end_time,
    e.current_registrations,
    e.max_capacity,
    ec.is_primary,

    -- Duration in minutes
    EXTRACT(EPOCH FROM (e.end_time - e.start_time)) / 60 AS duration_minutes,

    -- Time slot info
    DATE(e.start_time AT TIME ZONE 'America/New_York') AS event_date,
    TO_CHAR(e.start_time AT TIME ZONE 'America/New_York', 'HH24:MI') AS start_time_formatted,
    TO_CHAR(e.end_time AT TIME ZONE 'America/New_York', 'HH24:MI') AS end_time_formatted
FROM
    events.courts c
    LEFT JOIN events.event_courts ec ON c.id = ec.court_id
    LEFT JOIN events.events e ON ec.event_id = e.id AND e.is_cancelled = false
WHERE
    c.status = 'available'
ORDER BY
    c.court_number, e.start_time;

COMMENT ON VIEW api.court_schedule_view IS 'Court schedule timeline view';

-- ============================================================================
-- UPCOMING EVENTS VIEW
-- Events happening in the near future
-- ============================================================================

CREATE OR REPLACE VIEW api.upcoming_events_view AS
SELECT
    e.id,
    e.title,
    e.event_type,
    e.start_time,
    e.end_time,
    e.max_capacity,
    e.current_registrations,
    e.skill_levels,
    e.price_member,
    e.price_guest,

    -- Registration availability
    e.max_capacity - e.current_registrations AS spots_available,
    CASE
        WHEN e.current_registrations >= e.max_capacity THEN 'full'
        WHEN e.start_time <= NOW() THEN 'in_progress'
        WHEN e.start_time <= NOW() + INTERVAL '24 hours' THEN 'starting_soon'
        ELSE 'open'
    END AS status,

    -- Courts
    STRING_AGG(c.name, ', ' ORDER BY c.court_number) AS court_names,

    -- Time until event
    e.start_time - NOW() AS time_until_start
FROM
    events.events e
    LEFT JOIN events.event_courts ec ON e.id = ec.event_id
    LEFT JOIN events.courts c ON ec.court_id = c.id
WHERE
    e.is_published = true
    AND e.is_cancelled = false
    AND e.start_time > NOW()
    AND e.start_time <= NOW() + INTERVAL '7 days'
GROUP BY
    e.id
ORDER BY
    e.start_time;

COMMENT ON VIEW api.upcoming_events_view IS 'Events happening in the next 7 days';

-- ============================================================================
-- EVENT SERIES VIEW
-- Recurring event series with patterns
-- ============================================================================

CREATE OR REPLACE VIEW api.event_series_view AS
SELECT
    es.id AS series_id,
    es.series_name,
    es.parent_event_id,
    rp.frequency,
    rp.interval_count,
    rp.days_of_week,
    rp.day_of_month,
    rp.week_of_month,
    rp.series_start_date,
    rp.series_end_date,
    rp.occurrences_count,

    -- Parent event details
    pe.title AS parent_event_title,
    pe.event_type,
    EXTRACT(EPOCH FROM (pe.end_time - pe.start_time))/60 AS duration_minutes,

    -- Instance count
    COUNT(esi.id) AS total_instances,
    COUNT(esi.id) FILTER (WHERE esi.is_exception = false) AS regular_instances,
    COUNT(esi.id) FILTER (WHERE esi.is_exception = true) AS exception_instances,

    -- Next occurrence
    MIN(e.start_time) FILTER (WHERE e.start_time > NOW()) AS next_occurrence,

    es.created_by,
    es.created_at
FROM
    events.event_series es
    LEFT JOIN events.recurrence_patterns rp ON es.recurrence_pattern_id = rp.id
    LEFT JOIN events.events pe ON es.parent_event_id = pe.id
    LEFT JOIN events.event_series_instances esi ON es.id = esi.series_id
    LEFT JOIN events.events e ON esi.event_id = e.id
GROUP BY
    es.id, rp.id, pe.id, pe.start_time, pe.end_time;

COMMENT ON VIEW api.event_series_view IS 'Recurring event series with pattern details';

-- ============================================================================
-- DAILY SCHEDULE VIEW
-- Simplified view for daily schedules
-- ============================================================================

CREATE OR REPLACE VIEW api.daily_schedule_view AS
SELECT
    DATE(e.start_time AT TIME ZONE 'America/New_York') AS schedule_date,
    e.id,
    e.title,
    e.event_type,
    e.start_time,
    e.end_time,
    TO_CHAR(e.start_time AT TIME ZONE 'America/New_York', 'HH12:MI AM') AS start_time_display,
    TO_CHAR(e.end_time AT TIME ZONE 'America/New_York', 'HH12:MI AM') AS end_time_display,
    e.current_registrations,
    e.max_capacity,
    e.skill_levels,

    -- Courts
    ARRAY_AGG(c.court_number ORDER BY c.court_number) AS court_numbers,

    -- Color coding helper
    CASE e.event_type
        WHEN 'event_scramble' THEN '#B3FF00'      -- Lime
        WHEN 'dupr_open_play' THEN '#0EA5E9'      -- Blue
        WHEN 'dupr_tournament' THEN '#1D4ED8'     -- Indigo
        WHEN 'non_dupr_tournament' THEN '#EF4444' -- Red
        WHEN 'league' THEN '#8B5CF6'              -- Purple
        WHEN 'clinic' THEN '#10B981'              -- Green
        WHEN 'private_lesson' THEN '#64748B'      -- Gray
        ELSE '#6B7280'
    END AS event_color
FROM
    events.events e
    LEFT JOIN events.event_courts ec ON e.id = ec.event_id
    LEFT JOIN events.courts c ON ec.court_id = c.id
WHERE
    e.is_published = true
    AND e.is_cancelled = false
GROUP BY
    e.id
ORDER BY
    e.start_time;

COMMENT ON VIEW api.daily_schedule_view IS 'Daily event schedule with display formatting';

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

-- Grant select on all views to authenticated users
GRANT SELECT ON api.events_calendar_view TO authenticated;
GRANT SELECT ON api.court_availability_view TO authenticated;
GRANT SELECT ON api.event_templates_view TO authenticated;
GRANT SELECT ON api.event_registrations_view TO authenticated;
GRANT SELECT ON api.court_schedule_view TO authenticated;
GRANT SELECT ON api.upcoming_events_view TO authenticated;
GRANT SELECT ON api.event_series_view TO authenticated;
GRANT SELECT ON api.daily_schedule_view TO authenticated;

-- Grant select on views to anon for public events
GRANT SELECT ON api.upcoming_events_view TO anon;
GRANT SELECT ON api.daily_schedule_view TO anon;
-- ============================================================================
-- EVENTS API VIEWS
-- Create API views for courts and events in the api schema
-- ============================================================================

-- Switch to public schema
SET search_path TO public, events;

-- ============================================================================
-- COURTS VIEW (in public schema for Supabase API access)
-- ============================================================================

CREATE OR REPLACE VIEW public.courts_view AS
SELECT
    id,
    court_number,
    name,
    surface_type,
    environment,
    status,
    location,
    features,
    max_capacity,
    notes,
    created_at,
    updated_at
FROM events.courts
WHERE status IN ('available', 'reserved');

COMMENT ON VIEW public.courts_view IS 'Courts available via API';

-- Also create in api schema for consistency
CREATE OR REPLACE VIEW api.courts AS
SELECT * FROM public.courts_view;

-- ============================================================================
-- EVENTS CALENDAR VIEW (in public schema for Supabase API access)
-- ============================================================================

CREATE OR REPLACE VIEW public.events_view AS
SELECT
    e.id,
    e.title,
    e.description,
    e.event_type,
    e.start_time,
    e.end_time,
    e.check_in_time,
    e.max_capacity,
    e.min_capacity,
    e.price_member,
    e.price_guest,
    e.skill_levels,
    e.member_only,
    e.dupr_bracket_id,
    e.dupr_range_label,
    e.dupr_min_rating,
    e.dupr_max_rating,
    e.is_published,
    e.is_cancelled,
    e.equipment_provided,
    e.special_instructions,
    COALESCE((
        SELECT COUNT(*)
        FROM events.event_registrations er
        WHERE er.event_id = e.id
          AND er.status = 'registered'
    ), 0) AS current_registrations,
    (
        SELECT json_agg(
            json_build_object(
                'court_id', c.id,
                'court_number', c.court_number,
                'name', c.name,
                'environment', c.environment
            )
        )
        FROM events.event_courts ec
        JOIN events.courts c ON c.id = ec.court_id
        WHERE ec.event_id = e.id
    ) AS courts,
    e.created_at,
    e.updated_at
FROM events.events e
WHERE e.is_published = true
  AND e.is_cancelled = false;

COMMENT ON VIEW public.events_view IS 'Published events for calendar and player app';

-- Also create in api schema
CREATE OR REPLACE VIEW api.events_calendar_view AS
SELECT * FROM public.events_view;

-- ============================================================================
-- EVENT TEMPLATES VIEW
-- ============================================================================

CREATE OR REPLACE VIEW api.event_templates AS
SELECT
    id,
    name,
    description,
    event_type,
    duration_minutes,
    max_capacity,
    min_capacity,
    skill_levels,
    price_member,
    price_guest,
    equipment_provided,
    is_active,
    times_used,
    created_at,
    updated_at
FROM events.event_templates
WHERE is_active = true;

COMMENT ON VIEW api.event_templates IS 'Active event templates';

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

-- Grant SELECT to authenticated users
GRANT SELECT ON public.courts_view TO authenticated;
GRANT SELECT ON public.events_view TO authenticated;
GRANT SELECT ON api.courts TO authenticated;
GRANT SELECT ON api.events_calendar_view TO authenticated;
GRANT SELECT ON api.event_templates TO authenticated;

-- Grant SELECT on courts to anonymous users (for public booking pages)
GRANT SELECT ON public.courts_view TO anon;
GRANT SELECT ON public.events_view TO anon;
GRANT SELECT ON api.courts TO anon;
GRANT SELECT ON api.events_calendar_view TO anon;

-- ============================================================================
-- RPC FUNCTIONS (in public schema for Supabase API access)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.check_court_availability(
    p_court_ids UUID[],
    p_start_time TIMESTAMPTZ,
    p_end_time TIMESTAMPTZ,
    p_exclude_event_id UUID DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
    v_result JSON;
BEGIN
    WITH conflicts AS (
        SELECT
            ec.court_id,
            c.court_number,
            c.name AS court_name,
            e.id AS event_id,
            e.title AS event_title,
            e.start_time,
            e.end_time
        FROM events.event_courts ec
        JOIN events.events e ON ec.event_id = e.id
        JOIN events.courts c ON ec.court_id = c.id
        WHERE ec.court_id = ANY(p_court_ids)
        AND e.is_cancelled = false
        AND (p_exclude_event_id IS NULL OR e.id != p_exclude_event_id)
        AND (e.start_time, e.end_time) OVERLAPS (p_start_time, p_end_time)
    ),
    availability AS (
        SELECT
            c.id AS court_id,
            c.court_number,
            c.name AS court_name,
            c.status,
            CASE
                WHEN c.status != 'available' THEN false
                WHEN EXISTS (SELECT 1 FROM conflicts cf WHERE cf.court_id = c.id) THEN false
                ELSE true
            END AS is_available,
            (
                SELECT json_agg(json_build_object(
                    'event_id', cf.event_id,
                    'event_title', cf.event_title,
                    'start_time', cf.start_time,
                    'end_time', cf.end_time
                ))
                FROM conflicts cf
                WHERE cf.court_id = c.id
            ) AS conflicts
        FROM events.courts c
        WHERE c.id = ANY(p_court_ids)
    )
    SELECT json_object_agg(
        a.court_id,
        json_build_object(
            'court_id', a.court_id,
            'court_number', a.court_number,
            'court_name', a.court_name,
            'status', a.status,
            'available', a.is_available,
            'conflicts', COALESCE(a.conflicts, '[]'::json)
        )
    ) INTO v_result
    FROM availability a;

    RETURN COALESCE(v_result, '{}'::json);
END;
$$;

COMMENT ON FUNCTION public.check_court_availability IS 'Check court availability for booking';

-- Grant execute to authenticated and anonymous users
GRANT EXECUTE ON FUNCTION public.check_court_availability TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_court_availability TO anon;

-- Create court booking function
CREATE OR REPLACE FUNCTION public.create_court_booking(
    p_event_id UUID,
    p_player_id UUID,
    p_amount DECIMAL,
    p_booking_source VARCHAR DEFAULT 'player_app'
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_registration_id UUID;
    v_result JSON;
BEGIN
    -- Create event registration
    INSERT INTO events.event_registrations (
        event_id,
        user_id,
        amount_paid,
        payment_status,
        status,
        registration_source
    ) VALUES (
        p_event_id,
        p_player_id,
        p_amount,
        'pending',
        'registered',
        p_booking_source
    )
    RETURNING id INTO v_registration_id;

    -- Return registration details
    SELECT json_build_object(
        'id', v_registration_id,
        'event_id', p_event_id,
        'player_id', p_player_id,
        'amount', p_amount,
        'status', 'pending'
    ) INTO v_result;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.create_court_booking IS 'Create a court booking/event registration';

GRANT EXECUTE ON FUNCTION public.create_court_booking TO authenticated;
-- ============================================================================
-- EVENTS RLS POLICIES MODULE
-- Row Level Security policies for events system
-- ============================================================================

-- Enable RLS on all events tables
ALTER TABLE events.courts ENABLE ROW LEVEL SECURITY;
ALTER TABLE events.event_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE events.events ENABLE ROW LEVEL SECURITY;
ALTER TABLE events.event_courts ENABLE ROW LEVEL SECURITY;
ALTER TABLE events.recurrence_patterns ENABLE ROW LEVEL SECURITY;
ALTER TABLE events.event_series ENABLE ROW LEVEL SECURITY;
ALTER TABLE events.event_series_instances ENABLE ROW LEVEL SECURITY;
ALTER TABLE events.event_exceptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE events.event_registrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE events.court_availability ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Check if user is admin or manager
CREATE OR REPLACE FUNCTION events.is_admin_or_manager()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('manager', 'admin', 'super_admin')
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Check if user is staff (admin, manager, or coach)
CREATE OR REPLACE FUNCTION events.is_staff()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('admin', 'manager', 'coach', 'super_admin', 'editor')
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- COURTS POLICIES
-- ============================================================================

-- Courts: Everyone can view
CREATE POLICY "courts_select_all" ON events.courts
    FOR SELECT
    USING (true);

-- Courts: Only admins can insert
CREATE POLICY "courts_insert_admin" ON events.courts
    FOR INSERT
    WITH CHECK (events.is_admin_or_manager());

-- Courts: Only admins can update
CREATE POLICY "courts_update_admin" ON events.courts
    FOR UPDATE
    USING (events.is_admin_or_manager())
    WITH CHECK (events.is_admin_or_manager());

-- Courts: Only admins can delete
CREATE POLICY "courts_delete_admin" ON events.courts
    FOR DELETE
    USING (events.is_admin_or_manager());

-- ============================================================================
-- EVENT TEMPLATES POLICIES
-- ============================================================================

-- Templates: Staff can view all active templates
CREATE POLICY "templates_select_staff" ON events.event_templates
    FOR SELECT
    USING (
        is_active = true
        OR created_by = auth.uid()
        OR events.is_staff()
    );

-- Templates: Staff can create
CREATE POLICY "templates_insert_staff" ON events.event_templates
    FOR INSERT
    WITH CHECK (
        events.is_staff()
        AND created_by = auth.uid()
    );

-- Templates: Creators and admins can update
CREATE POLICY "templates_update_owner_admin" ON events.event_templates
    FOR UPDATE
    USING (
        created_by = auth.uid()
        OR events.is_admin_or_manager()
    )
    WITH CHECK (
        created_by = auth.uid()
        OR events.is_admin_or_manager()
    );

-- Templates: Only admins can delete
CREATE POLICY "templates_delete_admin" ON events.event_templates
    FOR DELETE
    USING (events.is_admin_or_manager());

-- ============================================================================
-- EVENTS POLICIES
-- ============================================================================

-- Events: Everyone can view published events
CREATE POLICY "events_select_published" ON events.events
    FOR SELECT
    USING (
        is_published = true
        OR created_by = auth.uid()
        OR events.is_staff()
    );

-- Events: Staff can create
CREATE POLICY "events_insert_staff" ON events.events
    FOR INSERT
    WITH CHECK (
        events.is_staff()
        AND created_by = auth.uid()
    );

-- Events: Creators and admins can update
CREATE POLICY "events_update_owner_admin" ON events.events
    FOR UPDATE
    USING (
        created_by = auth.uid()
        OR events.is_admin_or_manager()
    )
    WITH CHECK (
        created_by = auth.uid()
        OR events.is_admin_or_manager()
    );

-- Events: Only admins can delete
CREATE POLICY "events_delete_admin" ON events.events
    FOR DELETE
    USING (events.is_admin_or_manager());

-- ============================================================================
-- EVENT COURTS POLICIES
-- ============================================================================

-- Event Courts: View if can view event
CREATE POLICY "event_courts_select" ON events.event_courts
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM events.events e
            WHERE e.id = event_courts.event_id
            AND (
                e.is_published = true
                OR e.created_by = auth.uid()
                OR events.is_staff()
            )
        )
    );

-- Event Courts: Staff can manage
CREATE POLICY "event_courts_insert_staff" ON events.event_courts
    FOR INSERT
    WITH CHECK (events.is_staff());

CREATE POLICY "event_courts_update_staff" ON events.event_courts
    FOR UPDATE
    USING (events.is_staff())
    WITH CHECK (events.is_staff());

CREATE POLICY "event_courts_delete_staff" ON events.event_courts
    FOR DELETE
    USING (events.is_staff());

-- ============================================================================
-- RECURRENCE PATTERNS POLICIES
-- ============================================================================

-- Recurrence: Staff only
CREATE POLICY "recurrence_select_staff" ON events.recurrence_patterns
    FOR SELECT
    USING (events.is_staff());

CREATE POLICY "recurrence_insert_staff" ON events.recurrence_patterns
    FOR INSERT
    WITH CHECK (events.is_staff());

CREATE POLICY "recurrence_update_staff" ON events.recurrence_patterns
    FOR UPDATE
    USING (events.is_staff())
    WITH CHECK (events.is_staff());

CREATE POLICY "recurrence_delete_admin" ON events.recurrence_patterns
    FOR DELETE
    USING (events.is_admin_or_manager());

-- ============================================================================
-- EVENT SERIES POLICIES
-- ============================================================================

-- Series: Staff only
CREATE POLICY "series_select_staff" ON events.event_series
    FOR SELECT
    USING (events.is_staff());

CREATE POLICY "series_insert_staff" ON events.event_series
    FOR INSERT
    WITH CHECK (
        events.is_staff()
        AND created_by = auth.uid()
    );

CREATE POLICY "series_update_admin" ON events.event_series
    FOR UPDATE
    USING (events.is_admin_or_manager())
    WITH CHECK (events.is_admin_or_manager());

CREATE POLICY "series_delete_admin" ON events.event_series
    FOR DELETE
    USING (events.is_admin_or_manager());

-- ============================================================================
-- EVENT SERIES INSTANCES POLICIES
-- ============================================================================

-- Series Instances: Staff only
CREATE POLICY "series_instances_select_staff" ON events.event_series_instances
    FOR SELECT
    USING (events.is_staff());

CREATE POLICY "series_instances_insert_staff" ON events.event_series_instances
    FOR INSERT
    WITH CHECK (events.is_staff());

CREATE POLICY "series_instances_update_staff" ON events.event_series_instances
    FOR UPDATE
    USING (events.is_staff())
    WITH CHECK (events.is_staff());

CREATE POLICY "series_instances_delete_admin" ON events.event_series_instances
    FOR DELETE
    USING (events.is_admin_or_manager());

-- ============================================================================
-- EVENT EXCEPTIONS POLICIES
-- ============================================================================

-- Exceptions: Staff only
CREATE POLICY "exceptions_select_staff" ON events.event_exceptions
    FOR SELECT
    USING (events.is_staff());

CREATE POLICY "exceptions_insert_staff" ON events.event_exceptions
    FOR INSERT
    WITH CHECK (events.is_staff());

CREATE POLICY "exceptions_update_staff" ON events.event_exceptions
    FOR UPDATE
    USING (events.is_staff())
    WITH CHECK (events.is_staff());

CREATE POLICY "exceptions_delete_staff" ON events.event_exceptions
    FOR DELETE
    USING (events.is_staff());

-- ============================================================================
-- EVENT REGISTRATIONS POLICIES
-- ============================================================================

-- Registrations: View own or if staff
CREATE POLICY "registrations_select_own_or_staff" ON events.event_registrations
    FOR SELECT
    USING (
        user_id = auth.uid()
        OR events.is_staff()
        OR EXISTS (
            SELECT 1 FROM events.events e
            WHERE e.id = event_registrations.event_id
            AND e.created_by = auth.uid()
        )
    );

-- Registrations: Anyone can register (with business logic checks)
CREATE POLICY "registrations_insert_authenticated" ON events.event_registrations
    FOR INSERT
    WITH CHECK (
        -- User registering themselves
        (user_id = auth.uid() OR user_id IS NULL)
        -- Event must be published and not cancelled
        AND EXISTS (
            SELECT 1 FROM events.events e
            WHERE e.id = event_registrations.event_id
            AND e.is_published = true
            AND e.is_cancelled = false
            AND e.start_time > NOW()
        )
    );

-- Registrations: Update own or if staff
CREATE POLICY "registrations_update_own_or_staff" ON events.event_registrations
    FOR UPDATE
    USING (
        user_id = auth.uid()
        OR events.is_staff()
    )
    WITH CHECK (
        user_id = auth.uid()
        OR events.is_staff()
    );

-- Registrations: Delete own or if staff
CREATE POLICY "registrations_delete_own_or_staff" ON events.event_registrations
    FOR DELETE
    USING (
        user_id = auth.uid()
        OR events.is_staff()
    );

-- ============================================================================
-- COURT AVAILABILITY POLICIES
-- ============================================================================

-- Court Availability: Everyone can view
CREATE POLICY "availability_select_all" ON events.court_availability
    FOR SELECT
    USING (true);

-- Court Availability: Staff can manage
CREATE POLICY "availability_insert_staff" ON events.court_availability
    FOR INSERT
    WITH CHECK (
        events.is_staff()
        AND created_by = auth.uid()
    );

CREATE POLICY "availability_update_staff" ON events.court_availability
    FOR UPDATE
    USING (events.is_staff())
    WITH CHECK (events.is_staff());

CREATE POLICY "availability_delete_admin" ON events.court_availability
    FOR DELETE
    USING (events.is_admin_or_manager());

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

-- Grant usage on events schema
GRANT USAGE ON SCHEMA events TO authenticated;
GRANT USAGE ON SCHEMA events TO anon;

-- Grant permissions on tables
GRANT SELECT ON ALL TABLES IN SCHEMA events TO authenticated;
GRANT SELECT ON events.courts, events.events TO anon;

-- Grant permissions for authenticated users to manage their registrations
GRANT INSERT, UPDATE, DELETE ON events.event_registrations TO authenticated;

-- Grant sequence permissions
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA events TO authenticated;
-- ============================================================================
-- EVENTS API FUNCTIONS MODULE
-- Database functions for complex event operations
-- ============================================================================

-- ============================================================================
-- CREATE EVENT WITH COURTS
-- Creates an event and assigns courts in a single transaction
-- ============================================================================

CREATE OR REPLACE FUNCTION api.create_event_with_courts(
    p_title VARCHAR,
    p_event_type events.event_type,
    p_start_time TIMESTAMPTZ,
    p_end_time TIMESTAMPTZ,
    p_court_ids UUID[],
    p_description TEXT DEFAULT NULL,
    p_template_id UUID DEFAULT NULL,
    p_max_capacity INTEGER DEFAULT 16,
    p_min_capacity INTEGER DEFAULT 4,
    p_skill_levels events.skill_level[] DEFAULT NULL,
    p_price_member DECIMAL DEFAULT 0,
    p_price_guest DECIMAL DEFAULT 0,
    p_member_only BOOLEAN DEFAULT false,
    p_equipment_provided BOOLEAN DEFAULT false,
    p_special_instructions TEXT DEFAULT NULL,
    p_dupr_bracket_id UUID DEFAULT NULL,
    p_dupr_range_label VARCHAR DEFAULT NULL,
    p_dupr_min_rating NUMERIC DEFAULT NULL,
    p_dupr_max_rating NUMERIC DEFAULT NULL,
    p_dupr_open_ended BOOLEAN DEFAULT false,
    p_dupr_min_inclusive BOOLEAN DEFAULT true,
    p_dupr_max_inclusive BOOLEAN DEFAULT true
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_event_id UUID;
    v_court_id UUID;
    v_result JSON;
    v_dupr_bracket events.dupr_brackets%ROWTYPE;
    v_dupr_bracket_id UUID := p_dupr_bracket_id;
    v_dupr_range_label VARCHAR := p_dupr_range_label;
    v_dupr_min_rating NUMERIC(3, 2) := p_dupr_min_rating;
    v_dupr_max_rating NUMERIC(3, 2) := p_dupr_max_rating;
    v_dupr_open_ended BOOLEAN := p_dupr_open_ended;
    v_dupr_min_inclusive BOOLEAN := p_dupr_min_inclusive;
    v_dupr_max_inclusive BOOLEAN := p_dupr_max_inclusive;
BEGIN
    -- Check if user is staff
    IF NOT events.is_staff() THEN
        RAISE EXCEPTION 'Unauthorized: Only staff can create events';
    END IF;

    -- Validate DUPR configuration for DUPR-centric events
    IF p_event_type IN ('dupr_open_play', 'dupr_tournament') THEN
        IF v_dupr_bracket_id IS NOT NULL THEN
            SELECT *
            INTO v_dupr_bracket
            FROM events.dupr_brackets
            WHERE id = v_dupr_bracket_id;

            IF NOT FOUND THEN
                RAISE EXCEPTION 'Invalid DUPR bracket provided';
            END IF;

            v_dupr_range_label := COALESCE(v_dupr_range_label, v_dupr_bracket.label);
            v_dupr_min_rating := COALESCE(v_dupr_bracket.min_rating, v_dupr_min_rating);
            v_dupr_max_rating := COALESCE(v_dupr_bracket.max_rating, v_dupr_max_rating);
            v_dupr_min_inclusive := v_dupr_bracket.min_inclusive;
            v_dupr_max_inclusive := COALESCE(v_dupr_bracket.max_inclusive, true);
            v_dupr_open_ended := v_dupr_bracket.max_rating IS NULL;
        END IF;

        IF v_dupr_open_ended THEN
            v_dupr_max_rating := NULL;
            v_dupr_max_inclusive := true;
        END IF;

        IF v_dupr_range_label IS NULL THEN
            RAISE EXCEPTION 'DUPR range label is required for DUPR events';
        END IF;

        IF v_dupr_min_rating IS NULL THEN
            RAISE EXCEPTION 'Minimum DUPR rating is required for DUPR events';
        END IF;

        IF NOT v_dupr_open_ended AND v_dupr_max_rating IS NULL THEN
            RAISE EXCEPTION 'Maximum DUPR rating is required unless the range is open ended';
        END IF;

        IF v_dupr_max_rating IS NOT NULL AND v_dupr_max_rating < v_dupr_min_rating THEN
            RAISE EXCEPTION 'DUPR maximum rating must be greater than or equal to minimum rating';
        END IF;
    ELSE
        v_dupr_bracket_id := NULL;
        v_dupr_range_label := NULL;
        v_dupr_min_rating := NULL;
        v_dupr_max_rating := NULL;
        v_dupr_open_ended := false;
        v_dupr_min_inclusive := true;
        v_dupr_max_inclusive := true;
    END IF;

    -- Check for court conflicts
    IF EXISTS (
        SELECT 1
        FROM events.event_courts ec
        JOIN events.events e ON ec.event_id = e.id
        WHERE ec.court_id = ANY(p_court_ids)
        AND e.is_cancelled = false
        AND (
            (e.start_time, e.end_time) OVERLAPS (p_start_time, p_end_time)
        )
    ) THEN
        RAISE EXCEPTION 'Court conflict: One or more courts are already booked for this time';
    END IF;

    -- Create the event
    INSERT INTO events.events (
        title,
        event_type,
        start_time,
        end_time,
        description,
        template_id,
        max_capacity,
        min_capacity,
        skill_levels,
        dupr_bracket_id,
        dupr_range_label,
        dupr_min_rating,
        dupr_max_rating,
        dupr_open_ended,
        dupr_min_inclusive,
        dupr_max_inclusive,
        price_member,
        price_guest,
        member_only,
        equipment_provided,
        special_instructions,
        created_by
    ) VALUES (
        p_title,
        p_event_type,
        p_start_time,
        p_end_time,
        p_description,
        p_template_id,
        p_max_capacity,
        p_min_capacity,
        COALESCE(p_skill_levels, ARRAY['2.0', '2.5', '3.0', '3.5', '4.0', '4.5', '5.0']::events.skill_level[]),
        v_dupr_bracket_id,
        v_dupr_range_label,
        v_dupr_min_rating,
        v_dupr_max_rating,
        v_dupr_open_ended,
        v_dupr_min_inclusive,
        v_dupr_max_inclusive,
        p_price_member,
        p_price_guest,
        p_member_only,
        p_equipment_provided,
        p_special_instructions,
        auth.uid()
    ) RETURNING id INTO v_event_id;

    -- Assign courts
    IF p_court_ids IS NOT NULL AND array_length(p_court_ids, 1) > 0 THEN
        FOREACH v_court_id IN ARRAY p_court_ids
        LOOP
            INSERT INTO events.event_courts (event_id, court_id, is_primary)
            VALUES (v_event_id, v_court_id, v_court_id = p_court_ids[1]);
        END LOOP;
    END IF;

    -- Return the created event with courts
    SELECT json_build_object(
        'event_id', v_event_id,
        'title', p_title,
        'event_type', p_event_type,
        'start_time', p_start_time,
        'end_time', p_end_time,
        'dupr_bracket_id', v_dupr_bracket_id,
        'dupr_range', CASE
            WHEN p_event_type IN ('dupr_open_play', 'dupr_tournament') THEN json_build_object(
                'label', v_dupr_range_label,
                'min_rating', v_dupr_min_rating,
                'max_rating', v_dupr_max_rating,
                'min_inclusive', v_dupr_min_inclusive,
                'max_inclusive', v_dupr_max_inclusive,
                'open_ended', v_dupr_open_ended,
                'source', CASE WHEN v_dupr_bracket_id IS NOT NULL THEN 'catalog' ELSE 'custom' END
            )
            ELSE NULL
        END,
        'courts', (
            SELECT json_agg(json_build_object(
                'court_id', ec.court_id,
                'court_number', c.court_number,
                'court_name', c.name
            ) ORDER BY c.court_number)
            FROM events.event_courts ec
            JOIN events.courts c ON ec.court_id = c.id
            WHERE ec.event_id = v_event_id
        )
    ) INTO v_result;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION api.create_event_with_courts IS 'Creates an event with court assignments';

-- ============================================================================
-- CREATE RECURRING EVENTS
-- Creates a series of recurring events
-- ============================================================================

CREATE OR REPLACE FUNCTION api.create_recurring_events(
    p_base_event JSON,
    p_frequency events.recurrence_frequency,
    p_start_date DATE,
    p_end_date DATE,
    p_days_of_week INTEGER[] DEFAULT NULL,
    p_interval_count INTEGER DEFAULT 1,
    p_exceptions DATE[] DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_series_id UUID;
    v_pattern_id UUID;
    v_parent_event_id UUID;
    v_current_date DATE;
    v_event_id UUID;
    v_event_count INTEGER := 0;
    v_start_time TIME;
    v_end_time TIME;
    v_duration INTERVAL;
BEGIN
    -- Check if user is staff
    IF NOT events.is_staff() THEN
        RAISE EXCEPTION 'Unauthorized: Only staff can create recurring events';
    END IF;

    -- Extract time components from base event
    v_start_time := (p_base_event->>'start_time')::TIME;
    v_end_time := (p_base_event->>'end_time')::TIME;
    v_duration := v_end_time - v_start_time;

    -- Create parent event (first occurrence)
    v_parent_event_id := (api.create_event_with_courts(
        p_title := p_base_event->>'title',
        p_event_type := (p_base_event->>'event_type')::events.event_type,
        p_start_time := p_start_date + v_start_time,
        p_end_time := p_start_date + v_end_time,
        p_court_ids := ARRAY(SELECT json_array_elements_text(p_base_event->'court_ids'))::UUID[],
        p_description := p_base_event->>'description',
        p_template_id := (p_base_event->>'template_id')::UUID,
        p_max_capacity := (p_base_event->>'max_capacity')::INTEGER,
        p_min_capacity := (p_base_event->>'min_capacity')::INTEGER,
        p_skill_levels := ARRAY(SELECT json_array_elements_text(p_base_event->'skill_levels'))::events.skill_level[],
        p_price_member := (p_base_event->>'price_member')::DECIMAL,
        p_price_guest := (p_base_event->>'price_guest')::DECIMAL,
        p_member_only := (p_base_event->>'member_only')::BOOLEAN,
        p_equipment_provided := (p_base_event->>'equipment_provided')::BOOLEAN,
        p_special_instructions := p_base_event->>'special_instructions',
        p_dupr_bracket_id := (p_base_event->>'dupr_bracket_id')::UUID,
        p_dupr_range_label := p_base_event->>'dupr_range_label',
        p_dupr_min_rating := (p_base_event->>'dupr_min_rating')::NUMERIC,
        p_dupr_max_rating := (p_base_event->>'dupr_max_rating')::NUMERIC,
        p_dupr_open_ended := COALESCE((p_base_event->>'dupr_open_ended')::BOOLEAN, false),
        p_dupr_min_inclusive := COALESCE((p_base_event->>'dupr_min_inclusive')::BOOLEAN, true),
        p_dupr_max_inclusive := COALESCE((p_base_event->>'dupr_max_inclusive')::BOOLEAN, true)
    )->>'event_id')::UUID;

    v_event_count := 1;

    -- Create recurrence pattern
    INSERT INTO events.recurrence_patterns (
        event_id,
        frequency,
        interval_count,
        days_of_week,
        series_start_date,
        series_end_date
    ) VALUES (
        v_parent_event_id,
        p_frequency,
        p_interval_count,
        p_days_of_week,
        p_start_date,
        p_end_date
    ) RETURNING id INTO v_pattern_id;

    -- Create series
    INSERT INTO events.event_series (
        series_name,
        parent_event_id,
        recurrence_pattern_id,
        created_by
    ) VALUES (
        p_base_event->>'title' || ' Series',
        v_parent_event_id,
        v_pattern_id,
        auth.uid()
    ) RETURNING id INTO v_series_id;

    -- Add parent event to series
    INSERT INTO events.event_series_instances (series_id, event_id, original_start_time)
    VALUES (v_series_id, v_parent_event_id, p_start_date + v_start_time);

    -- Add exceptions
    IF p_exceptions IS NOT NULL THEN
        INSERT INTO events.event_exceptions (recurrence_pattern_id, exception_date)
        SELECT v_pattern_id, unnest(p_exceptions);
    END IF;

    -- Generate recurring events
    v_current_date := p_start_date;

    WHILE v_current_date <= p_end_date LOOP
        -- Move to next occurrence based on frequency
        CASE p_frequency
            WHEN 'daily' THEN
                v_current_date := v_current_date + (p_interval_count || ' days')::INTERVAL;
            WHEN 'weekly' THEN
                v_current_date := v_current_date + (p_interval_count || ' weeks')::INTERVAL;
            WHEN 'biweekly' THEN
                v_current_date := v_current_date + (p_interval_count * 2 || ' weeks')::INTERVAL;
            WHEN 'monthly' THEN
                v_current_date := v_current_date + (p_interval_count || ' months')::INTERVAL;
        END CASE;

        -- Check if date is valid
        IF v_current_date > p_end_date THEN
            EXIT;
        END IF;

        -- Skip if date is in exceptions
        IF p_exceptions IS NOT NULL AND v_current_date = ANY(p_exceptions) THEN
            CONTINUE;
        END IF;

        -- Check day of week for weekly recurrence
        IF p_frequency = 'weekly' AND p_days_of_week IS NOT NULL THEN
            IF NOT (EXTRACT(DOW FROM v_current_date)::INTEGER = ANY(p_days_of_week)) THEN
                CONTINUE;
            END IF;
        END IF;

        -- Create the event
        v_event_id := (api.create_event_with_courts(
            p_title := p_base_event->>'title',
            p_event_type := (p_base_event->>'event_type')::events.event_type,
            p_start_time := v_current_date + v_start_time,
            p_end_time := v_current_date + v_end_time,
            p_court_ids := ARRAY(SELECT json_array_elements_text(p_base_event->'court_ids'))::UUID[],
            p_description := p_base_event->>'description',
            p_template_id := (p_base_event->>'template_id')::UUID,
            p_max_capacity := (p_base_event->>'max_capacity')::INTEGER,
            p_min_capacity := (p_base_event->>'min_capacity')::INTEGER,
            p_skill_levels := ARRAY(SELECT json_array_elements_text(p_base_event->'skill_levels'))::events.skill_level[],
            p_price_member := (p_base_event->>'price_member')::DECIMAL,
            p_price_guest := (p_base_event->>'price_guest')::DECIMAL,
            p_member_only := (p_base_event->>'member_only')::BOOLEAN,
            p_equipment_provided := (p_base_event->>'equipment_provided')::BOOLEAN,
            p_special_instructions := p_base_event->>'special_instructions',
            p_dupr_bracket_id := (p_base_event->>'dupr_bracket_id')::UUID,
            p_dupr_range_label := p_base_event->>'dupr_range_label',
            p_dupr_min_rating := (p_base_event->>'dupr_min_rating')::NUMERIC,
            p_dupr_max_rating := (p_base_event->>'dupr_max_rating')::NUMERIC,
            p_dupr_open_ended := COALESCE((p_base_event->>'dupr_open_ended')::BOOLEAN, false),
            p_dupr_min_inclusive := COALESCE((p_base_event->>'dupr_min_inclusive')::BOOLEAN, true),
            p_dupr_max_inclusive := COALESCE((p_base_event->>'dupr_max_inclusive')::BOOLEAN, true)
        )->>'event_id')::UUID;

        -- Add to series
        INSERT INTO events.event_series_instances (series_id, event_id, original_start_time)
        VALUES (v_series_id, v_event_id, v_current_date + v_start_time);

        v_event_count := v_event_count + 1;
    END LOOP;

    RETURN json_build_object(
        'series_id', v_series_id,
        'pattern_id', v_pattern_id,
        'events_created', v_event_count,
        'start_date', p_start_date,
        'end_date', p_end_date
    );
END;
$$;

COMMENT ON FUNCTION api.create_recurring_events IS 'Creates a series of recurring events';

-- ============================================================================
-- CHECK COURT AVAILABILITY
-- Checks if courts are available for a given time range
-- ============================================================================

CREATE OR REPLACE FUNCTION api.check_court_availability(
    p_court_ids UUID[],
    p_start_time TIMESTAMPTZ,
    p_end_time TIMESTAMPTZ,
    p_exclude_event_id UUID DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_result JSON;
BEGIN
    WITH conflicts AS (
        SELECT
            ec.court_id,
            c.court_number,
            c.name AS court_name,
            e.id AS event_id,
            e.title AS event_title,
            e.start_time,
            e.end_time
        FROM events.event_courts ec
        JOIN events.events e ON ec.event_id = e.id
        JOIN events.courts c ON ec.court_id = c.id
        WHERE ec.court_id = ANY(p_court_ids)
        AND e.is_cancelled = false
        AND (p_exclude_event_id IS NULL OR e.id != p_exclude_event_id)
        AND (e.start_time, e.end_time) OVERLAPS (p_start_time, p_end_time)
    ),
    availability AS (
        SELECT
            c.id AS court_id,
            c.court_number,
            c.name AS court_name,
            c.status,
            CASE
                WHEN c.status != 'available' THEN false
                WHEN EXISTS (SELECT 1 FROM conflicts cf WHERE cf.court_id = c.id) THEN false
                ELSE true
            END AS is_available,
            (
                SELECT json_agg(json_build_object(
                    'event_id', cf.event_id,
                    'event_title', cf.event_title,
                    'start_time', cf.start_time,
                    'end_time', cf.end_time
                ))
                FROM conflicts cf
                WHERE cf.court_id = c.id
            ) AS conflicts
        FROM events.courts c
        WHERE c.id = ANY(p_court_ids)
    )
    SELECT json_build_object(
        'available_courts', (
            SELECT json_agg(json_build_object(
                'court_id', court_id,
                'court_number', court_number,
                'court_name', court_name
            ))
            FROM availability
            WHERE is_available = true
        ),
        'unavailable_courts', (
            SELECT json_agg(json_build_object(
                'court_id', court_id,
                'court_number', court_number,
                'court_name', court_name,
                'status', status,
                'conflicts', conflicts
            ))
            FROM availability
            WHERE is_available = false
        ),
        'all_available', NOT EXISTS (SELECT 1 FROM availability WHERE is_available = false)
    ) INTO v_result;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION api.check_court_availability IS 'Checks court availability for a time range';

-- ============================================================================
-- DUPLICATE EVENT TEMPLATE
-- Creates a copy of an event template
-- ============================================================================

CREATE OR REPLACE FUNCTION api.duplicate_event_template(
    p_template_id UUID,
    p_new_name VARCHAR DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_new_template_id UUID;
    v_original_name VARCHAR;
BEGIN
    -- Check if user is staff
    IF NOT events.is_staff() THEN
        RAISE EXCEPTION 'Unauthorized: Only staff can duplicate templates';
    END IF;

    -- Get original name if not provided
    IF p_new_name IS NULL THEN
        SELECT name || ' (Copy)' INTO v_original_name
        FROM events.event_templates
        WHERE id = p_template_id;

        p_new_name := v_original_name;
    END IF;

    -- Duplicate the template
    INSERT INTO events.event_templates (
        name,
        description,
        event_type,
        duration_minutes,
        max_capacity,
        min_capacity,
        skill_levels,
        price_member,
        price_guest,
        court_preferences,
        equipment_provided,
        settings,
        created_by
    )
    SELECT
        p_new_name,
        description,
        event_type,
        duration_minutes,
        max_capacity,
        min_capacity,
        skill_levels,
        price_member,
        price_guest,
        court_preferences,
        equipment_provided,
        settings,
        auth.uid()
    FROM events.event_templates
    WHERE id = p_template_id
    RETURNING id INTO v_new_template_id;

    RETURN v_new_template_id;
END;
$$;

COMMENT ON FUNCTION api.duplicate_event_template IS 'Creates a copy of an event template';

-- ============================================================================
-- UPDATE EVENT SERIES
-- Updates all or future events in a series
-- ============================================================================

CREATE OR REPLACE FUNCTION api.update_event_series(
    p_series_id UUID,
    p_update_scope VARCHAR, -- 'all', 'future', 'single'
    p_event_id UUID,
    p_updates JSON
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_affected_count INTEGER := 0;
    v_current_time TIMESTAMPTZ;
BEGIN
    -- Check if user is staff
    IF NOT events.is_staff() THEN
        RAISE EXCEPTION 'Unauthorized: Only staff can update event series';
    END IF;

    -- Determine scope
    IF p_update_scope = 'single' THEN
        -- Update single event
        UPDATE events.events
        SET
            title = COALESCE(p_updates->>'title', title),
            description = COALESCE(p_updates->>'description', description),
            max_capacity = COALESCE((p_updates->>'max_capacity')::INTEGER, max_capacity),
            min_capacity = COALESCE((p_updates->>'min_capacity')::INTEGER, min_capacity),
            price_member = COALESCE((p_updates->>'price_member')::DECIMAL, price_member),
            price_guest = COALESCE((p_updates->>'price_guest')::DECIMAL, price_guest),
            special_instructions = COALESCE(p_updates->>'special_instructions', special_instructions),
            updated_by = auth.uid(),
            updated_at = NOW()
        WHERE id = p_event_id;

        -- Mark as exception in series
        UPDATE events.event_series_instances
        SET is_exception = true
        WHERE event_id = p_event_id AND series_id = p_series_id;

        v_affected_count := 1;

    ELSIF p_update_scope = 'future' THEN
        -- Get current event time
        SELECT start_time INTO v_current_time
        FROM events.events
        WHERE id = p_event_id;

        -- Update future events
        UPDATE events.events e
        SET
            title = COALESCE(p_updates->>'title', title),
            description = COALESCE(p_updates->>'description', description),
            max_capacity = COALESCE((p_updates->>'max_capacity')::INTEGER, max_capacity),
            min_capacity = COALESCE((p_updates->>'min_capacity')::INTEGER, min_capacity),
            price_member = COALESCE((p_updates->>'price_member')::DECIMAL, price_member),
            price_guest = COALESCE((p_updates->>'price_guest')::DECIMAL, price_guest),
            special_instructions = COALESCE(p_updates->>'special_instructions', special_instructions),
            updated_by = auth.uid(),
            updated_at = NOW()
        FROM events.event_series_instances esi
        WHERE e.id = esi.event_id
        AND esi.series_id = p_series_id
        AND e.start_time >= v_current_time
        AND e.is_cancelled = false;

        GET DIAGNOSTICS v_affected_count = ROW_COUNT;

    ELSE -- 'all'
        -- Update all events in series
        UPDATE events.events e
        SET
            title = COALESCE(p_updates->>'title', title),
            description = COALESCE(p_updates->>'description', description),
            max_capacity = COALESCE((p_updates->>'max_capacity')::INTEGER, max_capacity),
            min_capacity = COALESCE((p_updates->>'min_capacity')::INTEGER, min_capacity),
            price_member = COALESCE((p_updates->>'price_member')::DECIMAL, price_member),
            price_guest = COALESCE((p_updates->>'price_guest')::DECIMAL, price_guest),
            special_instructions = COALESCE(p_updates->>'special_instructions', special_instructions),
            updated_by = auth.uid(),
            updated_at = NOW()
        FROM events.event_series_instances esi
        WHERE e.id = esi.event_id
        AND esi.series_id = p_series_id
        AND e.is_cancelled = false;

        GET DIAGNOSTICS v_affected_count = ROW_COUNT;
    END IF;

    RETURN json_build_object(
        'series_id', p_series_id,
        'update_scope', p_update_scope,
        'affected_events', v_affected_count
    );
END;
$$;

COMMENT ON FUNCTION api.update_event_series IS 'Updates events in a series';

-- ============================================================================
-- REGISTER FOR EVENT
-- Registers a user for an event
-- ============================================================================

CREATE OR REPLACE FUNCTION api.register_for_event(
    p_event_id UUID,
    p_player_name VARCHAR DEFAULT NULL,
    p_player_email VARCHAR DEFAULT NULL,
    p_player_phone VARCHAR DEFAULT NULL,
    p_skill_level events.skill_level DEFAULT NULL,
    p_dupr_rating NUMERIC DEFAULT NULL,
    p_notes TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_registration_id UUID;
    v_status events.registration_status;
    v_current_registrations INTEGER;
    v_max_capacity INTEGER;
    v_waitlist_capacity INTEGER;
    v_result JSON;
    v_player_id UUID;
    v_player_first_name TEXT;
    v_player_last_name TEXT;
    v_player_email TEXT;
    v_event_type events.event_type;
    v_dupr_min_rating NUMERIC(3, 2);
    v_dupr_max_rating NUMERIC(3, 2);
    v_dupr_open_ended BOOLEAN;
    v_dupr_min_inclusive BOOLEAN;
    v_dupr_max_inclusive BOOLEAN;
    v_required_dupr BOOLEAN := false;
    v_player_dupr_rating NUMERIC(3, 2);
    v_effective_dupr_rating NUMERIC(3, 2);
BEGIN
    -- Get event details
    SELECT
        current_registrations,
        max_capacity,
        waitlist_capacity,
        event_type,
        dupr_min_rating,
        dupr_max_rating,
        dupr_open_ended,
        dupr_min_inclusive,
        dupr_max_inclusive
    INTO
        v_current_registrations,
        v_max_capacity,
        v_waitlist_capacity,
        v_event_type,
        v_dupr_min_rating,
        v_dupr_max_rating,
        v_dupr_open_ended,
        v_dupr_min_inclusive,
        v_dupr_max_inclusive
    FROM events.events
    WHERE id = p_event_id
    AND is_published = true
    AND is_cancelled = false
    AND start_time > NOW();

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Event not found or registration closed';
    END IF;

    v_required_dupr := v_event_type IN ('dupr_open_play', 'dupr_tournament');

    -- Resolve authenticated player profile if available
    IF auth.uid() IS NOT NULL THEN
        SELECT p.id, p.first_name, p.last_name, ua.email, p.dupr_rating
        INTO v_player_id, v_player_first_name, v_player_last_name, v_player_email, v_player_dupr_rating
        FROM app_auth.players p
        JOIN app_auth.user_accounts ua ON ua.id = p.account_id
        WHERE p.account_id = auth.uid();
    END IF;

    -- Check if already registered
    IF EXISTS (
        SELECT 1 FROM events.event_registrations
        WHERE event_id = p_event_id
        AND (
            (v_player_id IS NOT NULL AND user_id = v_player_id)
            OR (p_player_email IS NOT NULL AND player_email = p_player_email)
        )
        AND status IN ('registered', 'waitlisted')
    ) THEN
        RAISE EXCEPTION 'Already registered for this event';
    END IF;

    -- Validate DUPR requirements when applicable
    IF v_required_dupr THEN
        v_effective_dupr_rating := COALESCE(v_player_dupr_rating, p_dupr_rating);

        IF v_effective_dupr_rating IS NULL THEN
            RAISE EXCEPTION 'DUPR rating is required to register for this event';
        END IF;

        IF v_dupr_min_rating IS NOT NULL THEN
            IF v_dupr_min_inclusive THEN
                IF v_effective_dupr_rating < v_dupr_min_rating THEN
                    RAISE EXCEPTION 'Player DUPR rating % is below the minimum % for this event', v_effective_dupr_rating, v_dupr_min_rating;
                END IF;
            ELSE
                IF v_effective_dupr_rating <= v_dupr_min_rating THEN
                    RAISE EXCEPTION 'Player DUPR rating % must be greater than % for this event', v_effective_dupr_rating, v_dupr_min_rating;
                END IF;
            END IF;
        END IF;

        IF NOT v_dupr_open_ended AND v_dupr_max_rating IS NOT NULL THEN
            IF v_dupr_max_inclusive THEN
                IF v_effective_dupr_rating > v_dupr_max_rating THEN
                    RAISE EXCEPTION 'Player DUPR rating % exceeds the maximum % for this event', v_effective_dupr_rating, v_dupr_max_rating;
                END IF;
            ELSE
                IF v_effective_dupr_rating >= v_dupr_max_rating THEN
                    RAISE EXCEPTION 'Player DUPR rating % must be less than % for this event', v_effective_dupr_rating, v_dupr_max_rating;
                END IF;
            END IF;
        END IF;
    ELSE
        v_effective_dupr_rating := COALESCE(v_player_dupr_rating, p_dupr_rating);
    END IF;

    -- Determine registration status
    IF v_current_registrations < v_max_capacity THEN
        v_status := 'registered';
    ELSIF v_current_registrations < v_max_capacity + v_waitlist_capacity THEN
        v_status := 'waitlisted';
    ELSE
        RAISE EXCEPTION 'Event is full';
    END IF;

    -- Create registration
    INSERT INTO events.event_registrations (
        event_id,
        user_id,
        player_name,
        player_email,
        player_phone,
        skill_level,
        dupr_rating,
        status,
        notes
    ) VALUES (
        p_event_id,
        v_player_id,
        COALESCE(
            p_player_name,
            NULLIF(CONCAT_WS(' ', v_player_first_name, v_player_last_name), '')
        ),
        COALESCE(p_player_email, v_player_email),
        p_player_phone,
        p_skill_level,
        v_effective_dupr_rating,
        v_status,
        p_notes
    ) RETURNING id INTO v_registration_id;

    -- Return result
    SELECT json_build_object(
        'registration_id', v_registration_id,
        'event_id', p_event_id,
        'status', v_status,
        'dupr_rating', v_effective_dupr_rating,
        'position', CASE
            WHEN v_status = 'registered' THEN v_current_registrations + 1
            ELSE v_current_registrations - v_max_capacity + 1
        END
    ) INTO v_result;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION api.register_for_event IS 'Registers a user for an event';

-- ============================================================================
-- CANCEL EVENT REGISTRATION
-- Cancels a user's event registration
-- ============================================================================

CREATE OR REPLACE FUNCTION api.cancel_event_registration(
    p_registration_id UUID,
    p_reason TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_event_id UUID;
    v_user_id UUID;
    v_was_registered BOOLEAN;
    v_next_waitlist_id UUID;
    v_result JSON;
BEGIN
    -- Get registration details
    SELECT event_id, user_id, (status = 'registered')
    INTO v_event_id, v_user_id, v_was_registered
    FROM events.event_registrations
    WHERE id = p_registration_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Registration not found';
    END IF;

    -- Check permissions
    IF v_user_id != auth.uid() AND NOT events.is_staff() THEN
        RAISE EXCEPTION 'Unauthorized to cancel this registration';
    END IF;

    -- Update registration status
    UPDATE events.event_registrations
    SET
        status = 'cancelled',
        notes = COALESCE(notes || E'\n', '') || 'Cancelled: ' || COALESCE(p_reason, 'User requested'),
        updated_at = NOW()
    WHERE id = p_registration_id;

    -- If was registered, promote from waitlist
    IF v_was_registered THEN
        SELECT id INTO v_next_waitlist_id
        FROM events.event_registrations
        WHERE event_id = v_event_id
        AND status = 'waitlisted'
        ORDER BY registration_time
        LIMIT 1;

        IF v_next_waitlist_id IS NOT NULL THEN
            UPDATE events.event_registrations
            SET status = 'registered', updated_at = NOW()
            WHERE id = v_next_waitlist_id;
        END IF;
    END IF;

    -- Return result
    SELECT json_build_object(
        'registration_id', p_registration_id,
        'cancelled', true,
        'promoted_from_waitlist', v_next_waitlist_id
    ) INTO v_result;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION api.cancel_event_registration IS 'Cancels an event registration';

-- ============================================================================
-- GET EVENT CALENDAR
-- Returns events for calendar display
-- ============================================================================

CREATE OR REPLACE FUNCTION api.get_event_calendar(
    p_start_date DATE,
    p_end_date DATE,
    p_event_types events.event_type[] DEFAULT NULL,
    p_court_ids UUID[] DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_result JSON;
BEGIN
    SELECT json_build_object(
        'events', json_agg(
            json_build_object(
                'id', e.id,
                'title', e.title,
                'event_type', e.event_type,
                'start', e.start_time,
                'end', e.end_time,
                'color', CASE e.event_type
                    WHEN 'event_scramble' THEN '#B3FF00'
                    WHEN 'dupr_open_play' THEN '#0EA5E9'
                    WHEN 'dupr_tournament' THEN '#1D4ED8'
                    WHEN 'non_dupr_tournament' THEN '#EF4444'
                    WHEN 'league' THEN '#8B5CF6'
                    WHEN 'clinic' THEN '#10B981'
                    WHEN 'private_lesson' THEN '#64748B'
                    ELSE '#6B7280'
                END,
                'capacity', e.max_capacity,
                'registered', e.current_registrations,
                'dupr_range', CASE
                    WHEN e.event_type IN ('dupr_open_play', 'dupr_tournament') THEN json_build_object(
                        'label', e.dupr_range_label,
                        'min_rating', e.dupr_min_rating,
                        'max_rating', e.dupr_max_rating,
                        'min_inclusive', e.dupr_min_inclusive,
                        'max_inclusive', e.dupr_max_inclusive,
                        'open_ended', e.dupr_open_ended
                    )
                    ELSE NULL
                END,
                'courts', (
                    SELECT array_agg(c.court_number ORDER BY c.court_number)
                    FROM events.event_courts ec
                    JOIN events.courts c ON ec.court_id = c.id
                    WHERE ec.event_id = e.id
                )
            ) ORDER BY e.start_time
        ),
        'summary', json_build_object(
            'total_events', COUNT(e.id),
            'total_capacity', SUM(e.max_capacity),
            'total_registered', SUM(e.current_registrations)
        )
    ) INTO v_result
    FROM events.events e
    WHERE e.is_published = true
    AND e.is_cancelled = false
    AND DATE(e.start_time) >= p_start_date
    AND DATE(e.start_time) <= p_end_date
    AND (p_event_types IS NULL OR e.event_type = ANY(p_event_types))
    AND (p_court_ids IS NULL OR EXISTS (
        SELECT 1 FROM events.event_courts ec
        WHERE ec.event_id = e.id
        AND ec.court_id = ANY(p_court_ids)
    ));

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION api.get_event_calendar IS 'Returns events for calendar display';

-- ============================================================================
-- GET COURT SCHEDULE
-- Returns court bookings and availability for a time range
-- ============================================================================

CREATE OR REPLACE FUNCTION api.get_court_schedule(
    p_start_time TIMESTAMPTZ,
    p_end_time TIMESTAMPTZ,
    p_court_ids UUID[] DEFAULT NULL,
    p_environment events.court_environment DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_result JSON;
BEGIN
    SELECT json_build_object(
        'courts', json_agg(
            json_build_object(
                'court_id', c.id,
                'court_number', c.court_number,
                'court_name', c.name,
                'environment', c.environment,
                'location', c.location,
                'status', c.status,
                'bookings', (
                    SELECT json_agg(
                        json_build_object(
                            'event_id', e.id,
                            'event_title', e.title,
                            'event_type', e.event_type,
                            'start_time', e.start_time,
                            'end_time', e.end_time,
                            'is_cancelled', e.is_cancelled,
                            'current_registrations', e.current_registrations,
                            'max_capacity', e.max_capacity
                        ) ORDER BY e.start_time
                    )
                    FROM events.event_courts ec
                    JOIN events.events e ON ec.event_id = e.id
                    WHERE ec.court_id = c.id
                    AND (e.start_time, e.end_time) OVERLAPS (p_start_time, p_end_time)
                    AND e.is_cancelled = false
                ),
                'available_slots', (
                    SELECT json_agg(
                        json_build_object(
                            'start', slot_start,
                            'end', slot_end
                        ) ORDER BY slot_start
                    )
                    FROM (
                        SELECT
                            GREATEST(p_start_time, LAG(e.end_time, 1, p_start_time) OVER (ORDER BY e.start_time)) AS slot_start,
                            LEAST(p_end_time, e.start_time) AS slot_end
                        FROM events.event_courts ec
                        JOIN events.events e ON ec.event_id = e.id
                        WHERE ec.court_id = c.id
                        AND (e.start_time, e.end_time) OVERLAPS (p_start_time, p_end_time)
                        AND e.is_cancelled = false
                        UNION ALL
                        SELECT
                            GREATEST(p_start_time, COALESCE(MAX(e.end_time), p_start_time)) AS slot_start,
                            p_end_time AS slot_end
                        FROM events.event_courts ec
                        JOIN events.events e ON ec.event_id = e.id
                        WHERE ec.court_id = c.id
                        AND e.end_time <= p_end_time
                        AND e.is_cancelled = false
                    ) slots
                    WHERE slot_end > slot_start
                )
            ) ORDER BY c.court_number
        )
    ) INTO v_result
    FROM events.courts c
    WHERE (p_court_ids IS NULL OR c.id = ANY(p_court_ids))
    AND (p_environment IS NULL OR c.environment = p_environment)
    AND c.status != 'closed';

    RETURN COALESCE(v_result, json_build_object('courts', '[]'::json));
END;
$$;

COMMENT ON FUNCTION api.get_court_schedule IS 'Returns court bookings and availability for a time range';

-- ============================================================================
-- GET AVAILABLE COURTS
-- Returns courts that are available for a specific time slot
-- ============================================================================

CREATE OR REPLACE FUNCTION api.get_available_courts(
    p_start_time TIMESTAMPTZ,
    p_end_time TIMESTAMPTZ,
    p_environment events.court_environment DEFAULT NULL,
    p_min_courts INTEGER DEFAULT 1
)
RETURNS JSON
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_result JSON;
BEGIN
    WITH court_conflicts AS (
        SELECT
            c.id AS court_id,
            c.court_number,
            c.name AS court_name,
            c.environment,
            c.location,
            c.status,
            CASE
                WHEN c.status != 'available' THEN false
                WHEN EXISTS (
                    SELECT 1
                    FROM events.event_courts ec
                    JOIN events.events e ON ec.event_id = e.id
                    WHERE ec.court_id = c.id
                    AND e.is_cancelled = false
                    AND (e.start_time, e.end_time) OVERLAPS (p_start_time, p_end_time)
                ) THEN false
                ELSE true
            END AS is_available,
            (
                SELECT json_agg(
                    json_build_object(
                        'event_id', e.id,
                        'event_title', e.title,
                        'start_time', e.start_time,
                        'end_time', e.end_time
                    ) ORDER BY e.start_time
                )
                FROM events.event_courts ec
                JOIN events.events e ON ec.event_id = e.id
                WHERE ec.court_id = c.id
                AND e.is_cancelled = false
                AND (e.start_time, e.end_time) OVERLAPS (p_start_time, p_end_time)
            ) AS conflicts
        FROM events.courts c
        WHERE (p_environment IS NULL OR c.environment = p_environment)
    )
    SELECT json_build_object(
        'available_courts', (
            SELECT json_agg(
                json_build_object(
                    'court_id', court_id,
                    'court_number', court_number,
                    'court_name', court_name,
                    'environment', environment,
                    'location', location
                ) ORDER BY court_number
            )
            FROM court_conflicts
            WHERE is_available = true
        ),
        'unavailable_courts', (
            SELECT json_agg(
                json_build_object(
                    'court_id', court_id,
                    'court_number', court_number,
                    'court_name', court_name,
                    'environment', environment,
                    'location', location,
                    'status', status,
                    'conflicts', conflicts
                ) ORDER BY court_number
            )
            FROM court_conflicts
            WHERE is_available = false
        ),
        'total_available', (SELECT COUNT(*) FROM court_conflicts WHERE is_available = true),
        'meets_minimum', (SELECT COUNT(*) >= p_min_courts FROM court_conflicts WHERE is_available = true),
        'time_range', json_build_object(
            'start', p_start_time,
            'end', p_end_time
        )
    ) INTO v_result;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION api.get_available_courts IS 'Returns courts available for a specific time slot';

-- ============================================================================
-- GRANT EXECUTE PERMISSIONS
-- ============================================================================

GRANT EXECUTE ON FUNCTION api.create_event_with_courts TO authenticated;
GRANT EXECUTE ON FUNCTION api.create_recurring_events TO authenticated;
GRANT EXECUTE ON FUNCTION api.check_court_availability TO authenticated;
GRANT EXECUTE ON FUNCTION api.duplicate_event_template TO authenticated;
GRANT EXECUTE ON FUNCTION api.update_event_series TO authenticated;
GRANT EXECUTE ON FUNCTION api.register_for_event TO authenticated;
GRANT EXECUTE ON FUNCTION api.cancel_event_registration TO authenticated;
GRANT EXECUTE ON FUNCTION api.get_event_calendar TO authenticated, anon;
GRANT EXECUTE ON FUNCTION api.get_court_schedule TO authenticated, anon;
GRANT EXECUTE ON FUNCTION api.get_available_courts TO authenticated, anon;
-- ============================================================================
-- USER API FUNCTIONS MODULE
-- Functions for retrieving user information via API
-- ============================================================================

SET search_path TO api, app_auth, public;

-- ============================================================================
-- SESSION VERIFICATION FUNCTIONS
-- ============================================================================

-- Verify session token and return session details
CREATE OR REPLACE FUNCTION api.verify_session(
    session_token TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_session RECORD;
    v_account RECORD;
BEGIN
    -- Validate input
    IF session_token IS NULL OR session_token = '' THEN
        RETURN json_build_object(
            'valid', false,
            'error', 'Session token is required'
        );
    END IF;

    -- Find session by hashed token
    SELECT
        s.id,
        s.account_id,
        s.user_type,
        s.expires_at,
        s.created_at
    INTO v_session
    FROM app_auth.sessions s
    WHERE s.token_hash = encode(public.digest(session_token, 'sha256'), 'hex')
        AND s.expires_at > CURRENT_TIMESTAMP
    LIMIT 1;

    IF v_session.id IS NULL THEN
        RETURN json_build_object(
            'valid', false,
            'error', 'Invalid or expired session'
        );
    END IF;

    -- Get account details
    SELECT
        ua.id,
        ua.email,
        ua.user_type,
        ua.is_active,
        ua.is_verified,
        ua.last_login
    INTO v_account
    FROM app_auth.user_accounts ua
    WHERE ua.id = v_session.account_id;

    IF v_account.id IS NULL THEN
        RETURN json_build_object(
            'valid', false,
            'error', 'Account not found'
        );
    END IF;

    -- Check if account is active
    IF NOT v_account.is_active THEN
        RETURN json_build_object(
            'valid', false,
            'error', 'Account is inactive'
        );
    END IF;

    RETURN json_build_object(
        'valid', true,
        'session_id', v_session.id,
        'account_id', v_session.account_id,
        'user_type', v_session.user_type::TEXT,
        'email', v_account.email,
        'expires_at', v_session.expires_at
    );
END;
$$;

-- Get user information by session token
CREATE OR REPLACE FUNCTION api.get_user_by_session(
    session_token TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_session RECORD;
    v_account RECORD;
    v_admin RECORD;
    v_player RECORD;
    v_guest RECORD;
    v_user_info JSONB;
BEGIN
    -- First verify the session
    SELECT
        s.id,
        s.account_id,
        s.user_type,
        s.expires_at
    INTO v_session
    FROM app_auth.sessions s
    WHERE s.token_hash = encode(public.digest(session_token, 'sha256'), 'hex')
        AND s.expires_at > CURRENT_TIMESTAMP
    LIMIT 1;

    IF v_session.id IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Invalid or expired session'
        );
    END IF;

    -- Get account details
    SELECT
        ua.id,
        ua.email,
        ua.user_type,
        ua.is_active,
        ua.is_verified,
        ua.last_login,
        ua.created_at
    INTO v_account
    FROM app_auth.user_accounts ua
    WHERE ua.id = v_session.account_id;

    IF v_account.id IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Account not found'
        );
    END IF;

    -- Check if account is active
    IF NOT v_account.is_active THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Account is inactive'
        );
    END IF;

    -- Get user type specific information
    IF v_account.user_type = 'admin' THEN
        SELECT
            au.id,
            au.username,
            au.first_name,
            au.last_name,
            au.role,
            au.department,
            au.phone
        INTO v_admin
        FROM app_auth.admin_users au
        WHERE au.account_id = v_account.id;

        IF v_admin.id IS NULL THEN
            RETURN json_build_object(
                'success', false,
                'error', 'Admin profile not found'
            );
        END IF;

        v_user_info := jsonb_build_object(
            'id', v_admin.id,
            'account_id', v_account.id,
            'email', v_account.email,
            'username', v_admin.username,
            'first_name', v_admin.first_name,
            'last_name', v_admin.last_name,
            'position', v_admin.role::TEXT,
            'role', v_admin.role::TEXT,
            'department', v_admin.department,
            'phone', v_admin.phone,
            'user_type', 'admin',
            'is_verified', v_account.is_verified,
            'last_login', v_account.last_login,
            'created_at', v_account.created_at
        );

    ELSIF v_account.user_type = 'player' THEN
        SELECT
            p.id,
            p.first_name,
            p.last_name,
            p.display_name,
            p.phone,
            p.membership_level,
            p.skill_level,
            p.club_id
        INTO v_player
        FROM app_auth.players p
        WHERE p.account_id = v_account.id;

        IF v_player.id IS NULL THEN
            RETURN json_build_object(
                'success', false,
                'error', 'Player profile not found'
            );
        END IF;

        v_user_info := jsonb_build_object(
            'id', v_player.id,
            'account_id', v_account.id,
            'email', v_account.email,
            'first_name', v_player.first_name,
            'last_name', v_player.last_name,
            'display_name', v_player.display_name,
            'phone', v_player.phone,
            'position', COALESCE(v_player.membership_level::TEXT, 'player'),
            'role', 'player',
            'membership_level', v_player.membership_level::TEXT,
            'skill_level', v_player.skill_level::TEXT,
            'user_type', 'player',
            'is_verified', v_account.is_verified,
            'last_login', v_account.last_login,
            'created_at', v_account.created_at
        );

    ELSIF v_account.user_type = 'guest' THEN
        SELECT
            g.id,
            g.display_name,
            g.email,
            g.phone,
            g.expires_at
        INTO v_guest
        FROM app_auth.guest_users g
        WHERE g.account_id = v_account.id;

        IF v_guest.id IS NULL THEN
            RETURN json_build_object(
                'success', false,
                'error', 'Guest profile not found'
            );
        END IF;

        -- Check if guest access has expired
        IF v_guest.expires_at < CURRENT_TIMESTAMP THEN
            RETURN json_build_object(
                'success', false,
                'error', 'Guest access has expired'
            );
        END IF;

        v_user_info := jsonb_build_object(
            'id', v_guest.id,
            'account_id', v_account.id,
            'email', COALESCE(v_guest.email, v_account.email),
            'first_name', v_guest.display_name,
            'last_name', '',
            'display_name', v_guest.display_name,
            'phone', v_guest.phone,
            'position', 'guest',
            'role', 'guest',
            'user_type', 'guest',
            'expires_at', v_guest.expires_at,
            'is_verified', v_account.is_verified,
            'last_login', v_account.last_login,
            'created_at', v_account.created_at
        );

    ELSE
        RETURN json_build_object(
            'success', false,
            'error', 'Unknown user type'
        );
    END IF;

    RETURN json_build_object(
        'success', true,
        'user', v_user_info
    );
END;
$$;

-- Get current user (simpler version for authenticated users)
CREATE OR REPLACE FUNCTION api.get_current_user(
    session_token TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN api.get_user_by_session(session_token);
END;
$$;

-- ============================================================================
-- GRANT EXECUTE PERMISSIONS
-- ============================================================================

-- These functions require authentication via session token
GRANT EXECUTE ON FUNCTION api.verify_session TO anon;
GRANT EXECUTE ON FUNCTION api.verify_session TO authenticated;
GRANT EXECUTE ON FUNCTION api.verify_session TO service_role;

GRANT EXECUTE ON FUNCTION api.get_user_by_session TO anon;
GRANT EXECUTE ON FUNCTION api.get_user_by_session TO authenticated;
GRANT EXECUTE ON FUNCTION api.get_user_by_session TO service_role;

GRANT EXECUTE ON FUNCTION api.get_current_user TO anon;
GRANT EXECUTE ON FUNCTION api.get_current_user TO authenticated;
GRANT EXECUTE ON FUNCTION api.get_current_user TO service_role;-- ============================================================================
-- PROFILE IMAGES MODULE
-- Add avatar/image URL support for user profiles
-- ============================================================================

SET search_path TO app_auth, public;

-- --------------------------------------------------------------------------
-- Add avatar_url columns to profile tables
-- --------------------------------------------------------------------------

-- Admin users avatars
ALTER TABLE app_auth.admin_users
ADD COLUMN IF NOT EXISTS avatar_url TEXT,
ADD COLUMN IF NOT EXISTS avatar_thumbnail_url TEXT;

-- Player avatars
ALTER TABLE app_auth.players
ADD COLUMN IF NOT EXISTS avatar_url TEXT,
ADD COLUMN IF NOT EXISTS avatar_thumbnail_url TEXT;

-- Guest avatars (commented out - guests table doesn't exist)
-- ALTER TABLE app_auth.guests
-- ADD COLUMN IF NOT EXISTS avatar_url TEXT,
-- ADD COLUMN IF NOT EXISTS avatar_thumbnail_url TEXT;

-- --------------------------------------------------------------------------
-- Image metadata table for tracking uploads
-- --------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS app_auth.user_images (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    account_id UUID NOT NULL REFERENCES app_auth.user_accounts(id) ON DELETE CASCADE,
    image_type VARCHAR(50) NOT NULL DEFAULT 'avatar', -- avatar, banner, etc.
    original_url TEXT NOT NULL,
    thumbnail_url TEXT,
    cdn_url TEXT,
    file_size INTEGER,
    mime_type VARCHAR(100),
    width INTEGER,
    height INTEGER,
    storage_provider VARCHAR(50) DEFAULT 'supabase', -- supabase, cloudflare, s3, local
    is_active BOOLEAN DEFAULT true,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_image_type CHECK (image_type IN ('avatar', 'banner', 'gallery'))
);

-- Index for quick lookups
CREATE INDEX IF NOT EXISTS idx_user_images_account_type
ON app_auth.user_images(account_id, image_type, is_active);

-- --------------------------------------------------------------------------
-- Update the get_user_info function to include avatar URLs
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION api.get_user_info(
    p_session_token TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_session RECORD;
    v_account RECORD;
    v_admin RECORD;
    v_player RECORD;
    v_guest RECORD;
    v_user_info JSONB;
BEGIN
    -- Validate input
    IF p_session_token IS NULL OR p_session_token = '' THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Session token is required'
        );
    END IF;

    -- Find session by hashed token
    SELECT
        s.id,
        s.account_id,
        s.user_type,
        s.expires_at
    INTO v_session
    FROM app_auth.sessions s
    WHERE s.token_hash = encode(public.digest(p_session_token, 'sha256'), 'hex')
        AND s.expires_at > CURRENT_TIMESTAMP
    LIMIT 1;

    IF v_session.id IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Invalid or expired session'
        );
    END IF;

    -- Get account details
    SELECT
        ua.id,
        ua.email,
        ua.user_type,
        ua.is_active,
        ua.is_verified,
        ua.last_login,
        ua.created_at
    INTO v_account
    FROM app_auth.user_accounts ua
    WHERE ua.id = v_session.account_id;

    IF v_account.id IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Account not found'
        );
    END IF;

    -- Check if account is active
    IF NOT v_account.is_active THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Account is inactive'
        );
    END IF;

    -- Build user info based on user type
    IF v_account.user_type = 'admin' THEN
        SELECT
            au.id,
            au.username,
            au.first_name,
            au.last_name,
            au.role,
            au.department,
            au.phone,
            au.avatar_url,
            au.avatar_thumbnail_url
        INTO v_admin
        FROM app_auth.admin_users au
        WHERE au.account_id = v_account.id;

        IF v_admin.id IS NULL THEN
            RETURN json_build_object(
                'success', false,
                'error', 'Admin profile not found'
            );
        END IF;

        v_user_info := jsonb_build_object(
            'id', v_admin.id,
            'account_id', v_account.id,
            'email', v_account.email,
            'username', v_admin.username,
            'first_name', v_admin.first_name,
            'last_name', v_admin.last_name,
            'position', v_admin.role::TEXT,
            'role', v_admin.role::TEXT,
            'department', v_admin.department,
            'phone', v_admin.phone,
            'avatar_url', v_admin.avatar_url,
            'avatar_thumbnail_url', v_admin.avatar_thumbnail_url,
            'user_type', 'admin',
            'is_verified', v_account.is_verified,
            'last_login', v_account.last_login,
            'created_at', v_account.created_at
        );

    ELSIF v_account.user_type = 'player' THEN
        SELECT
            p.id,
            p.first_name,
            p.last_name,
            p.display_name,
            p.phone,
            p.membership_level,
            p.skill_level,
            p.club_id,
            p.avatar_url,
            p.avatar_thumbnail_url
        INTO v_player
        FROM app_auth.players p
        WHERE p.account_id = v_account.id;

        IF v_player.id IS NULL THEN
            RETURN json_build_object(
                'success', false,
                'error', 'Player profile not found'
            );
        END IF;

        v_user_info := jsonb_build_object(
            'id', v_player.id,
            'account_id', v_account.id,
            'email', v_account.email,
            'first_name', v_player.first_name,
            'last_name', v_player.last_name,
            'display_name', v_player.display_name,
            'phone', v_player.phone,
            'avatar_url', v_player.avatar_url,
            'avatar_thumbnail_url', v_player.avatar_thumbnail_url,
            'position', COALESCE(v_player.membership_level::TEXT, 'player'),
            'role', 'player',
            'membership_level', v_player.membership_level::TEXT,
            'skill_level', v_player.skill_level::TEXT,
            'user_type', 'player',
            'is_verified', v_account.is_verified,
            'last_login', v_account.last_login,
            'created_at', v_account.created_at
        );

    ELSIF v_account.user_type = 'guest' THEN
        -- Guest profile handling (guests table doesn't exist yet)
        RETURN json_build_object(
            'success', false,
            'error', 'Guest profiles are not implemented'
        );
    END IF;

    RETURN json_build_object(
        'success', true,
        'data', v_user_info
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'success', false,
            'error', 'An unexpected error occurred: ' || SQLERRM
        );
END;
$$;

-- --------------------------------------------------------------------------
-- Function to update user avatar URL
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION api.update_user_avatar(
    p_session_token TEXT,
    p_avatar_url TEXT,
    p_thumbnail_url TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_session RECORD;
    v_account RECORD;
    v_updated BOOLEAN := FALSE;
BEGIN
    -- Validate input
    IF p_session_token IS NULL OR p_session_token = '' THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Session token is required'
        );
    END IF;

    -- Find session
    SELECT
        s.id,
        s.account_id,
        s.user_type
    INTO v_session
    FROM app_auth.sessions s
    WHERE s.token_hash = encode(public.digest(p_session_token, 'sha256'), 'hex')
        AND s.expires_at > CURRENT_TIMESTAMP
    LIMIT 1;

    IF v_session.id IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Invalid or expired session'
        );
    END IF;

    -- Get account details
    SELECT
        ua.id,
        ua.user_type,
        ua.is_active
    INTO v_account
    FROM app_auth.user_accounts ua
    WHERE ua.id = v_session.account_id;

    IF NOT v_account.is_active THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Account is inactive'
        );
    END IF;

    -- Update avatar based on user type
    IF v_account.user_type = 'admin' THEN
        UPDATE app_auth.admin_users
        SET
            avatar_url = p_avatar_url,
            avatar_thumbnail_url = COALESCE(p_thumbnail_url, avatar_thumbnail_url),
            updated_at = CURRENT_TIMESTAMP
        WHERE account_id = v_account.id;
        v_updated := FOUND;

    ELSIF v_account.user_type = 'player' THEN
        UPDATE app_auth.players
        SET
            avatar_url = p_avatar_url,
            avatar_thumbnail_url = COALESCE(p_thumbnail_url, avatar_thumbnail_url),
            updated_at = CURRENT_TIMESTAMP
        WHERE account_id = v_account.id;
        v_updated := FOUND;

    ELSIF v_account.user_type = 'guest' THEN
        -- Guest avatar updates not implemented (guests table doesn't exist)
        RETURN json_build_object(
            'success', false,
            'error', 'Guest avatar updates are not implemented'
        );
    END IF;

    IF v_updated THEN
        -- Log the image upload
        INSERT INTO app_auth.user_images (
            account_id,
            image_type,
            original_url,
            thumbnail_url,
            is_active
        ) VALUES (
            v_account.id,
            'avatar',
            p_avatar_url,
            p_thumbnail_url,
            true
        );

        -- Deactivate old avatars
        UPDATE app_auth.user_images
        SET is_active = false
        WHERE account_id = v_account.id
            AND image_type = 'avatar'
            AND original_url != p_avatar_url;

        RETURN json_build_object(
            'success', true,
            'message', 'Avatar updated successfully',
            'avatar_url', p_avatar_url,
            'thumbnail_url', p_thumbnail_url
        );
    ELSE
        RETURN json_build_object(
            'success', false,
            'error', 'Failed to update avatar'
        );
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'success', false,
            'error', 'An unexpected error occurred: ' || SQLERRM
        );
END;
$$;

-- --------------------------------------------------------------------------
-- Grant necessary permissions
-- --------------------------------------------------------------------------
GRANT SELECT ON app_auth.user_images TO postgres;
GRANT INSERT, UPDATE ON app_auth.user_images TO postgres;
GRANT EXECUTE ON FUNCTION api.update_user_avatar TO postgres;-- ============================================================================
-- POSTGREST CONFIGURATION MODULE
-- Ensures PostgREST can access the api schema and functions
-- ============================================================================

-- Grant usage on api schema to PostgREST roles
GRANT USAGE ON SCHEMA api TO anon, authenticated, service_role;

-- Grant execute permissions on all existing functions in api schema
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO anon, authenticated, service_role;

-- Set default privileges for future functions in api schema
ALTER DEFAULT PRIVILEGES IN SCHEMA api
    GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role;

-- Ensure specific login functions are accessible
DO $$
BEGIN
    -- Check if functions exist before granting
    IF EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'api' AND p.proname = 'login'
    ) THEN
        GRANT EXECUTE ON FUNCTION api.login(text, text) TO anon, authenticated, service_role;
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'api' AND p.proname = 'login_safe'
    ) THEN
        GRANT EXECUTE ON FUNCTION api.login_safe(text, text) TO anon, authenticated, service_role;
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'api' AND p.proname = 'get_user_by_session'
    ) THEN
        GRANT EXECUTE ON FUNCTION api.get_user_by_session(text) TO anon, authenticated, service_role;
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'api' AND p.proname = 'verify_session'
    ) THEN
        GRANT EXECUTE ON FUNCTION api.verify_session(text) TO anon, authenticated, service_role;
    END IF;

    -- Grant permissions for player management functions
    IF EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'api' AND p.proname = 'create_player_account'
    ) THEN
        GRANT EXECUTE ON FUNCTION api.create_player_account TO authenticated, service_role;
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'api' AND p.proname = 'list_player_accounts'
    ) THEN
        GRANT EXECUTE ON FUNCTION api.list_player_accounts TO authenticated, service_role;
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'api' AND p.proname = 'get_player_account'
    ) THEN
        GRANT EXECUTE ON FUNCTION api.get_player_account TO authenticated, service_role;
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'api' AND p.proname = 'update_player_account'
    ) THEN
        GRANT EXECUTE ON FUNCTION api.update_player_account TO authenticated, service_role;
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'api' AND p.proname = 'delete_player_account'
    ) THEN
        GRANT EXECUTE ON FUNCTION api.delete_player_account TO authenticated, service_role;
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'api' AND p.proname = 'reset_player_password'
    ) THEN
        GRANT EXECUTE ON FUNCTION api.reset_player_password TO authenticated, service_role;
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'api' AND p.proname = 'get_all_account_stats'
    ) THEN
        GRANT EXECUTE ON FUNCTION api.get_all_account_stats TO authenticated, service_role;
    END IF;
END;
$$;

-- Notify PostgREST to reload schema cache
NOTIFY pgrst, 'reload schema';

-- Add comment for documentation
COMMENT ON SCHEMA api IS 'API schema for PostgREST endpoints - contains functions exposed as REST endpoints';-- ============================================================================
-- ACCOUNT MANAGEMENT MODULE
-- Functions for managing admin/employee accounts
-- ============================================================================

SET search_path TO api, app_auth, public;

-- ============================================================================
-- ACCOUNT MANAGEMENT FUNCTIONS
-- ============================================================================

-- List all admin accounts with filters
CREATE OR REPLACE FUNCTION api.list_admin_accounts(
    p_search TEXT DEFAULT NULL,
    p_role app_auth.admin_role DEFAULT NULL,
    p_status TEXT DEFAULT NULL,
    p_department TEXT DEFAULT NULL,
    p_limit INT DEFAULT 50,
    p_offset INT DEFAULT 0
)
RETURNS JSON
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
    v_result JSON;
    v_total INT;
BEGIN
    -- Get total count
    SELECT COUNT(*)
    INTO v_total
    FROM app_auth.user_accounts ua
    JOIN app_auth.admin_users au ON au.account_id = ua.id
    WHERE ua.user_type = 'admin'
        AND (p_search IS NULL OR (
            au.first_name ILIKE '%' || p_search || '%'
            OR au.last_name ILIKE '%' || p_search || '%'
            OR au.username ILIKE '%' || p_search || '%'
            OR ua.email ILIKE '%' || p_search || '%'
        ))
        AND (p_role IS NULL OR au.role = p_role)
        AND (p_status IS NULL OR (
            (p_status = 'active' AND ua.is_active = true)
            OR (p_status = 'inactive' AND ua.is_active = false)
        ))
        AND (p_department IS NULL OR au.department ILIKE '%' || p_department || '%');

    -- Get paginated results
    SELECT json_build_object(
        'success', true,
        'total', v_total,
        'limit', p_limit,
        'offset', p_offset,
        'data', COALESCE(json_agg(
            json_build_object(
                'id', au.id,
                'account_id', ua.id,
                'email', ua.email,
                'username', au.username,
                'first_name', au.first_name,
                'last_name', au.last_name,
                'full_name', au.first_name || ' ' || au.last_name,
                'role', au.role,
                'department', au.department,
                'phone', au.phone,
                'is_active', ua.is_active,
                'is_verified', ua.is_verified,
                'last_login', ua.last_login,
                'failed_login_attempts', ua.failed_login_attempts,
                'locked_until', ua.locked_until,
                'created_at', au.created_at,
                'updated_at', au.updated_at
            ) ORDER BY au.created_at DESC
        ), '[]'::json)
    )
    INTO v_result
    FROM app_auth.user_accounts ua
    JOIN app_auth.admin_users au ON au.account_id = ua.id
    WHERE ua.user_type = 'admin'
        AND (p_search IS NULL OR (
            au.first_name ILIKE '%' || p_search || '%'
            OR au.last_name ILIKE '%' || p_search || '%'
            OR au.username ILIKE '%' || p_search || '%'
            OR ua.email ILIKE '%' || p_search || '%'
        ))
        AND (p_role IS NULL OR au.role = p_role)
        AND (p_status IS NULL OR (
            (p_status = 'active' AND ua.is_active = true)
            OR (p_status = 'inactive' AND ua.is_active = false)
        ))
        AND (p_department IS NULL OR au.department ILIKE '%' || p_department || '%')
    LIMIT p_limit
    OFFSET p_offset;

    RETURN v_result;
END;
$$;

-- Get single admin account details
CREATE OR REPLACE FUNCTION api.get_admin_account(
    p_account_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
    v_result JSON;
BEGIN
    SELECT json_build_object(
        'success', true,
        'data', json_build_object(
            'id', au.id,
            'account_id', ua.id,
            'email', ua.email,
            'username', au.username,
            'first_name', au.first_name,
            'last_name', au.last_name,
            'full_name', au.first_name || ' ' || au.last_name,
            'role', au.role,
            'department', au.department,
            'phone', au.phone,
            'is_active', ua.is_active,
            'is_verified', ua.is_verified,
            'last_login', ua.last_login,
            'failed_login_attempts', ua.failed_login_attempts,
            'locked_until', ua.locked_until,
            'created_at', au.created_at,
            'updated_at', au.updated_at
        )
    )
    INTO v_result
    FROM app_auth.user_accounts ua
    JOIN app_auth.admin_users au ON au.account_id = ua.id
    WHERE au.id = p_account_id OR ua.id = p_account_id;

    IF v_result IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'Account not found');
    END IF;

    RETURN v_result;
END;
$$;

-- Create new admin account
CREATE OR REPLACE FUNCTION api.create_admin_account(
    p_email TEXT,
    p_username TEXT,
    p_password TEXT,
    p_first_name TEXT,
    p_last_name TEXT,
    p_role app_auth.admin_role DEFAULT 'viewer',
    p_department TEXT DEFAULT NULL,
    p_phone TEXT DEFAULT NULL,
    p_created_by UUID DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_account_id UUID;
    v_admin_id UUID;
    v_password_hash TEXT;
BEGIN
    -- Check if email already exists
    IF EXISTS (SELECT 1 FROM app_auth.user_accounts WHERE email = lower(p_email)) THEN
        RETURN json_build_object('success', false, 'error', 'Email already exists');
    END IF;

    -- Check if username already exists
    IF EXISTS (SELECT 1 FROM app_auth.admin_users WHERE username = lower(p_username)) THEN
        RETURN json_build_object('success', false, 'error', 'Username already taken');
    END IF;

    -- Hash the password
    v_password_hash := hash_password(p_password);

    -- Create user account
    INSERT INTO app_auth.user_accounts (
        email,
        password_hash,
        user_type,
        is_active,
        is_verified
    ) VALUES (
        lower(p_email),
        v_password_hash,
        'admin',
        true,
        true -- Auto-verify admin accounts created by other admins
    ) RETURNING id INTO v_account_id;

    -- Create admin profile
    INSERT INTO app_auth.admin_users (
        account_id,
        username,
        first_name,
        last_name,
        role,
        department,
        phone
    ) VALUES (
        v_account_id,
        lower(p_username),
        p_first_name,
        p_last_name,
        p_role,
        p_department,
        p_phone
    ) RETURNING id INTO v_admin_id;

    -- Log activity if created_by is provided
    IF p_created_by IS NOT NULL THEN
        INSERT INTO system.activity_logs (
            user_id,
            action,
            entity_type,
            entity_id,
            details
        ) VALUES (
            p_created_by,
            'admin_account_created',
            'admin_user',
            v_admin_id,
            jsonb_build_object(
                'email', p_email,
                'username', p_username,
                'role', p_role
            )
        );
    END IF;

    RETURN json_build_object(
        'success', true,
        'id', v_admin_id,
        'account_id', v_account_id,
        'message', 'Account created successfully'
    );
END;
$$;

-- Update admin account
CREATE OR REPLACE FUNCTION api.update_admin_account(
    p_account_id UUID,
    p_first_name TEXT DEFAULT NULL,
    p_last_name TEXT DEFAULT NULL,
    p_role app_auth.admin_role DEFAULT NULL,
    p_department TEXT DEFAULT NULL,
    p_phone TEXT DEFAULT NULL,
    p_is_active BOOLEAN DEFAULT NULL,
    p_updated_by UUID DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_admin RECORD;
    v_old_values JSONB;
    v_new_values JSONB;
BEGIN
    -- Get current admin details
    SELECT au.*, ua.is_active
    INTO v_admin
    FROM app_auth.admin_users au
    JOIN app_auth.user_accounts ua ON ua.id = au.account_id
    WHERE au.id = p_account_id OR au.account_id = p_account_id;

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Account not found');
    END IF;

    -- Store old values for audit
    v_old_values := jsonb_build_object(
        'first_name', v_admin.first_name,
        'last_name', v_admin.last_name,
        'role', v_admin.role,
        'department', v_admin.department,
        'phone', v_admin.phone,
        'is_active', v_admin.is_active
    );

    -- Update admin profile
    UPDATE app_auth.admin_users
    SET first_name = COALESCE(p_first_name, first_name),
        last_name = COALESCE(p_last_name, last_name),
        role = COALESCE(p_role, role),
        department = COALESCE(p_department, department),
        phone = COALESCE(p_phone, phone),
        updated_at = CURRENT_TIMESTAMP
    WHERE id = v_admin.id;

    -- Update account status if provided
    IF p_is_active IS NOT NULL THEN
        UPDATE app_auth.user_accounts
        SET is_active = p_is_active
        WHERE id = v_admin.account_id;
    END IF;

    -- Store new values for audit
    v_new_values := jsonb_build_object(
        'first_name', COALESCE(p_first_name, v_admin.first_name),
        'last_name', COALESCE(p_last_name, v_admin.last_name),
        'role', COALESCE(p_role, v_admin.role),
        'department', COALESCE(p_department, v_admin.department),
        'phone', COALESCE(p_phone, v_admin.phone),
        'is_active', COALESCE(p_is_active, v_admin.is_active)
    );

    -- Log activity if updated_by is provided
    IF p_updated_by IS NOT NULL THEN
        INSERT INTO system.activity_logs (
            user_id,
            action,
            entity_type,
            entity_id,
            details
        ) VALUES (
            p_updated_by,
            'admin_account_updated',
            'admin_user',
            v_admin.id,
            jsonb_build_object(
                'old_values', v_old_values,
                'new_values', v_new_values
            )
        );
    END IF;

    RETURN json_build_object(
        'success', true,
        'message', 'Account updated successfully'
    );
END;
$$;

-- Delete/deactivate admin account
CREATE OR REPLACE FUNCTION api.delete_admin_account(
    p_account_id UUID,
    p_hard_delete BOOLEAN DEFAULT FALSE,
    p_deleted_by UUID DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_admin RECORD;
BEGIN
    -- Get admin details
    SELECT au.*, ua.email
    INTO v_admin
    FROM app_auth.admin_users au
    JOIN app_auth.user_accounts ua ON ua.id = au.account_id
    WHERE au.id = p_account_id OR au.account_id = p_account_id;

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Account not found');
    END IF;

    -- Prevent self-deletion
    IF p_deleted_by IS NOT NULL AND v_admin.id = p_deleted_by THEN
        RETURN json_build_object('success', false, 'error', 'Cannot delete your own account');
    END IF;

    IF p_hard_delete THEN
        -- Hard delete - remove from database
        DELETE FROM app_auth.user_accounts WHERE id = v_admin.account_id;

        -- Log activity if deleted_by is provided
        IF p_deleted_by IS NOT NULL THEN
            INSERT INTO system.activity_logs (
                user_id,
                action,
                entity_type,
                entity_id,
                details
            ) VALUES (
                p_deleted_by,
                'admin_account_deleted',
                'admin_user',
                v_admin.id,
                jsonb_build_object(
                    'email', v_admin.email,
                    'username', v_admin.username,
                    'hard_delete', true
                )
            );
        END IF;

        RETURN json_build_object(
            'success', true,
            'message', 'Account permanently deleted'
        );
    ELSE
        -- Soft delete - deactivate account
        UPDATE app_auth.user_accounts
        SET is_active = false
        WHERE id = v_admin.account_id;

        -- Log activity if deleted_by is provided
        IF p_deleted_by IS NOT NULL THEN
            INSERT INTO system.activity_logs (
                user_id,
                action,
                entity_type,
                entity_id,
                details
            ) VALUES (
                p_deleted_by,
                'admin_account_deactivated',
                'admin_user',
                v_admin.id,
                jsonb_build_object(
                    'email', v_admin.email,
                    'username', v_admin.username
                )
            );
        END IF;

        RETURN json_build_object(
            'success', true,
            'message', 'Account deactivated successfully'
        );
    END IF;
END;
$$;

-- Reset admin account password
CREATE OR REPLACE FUNCTION api.reset_admin_password(
    p_account_id UUID,
    p_new_password TEXT,
    p_reset_by UUID DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_admin RECORD;
    v_password_hash TEXT;
BEGIN
    -- Get admin details
    SELECT au.*, ua.email
    INTO v_admin
    FROM app_auth.admin_users au
    JOIN app_auth.user_accounts ua ON ua.id = au.account_id
    WHERE au.id = p_account_id OR au.account_id = p_account_id;

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Account not found');
    END IF;

    -- Hash the new password
    v_password_hash := hash_password(p_new_password);

    -- Update password
    UPDATE app_auth.user_accounts
    SET password_hash = v_password_hash,
        failed_login_attempts = 0,
        locked_until = NULL
    WHERE id = v_admin.account_id;

    -- Log activity if reset_by is provided
    IF p_reset_by IS NOT NULL THEN
        INSERT INTO system.activity_logs (
            user_id,
            action,
            entity_type,
            entity_id,
            details
        ) VALUES (
            p_reset_by,
            'admin_password_reset',
            'admin_user',
            v_admin.id,
            jsonb_build_object(
                'email', v_admin.email,
                'username', v_admin.username
            )
        );
    END IF;

    RETURN json_build_object(
        'success', true,
        'message', 'Password reset successfully'
    );
END;
$$;

-- Toggle account status
CREATE OR REPLACE FUNCTION api.toggle_account_status(
    p_account_id UUID,
    p_toggled_by UUID DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_admin RECORD;
    v_new_status BOOLEAN;
BEGIN
    -- Get current status
    SELECT au.*, ua.is_active, ua.email
    INTO v_admin
    FROM app_auth.admin_users au
    JOIN app_auth.user_accounts ua ON ua.id = au.account_id
    WHERE au.id = p_account_id OR au.account_id = p_account_id;

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Account not found');
    END IF;

    -- Toggle status
    v_new_status := NOT v_admin.is_active;

    UPDATE app_auth.user_accounts
    SET is_active = v_new_status
    WHERE id = v_admin.account_id;

    -- Log activity if toggled_by is provided
    IF p_toggled_by IS NOT NULL THEN
        INSERT INTO system.activity_logs (
            user_id,
            action,
            entity_type,
            entity_id,
            details
        ) VALUES (
            p_toggled_by,
            CASE WHEN v_new_status THEN 'admin_account_activated' ELSE 'admin_account_deactivated' END,
            'admin_user',
            v_admin.id,
            jsonb_build_object(
                'email', v_admin.email,
                'username', v_admin.username,
                'new_status', v_new_status
            )
        );
    END IF;

    RETURN json_build_object(
        'success', true,
        'is_active', v_new_status,
        'message', CASE WHEN v_new_status THEN 'Account activated' ELSE 'Account deactivated' END
    );
END;
$$;

-- Get account statistics
CREATE OR REPLACE FUNCTION api.get_account_stats()
RETURNS JSON
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
    v_stats JSON;
BEGIN
    SELECT json_build_object(
        'total_accounts', COUNT(*),
        'active_accounts', COUNT(*) FILTER (WHERE ua.is_active = true),
        'inactive_accounts', COUNT(*) FILTER (WHERE ua.is_active = false),
        'by_role', (
            SELECT json_object_agg(role, role_count)
            FROM (
                SELECT au2.role, COUNT(*) as role_count
                FROM app_auth.admin_users au2
                GROUP BY au2.role
            ) role_counts
        ),
        'recent_logins', (
            SELECT COUNT(*)
            FROM app_auth.user_accounts ua2
            JOIN app_auth.admin_users au2 ON au2.account_id = ua2.id
            WHERE ua2.last_login >= CURRENT_TIMESTAMP - INTERVAL '24 hours'
        ),
        'locked_accounts', COUNT(*) FILTER (WHERE ua.locked_until > CURRENT_TIMESTAMP)
    )
    INTO v_stats
    FROM app_auth.user_accounts ua
    JOIN app_auth.admin_users au ON au.account_id = ua.id
    WHERE ua.user_type = 'admin';

    RETURN json_build_object('success', true, 'data', v_stats);
END;
$$;

-- ============================================================================
-- PLAYER ACCOUNT MANAGEMENT FUNCTIONS
-- ============================================================================

-- Create new player account (by admin)
CREATE OR REPLACE FUNCTION api.create_player_account(
    p_email TEXT,
    p_password TEXT,
    p_first_name TEXT,
    p_last_name TEXT,
    p_display_name TEXT DEFAULT NULL,
    p_phone TEXT DEFAULT NULL,
    p_address TEXT DEFAULT NULL,
    p_dupr_rating NUMERIC(3, 2) DEFAULT NULL,
    p_membership_level app_auth.membership_level DEFAULT 'basic',
    p_skill_level app_auth.skill_level DEFAULT NULL,
    p_created_by UUID DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_account_id UUID;
    v_player_id UUID;
    v_password_hash TEXT;
BEGIN
    -- Check if email already exists
    IF EXISTS (SELECT 1 FROM app_auth.user_accounts WHERE email = lower(p_email)) THEN
        RETURN json_build_object('success', false, 'error', 'Email already exists');
    END IF;

    -- Hash the password
    v_password_hash := hash_password(p_password);

    -- Create user account
    INSERT INTO app_auth.user_accounts (
        email,
        password_hash,
        user_type,
        is_active,
        is_verified
    ) VALUES (
        lower(p_email),
        v_password_hash,
        'player',
        true,
        true -- Auto-verify player accounts created by admins
    ) RETURNING id INTO v_account_id;

    -- Create player profile
    INSERT INTO app_auth.players (
        account_id,
        first_name,
        last_name,
        display_name,
        phone,
        address,
        dupr_rating,
        dupr_rating_updated_at,
        membership_level,
        skill_level,
        membership_started_on
    ) VALUES (
        v_account_id,
        p_first_name,
        p_last_name,
        COALESCE(p_display_name, p_first_name || ' ' || SUBSTRING(p_last_name, 1, 1)),
        p_phone,
        p_address,
        p_dupr_rating,
        CASE WHEN p_dupr_rating IS NOT NULL THEN CURRENT_TIMESTAMP ELSE NULL END,
        p_membership_level,
        p_skill_level,
        CURRENT_DATE
    ) RETURNING id INTO v_player_id;

    -- Log activity if created_by is provided
    IF p_created_by IS NOT NULL THEN
        INSERT INTO system.activity_logs (
            user_id,
            action,
            entity_type,
            entity_id,
            details
        ) VALUES (
            p_created_by,
            'player_account_created',
            'player',
            v_player_id,
            jsonb_build_object(
                'email', p_email,
                'first_name', p_first_name,
                'last_name', p_last_name,
                'membership_level', p_membership_level
            )
        );
    END IF;

    RETURN json_build_object(
        'success', true,
        'id', v_player_id,
        'account_id', v_account_id,
        'message', 'Player account created successfully'
    );
END;
$$;

-- List all player accounts with filters
CREATE OR REPLACE FUNCTION api.list_player_accounts(
    p_search TEXT DEFAULT NULL,
    p_membership_level app_auth.membership_level DEFAULT NULL,
    p_skill_level app_auth.skill_level DEFAULT NULL,
    p_status TEXT DEFAULT NULL,
    p_limit INT DEFAULT 50,
    p_offset INT DEFAULT 0
)
RETURNS JSON
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
    v_result JSON;
    v_total INT;
BEGIN
    -- Get total count
    SELECT COUNT(*)
    INTO v_total
    FROM app_auth.user_accounts ua
    JOIN app_auth.players p ON p.account_id = ua.id
    WHERE ua.user_type = 'player'
        AND (p_search IS NULL OR (
            p.first_name ILIKE '%' || p_search || '%'
            OR p.last_name ILIKE '%' || p_search || '%'
            OR p.display_name ILIKE '%' || p_search || '%'
            OR ua.email ILIKE '%' || p_search || '%'
            OR p.phone ILIKE '%' || p_search || '%'
        ))
        AND (p_membership_level IS NULL OR p.membership_level = p_membership_level)
        AND (p_skill_level IS NULL OR p.skill_level = p_skill_level)
        AND (p_status IS NULL OR (
            (p_status = 'active' AND ua.is_active = true)
            OR (p_status = 'inactive' AND ua.is_active = false)
        ));

    -- Get paginated results
    SELECT json_build_object(
        'success', true,
        'total', v_total,
        'limit', p_limit,
        'offset', p_offset,
        'data', COALESCE(json_agg(
            json_build_object(
                'id', p.id,
                'account_id', ua.id,
                'email', ua.email,
                'first_name', p.first_name,
                'last_name', p.last_name,
                'full_name', p.first_name || ' ' || p.last_name,
                'display_name', p.display_name,
                'phone', p.phone,
                'address', p.address,
                'membership_level', p.membership_level,
                'skill_level', p.skill_level,
                'dupr_rating', p.dupr_rating,
                'dupr_rating_updated_at', p.dupr_rating_updated_at,
                'is_active', ua.is_active,
                'is_verified', ua.is_verified,
                'last_login', ua.last_login,
                'membership_started_on', p.membership_started_on,
                'membership_expires_on', p.membership_expires_on,
                'created_at', p.created_at,
                'updated_at', p.updated_at
            ) ORDER BY p.created_at DESC
        ), '[]'::json)
    )
    INTO v_result
    FROM app_auth.user_accounts ua
    JOIN app_auth.players p ON p.account_id = ua.id
    WHERE ua.user_type = 'player'
        AND (p_search IS NULL OR (
            p.first_name ILIKE '%' || p_search || '%'
            OR p.last_name ILIKE '%' || p_search || '%'
            OR p.display_name ILIKE '%' || p_search || '%'
            OR ua.email ILIKE '%' || p_search || '%'
            OR p.phone ILIKE '%' || p_search || '%'
        ))
        AND (p_membership_level IS NULL OR p.membership_level = p_membership_level)
        AND (p_skill_level IS NULL OR p.skill_level = p_skill_level)
        AND (p_status IS NULL OR (
            (p_status = 'active' AND ua.is_active = true)
            OR (p_status = 'inactive' AND ua.is_active = false)
        ))
    LIMIT p_limit
    OFFSET p_offset;

    RETURN v_result;
END;
$$;

-- Get single player account details
CREATE OR REPLACE FUNCTION api.get_player_account(
    p_player_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
    v_result JSON;
BEGIN
    SELECT json_build_object(
        'success', true,
        'data', json_build_object(
            'id', p.id,
            'account_id', ua.id,
            'email', ua.email,
            'first_name', p.first_name,
            'last_name', p.last_name,
            'full_name', p.first_name || ' ' || p.last_name,
            'display_name', p.display_name,
            'phone', p.phone,
            'address', p.address,
            'date_of_birth', p.date_of_birth,
            'membership_level', p.membership_level,
            'membership_started_on', p.membership_started_on,
            'membership_expires_on', p.membership_expires_on,
            'skill_level', p.skill_level,
            'dupr_rating', p.dupr_rating,
            'dupr_rating_updated_at', p.dupr_rating_updated_at,
            'is_active', ua.is_active,
            'is_verified', ua.is_verified,
            'last_login', ua.last_login,
            'created_at', p.created_at,
            'updated_at', p.updated_at
        )
    )
    INTO v_result
    FROM app_auth.user_accounts ua
    JOIN app_auth.players p ON p.account_id = ua.id
    WHERE p.id = p_player_id OR ua.id = p_player_id;

    IF v_result IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'Player not found');
    END IF;

    RETURN v_result;
END;
$$;

-- Update player account
CREATE OR REPLACE FUNCTION api.update_player_account(
    p_player_id UUID,
    p_first_name TEXT DEFAULT NULL,
    p_last_name TEXT DEFAULT NULL,
    p_display_name TEXT DEFAULT NULL,
    p_phone TEXT DEFAULT NULL,
    p_address TEXT DEFAULT NULL,
    p_date_of_birth DATE DEFAULT NULL,
    p_membership_level app_auth.membership_level DEFAULT NULL,
    p_skill_level app_auth.skill_level DEFAULT NULL,
    p_dupr_rating NUMERIC(3, 2) DEFAULT NULL,
    p_is_active BOOLEAN DEFAULT NULL,
    p_updated_by UUID DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_player RECORD;
    v_old_values JSONB;
    v_new_values JSONB;
BEGIN
    -- Get current player details
    SELECT p.*, ua.is_active
    INTO v_player
    FROM app_auth.players p
    JOIN app_auth.user_accounts ua ON ua.id = p.account_id
    WHERE p.id = p_player_id OR p.account_id = p_player_id;

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Player not found');
    END IF;

    -- Store old values for audit
    v_old_values := jsonb_build_object(
        'first_name', v_player.first_name,
        'last_name', v_player.last_name,
        'display_name', v_player.display_name,
        'phone', v_player.phone,
        'address', v_player.address,
        'membership_level', v_player.membership_level,
        'skill_level', v_player.skill_level,
        'dupr_rating', v_player.dupr_rating,
        'is_active', v_player.is_active
    );

    -- Update player profile
    UPDATE app_auth.players
    SET first_name = COALESCE(p_first_name, first_name),
        last_name = COALESCE(p_last_name, last_name),
        display_name = COALESCE(p_display_name, display_name),
        phone = COALESCE(p_phone, phone),
        address = COALESCE(p_address, address),
        date_of_birth = COALESCE(p_date_of_birth, date_of_birth),
        membership_level = COALESCE(p_membership_level, membership_level),
        skill_level = COALESCE(p_skill_level, skill_level),
        dupr_rating = COALESCE(p_dupr_rating, dupr_rating),
        dupr_rating_updated_at = CASE
            WHEN p_dupr_rating IS NOT NULL THEN CURRENT_TIMESTAMP
            ELSE dupr_rating_updated_at
        END,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = v_player.id;

    -- Update account status if provided
    IF p_is_active IS NOT NULL THEN
        UPDATE app_auth.user_accounts
        SET is_active = p_is_active
        WHERE id = v_player.account_id;
    END IF;

    -- Store new values for audit
    v_new_values := jsonb_build_object(
        'first_name', COALESCE(p_first_name, v_player.first_name),
        'last_name', COALESCE(p_last_name, v_player.last_name),
        'display_name', COALESCE(p_display_name, v_player.display_name),
        'phone', COALESCE(p_phone, v_player.phone),
        'address', COALESCE(p_address, v_player.address),
        'membership_level', COALESCE(p_membership_level, v_player.membership_level),
        'skill_level', COALESCE(p_skill_level, v_player.skill_level),
        'dupr_rating', COALESCE(p_dupr_rating, v_player.dupr_rating),
        'is_active', COALESCE(p_is_active, v_player.is_active)
    );

    -- Log activity if updated_by is provided
    IF p_updated_by IS NOT NULL THEN
        INSERT INTO system.activity_logs (
            user_id,
            action,
            entity_type,
            entity_id,
            details
        ) VALUES (
            p_updated_by,
            'player_account_updated',
            'player',
            v_player.id,
            jsonb_build_object(
                'old_values', v_old_values,
                'new_values', v_new_values
            )
        );
    END IF;

    RETURN json_build_object(
        'success', true,
        'message', 'Player account updated successfully'
    );
END;
$$;

-- Delete/deactivate player account
CREATE OR REPLACE FUNCTION api.delete_player_account(
    p_player_id UUID,
    p_hard_delete BOOLEAN DEFAULT FALSE,
    p_deleted_by UUID DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_player RECORD;
BEGIN
    -- Get player details
    SELECT p.*, ua.email
    INTO v_player
    FROM app_auth.players p
    JOIN app_auth.user_accounts ua ON ua.id = p.account_id
    WHERE p.id = p_player_id OR p.account_id = p_player_id;

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Player not found');
    END IF;

    IF p_hard_delete THEN
        -- Hard delete - remove from database
        DELETE FROM app_auth.user_accounts WHERE id = v_player.account_id;

        -- Log activity if deleted_by is provided
        IF p_deleted_by IS NOT NULL THEN
            INSERT INTO system.activity_logs (
                user_id,
                action,
                entity_type,
                entity_id,
                details
            ) VALUES (
                p_deleted_by,
                'player_account_deleted',
                'player',
                v_player.id,
                jsonb_build_object(
                    'email', v_player.email,
                    'first_name', v_player.first_name,
                    'last_name', v_player.last_name,
                    'hard_delete', true
                )
            );
        END IF;

        RETURN json_build_object(
            'success', true,
            'message', 'Player account permanently deleted'
        );
    ELSE
        -- Soft delete - deactivate account
        UPDATE app_auth.user_accounts
        SET is_active = false
        WHERE id = v_player.account_id;

        -- Log activity if deleted_by is provided
        IF p_deleted_by IS NOT NULL THEN
            INSERT INTO system.activity_logs (
                user_id,
                action,
                entity_type,
                entity_id,
                details
            ) VALUES (
                p_deleted_by,
                'player_account_deactivated',
                'player',
                v_player.id,
                jsonb_build_object(
                    'email', v_player.email,
                    'first_name', v_player.first_name,
                    'last_name', v_player.last_name
                )
            );
        END IF;

        RETURN json_build_object(
            'success', true,
            'message', 'Player account deactivated successfully'
        );
    END IF;
END;
$$;

-- Reset player account password
CREATE OR REPLACE FUNCTION api.reset_player_password(
    p_player_id UUID,
    p_new_password TEXT,
    p_reset_by UUID DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_player RECORD;
    v_password_hash TEXT;
BEGIN
    -- Get player details
    SELECT p.*, ua.email
    INTO v_player
    FROM app_auth.players p
    JOIN app_auth.user_accounts ua ON ua.id = p.account_id
    WHERE p.id = p_player_id OR p.account_id = p_player_id;

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Player not found');
    END IF;

    -- Hash the new password
    v_password_hash := hash_password(p_new_password);

    -- Update password
    UPDATE app_auth.user_accounts
    SET password_hash = v_password_hash,
        failed_login_attempts = 0,
        locked_until = NULL
    WHERE id = v_player.account_id;

    -- Log activity if reset_by is provided
    IF p_reset_by IS NOT NULL THEN
        INSERT INTO system.activity_logs (
            user_id,
            action,
            entity_type,
            entity_id,
            details
        ) VALUES (
            p_reset_by,
            'player_password_reset',
            'player',
            v_player.id,
            jsonb_build_object(
                'email', v_player.email,
                'first_name', v_player.first_name,
                'last_name', v_player.last_name
            )
        );
    END IF;

    RETURN json_build_object(
        'success', true,
        'message', 'Password reset successfully'
    );
END;
$$;

-- Get combined account statistics
CREATE OR REPLACE FUNCTION api.get_all_account_stats()
RETURNS JSON
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
    v_stats JSON;
BEGIN
    SELECT json_build_object(
        'admin_stats', (
            SELECT json_build_object(
                'total', COUNT(*),
                'active', COUNT(*) FILTER (WHERE ua.is_active = true),
                'inactive', COUNT(*) FILTER (WHERE ua.is_active = false),
                'by_role', (
                    SELECT json_object_agg(role, role_count)
                    FROM (
                        SELECT au.role, COUNT(*) as role_count
                        FROM app_auth.admin_users au
                        GROUP BY au.role
                    ) role_counts
                )
            )
            FROM app_auth.user_accounts ua
            JOIN app_auth.admin_users au ON au.account_id = ua.id
            WHERE ua.user_type = 'admin'
        ),
        'player_stats', (
            SELECT json_build_object(
                'total', COUNT(*),
                'active', COUNT(*) FILTER (WHERE ua.is_active = true),
                'inactive', COUNT(*) FILTER (WHERE ua.is_active = false),
                'by_membership', (
                    SELECT json_object_agg(membership_level, membership_count)
                    FROM (
                        SELECT p.membership_level, COUNT(*) as membership_count
                        FROM app_auth.players p
                        GROUP BY p.membership_level
                    ) membership_counts
                ),
                'by_skill', (
                    SELECT json_object_agg(skill_level, skill_count)
                    FROM (
                        SELECT p.skill_level, COUNT(*) as skill_count
                        FROM app_auth.players p
                        WHERE p.skill_level IS NOT NULL
                        GROUP BY p.skill_level
                    ) skill_counts
                ),
                'with_dupr', COUNT(*) FILTER (WHERE p.dupr_rating IS NOT NULL)
            )
            FROM app_auth.user_accounts ua
            JOIN app_auth.players p ON p.account_id = ua.id
            WHERE ua.user_type = 'player'
        ),
        'total_accounts', (
            SELECT COUNT(*) FROM app_auth.user_accounts
        ),
        'recent_logins_24h', (
            SELECT COUNT(*)
            FROM app_auth.user_accounts
            WHERE last_login >= CURRENT_TIMESTAMP - INTERVAL '24 hours'
        )
    )
    INTO v_stats;

    RETURN json_build_object('success', true, 'data', v_stats);
END;
$$;

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

-- Grant execute permissions to authenticated users
GRANT EXECUTE ON FUNCTION api.list_admin_accounts TO authenticated;
GRANT EXECUTE ON FUNCTION api.get_admin_account TO authenticated;
GRANT EXECUTE ON FUNCTION api.create_admin_account TO authenticated;
GRANT EXECUTE ON FUNCTION api.update_admin_account TO authenticated;
GRANT EXECUTE ON FUNCTION api.delete_admin_account TO authenticated;
GRANT EXECUTE ON FUNCTION api.reset_admin_password TO authenticated;
GRANT EXECUTE ON FUNCTION api.toggle_account_status TO authenticated;
GRANT EXECUTE ON FUNCTION api.get_account_stats TO authenticated;

-- Grant to service role
GRANT EXECUTE ON FUNCTION api.list_admin_accounts TO service_role;
GRANT EXECUTE ON FUNCTION api.get_admin_account TO service_role;
GRANT EXECUTE ON FUNCTION api.create_admin_account TO service_role;
GRANT EXECUTE ON FUNCTION api.update_admin_account TO service_role;
GRANT EXECUTE ON FUNCTION api.delete_admin_account TO service_role;
GRANT EXECUTE ON FUNCTION api.reset_admin_password TO service_role;
GRANT EXECUTE ON FUNCTION api.toggle_account_status TO service_role;
GRANT EXECUTE ON FUNCTION api.get_account_stats TO service_role;

-- Grant player management functions to authenticated users
GRANT EXECUTE ON FUNCTION api.create_player_account TO authenticated;
GRANT EXECUTE ON FUNCTION api.list_player_accounts TO authenticated;
GRANT EXECUTE ON FUNCTION api.get_player_account TO authenticated;
GRANT EXECUTE ON FUNCTION api.update_player_account TO authenticated;
GRANT EXECUTE ON FUNCTION api.delete_player_account TO authenticated;
GRANT EXECUTE ON FUNCTION api.reset_player_password TO authenticated;
GRANT EXECUTE ON FUNCTION api.get_all_account_stats TO authenticated;

-- Grant player management functions to service role
GRANT EXECUTE ON FUNCTION api.create_player_account TO service_role;
GRANT EXECUTE ON FUNCTION api.list_player_accounts TO service_role;
GRANT EXECUTE ON FUNCTION api.get_player_account TO service_role;
GRANT EXECUTE ON FUNCTION api.update_player_account TO service_role;
GRANT EXECUTE ON FUNCTION api.delete_player_account TO service_role;
GRANT EXECUTE ON FUNCTION api.reset_player_password TO service_role;
GRANT EXECUTE ON FUNCTION api.get_all_account_stats TO service_role;-- ============================================================================
-- MARKETING SCHEMA MODULE
-- Email marketing campaigns with AI-generated content and analytics
-- ============================================================================

-- Create marketing schema
CREATE SCHEMA IF NOT EXISTS marketing;

-- Set search path
SET search_path TO marketing, public;

COMMENT ON SCHEMA marketing IS 'Marketing email campaigns and analytics';

-- ============================================================================
-- TABLES
-- ============================================================================

-- Main emails table - stores generated marketing emails
CREATE TABLE IF NOT EXISTS marketing.emails (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subject VARCHAR(500) NOT NULL,
    html_content TEXT NOT NULL,
    text_content TEXT,

    -- AI Generation metadata
    source_prompt TEXT,
    grok_model VARCHAR(100) DEFAULT 'grok-code-fast-1',
    content_sources JSONB DEFAULT '[]', -- Array of sources/references cited
    images_email TEXT[] DEFAULT '{}', -- Array of image URLs used in email

    -- Branding
    theme_color VARCHAR(50) DEFAULT '#B3FF00',
    logo_url TEXT DEFAULT 'https://wchxzbuuwssrnaxshseu.supabase.co/storage/v1/object/public/dink-files/dinklogo.jpg',

    -- Status tracking
    status VARCHAR(50) DEFAULT 'draft',
        CHECK (status IN ('draft', 'reviewed', 'scheduled', 'sending', 'sent', 'failed')),

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    reviewed_at TIMESTAMP WITH TIME ZONE,
    scheduled_for TIMESTAMP WITH TIME ZONE,
    sent_at TIMESTAMP WITH TIME ZONE,

    -- Audit
    created_by UUID, -- References auth.users(id) but nullable for system-generated

    -- Metadata
    metadata JSONB DEFAULT '{}'
);

-- Email recipients tracking - one record per recipient per email
CREATE TABLE IF NOT EXISTS marketing.email_recipients (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email_id UUID NOT NULL REFERENCES marketing.emails(id) ON DELETE CASCADE,
    subscriber_id UUID REFERENCES launch.launch_subscribers(id) ON DELETE SET NULL,
    email_address TEXT NOT NULL,

    -- SendGrid tracking
    sendgrid_message_id TEXT,

    -- Status
    status VARCHAR(50) DEFAULT 'pending',
        CHECK (status IN ('pending', 'sent', 'failed', 'bounced', 'dropped', 'deferred')),

    -- Engagement timestamps
    sent_at TIMESTAMP WITH TIME ZONE,
    delivered_at TIMESTAMP WITH TIME ZONE,
    opened_at TIMESTAMP WITH TIME ZONE, -- First open
    last_opened_at TIMESTAMP WITH TIME ZONE, -- Most recent open
    clicked_at TIMESTAMP WITH TIME ZONE, -- First click
    last_clicked_at TIMESTAMP WITH TIME ZONE, -- Most recent click
    bounced_at TIMESTAMP WITH TIME ZONE,

    -- Open and click counts
    open_count INTEGER DEFAULT 0,
    click_count INTEGER DEFAULT 0,

    -- Error tracking
    error_message TEXT,
    bounce_type VARCHAR(50), -- hard, soft, blocked

    -- Additional data
    metadata JSONB DEFAULT '{}',

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- INDEXES
-- ============================================================================

CREATE INDEX idx_emails_status ON marketing.emails(status);
CREATE INDEX idx_emails_created_at ON marketing.emails(created_at DESC);
CREATE INDEX idx_emails_sent_at ON marketing.emails(sent_at DESC) WHERE sent_at IS NOT NULL;

CREATE INDEX idx_recipients_email_id ON marketing.email_recipients(email_id);
CREATE INDEX idx_recipients_subscriber_id ON marketing.email_recipients(subscriber_id) WHERE subscriber_id IS NOT NULL;
CREATE INDEX idx_recipients_status ON marketing.email_recipients(status);
CREATE INDEX idx_recipients_sendgrid_id ON marketing.email_recipients(sendgrid_message_id) WHERE sendgrid_message_id IS NOT NULL;
CREATE INDEX idx_recipients_opened ON marketing.email_recipients(opened_at) WHERE opened_at IS NOT NULL;
CREATE INDEX idx_recipients_clicked ON marketing.email_recipients(clicked_at) WHERE clicked_at IS NOT NULL;

-- ============================================================================
-- VIEWS
-- ============================================================================

-- Email analytics view - comprehensive stats per email
CREATE OR REPLACE VIEW marketing.email_analytics AS
SELECT
    e.id,
    e.subject,
    e.status,
    e.created_at,
    e.sent_at,
    e.grok_model,

    -- Recipient counts
    COUNT(er.id) as total_recipients,
    COUNT(CASE WHEN er.status = 'sent' THEN 1 END) as sent_count,
    COUNT(CASE WHEN er.status = 'failed' THEN 1 END) as failed_count,
    COUNT(CASE WHEN er.status = 'bounced' THEN 1 END) as bounced_count,

    -- Engagement counts
    COUNT(er.delivered_at) as delivered_count,
    COUNT(er.opened_at) as unique_opens,
    COUNT(er.clicked_at) as unique_clicks,
    SUM(er.open_count) as total_opens,
    SUM(er.click_count) as total_clicks,

    -- Rates (as percentages)
    ROUND(
        (COUNT(er.delivered_at)::numeric / NULLIF(COUNT(CASE WHEN er.status = 'sent' THEN 1 END), 0)) * 100,
        2
    ) as delivery_rate,
    ROUND(
        (COUNT(er.opened_at)::numeric / NULLIF(COUNT(er.delivered_at), 0)) * 100,
        2
    ) as open_rate,
    ROUND(
        (COUNT(er.clicked_at)::numeric / NULLIF(COUNT(er.delivered_at), 0)) * 100,
        2
    ) as click_rate,
    ROUND(
        (COUNT(er.clicked_at)::numeric / NULLIF(COUNT(er.opened_at), 0)) * 100,
        2
    ) as click_to_open_rate,
    ROUND(
        (COUNT(CASE WHEN er.status = 'bounced' THEN 1 END)::numeric / NULLIF(COUNT(er.id), 0)) * 100,
        2
    ) as bounce_rate,

    -- Timing
    EXTRACT(EPOCH FROM (MIN(er.opened_at) - e.sent_at)) / 60 as minutes_to_first_open,
    EXTRACT(EPOCH FROM (MIN(er.clicked_at) - e.sent_at)) / 60 as minutes_to_first_click

FROM marketing.emails e
LEFT JOIN marketing.email_recipients er ON e.id = er.email_id
GROUP BY e.id, e.subject, e.status, e.created_at, e.sent_at, e.grok_model;

-- Campaign overview - aggregate stats
CREATE OR REPLACE VIEW marketing.campaign_overview AS
SELECT
    DATE_TRUNC('day', e.sent_at) as sent_date,
    COUNT(DISTINCT e.id) as emails_sent,
    COUNT(er.id) as total_recipients,
    COUNT(er.opened_at) as total_opens,
    COUNT(er.clicked_at) as total_clicks,
    ROUND(
        (COUNT(er.opened_at)::numeric / NULLIF(COUNT(er.id), 0)) * 100,
        2
    ) as avg_open_rate,
    ROUND(
        (COUNT(er.clicked_at)::numeric / NULLIF(COUNT(er.id), 0)) * 100,
        2
    ) as avg_click_rate
FROM marketing.emails e
LEFT JOIN marketing.email_recipients er ON e.id = er.email_id
WHERE e.sent_at IS NOT NULL
GROUP BY DATE_TRUNC('day', e.sent_at)
ORDER BY sent_date DESC;

-- Top performers - emails with best engagement
CREATE OR REPLACE VIEW marketing.top_performing_emails AS
SELECT
    e.id,
    e.subject,
    e.sent_at,
    COUNT(er.opened_at) as opens,
    COUNT(er.clicked_at) as clicks,
    ROUND(
        (COUNT(er.opened_at)::numeric / NULLIF(COUNT(er.id), 0)) * 100,
        2
    ) as open_rate,
    ROUND(
        (COUNT(er.clicked_at)::numeric / NULLIF(COUNT(er.id), 0)) * 100,
        2
    ) as click_rate
FROM marketing.emails e
LEFT JOIN marketing.email_recipients er ON e.id = er.email_id
WHERE e.status = 'sent'
GROUP BY e.id, e.subject, e.sent_at
HAVING COUNT(er.id) > 0
ORDER BY open_rate DESC, click_rate DESC
LIMIT 20;

-- ============================================================================
-- FUNCTIONS
-- ============================================================================

-- Update timestamp function
CREATE OR REPLACE FUNCTION marketing.update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger for email_recipients updated_at
CREATE TRIGGER update_email_recipients_updated_at
    BEFORE UPDATE ON marketing.email_recipients
    FOR EACH ROW
    EXECUTE FUNCTION marketing.update_updated_at();

-- Function to mark email as opened
CREATE OR REPLACE FUNCTION marketing.mark_email_opened(
    p_sendgrid_message_id TEXT,
    p_opened_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
)
RETURNS BOOLEAN AS $$
DECLARE
    v_recipient_id UUID;
BEGIN
    -- Find recipient by SendGrid message ID
    SELECT id INTO v_recipient_id
    FROM marketing.email_recipients
    WHERE sendgrid_message_id = p_sendgrid_message_id;

    IF v_recipient_id IS NULL THEN
        RETURN FALSE;
    END IF;

    -- Update open tracking
    UPDATE marketing.email_recipients
    SET
        opened_at = COALESCE(opened_at, p_opened_at),
        last_opened_at = p_opened_at,
        open_count = open_count + 1,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = v_recipient_id;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- Function to mark email as clicked
CREATE OR REPLACE FUNCTION marketing.mark_email_clicked(
    p_sendgrid_message_id TEXT,
    p_clicked_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
)
RETURNS BOOLEAN AS $$
DECLARE
    v_recipient_id UUID;
BEGIN
    -- Find recipient by SendGrid message ID
    SELECT id INTO v_recipient_id
    FROM marketing.email_recipients
    WHERE sendgrid_message_id = p_sendgrid_message_id;

    IF v_recipient_id IS NULL THEN
        RETURN FALSE;
    END IF;

    -- Update click tracking
    UPDATE marketing.email_recipients
    SET
        clicked_at = COALESCE(clicked_at, p_clicked_at),
        last_clicked_at = p_clicked_at,
        click_count = click_count + 1,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = v_recipient_id;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- PERMISSIONS
-- ============================================================================

-- Grant usage on schema
GRANT USAGE ON SCHEMA marketing TO authenticated, service_role;

-- Service role (Edge Functions) needs full access
GRANT ALL ON ALL TABLES IN SCHEMA marketing TO service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA marketing TO service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA marketing TO service_role;

-- Authenticated users (admins) need read access for analytics
GRANT SELECT ON ALL TABLES IN SCHEMA marketing TO authenticated;
GRANT SELECT ON marketing.email_analytics TO authenticated;
GRANT SELECT ON marketing.campaign_overview TO authenticated;
GRANT SELECT ON marketing.top_performing_emails TO authenticated;

-- Anonymous users have no access to marketing data
-- (tracking webhooks use service_role)

COMMENT ON TABLE marketing.emails IS 'AI-generated marketing emails with engagement tracking';
COMMENT ON TABLE marketing.email_recipients IS 'Individual recipient tracking for each email campaign';
COMMENT ON VIEW marketing.email_analytics IS 'Comprehensive analytics per email campaign';
COMMENT ON VIEW marketing.campaign_overview IS 'Aggregate campaign performance over time';
COMMENT ON VIEW marketing.top_performing_emails IS 'Best performing emails by engagement rate';
-- ============================================================================
-- RESUBSCRIBE FUNCTIONS MODULE
-- Functions to handle newsletter resubscription
-- ============================================================================

SET search_path TO api, launch, system, public;

-- ============================================================================
-- RESUBSCRIBE NEWSLETTER FUNCTION
-- ============================================================================

-- Resubscribe to newsletter
CREATE OR REPLACE FUNCTION api.resubscribe_newsletter(
    p_email TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_subscriber RECORD;
BEGIN
    -- Find subscriber by email (case-insensitive)
    SELECT * INTO v_subscriber
    FROM launch.launch_subscribers
    WHERE email = lower(p_email);

    -- Check if email exists in database
    IF v_subscriber IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'message', 'Email not found. Please sign up first to join our newsletter.'
        );
    END IF;

    -- Check if already active/subscribed
    IF v_subscriber.is_active = true AND v_subscriber.unsubscribed_at IS NULL THEN
        RETURN json_build_object(
            'success', true,
            'already_subscribed', true,
            'message', 'You are already subscribed to our newsletter!'
        );
    END IF;

    -- Reactivate subscription
    UPDATE launch.launch_subscribers
    SET is_active = true,
        unsubscribed_at = NULL,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = v_subscriber.id;

    -- Log the resubscribe action
    INSERT INTO system.activity_logs (
        action,
        entity_type,
        entity_id,
        details
    ) VALUES (
        'newsletter_resubscribe',
        'subscriber',
        v_subscriber.id,
        jsonb_build_object(
            'email', v_subscriber.email,
            'resubscribed_at', CURRENT_TIMESTAMP
        )
    );

    RETURN json_build_object(
        'success', true,
        'message', 'Thank you for resubscribing! You will now receive our newsletter updates.',
        'subscriber_id', v_subscriber.id
    );
END;
$$;

-- ============================================================================
-- PERMISSIONS
-- ============================================================================

-- Grant execute permission to anonymous users (public access)
GRANT EXECUTE ON FUNCTION api.resubscribe_newsletter TO anon;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION api.resubscribe_newsletter TO authenticated;
-- ============================================================================
-- CROWDFUNDING MODULE
-- Campaign management, backer tracking, and Stripe integration
-- ============================================================================

-- Create crowdfunding schema
CREATE SCHEMA IF NOT EXISTS crowdfunding;

-- Set search path for crowdfunding schema
SET search_path TO crowdfunding, public;

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================================
-- CORE TABLES
-- ============================================================================

-- Backers/Supporters Table
CREATE TABLE IF NOT EXISTS crowdfunding.backers (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    email public.CITEXT UNIQUE NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_initial VARCHAR(1) NOT NULL,
    phone VARCHAR(30),
    city VARCHAR(100),
    state VARCHAR(2),
    stripe_customer_id TEXT UNIQUE,
    total_contributed DECIMAL(10, 2) DEFAULT 0,
    contribution_count INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Campaign Types (Main, Equipment, etc.)
CREATE TABLE IF NOT EXISTS crowdfunding.campaign_types (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(255) UNIQUE NOT NULL,
    description TEXT,
    goal_amount DECIMAL(10, 2) NOT NULL,
    current_amount DECIMAL(10, 2) DEFAULT 0,
    backer_count INTEGER DEFAULT 0,
    display_order INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Contribution Tiers
CREATE TABLE IF NOT EXISTS crowdfunding.contribution_tiers (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    campaign_type_id UUID NOT NULL REFERENCES crowdfunding.campaign_types(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    amount DECIMAL(10, 2) NOT NULL,
    description TEXT,
    benefits JSONB DEFAULT '[]',
    stripe_price_id TEXT UNIQUE,
    max_backers INTEGER,
    current_backers INTEGER DEFAULT 0,
    display_order INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Contributions/Pledges
CREATE TABLE IF NOT EXISTS crowdfunding.contributions (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    backer_id UUID NOT NULL REFERENCES crowdfunding.backers(id) ON DELETE CASCADE,
    campaign_type_id UUID NOT NULL REFERENCES crowdfunding.campaign_types(id) ON DELETE CASCADE,
    tier_id UUID REFERENCES crowdfunding.contribution_tiers(id) ON DELETE SET NULL,
    amount DECIMAL(10, 2) NOT NULL,
    stripe_payment_intent_id TEXT UNIQUE,
    stripe_charge_id TEXT,
    stripe_checkout_session_id TEXT UNIQUE,
    status VARCHAR(50) NOT NULL DEFAULT 'pending',
    payment_method VARCHAR(50),
    is_public BOOLEAN DEFAULT true,
    show_amount BOOLEAN DEFAULT true,
    custom_message TEXT,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP WITH TIME ZONE,
    refunded_at TIMESTAMP WITH TIME ZONE,
    CONSTRAINT valid_status CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'refunded', 'cancelled'))
);

-- Benefits Tracking (for lifetime benefits)
CREATE TABLE IF NOT EXISTS crowdfunding.backer_benefits (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    backer_id UUID NOT NULL REFERENCES crowdfunding.backers(id) ON DELETE CASCADE,
    contribution_id UUID NOT NULL REFERENCES crowdfunding.contributions(id) ON DELETE CASCADE,
    benefit_type VARCHAR(100) NOT NULL,
    benefit_details JSONB DEFAULT '{}',
    is_active BOOLEAN DEFAULT true,
    activated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP WITH TIME ZONE,
    redeemed_count INTEGER DEFAULT 0,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT valid_benefit_type CHECK (benefit_type IN (
        'lifetime_dink_board', 'lifetime_ball_machine', 'founding_membership',
        'court_sponsor', 'pro_shop_discount', 'priority_booking', 'name_on_wall',
        'free_lessons', 'vip_events', 'custom'
    ))
);

-- Court Sponsors (for $1,000+ tiers)
CREATE TABLE IF NOT EXISTS crowdfunding.court_sponsors (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    backer_id UUID NOT NULL REFERENCES crowdfunding.backers(id) ON DELETE CASCADE,
    contribution_id UUID NOT NULL REFERENCES crowdfunding.contributions(id) ON DELETE CASCADE,
    sponsor_name VARCHAR(255) NOT NULL,
    sponsor_type VARCHAR(50) DEFAULT 'individual',
    logo_url TEXT,
    court_number INTEGER,
    sponsorship_start DATE NOT NULL DEFAULT CURRENT_DATE,
    sponsorship_end DATE,
    is_active BOOLEAN DEFAULT true,
    display_order INTEGER,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT valid_sponsor_type CHECK (sponsor_type IN ('individual', 'business', 'memorial'))
);

-- Founders Wall (Public Display)
CREATE TABLE IF NOT EXISTS crowdfunding.founders_wall (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    backer_id UUID UNIQUE NOT NULL REFERENCES crowdfunding.backers(id) ON DELETE CASCADE,
    display_name VARCHAR(255) NOT NULL,
    location VARCHAR(255),
    contribution_tier VARCHAR(255),
    total_contributed DECIMAL(10, 2) NOT NULL DEFAULT 0,
    is_featured BOOLEAN DEFAULT false,
    display_order INTEGER,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- INDEXES
-- ============================================================================

CREATE INDEX idx_backers_email ON crowdfunding.backers(email);
CREATE INDEX idx_backers_stripe_customer ON crowdfunding.backers(stripe_customer_id);

CREATE INDEX idx_campaign_types_slug ON crowdfunding.campaign_types(slug);
CREATE INDEX idx_campaign_types_active ON crowdfunding.campaign_types(is_active);
CREATE INDEX idx_campaign_types_display_order ON crowdfunding.campaign_types(display_order);

CREATE INDEX idx_tiers_campaign ON crowdfunding.contribution_tiers(campaign_type_id);
CREATE INDEX idx_tiers_active ON crowdfunding.contribution_tiers(is_active);
CREATE INDEX idx_tiers_price_id ON crowdfunding.contribution_tiers(stripe_price_id);

CREATE INDEX idx_contributions_backer ON crowdfunding.contributions(backer_id);
CREATE INDEX idx_contributions_campaign ON crowdfunding.contributions(campaign_type_id);
CREATE INDEX idx_contributions_tier ON crowdfunding.contributions(tier_id);
CREATE INDEX idx_contributions_status ON crowdfunding.contributions(status);
CREATE INDEX idx_contributions_completed_at ON crowdfunding.contributions(completed_at);
CREATE INDEX idx_contributions_stripe_payment_intent ON crowdfunding.contributions(stripe_payment_intent_id);
CREATE INDEX idx_contributions_stripe_session ON crowdfunding.contributions(stripe_checkout_session_id);

CREATE INDEX idx_benefits_backer ON crowdfunding.backer_benefits(backer_id);
CREATE INDEX idx_benefits_contribution ON crowdfunding.backer_benefits(contribution_id);
CREATE INDEX idx_benefits_type ON crowdfunding.backer_benefits(benefit_type);
CREATE INDEX idx_benefits_active ON crowdfunding.backer_benefits(is_active);

CREATE INDEX idx_sponsors_backer ON crowdfunding.court_sponsors(backer_id);
CREATE INDEX idx_sponsors_active ON crowdfunding.court_sponsors(is_active);

CREATE INDEX idx_founders_wall_display_order ON crowdfunding.founders_wall(display_order);
CREATE INDEX idx_founders_wall_featured ON crowdfunding.founders_wall(is_featured);

-- ============================================================================
-- TRIGGERS & FUNCTIONS
-- ============================================================================

-- Function to update campaign totals when contribution is completed
CREATE OR REPLACE FUNCTION crowdfunding.update_campaign_total()
RETURNS TRIGGER AS $$
BEGIN
    -- Only process when status changes to 'completed'
    IF NEW.status = 'completed' AND (OLD IS NULL OR OLD.status != 'completed') THEN
        -- Update campaign type current amount
        UPDATE crowdfunding.campaign_types
        SET
            current_amount = current_amount + NEW.amount,
            backer_count = backer_count + 1,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = NEW.campaign_type_id;

        -- Update tier backer count
        IF NEW.tier_id IS NOT NULL THEN
            UPDATE crowdfunding.contribution_tiers
            SET
                current_backers = current_backers + 1,
                updated_at = CURRENT_TIMESTAMP
            WHERE id = NEW.tier_id;
        END IF;

        -- Update backer totals
        UPDATE crowdfunding.backers
        SET
            total_contributed = total_contributed + NEW.amount,
            contribution_count = contribution_count + 1,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = NEW.backer_id;
    END IF;

    -- Handle refunds
    IF NEW.status = 'refunded' AND OLD.status = 'completed' THEN
        -- Reverse campaign type amounts
        UPDATE crowdfunding.campaign_types
        SET
            current_amount = GREATEST(0, current_amount - NEW.amount),
            backer_count = GREATEST(0, backer_count - 1),
            updated_at = CURRENT_TIMESTAMP
        WHERE id = NEW.campaign_type_id;

        -- Reverse tier backer count
        IF NEW.tier_id IS NOT NULL THEN
            UPDATE crowdfunding.contribution_tiers
            SET
                current_backers = GREATEST(0, current_backers - 1),
                updated_at = CURRENT_TIMESTAMP
            WHERE id = NEW.tier_id;
        END IF;

        -- Reverse backer totals
        UPDATE crowdfunding.backers
        SET
            total_contributed = GREATEST(0, total_contributed - NEW.amount),
            contribution_count = GREATEST(0, contribution_count - 1),
            updated_at = CURRENT_TIMESTAMP
        WHERE id = NEW.backer_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_campaign_total
    AFTER INSERT OR UPDATE ON crowdfunding.contributions
    FOR EACH ROW
    EXECUTE FUNCTION crowdfunding.update_campaign_total();

-- Function to create or update founders wall entry
CREATE OR REPLACE FUNCTION crowdfunding.upsert_founders_wall()
RETURNS TRIGGER AS $$
DECLARE
    v_display_name VARCHAR(255);
    v_location VARCHAR(255);
    v_tier_name VARCHAR(255);
    v_backer RECORD;
BEGIN
    -- Only process completed contributions that are public
    IF NEW.status = 'completed' AND NEW.is_public = true THEN
        -- Get backer info
        SELECT first_name, last_initial, city, state
        INTO v_backer
        FROM crowdfunding.backers
        WHERE id = NEW.backer_id;

        -- Format display name as "First L."
        v_display_name := v_backer.first_name || ' ' || v_backer.last_initial || '.';

        -- Format location as "City, ST" if available
        IF v_backer.city IS NOT NULL AND v_backer.state IS NOT NULL THEN
            v_location := v_backer.city || ', ' || v_backer.state;
        ELSIF v_backer.city IS NOT NULL THEN
            v_location := v_backer.city;
        ELSIF v_backer.state IS NOT NULL THEN
            v_location := v_backer.state;
        ELSE
            v_location := NULL;
        END IF;

        -- Get tier name
        IF NEW.tier_id IS NOT NULL THEN
            SELECT name INTO v_tier_name
            FROM crowdfunding.contribution_tiers
            WHERE id = NEW.tier_id;
        ELSE
            v_tier_name := 'Supporter';
        END IF;

        -- Insert or update founders wall
        INSERT INTO crowdfunding.founders_wall (
            backer_id,
            display_name,
            location,
            contribution_tier,
            total_contributed,
            is_featured
        )
        VALUES (
            NEW.backer_id,
            v_display_name,
            v_location,
            v_tier_name,
            NEW.amount,
            (NEW.amount >= 1000.00) -- Featured for $1000+ contributions
        )
        ON CONFLICT (backer_id)
        DO UPDATE SET
            total_contributed = crowdfunding.founders_wall.total_contributed + NEW.amount,
            contribution_tier = CASE
                WHEN NEW.amount >= 1000.00 THEN v_tier_name
                WHEN crowdfunding.founders_wall.total_contributed + NEW.amount >= 1000.00 THEN v_tier_name
                ELSE crowdfunding.founders_wall.contribution_tier
            END,
            is_featured = (crowdfunding.founders_wall.total_contributed + NEW.amount >= 1000.00),
            updated_at = CURRENT_TIMESTAMP;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_upsert_founders_wall
    AFTER INSERT OR UPDATE ON crowdfunding.contributions
    FOR EACH ROW
    EXECUTE FUNCTION crowdfunding.upsert_founders_wall();

-- ============================================================================
-- ROW LEVEL SECURITY
-- ============================================================================

ALTER TABLE crowdfunding.backers ENABLE ROW LEVEL SECURITY;
ALTER TABLE crowdfunding.campaign_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE crowdfunding.contribution_tiers ENABLE ROW LEVEL SECURITY;
ALTER TABLE crowdfunding.contributions ENABLE ROW LEVEL SECURITY;
ALTER TABLE crowdfunding.backer_benefits ENABLE ROW LEVEL SECURITY;
ALTER TABLE crowdfunding.court_sponsors ENABLE ROW LEVEL SECURITY;
ALTER TABLE crowdfunding.founders_wall ENABLE ROW LEVEL SECURITY;

-- Campaign types are public
CREATE POLICY "Campaign types are viewable by everyone"
    ON crowdfunding.campaign_types FOR SELECT
    USING (is_active = true);

-- Contribution tiers are public
CREATE POLICY "Contribution tiers are viewable by everyone"
    ON crowdfunding.contribution_tiers FOR SELECT
    USING (is_active = true);

-- Public contributions are viewable
CREATE POLICY "Public contributions are viewable by everyone"
    ON crowdfunding.contributions FOR SELECT
    USING (is_public = true AND status = 'completed');

-- Founders wall is public
CREATE POLICY "Founders wall is public"
    ON crowdfunding.founders_wall FOR SELECT
    USING (true);

-- Court sponsors are public
CREATE POLICY "Court sponsors are public"
    ON crowdfunding.court_sponsors FOR SELECT
    USING (is_active = true);

-- Service role has full access to all tables
CREATE POLICY "Service role has full access to backers"
    ON crowdfunding.backers FOR ALL
    USING (current_setting('request.jwt.claims', true)::json->>'role' = 'service_role');

CREATE POLICY "Service role has full access to contributions"
    ON crowdfunding.contributions FOR ALL
    USING (current_setting('request.jwt.claims', true)::json->>'role' = 'service_role');

CREATE POLICY "Service role has full access to benefits"
    ON crowdfunding.backer_benefits FOR ALL
    USING (current_setting('request.jwt.claims', true)::json->>'role' = 'service_role');

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Function to get campaign progress
CREATE OR REPLACE FUNCTION crowdfunding.get_campaign_progress(p_campaign_id UUID)
RETURNS TABLE(
    campaign_id UUID,
    campaign_name VARCHAR(255),
    current_amount DECIMAL(10, 2),
    goal_amount DECIMAL(10, 2),
    percentage DECIMAL(5, 2),
    backer_count INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        ct.id,
        ct.name,
        ct.current_amount,
        ct.goal_amount,
        CASE
            WHEN ct.goal_amount > 0 THEN ROUND((ct.current_amount / ct.goal_amount * 100)::NUMERIC, 2)
            ELSE 0
        END AS percentage,
        ct.backer_count
    FROM crowdfunding.campaign_types ct
    WHERE ct.id = p_campaign_id AND ct.is_active = true;
END;
$$ LANGUAGE plpgsql;

-- Function to get available tiers for a campaign
CREATE OR REPLACE FUNCTION crowdfunding.get_available_tiers(p_campaign_id UUID)
RETURNS TABLE(
    tier_id UUID,
    tier_name VARCHAR(255),
    amount DECIMAL(10, 2),
    description TEXT,
    benefits JSONB,
    available_spots INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        t.id,
        t.name,
        t.amount,
        t.description,
        t.benefits,
        CASE
            WHEN t.max_backers IS NULL THEN NULL
            ELSE t.max_backers - t.current_backers
        END AS available_spots
    FROM crowdfunding.contribution_tiers t
    WHERE t.campaign_type_id = p_campaign_id
        AND t.is_active = true
        AND (t.max_backers IS NULL OR t.current_backers < t.max_backers)
    ORDER BY t.display_order, t.amount;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

-- Grant usage on schema
GRANT USAGE ON SCHEMA crowdfunding TO anon, authenticated, service_role;

-- Grant select on tables (public read)
GRANT SELECT ON crowdfunding.campaign_types TO anon, authenticated;
GRANT SELECT ON crowdfunding.contribution_tiers TO anon, authenticated;
GRANT SELECT ON crowdfunding.contributions TO anon, authenticated;
GRANT SELECT ON crowdfunding.founders_wall TO anon, authenticated;
GRANT SELECT ON crowdfunding.court_sponsors TO anon, authenticated;

-- Grant all to service role
GRANT ALL ON ALL TABLES IN SCHEMA crowdfunding TO service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA crowdfunding TO service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA crowdfunding TO service_role;

-- Grant execute on functions
GRANT EXECUTE ON FUNCTION crowdfunding.get_campaign_progress(UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION crowdfunding.get_available_tiers(UUID) TO anon, authenticated;

COMMENT ON SCHEMA crowdfunding IS 'Crowdfunding campaign management with Stripe integration';
-- ============================================================================
-- DUPR VERIFICATION MODULE
-- Staff verification workflow for player DUPR ratings
-- ============================================================================

SET search_path TO app_auth, api, public;

-- ============================================================================
-- ADD VERIFICATION COLUMNS TO PLAYERS TABLE
-- ============================================================================

-- Add verification tracking columns
ALTER TABLE app_auth.players
ADD COLUMN IF NOT EXISTS dupr_verified BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS dupr_verified_by UUID REFERENCES app_auth.admin_users(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS dupr_verified_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS dupr_verification_notes TEXT;

-- Create indexes for verification queries
CREATE INDEX IF NOT EXISTS idx_players_dupr_verified ON app_auth.players(dupr_verified);
CREATE INDEX IF NOT EXISTS idx_players_pending_verification
    ON app_auth.players(dupr_rating_updated_at)
    WHERE dupr_rating IS NOT NULL AND dupr_verified = false;

COMMENT ON COLUMN app_auth.players.dupr_verified IS 'Whether staff has verified the DUPR rating';
COMMENT ON COLUMN app_auth.players.dupr_verified_by IS 'Admin user who verified the DUPR rating';
COMMENT ON COLUMN app_auth.players.dupr_verified_at IS 'Timestamp when DUPR was verified';
COMMENT ON COLUMN app_auth.players.dupr_verification_notes IS 'Staff notes about DUPR verification';

-- ============================================================================
-- API FUNCTION: Submit DUPR for Verification (Player Self-Service)
-- ============================================================================

CREATE OR REPLACE FUNCTION api.submit_dupr_for_verification(
    p_player_id UUID,
    p_dupr_rating NUMERIC(3, 2)
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_player RECORD;
BEGIN
    -- Validate DUPR rating range (2.00 to 8.00 is standard DUPR range)
    IF p_dupr_rating < 2.00 OR p_dupr_rating > 8.00 THEN
        RETURN json_build_object(
            'success', false,
            'error', 'DUPR rating must be between 2.00 and 8.00'
        );
    END IF;

    -- Get player record
    SELECT * INTO v_player
    FROM app_auth.players
    WHERE id = p_player_id;

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Player not found');
    END IF;

    -- Update DUPR rating and reset verification status
    UPDATE app_auth.players
    SET dupr_rating = p_dupr_rating,
        dupr_rating_updated_at = CURRENT_TIMESTAMP,
        dupr_verified = false,
        dupr_verified_by = NULL,
        dupr_verified_at = NULL,
        dupr_verification_notes = NULL,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_player_id;

    -- Log activity
    INSERT INTO system.activity_logs (
        user_id,
        action,
        entity_type,
        entity_id,
        details
    ) VALUES (
        p_player_id,
        'dupr_submitted_for_verification',
        'player',
        p_player_id,
        jsonb_build_object(
            'dupr_rating', p_dupr_rating,
            'status', 'pending_verification'
        )
    );

    RETURN json_build_object(
        'success', true,
        'message', 'DUPR rating submitted for staff verification',
        'dupr_rating', p_dupr_rating,
        'status', 'pending_verification'
    );
END;
$$;

COMMENT ON FUNCTION api.submit_dupr_for_verification IS 'Player submits DUPR rating for staff verification';

-- ============================================================================
-- API FUNCTION: Verify Player DUPR (Staff Only)
-- ============================================================================

CREATE OR REPLACE FUNCTION api.verify_player_dupr(
    p_player_id UUID,
    p_admin_id UUID,
    p_verified BOOLEAN,
    p_notes TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_player RECORD;
    v_admin RECORD;
BEGIN
    -- Get player record
    SELECT p.*, ua.email
    INTO v_player
    FROM app_auth.players p
    JOIN app_auth.user_accounts ua ON ua.id = p.account_id
    WHERE p.id = p_player_id;

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Player not found');
    END IF;

    -- Verify admin exists
    SELECT * INTO v_admin
    FROM app_auth.admin_users
    WHERE id = p_admin_id;

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Admin user not found');
    END IF;

    -- Check if player has submitted a DUPR rating
    IF v_player.dupr_rating IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Player has not submitted a DUPR rating'
        );
    END IF;

    IF p_verified THEN
        -- Approve verification
        UPDATE app_auth.players
        SET dupr_verified = true,
            dupr_verified_by = p_admin_id,
            dupr_verified_at = CURRENT_TIMESTAMP,
            dupr_verification_notes = p_notes,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = p_player_id;

        -- Log approval
        INSERT INTO system.activity_logs (
            user_id,
            action,
            entity_type,
            entity_id,
            details
        ) VALUES (
            p_admin_id,
            'dupr_verified',
            'player',
            p_player_id,
            jsonb_build_object(
                'player_email', v_player.email,
                'player_name', v_player.first_name || ' ' || v_player.last_name,
                'dupr_rating', v_player.dupr_rating,
                'verified_by', v_admin.username,
                'notes', p_notes
            )
        );

        RETURN json_build_object(
            'success', true,
            'message', 'Player DUPR rating verified successfully',
            'player_name', v_player.first_name || ' ' || v_player.last_name,
            'dupr_rating', v_player.dupr_rating
        );
    ELSE
        -- Reject verification - reset DUPR to null
        UPDATE app_auth.players
        SET dupr_rating = NULL,
            dupr_rating_updated_at = NULL,
            dupr_verified = false,
            dupr_verified_by = NULL,
            dupr_verified_at = NULL,
            dupr_verification_notes = p_notes,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = p_player_id;

        -- Log rejection
        INSERT INTO system.activity_logs (
            user_id,
            action,
            entity_type,
            entity_id,
            details
        ) VALUES (
            p_admin_id,
            'dupr_rejected',
            'player',
            p_player_id,
            jsonb_build_object(
                'player_email', v_player.email,
                'player_name', v_player.first_name || ' ' || v_player.last_name,
                'previous_dupr_rating', v_player.dupr_rating,
                'rejected_by', v_admin.username,
                'notes', p_notes
            )
        );

        RETURN json_build_object(
            'success', true,
            'message', 'DUPR rating rejected. Player must resubmit.',
            'player_name', v_player.first_name || ' ' || v_player.last_name
        );
    END IF;
END;
$$;

COMMENT ON FUNCTION api.verify_player_dupr IS 'Staff verifies or rejects a player DUPR rating';

-- ============================================================================
-- API FUNCTION: Get Pending DUPR Verifications
-- ============================================================================

CREATE OR REPLACE FUNCTION api.get_pending_dupr_verifications(
    p_limit INT DEFAULT 50,
    p_offset INT DEFAULT 0
)
RETURNS JSON
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
    v_result JSON;
    v_total INT;
BEGIN
    -- Get total count
    SELECT COUNT(*)
    INTO v_total
    FROM app_auth.players p
    WHERE p.dupr_rating IS NOT NULL
      AND p.dupr_verified = false;

    -- Get paginated results
    SELECT json_build_object(
        'success', true,
        'total', v_total,
        'limit', p_limit,
        'offset', p_offset,
        'data', COALESCE(json_agg(
            json_build_object(
                'id', p.id,
                'account_id', ua.id,
                'first_name', p.first_name,
                'last_name', p.last_name,
                'full_name', p.first_name || ' ' || p.last_name,
                'email', ua.email,
                'phone', p.phone,
                'dupr_rating', p.dupr_rating,
                'submitted_at', p.dupr_rating_updated_at,
                'membership_level', p.membership_level,
                'created_at', p.created_at
            ) ORDER BY p.dupr_rating_updated_at ASC
        ), '[]'::json)
    )
    INTO v_result
    FROM app_auth.players p
    JOIN app_auth.user_accounts ua ON ua.id = p.account_id
    WHERE p.dupr_rating IS NOT NULL
      AND p.dupr_verified = false
    LIMIT p_limit
    OFFSET p_offset;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION api.get_pending_dupr_verifications IS 'Get list of players awaiting DUPR verification';

-- ============================================================================
-- API FUNCTION: Get Player Profile with Verification Status
-- ============================================================================

CREATE OR REPLACE FUNCTION api.get_player_profile(
    p_account_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
    v_result JSON;
BEGIN
    SELECT json_build_object(
        'success', true,
        'data', json_build_object(
            'id', p.id,
            'account_id', ua.id,
            'email', ua.email,
            'first_name', p.first_name,
            'last_name', p.last_name,
            'full_name', p.first_name || ' ' || p.last_name,
            'display_name', p.display_name,
            'phone', p.phone,
            'address', p.address,
            'date_of_birth', p.date_of_birth,
            'membership_level', p.membership_level,
            'membership_started_on', p.membership_started_on,
            'membership_expires_on', p.membership_expires_on,
            'skill_level', p.skill_level,
            'dupr_rating', p.dupr_rating,
            'dupr_rating_updated_at', p.dupr_rating_updated_at,
            'dupr_verified', p.dupr_verified,
            'dupr_verified_at', p.dupr_verified_at,
            'dupr_verification_notes', p.dupr_verification_notes,
            'verified_by_name', CASE
                WHEN p.dupr_verified_by IS NOT NULL
                THEN (SELECT au.first_name || ' ' || au.last_name FROM app_auth.admin_users au WHERE au.id = p.dupr_verified_by)
                ELSE NULL
            END,
            'stripe_customer_id', p.stripe_customer_id,
            'is_active', ua.is_active,
            'is_verified', ua.is_verified,
            'last_login', ua.last_login,
            'created_at', p.created_at,
            'updated_at', p.updated_at,
            'profile_status', CASE
                WHEN p.dupr_rating IS NULL THEN 'incomplete'
                WHEN p.dupr_rating IS NOT NULL AND p.dupr_verified = false THEN 'pending_verification'
                WHEN p.dupr_verified = true THEN 'verified'
                ELSE 'unknown'
            END
        )
    )
    INTO v_result
    FROM app_auth.user_accounts ua
    JOIN app_auth.players p ON p.account_id = ua.id
    WHERE ua.id = p_account_id OR p.id = p_account_id;

    IF v_result IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'Player profile not found');
    END IF;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION api.get_player_profile IS 'Get player profile including DUPR verification status';

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

-- Grant execute permissions to authenticated users
GRANT EXECUTE ON FUNCTION api.submit_dupr_for_verification TO authenticated;
GRANT EXECUTE ON FUNCTION api.get_player_profile TO authenticated;

-- Grant execute permissions to service role
GRANT EXECUTE ON FUNCTION api.submit_dupr_for_verification TO service_role;
GRANT EXECUTE ON FUNCTION api.verify_player_dupr TO service_role;
GRANT EXECUTE ON FUNCTION api.get_pending_dupr_verifications TO service_role;
GRANT EXECUTE ON FUNCTION api.get_player_profile TO service_role;

-- Grant to admin authenticated users (additional layer - can be enforced in app)
GRANT EXECUTE ON FUNCTION api.verify_player_dupr TO authenticated;
GRANT EXECUTE ON FUNCTION api.get_pending_dupr_verifications TO authenticated;
-- Module 26: Migrate benefits column to prevent qty regex errors
-- Created: 2025-10-05
-- Purpose: Move benefits data to backup column and clear original to prevent
--          quantity regex from concatenating numbers (e.g., "2 months ($200 value)" → "2200")

BEGIN;

-- Step 1: Add backup column for benefits data
ALTER TABLE crowdfunding.contribution_tiers
ADD COLUMN IF NOT EXISTS benefits_backup jsonb;

-- Step 2: Copy all benefits data to the backup column
UPDATE crowdfunding.contribution_tiers
SET benefits_backup = benefits
WHERE benefits IS NOT NULL;

-- Step 3: Clear the original benefits column to prevent qty regex errors
UPDATE crowdfunding.contribution_tiers
SET benefits = '[]'::jsonb;

COMMIT;

-- Verification query (uncomment to check results):
-- SELECT id, name, benefits, benefits_backup FROM crowdfunding.contribution_tiers ORDER BY display_order;
-- ============================================================================
-- CROWDFUNDING RPC FUNCTIONS
-- Functions for checkout flow, payment processing, and backer management
-- ============================================================================

SET search_path TO crowdfunding, public;

-- ============================================================================
-- BACKER MANAGEMENT FUNCTIONS
-- ============================================================================

-- Get backer by email (used during checkout to check if backer exists)
CREATE OR REPLACE FUNCTION crowdfunding.get_backer_by_email(p_email public.CITEXT)
RETURNS TABLE(
    id UUID,
    email public.CITEXT,
    first_name VARCHAR(100),
    last_initial VARCHAR(1),
    phone VARCHAR(30),
    city VARCHAR(100),
    state VARCHAR(2),
    stripe_customer_id TEXT,
    total_contributed DECIMAL(10, 2),
    contribution_count INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        b.id,
        b.email,
        b.first_name,
        b.last_initial,
        b.phone,
        b.city,
        b.state,
        b.stripe_customer_id,
        b.total_contributed,
        b.contribution_count
    FROM crowdfunding.backers b
    WHERE b.email = p_email;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- CHECKOUT & CONTRIBUTION FUNCTIONS
-- ============================================================================

-- Create or update backer and create pending contribution
CREATE OR REPLACE FUNCTION crowdfunding.create_checkout_contribution(
    p_email public.CITEXT,
    p_first_name VARCHAR(100),
    p_last_initial VARCHAR(1),
    p_campaign_type_id UUID,
    p_tier_id UUID,
    p_amount DECIMAL(10, 2),
    p_phone VARCHAR(30) DEFAULT NULL,
    p_city VARCHAR(100) DEFAULT NULL,
    p_state VARCHAR(2) DEFAULT NULL,
    p_stripe_customer_id TEXT DEFAULT NULL,
    p_is_public BOOLEAN DEFAULT TRUE,
    p_show_amount BOOLEAN DEFAULT TRUE
)
RETURNS TABLE(
    backer_id UUID,
    contribution_id UUID
) AS $$
DECLARE
    v_backer_id UUID;
    v_contribution_id UUID;
BEGIN
    -- Create or update backer
    INSERT INTO crowdfunding.backers (
        email,
        first_name,
        last_initial,
        phone,
        city,
        state,
        stripe_customer_id
    )
    VALUES (
        p_email,
        p_first_name,
        p_last_initial,
        p_phone,
        p_city,
        p_state,
        p_stripe_customer_id
    )
    ON CONFLICT (email)
    DO UPDATE SET
        first_name = EXCLUDED.first_name,
        last_initial = EXCLUDED.last_initial,
        phone = COALESCE(EXCLUDED.phone, crowdfunding.backers.phone),
        city = COALESCE(EXCLUDED.city, crowdfunding.backers.city),
        state = COALESCE(EXCLUDED.state, crowdfunding.backers.state),
        stripe_customer_id = COALESCE(EXCLUDED.stripe_customer_id, crowdfunding.backers.stripe_customer_id),
        updated_at = CURRENT_TIMESTAMP
    RETURNING id INTO v_backer_id;

    -- Create pending contribution
    INSERT INTO crowdfunding.contributions (
        backer_id,
        campaign_type_id,
        tier_id,
        amount,
        status,
        is_public,
        show_amount
    )
    VALUES (
        v_backer_id,
        p_campaign_type_id,
        p_tier_id,
        p_amount,
        'pending',
        p_is_public,
        p_show_amount
    )
    RETURNING id INTO v_contribution_id;

    -- Return both IDs
    RETURN QUERY SELECT v_backer_id, v_contribution_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Update contribution with Stripe checkout session ID
CREATE OR REPLACE FUNCTION crowdfunding.update_contribution_session(
    p_contribution_id UUID,
    p_session_id TEXT
)
RETURNS VOID AS $$
BEGIN
    UPDATE crowdfunding.contributions
    SET stripe_checkout_session_id = p_session_id
    WHERE id = p_contribution_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Mark contribution as completed (called by webhook)
CREATE OR REPLACE FUNCTION crowdfunding.complete_contribution(
    p_contribution_id UUID,
    p_payment_intent_id TEXT,
    p_checkout_session_id TEXT,
    p_payment_method VARCHAR(50)
)
RETURNS VOID AS $$
BEGIN
    UPDATE crowdfunding.contributions
    SET
        status = 'completed',
        stripe_payment_intent_id = p_payment_intent_id,
        stripe_checkout_session_id = p_checkout_session_id,
        payment_method = p_payment_method,
        completed_at = CURRENT_TIMESTAMP
    WHERE id = p_contribution_id;

    -- Note: Triggers will handle updating campaign totals and creating founders wall entry
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

-- Grant execute to service role (used by API)
GRANT EXECUTE ON FUNCTION crowdfunding.get_backer_by_email(public.CITEXT) TO service_role;
GRANT EXECUTE ON FUNCTION crowdfunding.create_checkout_contribution(
    public.CITEXT, VARCHAR(100), VARCHAR(1), UUID, UUID, DECIMAL(10, 2),
    VARCHAR(30), VARCHAR(100), VARCHAR(2), TEXT, BOOLEAN, BOOLEAN
) TO service_role;
GRANT EXECUTE ON FUNCTION crowdfunding.update_contribution_session(UUID, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION crowdfunding.complete_contribution(UUID, TEXT, TEXT, VARCHAR(50)) TO service_role;

-- Grant execute to anon for public-facing checkout
GRANT EXECUTE ON FUNCTION crowdfunding.get_backer_by_email(public.CITEXT) TO anon;

COMMENT ON FUNCTION crowdfunding.get_backer_by_email IS 'Get backer details by email for checkout flow';
COMMENT ON FUNCTION crowdfunding.create_checkout_contribution IS 'Create or update backer and create pending contribution';
COMMENT ON FUNCTION crowdfunding.update_contribution_session IS 'Update contribution with Stripe session ID';
COMMENT ON FUNCTION crowdfunding.complete_contribution IS 'Mark contribution as completed after successful payment';
-- ============================================================================
-- BENEFIT TRACKING SYSTEM
-- Tables, views, and functions for tracking benefit allocations and usage
-- ============================================================================

SET search_path TO crowdfunding, public;

-- ============================================================================
-- TABLES
-- ============================================================================

-- Benefit Allocations - Individual benefit items allocated to backers
CREATE TABLE IF NOT EXISTS crowdfunding.benefit_allocations (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    backer_id UUID NOT NULL REFERENCES crowdfunding.backers(id) ON DELETE CASCADE,
    contribution_id UUID NOT NULL REFERENCES crowdfunding.contributions(id) ON DELETE CASCADE,
    tier_id UUID REFERENCES crowdfunding.contribution_tiers(id) ON DELETE SET NULL,

    -- Benefit details
    benefit_type VARCHAR(100) NOT NULL,
    benefit_name TEXT NOT NULL,
    benefit_description TEXT,

    -- Quantity tracking
    quantity_allocated DECIMAL(10, 2), -- NULL for unlimited/one-time benefits
    quantity_used DECIMAL(10, 2) DEFAULT 0,
    quantity_remaining DECIMAL(10, 2), -- Auto-calculated

    -- Validity period
    valid_from TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    valid_until TIMESTAMP WITH TIME ZONE, -- NULL for lifetime benefits

    -- Fulfillment tracking
    fulfillment_status VARCHAR(50) DEFAULT 'allocated',
    fulfillment_notes TEXT,
    fulfilled_at TIMESTAMP WITH TIME ZONE,
    fulfilled_by UUID, -- References staff user who fulfilled

    -- Metadata
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT valid_fulfillment_status CHECK (fulfillment_status IN (
        'allocated', 'in_progress', 'fulfilled', 'expired', 'cancelled'
    )),
    CONSTRAINT valid_benefit_type CHECK (benefit_type IN (
        'court_time_hours', 'dink_board_sessions', 'ball_machine_sessions',
        'pro_shop_discount', 'membership_months', 'private_lessons',
        'guest_passes', 'priority_booking', 'recognition', 'custom'
    ))
);

-- Benefit Usage Log - Track each redemption/usage
CREATE TABLE IF NOT EXISTS crowdfunding.benefit_usage_log (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    allocation_id UUID NOT NULL REFERENCES crowdfunding.benefit_allocations(id) ON DELETE CASCADE,

    -- Usage details
    quantity_used DECIMAL(10, 2) NOT NULL,
    usage_date DATE NOT NULL DEFAULT CURRENT_DATE,
    usage_time TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    used_for TEXT, -- Description of what it was used for

    -- Staff verification
    staff_id UUID, -- References staff user who processed
    staff_verified BOOLEAN DEFAULT false,
    notes TEXT,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- INDEXES
-- ============================================================================

CREATE INDEX idx_allocations_backer ON crowdfunding.benefit_allocations(backer_id);
CREATE INDEX idx_allocations_contribution ON crowdfunding.benefit_allocations(contribution_id);
CREATE INDEX idx_allocations_tier ON crowdfunding.benefit_allocations(tier_id);
CREATE INDEX idx_allocations_status ON crowdfunding.benefit_allocations(fulfillment_status);
CREATE INDEX idx_allocations_type ON crowdfunding.benefit_allocations(benefit_type);
CREATE INDEX idx_allocations_valid_until ON crowdfunding.benefit_allocations(valid_until);

CREATE INDEX idx_usage_allocation ON crowdfunding.benefit_usage_log(allocation_id);
CREATE INDEX idx_usage_date ON crowdfunding.benefit_usage_log(usage_date);
CREATE INDEX idx_usage_staff ON crowdfunding.benefit_usage_log(staff_id);

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Auto-calculate quantity_remaining
CREATE OR REPLACE FUNCTION crowdfunding.update_benefit_remaining()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.quantity_allocated IS NOT NULL THEN
        NEW.quantity_remaining := NEW.quantity_allocated - NEW.quantity_used;
    ELSE
        NEW.quantity_remaining := NULL; -- Unlimited
    END IF;

    NEW.updated_at := CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_benefit_remaining
    BEFORE INSERT OR UPDATE ON crowdfunding.benefit_allocations
    FOR EACH ROW
    EXECUTE FUNCTION crowdfunding.update_benefit_remaining();

-- ============================================================================
-- VIEWS
-- ============================================================================

-- View: All backers with summary of contributions and benefits
CREATE OR REPLACE VIEW crowdfunding.v_backer_summary AS
SELECT
    b.id AS backer_id,
    b.email,
    b.first_name,
    b.last_initial,
    b.phone,
    b.city,
    b.state,
    b.total_contributed,
    b.contribution_count,
    b.created_at AS backer_since,

    -- Benefit summary
    COUNT(DISTINCT ba.id) AS total_benefits,
    COUNT(DISTINCT ba.id) FILTER (WHERE ba.fulfillment_status = 'allocated') AS benefits_unclaimed,
    COUNT(DISTINCT ba.id) FILTER (WHERE ba.fulfillment_status = 'fulfilled') AS benefits_claimed,
    COUNT(DISTINCT ba.id) FILTER (WHERE ba.fulfillment_status = 'expired') AS benefits_expired,
    COUNT(DISTINCT ba.id) FILTER (WHERE ba.valid_until IS NOT NULL AND ba.valid_until < CURRENT_TIMESTAMP) AS benefits_expiring_soon,

    -- Latest contribution
    MAX(c.completed_at) AS last_contribution_date,

    -- Highest tier
    MAX(ct.amount) AS highest_tier_amount
FROM crowdfunding.backers b
LEFT JOIN crowdfunding.contributions c ON c.backer_id = b.id AND c.status = 'completed'
LEFT JOIN crowdfunding.contribution_tiers ct ON ct.id = c.tier_id
LEFT JOIN crowdfunding.benefit_allocations ba ON ba.backer_id = b.id
GROUP BY b.id, b.email, b.first_name, b.last_initial, b.phone, b.city, b.state,
         b.total_contributed, b.contribution_count, b.created_at
ORDER BY b.total_contributed DESC, b.created_at DESC;

-- View: Detailed backer benefits with claim status
CREATE OR REPLACE VIEW crowdfunding.v_backer_benefits_detailed AS
SELECT
    ba.id AS allocation_id,
    ba.backer_id,
    b.email,
    b.first_name,
    b.last_initial,
    ba.contribution_id,
    c.completed_at AS contribution_date,
    ct.name AS tier_name,
    c.amount AS contribution_amount,

    -- Benefit details
    ba.benefit_type,
    ba.benefit_name,
    ba.benefit_description,
    ba.quantity_allocated,
    ba.quantity_used,
    ba.quantity_remaining,

    -- Status
    ba.fulfillment_status,
    ba.valid_from,
    ba.valid_until,
    CASE
        WHEN ba.valid_until IS NULL THEN true
        WHEN ba.valid_until > CURRENT_TIMESTAMP THEN true
        ELSE false
    END AS is_valid,

    CASE
        WHEN ba.valid_until IS NOT NULL THEN
            EXTRACT(DAY FROM (ba.valid_until - CURRENT_TIMESTAMP))::INTEGER
        ELSE NULL
    END AS days_until_expiration,

    ba.fulfilled_at,
    ba.fulfillment_notes,
    ba.metadata,
    ba.created_at
FROM crowdfunding.benefit_allocations ba
JOIN crowdfunding.backers b ON b.id = ba.backer_id
JOIN crowdfunding.contributions c ON c.id = ba.contribution_id
LEFT JOIN crowdfunding.contribution_tiers ct ON ct.id = ba.tier_id
ORDER BY b.email, ba.created_at DESC;

-- View: Pending fulfillment (for staff)
CREATE OR REPLACE VIEW crowdfunding.v_pending_fulfillment AS
SELECT
    ba.id AS allocation_id,
    ba.backer_id,
    b.email,
    b.first_name,
    b.last_initial,
    b.phone,
    ba.benefit_type,
    ba.benefit_name,
    ba.quantity_allocated AS total_allocated,
    ba.quantity_remaining AS remaining,
    ba.valid_until,
    ba.fulfillment_status,
    ba.created_at,
    ct.name AS tier_name,
    c.amount AS contribution_amount,

    CASE
        WHEN ba.valid_until IS NOT NULL THEN
            EXTRACT(DAY FROM (ba.valid_until - CURRENT_TIMESTAMP))::INTEGER
        ELSE NULL
    END AS days_until_expiration
FROM crowdfunding.benefit_allocations ba
JOIN crowdfunding.backers b ON b.id = ba.backer_id
JOIN crowdfunding.contributions c ON c.id = ba.contribution_id
LEFT JOIN crowdfunding.contribution_tiers ct ON ct.id = c.tier_id
WHERE ba.fulfillment_status IN ('allocated', 'in_progress')
  AND (ba.valid_until IS NULL OR ba.valid_until > CURRENT_TIMESTAMP)
  AND (ba.quantity_remaining IS NULL OR ba.quantity_remaining > 0)
ORDER BY
    CASE WHEN ba.valid_until IS NOT NULL THEN EXTRACT(DAY FROM (ba.valid_until - CURRENT_TIMESTAMP)) END ASC NULLS LAST,
    ba.created_at ASC;

-- View: Fulfillment summary by benefit type
CREATE OR REPLACE VIEW crowdfunding.v_fulfillment_summary AS
SELECT
    ba.benefit_type,
    COUNT(*) AS total_allocations,
    COUNT(*) FILTER (WHERE ba.fulfillment_status = 'allocated') AS pending_count,
    COUNT(*) FILTER (WHERE ba.fulfillment_status = 'in_progress') AS in_progress_count,
    COUNT(*) FILTER (WHERE ba.fulfillment_status = 'fulfilled') AS fulfilled_count,
    COUNT(*) FILTER (WHERE ba.fulfillment_status = 'expired') AS expired_count,
    SUM(ba.quantity_allocated) AS total_units_allocated,
    SUM(ba.quantity_used) AS total_units_used,
    SUM(ba.quantity_remaining) AS total_units_remaining
FROM crowdfunding.benefit_allocations ba
GROUP BY ba.benefit_type
ORDER BY total_allocations DESC;

-- View: Active backer benefits (for redemption)
-- Aggregates multiple allocations of the same benefit type for each backer
CREATE OR REPLACE VIEW crowdfunding.v_active_backer_benefits AS
SELECT
    (array_agg(ba.id ORDER BY ba.created_at))[1] AS id,  -- Use first allocation ID as reference
    ba.backer_id,
    b.email,
    b.first_name,
    b.last_initial,
    ba.benefit_type,
    ba.benefit_name,
    SUM(ba.quantity_allocated)::numeric(10,2) AS total_allocated,  -- SUM and cast to maintain type
    SUM(ba.quantity_used)::numeric(10,2) AS total_used,            -- SUM and cast to maintain type
    SUM(ba.quantity_remaining)::numeric(10,2) AS remaining,        -- SUM and cast to maintain type
    MIN(ba.valid_from) AS valid_from,
    MAX(ba.valid_until) AS valid_until,
    MAX(ba.valid_until) IS NULL OR MAX(ba.valid_until) > CURRENT_TIMESTAMP AS is_valid,
    jsonb_agg(ba.metadata) AS metadata,
    MIN(ba.created_at) AS created_at
FROM crowdfunding.benefit_allocations ba
JOIN crowdfunding.backers b ON b.id = ba.backer_id
WHERE ba.fulfillment_status IN ('allocated', 'in_progress', 'fulfilled')
  AND (ba.valid_until IS NULL OR ba.valid_until > CURRENT_TIMESTAMP)
  AND (ba.quantity_remaining IS NULL OR ba.quantity_remaining > 0)
GROUP BY ba.backer_id, b.email, b.first_name, b.last_initial, ba.benefit_type, ba.benefit_name
ORDER BY MIN(ba.created_at) DESC;

-- ============================================================================
-- FUNCTIONS
-- ============================================================================

-- Allocate benefits from tier (called after contribution is completed)
CREATE OR REPLACE FUNCTION crowdfunding.allocate_benefits_from_tier(
    p_contribution_id UUID,
    p_tier_id UUID,
    p_backer_id UUID
)
RETURNS INTEGER AS $$
DECLARE
    v_tier RECORD;
    v_benefit JSONB;
    v_benefit_count INTEGER := 0;
    v_existing_count INTEGER := 0;
    v_quantity DECIMAL(10, 2);
    v_valid_until TIMESTAMP WITH TIME ZONE;
    v_duration_months INTEGER;
    v_duration_years INTEGER;
BEGIN
    -- Check if benefits have already been allocated for this contribution
    SELECT COUNT(*) INTO v_existing_count
    FROM crowdfunding.benefit_allocations
    WHERE contribution_id = p_contribution_id;

    -- If allocations already exist, return early to prevent duplicates
    IF v_existing_count > 0 THEN
        RETURN v_existing_count;
    END IF;

    -- Get tier details
    SELECT * INTO v_tier
    FROM crowdfunding.contribution_tiers
    WHERE id = p_tier_id;

    IF v_tier IS NULL THEN
        RAISE EXCEPTION 'Tier not found: %', p_tier_id;
    END IF;

    -- Parse benefits JSON and create allocations
    FOR v_benefit IN SELECT * FROM jsonb_array_elements(v_tier.benefits)
    LOOP
        v_quantity := NULL;
        v_valid_until := NULL;

        -- Extract quantity if specified in benefit metadata
        IF v_benefit ? 'quantity' THEN
            v_quantity := (v_benefit->>'quantity')::DECIMAL(10, 2);
        END IF;

        -- Calculate expiration based on duration
        IF v_benefit ? 'duration_months' THEN
            v_duration_months := (v_benefit->>'duration_months')::INTEGER;
            v_valid_until := CURRENT_TIMESTAMP + (v_duration_months || ' months')::INTERVAL;
        ELSIF v_benefit ? 'duration_years' THEN
            v_duration_years := (v_benefit->>'duration_years')::INTEGER;
            v_valid_until := CURRENT_TIMESTAMP + (v_duration_years || ' years')::INTERVAL;
        ELSIF v_benefit ? 'lifetime' AND (v_benefit->>'lifetime')::BOOLEAN THEN
            v_valid_until := NULL; -- Lifetime benefit
        END IF;

        -- Determine benefit type
        DECLARE
            v_benefit_type VARCHAR(100);
        BEGIN
            v_benefit_type := v_benefit->>'type';

            -- Map tier benefit types to allocation benefit types
            CASE v_benefit_type
                WHEN 'court_time_hours' THEN v_benefit_type := 'court_time_hours';
                WHEN 'dink_board_sessions' THEN v_benefit_type := 'dink_board_sessions';
                WHEN 'ball_machine_sessions' THEN v_benefit_type := 'ball_machine_sessions';
                WHEN 'pro_shop_discount' THEN v_benefit_type := 'pro_shop_discount';
                WHEN 'founding_membership', 'membership_months' THEN v_benefit_type := 'membership_months';
                WHEN 'free_lessons', 'private_lessons' THEN v_benefit_type := 'private_lessons';
                WHEN 'guest_passes' THEN v_benefit_type := 'guest_passes';
                WHEN 'priority_booking' THEN v_benefit_type := 'priority_booking';
                WHEN 'name_on_wall', 'court_sponsor' THEN v_benefit_type := 'recognition';
                ELSE v_benefit_type := 'custom';
            END CASE;

            -- Create benefit allocation
            INSERT INTO crowdfunding.benefit_allocations (
                backer_id,
                contribution_id,
                tier_id,
                benefit_type,
                benefit_name,
                benefit_description,
                quantity_allocated,
                valid_until,
                fulfillment_status,
                metadata
            )
            VALUES (
                p_backer_id,
                p_contribution_id,
                p_tier_id,
                v_benefit_type,
                COALESCE(v_benefit->>'text', v_tier.name || ' Benefit'),
                v_benefit->>'text',
                v_quantity,
                v_valid_until,
                'allocated',
                v_benefit
            );

            v_benefit_count := v_benefit_count + 1;
        END;
    END LOOP;

    RETURN v_benefit_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Redeem/use a benefit
CREATE OR REPLACE FUNCTION crowdfunding.redeem_benefit(
    p_allocation_id UUID,
    p_quantity DECIMAL(10, 2),
    p_used_for TEXT DEFAULT NULL,
    p_staff_id UUID DEFAULT NULL,
    p_notes TEXT DEFAULT NULL
)
RETURNS VOID AS $$
DECLARE
    v_allocation RECORD;
BEGIN
    -- Get allocation
    SELECT * INTO v_allocation
    FROM crowdfunding.benefit_allocations
    WHERE id = p_allocation_id;

    IF v_allocation IS NULL THEN
        RAISE EXCEPTION 'Benefit allocation not found: %', p_allocation_id;
    END IF;

    -- Check if valid
    IF v_allocation.valid_until IS NOT NULL AND v_allocation.valid_until < CURRENT_TIMESTAMP THEN
        RAISE EXCEPTION 'Benefit has expired';
    END IF;

    -- Check if enough remaining
    IF v_allocation.quantity_remaining IS NOT NULL AND v_allocation.quantity_remaining < p_quantity THEN
        RAISE EXCEPTION 'Insufficient quantity remaining. Available: %, Requested: %',
            v_allocation.quantity_remaining, p_quantity;
    END IF;

    -- Update allocation
    UPDATE crowdfunding.benefit_allocations
    SET
        quantity_used = quantity_used + p_quantity,
        fulfillment_status = CASE
            WHEN quantity_remaining - p_quantity <= 0 THEN 'fulfilled'
            ELSE 'in_progress'
        END,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_allocation_id;

    -- Log usage
    INSERT INTO crowdfunding.benefit_usage_log (
        allocation_id,
        quantity_used,
        used_for,
        staff_id,
        staff_verified,
        notes
    )
    VALUES (
        p_allocation_id,
        p_quantity,
        p_used_for,
        p_staff_id,
        p_staff_id IS NOT NULL, -- Auto-verify if staff processed
        p_notes
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- ROW LEVEL SECURITY
-- ============================================================================

ALTER TABLE crowdfunding.benefit_allocations ENABLE ROW LEVEL SECURITY;
ALTER TABLE crowdfunding.benefit_usage_log ENABLE ROW LEVEL SECURITY;

-- Service role has full access
CREATE POLICY "Service role has full access to allocations"
    ON crowdfunding.benefit_allocations FOR ALL
    USING (current_setting('request.jwt.claims', true)::json->>'role' = 'service_role');

CREATE POLICY "Service role has full access to usage log"
    ON crowdfunding.benefit_usage_log FOR ALL
    USING (current_setting('request.jwt.claims', true)::json->>'role' = 'service_role');

-- Authenticated users can view their own benefits (for future user accounts)
CREATE POLICY "Users can view their own benefits"
    ON crowdfunding.benefit_allocations FOR SELECT
    USING (
        backer_id IN (
            SELECT id FROM crowdfunding.backers
            WHERE user_id = auth.uid()
        )
    );

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

GRANT SELECT ON crowdfunding.v_backer_summary TO authenticated, service_role;
GRANT SELECT ON crowdfunding.v_backer_benefits_detailed TO authenticated, service_role;
GRANT SELECT ON crowdfunding.v_pending_fulfillment TO authenticated, service_role;
GRANT SELECT ON crowdfunding.v_fulfillment_summary TO authenticated, service_role;
GRANT SELECT ON crowdfunding.v_active_backer_benefits TO authenticated, service_role;

GRANT EXECUTE ON FUNCTION crowdfunding.allocate_benefits_from_tier(UUID, UUID, UUID) TO service_role;
GRANT EXECUTE ON FUNCTION crowdfunding.redeem_benefit(UUID, DECIMAL, TEXT, UUID, TEXT) TO service_role, authenticated;

COMMENT ON TABLE crowdfunding.benefit_allocations IS 'Individual benefit items allocated to backers with redemption tracking';
COMMENT ON TABLE crowdfunding.benefit_usage_log IS 'Log of benefit redemptions and usage';
COMMENT ON VIEW crowdfunding.v_backer_summary IS 'All backers with contribution and benefit summary';
COMMENT ON VIEW crowdfunding.v_backer_benefits_detailed IS 'Detailed view of backer benefits with claim status';
COMMENT ON FUNCTION crowdfunding.allocate_benefits_from_tier IS 'Create benefit allocations from tier benefits JSON';
COMMENT ON FUNCTION crowdfunding.redeem_benefit IS 'Record benefit usage and update quantities';
-- ============================================================================
-- CONTRIBUTION EMAIL FUNCTIONS
-- Functions to send thank you emails with receipts and benefits
-- ============================================================================

SET search_path TO crowdfunding, system, public;

-- ============================================================================
-- EMAIL GENERATION FUNCTIONS
-- ============================================================================

-- Function to format a single benefit for HTML display
CREATE OR REPLACE FUNCTION crowdfunding.format_benefit_html(
    p_benefit_name TEXT,
    p_benefit_description TEXT,
    p_quantity DECIMAL(10, 2),
    p_valid_until TIMESTAMP WITH TIME ZONE
)
RETURNS TEXT AS $$
DECLARE
    v_html TEXT;
    v_details TEXT := '';
BEGIN
    -- Build details string
    IF p_quantity IS NOT NULL THEN
        v_details := '<span class="benefit-quantity">' || p_quantity::TEXT || 'x</span>';
    END IF;

    IF p_valid_until IS NOT NULL THEN
        IF v_details != '' THEN
            v_details := v_details || ' • ';
        END IF;
        v_details := v_details || 'Valid until ' || TO_CHAR(p_valid_until, 'Mon DD, YYYY');
    ELSIF p_quantity IS NULL THEN
        v_details := '<span class="benefit-quantity">Lifetime</span>';
    END IF;

    -- Build HTML
    v_html := '<div class="benefit-item">' ||
              '<div class="checkmark">✓</div>' ||
              '<div class="benefit-content">' ||
              '<div class="benefit-name">' || COALESCE(p_benefit_description, p_benefit_name) || '</div>';

    IF v_details != '' THEN
        v_html := v_html || '<div class="benefit-details">' || v_details || '</div>';
    END IF;

    v_html := v_html || '</div></div>';

    RETURN v_html;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Function to format a single benefit for plain text display
CREATE OR REPLACE FUNCTION crowdfunding.format_benefit_text(
    p_benefit_name TEXT,
    p_benefit_description TEXT,
    p_quantity DECIMAL(10, 2),
    p_valid_until TIMESTAMP WITH TIME ZONE
)
RETURNS TEXT AS $$
DECLARE
    v_text TEXT;
    v_details TEXT := '';
BEGIN
    v_text := '• ' || COALESCE(p_benefit_description, p_benefit_name);

    -- Add quantity if specified
    IF p_quantity IS NOT NULL THEN
        v_details := ' (' || p_quantity::TEXT || 'x';
    END IF;

    -- Add expiration if specified
    IF p_valid_until IS NOT NULL THEN
        IF v_details = '' THEN
            v_details := ' (Valid until ' || TO_CHAR(p_valid_until, 'Mon DD, YYYY') || ')';
        ELSE
            v_details := v_details || ', valid until ' || TO_CHAR(p_valid_until, 'Mon DD, YYYY') || ')';
        END IF;
    ELSIF p_quantity IS NULL THEN
        v_details := ' (Lifetime benefit)';
    ELSIF p_quantity IS NOT NULL AND v_details != '' THEN
        v_details := v_details || ')';
    END IF;

    RETURN v_text || v_details;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ============================================================================
-- MAIN EMAIL SENDING FUNCTION
-- ============================================================================

-- Function to send contribution thank you email with receipt and benefits
CREATE OR REPLACE FUNCTION crowdfunding.send_contribution_thank_you_email(
    p_contribution_id UUID
)
RETURNS JSONB AS $$
DECLARE
    v_contribution RECORD;
    v_backer RECORD;
    v_tier RECORD;
    v_campaign RECORD;
    v_founders_wall RECORD;
    v_benefits RECORD;
    v_benefits_html TEXT := '';
    v_benefits_text TEXT := '';
    v_email_data JSONB;
    v_email_log_id UUID;
    v_benefit_count INTEGER := 0;
BEGIN
    -- Get contribution details
    SELECT
        c.id,
        c.amount,
        c.completed_at,
        c.stripe_payment_intent_id,
        c.stripe_charge_id,
        c.payment_method,
        c.backer_id,
        c.tier_id,
        c.campaign_type_id
    INTO v_contribution
    FROM crowdfunding.contributions c
    WHERE c.id = p_contribution_id;

    IF v_contribution IS NULL THEN
        RAISE EXCEPTION 'Contribution not found: %', p_contribution_id;
    END IF;

    IF v_contribution.completed_at IS NULL THEN
        RAISE EXCEPTION 'Contribution has not been completed yet';
    END IF;

    -- Get backer details
    SELECT * INTO v_backer
    FROM crowdfunding.backers
    WHERE id = v_contribution.backer_id;

    -- Get tier details
    IF v_contribution.tier_id IS NOT NULL THEN
        SELECT * INTO v_tier
        FROM crowdfunding.contribution_tiers
        WHERE id = v_contribution.tier_id;
    END IF;

    -- Get campaign details
    SELECT * INTO v_campaign
    FROM crowdfunding.campaign_types
    WHERE id = v_contribution.campaign_type_id;

    -- Get founders wall entry if exists
    SELECT * INTO v_founders_wall
    FROM crowdfunding.founders_wall
    WHERE backer_id = v_contribution.backer_id;

    -- Get all benefits allocated to this contribution
    FOR v_benefits IN
        SELECT
            benefit_name,
            benefit_description,
            quantity_allocated,
            valid_until
        FROM crowdfunding.benefit_allocations
        WHERE contribution_id = p_contribution_id
        ORDER BY created_at
    LOOP
        v_benefit_count := v_benefit_count + 1;

        -- Build HTML benefits list
        v_benefits_html := v_benefits_html ||
            crowdfunding.format_benefit_html(
                v_benefits.benefit_name,
                v_benefits.benefit_description,
                v_benefits.quantity_allocated,
                v_benefits.valid_until
            );

        -- Build plain text benefits list
        v_benefits_text := v_benefits_text ||
            crowdfunding.format_benefit_text(
                v_benefits.benefit_name,
                v_benefits.benefit_description,
                v_benefits.quantity_allocated,
                v_benefits.valid_until
            ) || E'\n';
    END LOOP;

    -- If no benefits found, check tier benefits directly
    IF v_benefit_count = 0 AND v_tier IS NOT NULL THEN
        DECLARE
            v_tier_benefit JSONB;
        BEGIN
            FOR v_tier_benefit IN SELECT * FROM jsonb_array_elements(v_tier.benefits)
            LOOP
                v_benefits_html := v_benefits_html ||
                    crowdfunding.format_benefit_html(
                        v_tier_benefit->>'type',
                        v_tier_benefit->>'text',
                        NULL,
                        NULL
                    );

                v_benefits_text := v_benefits_text || '• ' || (v_tier_benefit->>'text') || E'\n';
            END LOOP;
        END;
    END IF;

    -- If still no benefits, add a default message
    IF v_benefits_html = '' THEN
        v_benefits_html := '<div class="benefit-item"><div class="checkmark">✓</div><div class="benefit-content"><div class="benefit-name">Your support is making The Dink House possible!</div></div></div>';
        v_benefits_text := '• Your support is making The Dink House possible!';
    END IF;

    -- Build email data
    v_email_data := jsonb_build_object(
        'first_name', v_backer.first_name,
        'amount', TO_CHAR(v_contribution.amount, 'FM999,999.00'),
        'tier_name', COALESCE(v_tier.name, 'Custom Contribution'),
        'contribution_date', TO_CHAR(v_contribution.completed_at, 'Mon DD, YYYY at HH12:MI AM'),
        'contribution_id', v_contribution.id::TEXT,
        'payment_method', COALESCE(INITCAP(v_contribution.payment_method), 'Card'),
        'stripe_charge_id', COALESCE(v_contribution.stripe_charge_id, v_contribution.stripe_payment_intent_id, 'N/A'),
        'benefits_html', v_benefits_html,
        'benefits_text', v_benefits_text,
        'on_founders_wall', (v_founders_wall IS NOT NULL),
        'display_name', COALESCE(v_founders_wall.display_name, v_backer.first_name || ' ' || v_backer.last_initial || '.'),
        'founders_wall_message', CASE
            WHEN v_founders_wall.is_featured THEN
                'You''ll be featured prominently as a major supporter!'
            WHEN v_founders_wall IS NOT NULL THEN
                'Thank you for being a founding member of our community!'
            ELSE
                ''
        END,
        'site_url', 'https://thedinkhouse.com',
        'campaign_name', v_campaign.name
    );

    -- Log the email (ready to be sent by external service)
    v_email_log_id := system.log_email(
        'contribution_thank_you',
        v_backer.email,
        'support@thedinkhouse.com',
        'Thank You for Your Contribution to The Dink House! 🎉',
        'pending',
        jsonb_build_object(
            'contribution_id', v_contribution.id,
            'backer_id', v_backer.id,
            'amount', v_contribution.amount,
            'tier_id', v_contribution.tier_id
        )
    );

    -- Return success with email data and log ID
    RETURN jsonb_build_object(
        'success', true,
        'email_log_id', v_email_log_id,
        'recipient', v_backer.email,
        'email_data', v_email_data,
        'message', 'Email queued for sending'
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', SQLERRM,
            'message', 'Failed to prepare thank you email'
        );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- TRIGGER TO AUTO-SEND EMAILS ON CONTRIBUTION COMPLETION
-- ============================================================================

-- Function to trigger thank you email after contribution is completed
CREATE OR REPLACE FUNCTION crowdfunding.trigger_contribution_thank_you_email()
RETURNS TRIGGER AS $$
DECLARE
    v_result JSONB;
BEGIN
    -- Only send email when contribution status changes to 'completed'
    IF NEW.status = 'completed' AND (OLD IS NULL OR OLD.status != 'completed') THEN
        -- First, allocate benefits if tier exists
        IF NEW.tier_id IS NOT NULL THEN
            PERFORM crowdfunding.allocate_benefits_from_tier(
                NEW.id,
                NEW.tier_id,
                NEW.backer_id
            );
        END IF;

        -- Then send thank you email
        v_result := crowdfunding.send_contribution_thank_you_email(NEW.id);

        -- Log result (for debugging)
        IF NOT (v_result->>'success')::BOOLEAN THEN
            RAISE WARNING 'Failed to send contribution thank you email: %', v_result->>'error';
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger
DROP TRIGGER IF EXISTS trigger_send_contribution_thank_you ON crowdfunding.contributions;
CREATE TRIGGER trigger_send_contribution_thank_you
    AFTER INSERT OR UPDATE ON crowdfunding.contributions
    FOR EACH ROW
    EXECUTE FUNCTION crowdfunding.trigger_contribution_thank_you_email();

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

GRANT EXECUTE ON FUNCTION crowdfunding.format_benefit_html(TEXT, TEXT, DECIMAL, TIMESTAMP WITH TIME ZONE) TO service_role;
GRANT EXECUTE ON FUNCTION crowdfunding.format_benefit_text(TEXT, TEXT, DECIMAL, TIMESTAMP WITH TIME ZONE) TO service_role;
GRANT EXECUTE ON FUNCTION crowdfunding.send_contribution_thank_you_email(UUID) TO service_role, authenticated;

COMMENT ON FUNCTION crowdfunding.send_contribution_thank_you_email IS 'Send contribution thank you email with receipt and benefits';
COMMENT ON FUNCTION crowdfunding.trigger_contribution_thank_you_email IS 'Trigger function to auto-send thank you emails when contributions are completed';
-- ============================================================================
-- MEMBERSHIP PRICING MODULE
-- Membership tier configuration and pricing management
-- ============================================================================

SET search_path TO system, app_auth, public;

-- ============================================================================
-- MEMBERSHIP TIERS TABLE
-- Configuration for all membership levels
-- ============================================================================

CREATE TABLE IF NOT EXISTS system.membership_tiers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tier_code app_auth.membership_level NOT NULL UNIQUE,
    tier_name VARCHAR(50) NOT NULL,
    monthly_price DECIMAL(10, 2) NOT NULL DEFAULT 0,
    description TEXT,

    -- Open Play Pricing
    open_play_access TEXT, -- 'unlimited', 'off-peak', 'none'
    open_play_peak_price DECIMAL(10, 2) DEFAULT 0,
    open_play_offpeak_price DECIMAL(10, 2) DEFAULT 0,

    -- Court Rental Pricing
    court_rental_discount_percent INTEGER DEFAULT 0, -- Percentage off
    court_rental_peak_price DECIMAL(10, 2),
    court_rental_offpeak_price DECIMAL(10, 2),
    free_court_rental_hours TEXT, -- e.g., 'weekdays 7am-5pm outdoor'

    -- Equipment & Other
    equipment_rental_price DECIMAL(10, 2) DEFAULT 0,

    -- Access & Policies
    booking_window_days INTEGER DEFAULT 3, -- Days in advance
    cancellation_hours INTEGER DEFAULT 24, -- Hours notice required
    guest_passes_per_month INTEGER DEFAULT 0,

    -- Benefits (JSON for flexibility)
    benefits JSONB DEFAULT '[]'::jsonb,
    features JSONB DEFAULT '[]'::jsonb,

    -- Metadata
    is_active BOOLEAN DEFAULT true,
    sort_order INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE system.membership_tiers IS 'Configuration for all membership tier pricing and benefits';

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_membership_tiers_code ON system.membership_tiers(tier_code);
CREATE INDEX IF NOT EXISTS idx_membership_tiers_active ON system.membership_tiers(is_active);

-- ============================================================================
-- PLAYER REGISTRATION FEES TABLE
-- Track one-time $5 registration fee for guests
-- ============================================================================

CREATE TABLE IF NOT EXISTS app_auth.player_fees (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id UUID NOT NULL REFERENCES app_auth.players(id) ON DELETE CASCADE,
    fee_type VARCHAR(50) NOT NULL DEFAULT 'registration', -- 'registration', 'late_cancellation', etc.
    amount DECIMAL(10, 2) NOT NULL,

    -- Payment tracking
    stripe_payment_intent_id TEXT,
    stripe_charge_id TEXT,
    payment_status VARCHAR(50) DEFAULT 'pending', -- 'pending', 'paid', 'failed', 'refunded'
    paid_at TIMESTAMPTZ,

    -- Metadata
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_player_registration_fee UNIQUE (player_id, fee_type)
);

COMMENT ON TABLE app_auth.player_fees IS 'Track one-time fees like $5 registration fee';

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_player_fees_player ON app_auth.player_fees(player_id);
CREATE INDEX IF NOT EXISTS idx_player_fees_status ON app_auth.player_fees(payment_status);
CREATE INDEX IF NOT EXISTS idx_player_fees_type ON app_auth.player_fees(fee_type);

-- ============================================================================
-- MEMBERSHIP TRANSACTIONS TABLE
-- Track all membership payments, upgrades, renewals
-- ============================================================================

CREATE TABLE IF NOT EXISTS app_auth.membership_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id UUID NOT NULL REFERENCES app_auth.players(id) ON DELETE CASCADE,

    -- Membership details
    from_tier app_auth.membership_level,
    to_tier app_auth.membership_level NOT NULL,
    transaction_type VARCHAR(50) NOT NULL, -- 'upgrade', 'downgrade', 'renewal', 'new'

    -- Payment
    amount DECIMAL(10, 2) NOT NULL,
    stripe_payment_intent_id TEXT,
    stripe_subscription_id TEXT,
    payment_status VARCHAR(50) DEFAULT 'pending', -- 'pending', 'completed', 'failed', 'refunded'

    -- Period
    effective_date DATE NOT NULL,
    expires_date DATE,

    -- Metadata
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE app_auth.membership_transactions IS 'All membership payment and upgrade transactions';

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_membership_transactions_player ON app_auth.membership_transactions(player_id);
CREATE INDEX IF NOT EXISTS idx_membership_transactions_status ON app_auth.membership_transactions(payment_status);
CREATE INDEX IF NOT EXISTS idx_membership_transactions_type ON app_auth.membership_transactions(transaction_type);
CREATE INDEX IF NOT EXISTS idx_membership_transactions_effective ON app_auth.membership_transactions(effective_date);

-- ============================================================================
-- SEED MEMBERSHIP TIER DATA
-- ============================================================================

INSERT INTO system.membership_tiers (
    tier_code,
    tier_name,
    monthly_price,
    description,
    open_play_access,
    open_play_peak_price,
    open_play_offpeak_price,
    court_rental_peak_price,
    court_rental_offpeak_price,
    equipment_rental_price,
    booking_window_days,
    cancellation_hours,
    guest_passes_per_month,
    benefits,
    features,
    sort_order
) VALUES
-- GUEST TIER
(
    'guest',
    'Guest',
    0.00,
    'Pay-per-session access with no monthly commitment',
    'none',
    15.00, -- $15 peak open play
    10.00, -- $10 off-peak open play
    45.00, -- $45/hour peak court rental
    35.00, -- $35/hour off-peak court rental
    8.00,  -- $8 equipment rental
    3,     -- 3 days advance booking
    24,    -- 24 hour cancellation
    0,
    '["One-time $5 registration fee", "Pay per session", "No monthly commitment", "Access to all facilities"]'::jsonb,
    '["Open play access (pay per session)", "Court rentals (pay per hour)", "Equipment rentals available"]'::jsonb,
    1
),
-- BASIC TIER (Dink)
(
    'basic',
    'Dink',
    59.00,
    'Perfect for casual players who want regular access',
    'unlimited-outdoor',
    0.00,  -- Free open play
    0.00,
    40.50, -- 10% off: $45 -> $40.50
    31.50, -- 10% off: $35 -> $31.50
    8.00,
    7,     -- 7 days advance
    24,
    1,     -- 1 guest pass per month
    '["Unlimited outdoor open play", "10% off court bookings", "1 guest pass per month", "7-day advance booking"]'::jsonb,
    '["Unlimited outdoor open play", "10% discount on court bookings", "Book up to 7 days in advance", "1 free guest pass per month"]'::jsonb,
    2
),
-- PREMIUM TIER (Ace)
(
    'premium',
    'Ace',
    109.00,
    'For dedicated players who want indoor + outdoor access',
    'unlimited',
    0.00,  -- Free all open play
    0.00,
    36.00, -- 20% off: $45 -> $36
    28.00, -- 20% off: $35 -> $28
    0.00,  -- Free equipment rental
    10,    -- 10 days advance
    24,
    2,     -- 2 guest passes per month
    '["Unlimited indoor + outdoor open play", "Free weekday court rentals (7am-5pm outdoor)", "20% off all court bookings", "Free equipment rental", "Free clinics access", "2 guest passes per month", "10-day advance booking"]'::jsonb,
    '["Unlimited open play (all times)", "Free court rentals weekdays 7am-5pm (outdoor)", "20% discount on court bookings", "Free equipment rental", "Free clinics access", "Book up to 10 days in advance", "2 free guest passes per month"]'::jsonb,
    3
),
-- VIP TIER (Champion)
(
    'vip',
    'Champion',
    159.00,
    'Elite membership with maximum benefits and priority access',
    'unlimited',
    0.00,  -- Free all open play
    0.00,
    33.75, -- 25% off: $45 -> $33.75
    26.25, -- 25% off: $35 -> $26.25
    0.00,  -- Free equipment rental
    14,    -- 14 days advance
    24,
    4,     -- 4 guest passes per month
    '["Unlimited indoor + outdoor open play (all times)", "Free weekday court rentals (7am-5pm indoor + outdoor)", "25% off prime-time bookings", "Free equipment rental", "Free clinics + 1 private lesson per month", "Priority tournament registration", "4 guest passes per month", "14-day advance booking"]'::jsonb,
    '["Unlimited open play (peak + off-peak)", "Free court rentals weekdays 7am-5pm (indoor + outdoor)", "25% discount on prime-time bookings", "Free equipment rental", "Free clinics + 1 private lesson monthly", "Priority tournament registration", "Book up to 14 days in advance", "4 free guest passes per month"]'::jsonb,
    4
)
ON CONFLICT (tier_code) DO UPDATE SET
    tier_name = EXCLUDED.tier_name,
    monthly_price = EXCLUDED.monthly_price,
    description = EXCLUDED.description,
    open_play_access = EXCLUDED.open_play_access,
    open_play_peak_price = EXCLUDED.open_play_peak_price,
    open_play_offpeak_price = EXCLUDED.open_play_offpeak_price,
    court_rental_peak_price = EXCLUDED.court_rental_peak_price,
    court_rental_offpeak_price = EXCLUDED.court_rental_offpeak_price,
    equipment_rental_price = EXCLUDED.equipment_rental_price,
    booking_window_days = EXCLUDED.booking_window_days,
    cancellation_hours = EXCLUDED.cancellation_hours,
    guest_passes_per_month = EXCLUDED.guest_passes_per_month,
    benefits = EXCLUDED.benefits,
    features = EXCLUDED.features,
    sort_order = EXCLUDED.sort_order,
    updated_at = CURRENT_TIMESTAMP;

-- ============================================================================
-- RPC FUNCTIONS
-- ============================================================================

-- Get pricing for a specific membership tier
CREATE OR REPLACE FUNCTION get_membership_pricing(p_tier app_auth.membership_level)
RETURNS TABLE (
    tier_code TEXT,
    tier_name TEXT,
    monthly_price DECIMAL,
    description TEXT,
    open_play_access TEXT,
    open_play_peak_price DECIMAL,
    open_play_offpeak_price DECIMAL,
    court_rental_peak_price DECIMAL,
    court_rental_offpeak_price DECIMAL,
    equipment_rental_price DECIMAL,
    booking_window_days INTEGER,
    cancellation_hours INTEGER,
    guest_passes_per_month INTEGER,
    benefits JSONB,
    features JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT
        mt.tier_code::TEXT,
        mt.tier_name,
        mt.monthly_price,
        mt.description,
        mt.open_play_access,
        mt.open_play_peak_price,
        mt.open_play_offpeak_price,
        mt.court_rental_peak_price,
        mt.court_rental_offpeak_price,
        mt.equipment_rental_price,
        mt.booking_window_days,
        mt.cancellation_hours,
        mt.guest_passes_per_month,
        mt.benefits,
        mt.features
    FROM system.membership_tiers mt
    WHERE mt.tier_code = p_tier
    AND mt.is_active = true;
END;
$$;

-- Get all membership tiers for comparison
CREATE OR REPLACE FUNCTION get_all_membership_tiers()
RETURNS TABLE (
    tier_code TEXT,
    tier_name TEXT,
    monthly_price DECIMAL,
    description TEXT,
    open_play_access TEXT,
    open_play_peak_price DECIMAL,
    open_play_offpeak_price DECIMAL,
    court_rental_peak_price DECIMAL,
    court_rental_offpeak_price DECIMAL,
    equipment_rental_price DECIMAL,
    booking_window_days INTEGER,
    cancellation_hours INTEGER,
    guest_passes_per_month INTEGER,
    benefits JSONB,
    features JSONB,
    sort_order INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT
        mt.tier_code::TEXT,
        mt.tier_name,
        mt.monthly_price,
        mt.description,
        mt.open_play_access,
        mt.open_play_peak_price,
        mt.open_play_offpeak_price,
        mt.court_rental_peak_price,
        mt.court_rental_offpeak_price,
        mt.equipment_rental_price,
        mt.booking_window_days,
        mt.cancellation_hours,
        mt.guest_passes_per_month,
        mt.benefits,
        mt.features,
        mt.sort_order
    FROM system.membership_tiers mt
    WHERE mt.is_active = true
    ORDER BY mt.sort_order;
END;
$$;

-- Get player's current pricing information
CREATE OR REPLACE FUNCTION get_player_pricing_info(p_player_id UUID)
RETURNS TABLE (
    player_id UUID,
    membership_level TEXT,
    tier_name TEXT,
    monthly_price DECIMAL,
    registration_fee_paid BOOLEAN,
    registration_fee_amount DECIMAL,
    open_play_peak_price DECIMAL,
    open_play_offpeak_price DECIMAL,
    court_rental_peak_price DECIMAL,
    court_rental_offpeak_price DECIMAL,
    equipment_rental_price DECIMAL,
    booking_window_days INTEGER,
    cancellation_hours INTEGER,
    guest_passes_per_month INTEGER,
    benefits JSONB,
    features JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.id,
        p.membership_level::TEXT,
        mt.tier_name,
        mt.monthly_price,
        COALESCE(pf.payment_status = 'paid', false) as registration_fee_paid,
        COALESCE(pf.amount, 5.00) as registration_fee_amount,
        mt.open_play_peak_price,
        mt.open_play_offpeak_price,
        mt.court_rental_peak_price,
        mt.court_rental_offpeak_price,
        mt.equipment_rental_price,
        mt.booking_window_days,
        mt.cancellation_hours,
        mt.guest_passes_per_month,
        mt.benefits,
        mt.features
    FROM app_auth.players p
    JOIN system.membership_tiers mt ON mt.tier_code = p.membership_level
    LEFT JOIN app_auth.player_fees pf ON pf.player_id = p.id AND pf.fee_type = 'registration'
    WHERE p.id = p_player_id;
END;
$$;

-- Check if player has paid registration fee
CREATE OR REPLACE FUNCTION has_paid_registration_fee(p_player_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_paid BOOLEAN;
BEGIN
    SELECT COALESCE(payment_status = 'paid', false)
    INTO v_paid
    FROM app_auth.player_fees
    WHERE player_id = p_player_id
    AND fee_type = 'registration';

    RETURN COALESCE(v_paid, false);
END;
$$;

-- Record registration fee payment
CREATE OR REPLACE FUNCTION record_registration_fee(
    p_player_id UUID,
    p_stripe_payment_intent_id TEXT,
    p_stripe_charge_id TEXT DEFAULT NULL
)
RETURNS TABLE (
    success BOOLEAN,
    message TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Insert or update registration fee record
    INSERT INTO app_auth.player_fees (
        player_id,
        fee_type,
        amount,
        stripe_payment_intent_id,
        stripe_charge_id,
        payment_status,
        paid_at
    ) VALUES (
        p_player_id,
        'registration',
        5.00,
        p_stripe_payment_intent_id,
        p_stripe_charge_id,
        'paid',
        CURRENT_TIMESTAMP
    )
    ON CONFLICT (player_id, fee_type)
    DO UPDATE SET
        stripe_payment_intent_id = EXCLUDED.stripe_payment_intent_id,
        stripe_charge_id = EXCLUDED.stripe_charge_id,
        payment_status = 'paid',
        paid_at = CURRENT_TIMESTAMP,
        updated_at = CURRENT_TIMESTAMP;

    RETURN QUERY SELECT true, 'Registration fee recorded successfully'::TEXT;
END;
$$;

-- Record membership upgrade/change transaction
CREATE OR REPLACE FUNCTION record_membership_transaction(
    p_player_id UUID,
    p_to_tier app_auth.membership_level,
    p_transaction_type VARCHAR(50),
    p_amount DECIMAL,
    p_stripe_payment_intent_id TEXT DEFAULT NULL,
    p_stripe_subscription_id TEXT DEFAULT NULL,
    p_effective_date DATE DEFAULT CURRENT_DATE,
    p_expires_date DATE DEFAULT NULL
)
RETURNS TABLE (
    success BOOLEAN,
    message TEXT,
    transaction_id UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_from_tier app_auth.membership_level;
    v_transaction_id UUID;
BEGIN
    -- Get current membership level
    SELECT membership_level INTO v_from_tier
    FROM app_auth.players
    WHERE id = p_player_id;

    -- Insert transaction
    INSERT INTO app_auth.membership_transactions (
        player_id,
        from_tier,
        to_tier,
        transaction_type,
        amount,
        stripe_payment_intent_id,
        stripe_subscription_id,
        payment_status,
        effective_date,
        expires_date
    ) VALUES (
        p_player_id,
        v_from_tier,
        p_to_tier,
        p_transaction_type,
        p_amount,
        p_stripe_payment_intent_id,
        p_stripe_subscription_id,
        'completed',
        p_effective_date,
        p_expires_date
    )
    RETURNING id INTO v_transaction_id;

    -- Update player's membership level
    UPDATE app_auth.players
    SET
        membership_level = p_to_tier,
        membership_started_on = p_effective_date,
        membership_expires_on = p_expires_date,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_player_id;

    RETURN QUERY SELECT true, 'Membership transaction recorded successfully'::TEXT, v_transaction_id;
END;
$$;

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

-- Grant access to membership tiers (public read)
GRANT SELECT ON system.membership_tiers TO anon;
GRANT SELECT ON system.membership_tiers TO authenticated;
GRANT SELECT ON system.membership_tiers TO service_role;

-- Grant access to player fees (restricted)
GRANT SELECT ON app_auth.player_fees TO authenticated;
GRANT INSERT, UPDATE ON app_auth.player_fees TO authenticated;
GRANT ALL ON app_auth.player_fees TO service_role;

-- Grant access to membership transactions (restricted)
GRANT SELECT ON app_auth.membership_transactions TO authenticated;
GRANT INSERT ON app_auth.membership_transactions TO authenticated;
GRANT ALL ON app_auth.membership_transactions TO service_role;

-- Grant execute on functions
GRANT EXECUTE ON FUNCTION get_membership_pricing TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION get_all_membership_tiers TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION get_player_pricing_info TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION has_paid_registration_fee TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION record_registration_fee TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION record_membership_transaction TO authenticated, service_role;

COMMENT ON FUNCTION get_membership_pricing IS 'Get pricing details for a specific membership tier';
COMMENT ON FUNCTION get_all_membership_tiers IS 'Get all active membership tiers for comparison';
COMMENT ON FUNCTION get_player_pricing_info IS 'Get player current pricing including registration fee status';
COMMENT ON FUNCTION has_paid_registration_fee IS 'Check if player has paid the one-time registration fee';
COMMENT ON FUNCTION record_registration_fee IS 'Record successful $5 registration fee payment';
COMMENT ON FUNCTION record_membership_transaction IS 'Record membership upgrade/downgrade/renewal transaction';
-- ============================================================================
-- PLAYER BOOKING RLS POLICY
-- Allow authenticated players to create private lesson bookings
-- ============================================================================

-- Drop existing restrictive INSERT policy for events
DROP POLICY IF EXISTS "events_insert_staff" ON events.events;

-- Create new policy: Staff can create any event type
CREATE POLICY "events_insert_staff" ON events.events
    FOR INSERT
    WITH CHECK (
        events.is_staff()
        AND created_by = auth.uid()
    );

-- Create new policy: Players can create private bookings only
CREATE POLICY "events_insert_players_private_booking" ON events.events
    FOR INSERT
    WITH CHECK (
        auth.uid() IS NOT NULL
        AND event_type = 'private_booking'
        AND created_by = auth.uid()
        AND is_published = true  -- Player bookings are auto-published
    );

-- Drop existing restrictive INSERT policy for event_courts
DROP POLICY IF EXISTS "event_courts_insert_staff" ON events.event_courts;

-- Create new policy: Staff can assign any courts
CREATE POLICY "event_courts_insert_staff" ON events.event_courts
    FOR INSERT
    WITH CHECK (events.is_staff());

-- Create new policy: Players can assign courts to their own private booking events
CREATE POLICY "event_courts_insert_players" ON events.event_courts
    FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM events.events e
            WHERE e.id = event_courts.event_id
            AND e.created_by = auth.uid()
            AND e.event_type = 'private_booking'
        )
    );

COMMENT ON POLICY "events_insert_players_private_booking" ON events.events IS
    'Allow authenticated players to create private court bookings';

COMMENT ON POLICY "event_courts_insert_players" ON events.event_courts IS
    'Allow players to assign courts to their own private court bookings';
-- ============================================================================
-- PLAYERS API VIEW
-- Create public view for players table to enable PostgREST access
-- ============================================================================

-- Create players view in public schema for PostgREST API access
CREATE OR REPLACE VIEW public.players AS
SELECT
    p.id,
    p.account_id,
    p.first_name,
    p.last_name,
    ua.email,
    p.phone,
    p.membership_level,
    p.skill_level,
    p.dupr_rating,
    p.stripe_customer_id,
    p.date_of_birth,
    ua.is_verified,
    ua.is_active,
    p.display_name,
    p.street_address,
    p.city,
    p.state,
    p.membership_started_on,
    p.membership_expires_on,
    p.dupr_rating_updated_at,
    p.club_id,
    p.profile,
    p.created_at,
    p.updated_at
FROM app_auth.players p
JOIN app_auth.user_accounts ua ON p.account_id = ua.id;

COMMENT ON VIEW public.players IS 'Players API view for PostgREST access';

-- Grant permissions
GRANT SELECT ON public.players TO authenticated;
GRANT SELECT ON public.players TO anon;

-- Staff can see all fields
GRANT ALL ON public.players TO service_role;
-- ============================================================================
-- FIX EVENTS SELECT POLICY
-- Allow authenticated users to see all published events
-- ============================================================================

-- Drop the existing restrictive SELECT policy
DROP POLICY IF EXISTS "events_select_published" ON events.events;

-- Create new policy: Authenticated users can see published events and their own events
-- This avoids the admin_users permission issue
CREATE POLICY "events_select_published" ON events.events
    FOR SELECT
    USING (
        -- Anyone authenticated can see published events
        (auth.uid() IS NOT NULL AND is_published = true)
        -- Event creators can see their own events
        OR created_by = auth.uid()
    );

COMMENT ON POLICY "events_select_published" ON events.events IS
    'Allow viewing of published events by all authenticated users, and own events by creators';
-- ============================================================================
-- FIX EVENT COURTS SELECT POLICY
-- Allow authenticated users to see courts for published events
-- ============================================================================

-- Drop the existing restrictive SELECT policy
DROP POLICY IF EXISTS "event_courts_select" ON events.event_courts;

-- Create new policy: All authenticated users can see event_courts
-- This is a junction table, security is enforced on the events table
CREATE POLICY "event_courts_select" ON events.event_courts
    FOR SELECT
    USING (auth.uid() IS NOT NULL);

COMMENT ON POLICY "event_courts_select" ON events.event_courts IS
    'Allow all authenticated users to view event court assignments - security is enforced on events table';
-- ============================================================================
-- COMPREHENSIVE EVENTS PERMISSIONS FIX
-- Fix all permission issues for admin dashboard event display
-- ============================================================================

-- ============================================================================
-- STEP 1: EXPLICIT TABLE GRANTS
-- Ensure authenticated users can SELECT from all necessary tables
-- ============================================================================

-- Grant SELECT on core tables (explicit, not relying on ALL TABLES)
GRANT SELECT ON events.events TO authenticated;
GRANT SELECT ON events.event_courts TO authenticated;
GRANT SELECT ON events.courts TO authenticated;
GRANT SELECT ON events.event_registrations TO authenticated;
GRANT SELECT ON events.event_templates TO authenticated;

-- CRITICAL: Grant SELECT on admin_users for foreign key validation
-- The events.created_by column references admin_users(id)
-- PostgreSQL RLS requires read access to validate foreign keys
GRANT SELECT ON app_auth.admin_users TO authenticated;

-- Grant SELECT to anon for public data
GRANT SELECT ON events.events TO anon;
GRANT SELECT ON events.courts TO anon;

-- Grant INSERT for player bookings
GRANT INSERT ON events.events TO authenticated;
GRANT INSERT ON events.event_courts TO authenticated;
GRANT INSERT ON events.event_registrations TO authenticated;

-- ============================================================================
-- STEP 2: SIMPLIFIED RLS POLICIES
-- Remove complex policies that cause circular permission checks
-- ============================================================================

-- -----------------------------------------------
-- EVENTS TABLE POLICIES
-- -----------------------------------------------

-- Drop all existing SELECT policies
DROP POLICY IF EXISTS "events_select_published" ON events.events;
DROP POLICY IF EXISTS "events_select_all_authenticated" ON events.events;
DROP POLICY IF EXISTS "events_select_anon" ON events.events;

-- Simple SELECT policy: authenticated users see published events + own events
CREATE POLICY "events_select_all_authenticated" ON events.events
    FOR SELECT
    TO authenticated
    USING (
        is_published = true OR created_by = auth.uid()
    );

-- Anon users can only see published events
CREATE POLICY "events_select_anon" ON events.events
    FOR SELECT
    TO anon
    USING (is_published = true);

-- -----------------------------------------------
-- EVENT_COURTS TABLE POLICIES
-- -----------------------------------------------

-- Drop all existing SELECT policies
DROP POLICY IF EXISTS "event_courts_select" ON events.event_courts;
DROP POLICY IF EXISTS "event_courts_select_all_authenticated" ON events.event_courts;
DROP POLICY IF EXISTS "event_courts_select_anon" ON events.event_courts;

-- Simple SELECT policy: all authenticated users can see event_courts
-- Security is enforced at the events table level
CREATE POLICY "event_courts_select_all_authenticated" ON events.event_courts
    FOR SELECT
    TO authenticated
    USING (true);

-- Anon can see event_courts for public events
CREATE POLICY "event_courts_select_anon" ON events.event_courts
    FOR SELECT
    TO anon
    USING (true);

-- -----------------------------------------------
-- COURTS TABLE POLICIES
-- -----------------------------------------------

-- Drop all existing SELECT policies on courts
DROP POLICY IF EXISTS "courts_select_all" ON events.courts;

-- Ensure courts are visible to everyone
CREATE POLICY "courts_select_all" ON events.courts
    FOR SELECT
    USING (true);

-- -----------------------------------------------
-- ADMIN_USERS TABLE POLICY (for FK validation)
-- -----------------------------------------------

-- Ensure RLS is enabled on admin_users (idempotent)
DO $$
BEGIN
    ALTER TABLE app_auth.admin_users ENABLE ROW LEVEL SECURITY;
EXCEPTION
    WHEN OTHERS THEN NULL;
END $$;

-- Drop all existing SELECT policies on admin_users
DROP POLICY IF EXISTS "admin_users_select_for_fk" ON app_auth.admin_users;

-- Allow authenticated users to see admin_users for foreign key validation
-- This is needed because events.created_by references admin_users(id)
CREATE POLICY "admin_users_select_for_fk" ON app_auth.admin_users
    FOR SELECT
    TO authenticated
    USING (true);

-- ============================================================================
-- STEP 3: COMMENTS
-- ============================================================================

COMMENT ON POLICY "events_select_all_authenticated" ON events.events IS
    'Authenticated users can see published events and their own events';

COMMENT ON POLICY "event_courts_select_all_authenticated" ON events.event_courts IS
    'All authenticated users can see event-court assignments - security enforced at events table level';

COMMENT ON POLICY "courts_select_all" ON events.courts IS
    'All users can see court information';

COMMENT ON POLICY "admin_users_select_for_fk" ON app_auth.admin_users IS
    'Allow authenticated users to read admin_users for foreign key validation on events.created_by';

-- ============================================================================
-- VERIFICATION
-- ============================================================================

-- To verify, run as authenticated user:
-- SELECT * FROM events.events WHERE is_published = true LIMIT 1;
-- SELECT * FROM events.event_courts LIMIT 1;
-- SELECT * FROM events.courts LIMIT 1;
-- ============================================================================
-- OPEN PLAY SCHEDULE MODULE
-- Recurring weekly open play schedule with court allocations by skill level
-- ============================================================================

-- ============================================================================
-- ENUMS AND TYPES
-- ============================================================================

CREATE TYPE events.open_play_session_type AS ENUM (
    'divided_by_skill',  -- Courts split among skill levels (peak hours)
    'mixed_levels',      -- All skill levels can play together
    'dedicated_skill',   -- All courts for one skill level
    'special_event'      -- Named events (Ladies Night, Clinics, etc.)
);

COMMENT ON TYPE events.open_play_session_type IS 'Types of open play sessions';

-- ============================================================================
-- OPEN PLAY SCHEDULE BLOCKS TABLE
-- Defines recurring weekly schedule blocks
-- ============================================================================

CREATE TABLE events.open_play_schedule_blocks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(200) NOT NULL,
    description TEXT,

    -- Timing
    day_of_week INTEGER NOT NULL CHECK (day_of_week >= 0 AND day_of_week <= 6), -- 0=Sunday, 6=Saturday (single day per block)
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,

    -- Session configuration
    session_type events.open_play_session_type NOT NULL,
    special_event_name VARCHAR(200), -- For special events (Ladies Night, Sunset Social, etc.)

    -- For dedicated_skill sessions, specify which skill level gets all courts
    dedicated_skill_min NUMERIC(3, 2),
    dedicated_skill_max NUMERIC(3, 2),
    dedicated_skill_label VARCHAR(100), -- Beginner, Intermediate, Advanced

    -- Pricing
    price_member DECIMAL(10, 2) DEFAULT 15.00,
    price_guest DECIMAL(10, 2) DEFAULT 20.00,

    -- Session details
    max_capacity INTEGER DEFAULT 20, -- Total players across all courts (deprecated - use calculated capacity)
    max_players_per_court INTEGER DEFAULT 8, -- Max players per court (4 playing + 4 waiting)
    check_in_instructions TEXT,
    special_instructions TEXT,

    -- Status
    is_active BOOLEAN DEFAULT true,
    effective_from DATE DEFAULT CURRENT_DATE,
    effective_until DATE,

    -- Metadata
    created_by UUID REFERENCES app_auth.admin_users(id),
    updated_by UUID REFERENCES app_auth.admin_users(id),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
    CONSTRAINT valid_time_range CHECK (end_time > start_time),
    CONSTRAINT dedicated_skill_required CHECK (
        (session_type = 'dedicated_skill' AND dedicated_skill_min IS NOT NULL AND dedicated_skill_label IS NOT NULL)
        OR session_type != 'dedicated_skill'
    ),
    CONSTRAINT special_event_name_required CHECK (
        (session_type = 'special_event' AND special_event_name IS NOT NULL)
        OR session_type != 'special_event'
    ),
    CONSTRAINT valid_effective_dates CHECK (
        effective_until IS NULL OR effective_until >= effective_from
    )
);

COMMENT ON TABLE events.open_play_schedule_blocks IS 'Recurring weekly open play schedule blocks';

-- Create indexes
CREATE INDEX idx_schedule_blocks_day ON events.open_play_schedule_blocks(day_of_week);
CREATE INDEX idx_schedule_blocks_time ON events.open_play_schedule_blocks(start_time, end_time);
CREATE INDEX idx_schedule_blocks_active ON events.open_play_schedule_blocks(is_active);
CREATE INDEX idx_schedule_blocks_session_type ON events.open_play_schedule_blocks(session_type);
CREATE INDEX idx_schedule_blocks_effective ON events.open_play_schedule_blocks(effective_from, effective_until);

-- ============================================================================
-- OPEN PLAY COURT ALLOCATIONS TABLE
-- Defines which courts are assigned to which skill levels during each block
-- ============================================================================

CREATE TABLE events.open_play_court_allocations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    schedule_block_id UUID NOT NULL REFERENCES events.open_play_schedule_blocks(id) ON DELETE CASCADE,
    court_id UUID NOT NULL REFERENCES events.courts(id) ON DELETE CASCADE,

    -- Skill level for this court during this block
    skill_level_min NUMERIC(3, 2) NOT NULL,
    skill_level_max NUMERIC(3, 2),
    skill_level_label VARCHAR(100) NOT NULL, -- Beginner, Intermediate, Advanced, Mixed

    -- For mixed sessions, this might be NULL or open to all
    is_mixed_level BOOLEAN DEFAULT false, -- True if this court allows all skill levels

    -- Display order
    sort_order INTEGER DEFAULT 0,

    -- Notes
    notes TEXT,

    -- Metadata
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
    CONSTRAINT valid_skill_range CHECK (
        skill_level_max IS NULL
        OR skill_level_max >= skill_level_min
    ),
    CONSTRAINT unique_block_court UNIQUE(schedule_block_id, court_id)
);

COMMENT ON TABLE events.open_play_court_allocations IS 'Court assignments for each schedule block';

-- Create indexes
CREATE INDEX idx_allocations_block ON events.open_play_court_allocations(schedule_block_id);
CREATE INDEX idx_allocations_court ON events.open_play_court_allocations(court_id);
CREATE INDEX idx_allocations_skill_range ON events.open_play_court_allocations(skill_level_min, skill_level_max);

-- ============================================================================
-- OPEN PLAY SCHEDULE OVERRIDES TABLE
-- One-off changes to the regular schedule (holidays, special events, etc.)
-- ============================================================================

CREATE TABLE events.open_play_schedule_overrides (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    schedule_block_id UUID REFERENCES events.open_play_schedule_blocks(id) ON DELETE CASCADE,

    -- Override details
    override_date DATE NOT NULL,
    is_cancelled BOOLEAN DEFAULT false,

    -- If not cancelled, provide replacement details
    replacement_name VARCHAR(200),
    replacement_start_time TIME,
    replacement_end_time TIME,
    replacement_session_type events.open_play_session_type,

    -- Reason and notes
    reason TEXT NOT NULL,
    special_instructions TEXT,

    -- Metadata
    created_by UUID REFERENCES app_auth.admin_users(id),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
    CONSTRAINT valid_replacement_time CHECK (
        is_cancelled = true
        OR (replacement_start_time IS NOT NULL AND replacement_end_time IS NOT NULL)
    ),
    CONSTRAINT unique_block_override_date UNIQUE(schedule_block_id, override_date)
);

COMMENT ON TABLE events.open_play_schedule_overrides IS 'One-off changes to regular schedule';

-- Create indexes
CREATE INDEX idx_overrides_block ON events.open_play_schedule_overrides(schedule_block_id);
CREATE INDEX idx_overrides_date ON events.open_play_schedule_overrides(override_date);
CREATE INDEX idx_overrides_cancelled ON events.open_play_schedule_overrides(is_cancelled);

-- ============================================================================
-- OPEN PLAY GENERATED INSTANCES TABLE
-- Generated instances for conflict detection with player bookings
-- This table will be populated by a function that generates instances
-- ============================================================================

CREATE TABLE events.open_play_instances (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    schedule_block_id UUID NOT NULL REFERENCES events.open_play_schedule_blocks(id) ON DELETE CASCADE,

    -- Instance details
    instance_date DATE NOT NULL,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,

    -- Override tracking
    override_id UUID REFERENCES events.open_play_schedule_overrides(id) ON DELETE CASCADE,
    is_cancelled BOOLEAN DEFAULT false,

    -- Metadata
    generated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
    CONSTRAINT valid_instance_time CHECK (end_time > start_time),
    CONSTRAINT unique_block_instance_date UNIQUE(schedule_block_id, instance_date)
);

COMMENT ON TABLE events.open_play_instances IS 'Generated open play instances for booking conflict detection';

-- Create indexes for performance
CREATE INDEX idx_instances_block ON events.open_play_instances(schedule_block_id);
CREATE INDEX idx_instances_date ON events.open_play_instances(instance_date);
CREATE INDEX idx_instances_time_range ON events.open_play_instances(start_time, end_time);
CREATE INDEX idx_instances_cancelled ON events.open_play_instances(is_cancelled);

-- Composite index for conflict detection queries
CREATE INDEX idx_instances_conflict_detection ON events.open_play_instances(instance_date, start_time, end_time)
    WHERE is_cancelled = false;

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Update timestamp trigger for schedule blocks
CREATE TRIGGER update_schedule_blocks_updated_at
    BEFORE UPDATE ON events.open_play_schedule_blocks
    FOR EACH ROW EXECUTE FUNCTION events.update_updated_at();

-- Update timestamp trigger for court allocations
CREATE TRIGGER update_court_allocations_updated_at
    BEFORE UPDATE ON events.open_play_court_allocations
    FOR EACH ROW EXECUTE FUNCTION events.update_updated_at();

-- Update timestamp trigger for overrides
CREATE TRIGGER update_overrides_updated_at
    BEFORE UPDATE ON events.open_play_schedule_overrides
    FOR EACH ROW EXECUTE FUNCTION events.update_updated_at();

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Function to check if a time overlaps with open play
CREATE OR REPLACE FUNCTION events.check_open_play_conflict(
    p_start_time TIMESTAMPTZ,
    p_end_time TIMESTAMPTZ,
    p_court_ids UUID[] DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_has_conflict BOOLEAN;
BEGIN
    -- Check if the requested time overlaps with any open play instances
    SELECT EXISTS (
        SELECT 1
        FROM events.open_play_instances opi
        WHERE opi.is_cancelled = false
        AND (opi.start_time, opi.end_time) OVERLAPS (p_start_time, p_end_time)
        AND (
            p_court_ids IS NULL
            OR EXISTS (
                SELECT 1
                FROM events.open_play_court_allocations opca
                WHERE opca.schedule_block_id = opi.schedule_block_id
                AND opca.court_id = ANY(p_court_ids)
            )
        )
    ) INTO v_has_conflict;

    RETURN v_has_conflict;
END;
$$;

COMMENT ON FUNCTION events.check_open_play_conflict IS 'Check if a booking time conflicts with open play schedule';

-- Function to get schedule block for a specific day/time
CREATE OR REPLACE FUNCTION events.get_schedule_block_at_time(
    p_day_of_week INTEGER,
    p_time TIME
)
RETURNS SETOF events.open_play_schedule_blocks
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN QUERY
    SELECT *
    FROM events.open_play_schedule_blocks
    WHERE day_of_week = p_day_of_week
    AND start_time <= p_time
    AND end_time > p_time
    AND is_active = true
    AND (effective_from IS NULL OR effective_from <= CURRENT_DATE)
    AND (effective_until IS NULL OR effective_until >= CURRENT_DATE);
END;
$$;

COMMENT ON FUNCTION events.get_schedule_block_at_time IS 'Get active schedule block for a specific day and time';

-- Function to calculate max capacity for a skill level in a schedule block
CREATE OR REPLACE FUNCTION events.calculate_skill_level_capacity(
    p_schedule_block_id UUID,
    p_skill_level_label VARCHAR
)
RETURNS INTEGER
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_court_count INTEGER;
    v_max_players_per_court INTEGER;
    v_calculated_capacity INTEGER;
BEGIN
    -- Get max players per court from schedule block
    SELECT max_players_per_court INTO v_max_players_per_court
    FROM events.open_play_schedule_blocks
    WHERE id = p_schedule_block_id;

    -- Count courts allocated to this skill level
    SELECT COUNT(*) INTO v_court_count
    FROM events.open_play_court_allocations
    WHERE schedule_block_id = p_schedule_block_id
    AND skill_level_label = p_skill_level_label;

    -- Calculate capacity: courts × max_players_per_court
    v_calculated_capacity := v_court_count * COALESCE(v_max_players_per_court, 8);

    RETURN v_calculated_capacity;
END;
$$;

COMMENT ON FUNCTION events.calculate_skill_level_capacity IS 'Calculate max capacity for a skill level based on court allocations';

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

-- Grant SELECT to authenticated users (to view schedule)
GRANT SELECT ON events.open_play_schedule_blocks TO authenticated;
GRANT SELECT ON events.open_play_court_allocations TO authenticated;
GRANT SELECT ON events.open_play_instances TO authenticated;

-- Grant SELECT to anonymous users (for public schedule view)
GRANT SELECT ON events.open_play_schedule_blocks TO anon;
GRANT SELECT ON events.open_play_court_allocations TO anon;
GRANT SELECT ON events.open_play_instances TO anon;
-- ============================================================================
-- OPEN PLAY SCHEDULE API FUNCTIONS
-- API functions for managing open play schedule
-- ============================================================================

-- ============================================================================
-- CREATE SCHEDULE BLOCK WITH COURT ALLOCATIONS
-- Creates a recurring schedule block and assigns courts in one transaction
-- ============================================================================

CREATE OR REPLACE FUNCTION api.create_schedule_block(
    p_name VARCHAR,
    p_day_of_week INTEGER,
    p_start_time TIME,
    p_end_time TIME,
    p_session_type events.open_play_session_type,
    p_court_allocations JSONB, -- Array of {court_id, skill_min, skill_max, skill_label}
    p_description TEXT DEFAULT NULL,
    p_special_event_name VARCHAR DEFAULT NULL,
    p_dedicated_skill_min NUMERIC DEFAULT NULL,
    p_dedicated_skill_max NUMERIC DEFAULT NULL,
    p_dedicated_skill_label VARCHAR DEFAULT NULL,
    p_price_member DECIMAL DEFAULT 15.00,
    p_price_guest DECIMAL DEFAULT 20.00,
    p_max_capacity INTEGER DEFAULT 20,
    p_special_instructions TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_block_id UUID;
    v_allocation JSONB;
    v_result JSON;
BEGIN
    -- Check if user is staff
    IF NOT events.is_staff() THEN
        RAISE EXCEPTION 'Unauthorized: Only staff can create schedule blocks';
    END IF;

    -- Validate day of week
    IF p_day_of_week < 0 OR p_day_of_week > 6 THEN
        RAISE EXCEPTION 'Invalid day of week: must be 0-6';
    END IF;

    -- Create the schedule block
    INSERT INTO events.open_play_schedule_blocks (
        name,
        description,
        day_of_week,
        start_time,
        end_time,
        session_type,
        special_event_name,
        dedicated_skill_min,
        dedicated_skill_max,
        dedicated_skill_label,
        price_member,
        price_guest,
        max_capacity,
        special_instructions,
        created_by
    ) VALUES (
        p_name,
        p_description,
        p_day_of_week,
        p_start_time,
        p_end_time,
        p_session_type,
        p_special_event_name,
        p_dedicated_skill_min,
        p_dedicated_skill_max,
        p_dedicated_skill_label,
        p_price_member,
        p_price_guest,
        p_max_capacity,
        p_special_instructions,
        auth.uid()
    ) RETURNING id INTO v_block_id;

    -- Insert court allocations
    IF p_court_allocations IS NOT NULL AND jsonb_array_length(p_court_allocations) > 0 THEN
        FOR v_allocation IN SELECT * FROM jsonb_array_elements(p_court_allocations)
        LOOP
            INSERT INTO events.open_play_court_allocations (
                schedule_block_id,
                court_id,
                skill_level_min,
                skill_level_max,
                skill_level_label,
                is_mixed_level,
                sort_order
            ) VALUES (
                v_block_id,
                (v_allocation->>'court_id')::UUID,
                (v_allocation->>'skill_level_min')::NUMERIC,
                (v_allocation->>'skill_level_max')::NUMERIC,
                v_allocation->>'skill_level_label',
                COALESCE((v_allocation->>'is_mixed_level')::BOOLEAN, false),
                COALESCE((v_allocation->>'sort_order')::INTEGER, 0)
            );
        END LOOP;
    END IF;

    -- Return the created block with allocations
    SELECT json_build_object(
        'block_id', v_block_id,
        'name', p_name,
        'day_of_week', p_day_of_week,
        'start_time', p_start_time,
        'end_time', p_end_time,
        'session_type', p_session_type,
        'court_allocations', (
            SELECT json_agg(
                json_build_object(
                    'court_id', opca.court_id,
                    'court_number', c.court_number,
                    'court_name', c.name,
                    'skill_level_min', opca.skill_level_min,
                    'skill_level_max', opca.skill_level_max,
                    'skill_level_label', opca.skill_level_label
                ) ORDER BY opca.sort_order, c.court_number
            )
            FROM events.open_play_court_allocations opca
            JOIN events.courts c ON opca.court_id = c.id
            WHERE opca.schedule_block_id = v_block_id
        )
    ) INTO v_result;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION api.create_schedule_block IS 'Creates a recurring schedule block with court allocations';

-- ============================================================================
-- CREATE SCHEDULE BLOCKS WITH DATE RANGE (MULTIPLE DAYS)
-- Creates multiple schedule blocks for selected days within a date range
-- and automatically generates instances
-- ============================================================================

CREATE OR REPLACE FUNCTION api.create_schedule_blocks_multi_day(
    p_name VARCHAR,
    p_days_of_week INTEGER[], -- Array of days: [1, 3, 5] for Mon, Wed, Fri
    p_start_time TIME,
    p_end_time TIME,
    p_session_type events.open_play_session_type,
    p_court_allocations JSONB, -- Array of {court_id, skill_min, skill_max, skill_label}
    p_effective_from DATE DEFAULT CURRENT_DATE,
    p_effective_until DATE DEFAULT NULL, -- Required to prevent infinite schedules
    p_description TEXT DEFAULT NULL,
    p_special_event_name VARCHAR DEFAULT NULL,
    p_dedicated_skill_min NUMERIC DEFAULT NULL,
    p_dedicated_skill_max NUMERIC DEFAULT NULL,
    p_dedicated_skill_label VARCHAR DEFAULT NULL,
    p_price_member DECIMAL DEFAULT 15.00,
    p_price_guest DECIMAL DEFAULT 20.00,
    p_max_capacity INTEGER DEFAULT 20,
    p_special_instructions TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_day INTEGER;
    v_block_id UUID;
    v_allocation JSONB;
    v_created_blocks UUID[] := ARRAY[]::UUID[];
    v_instances_created INTEGER := 0;
    v_day_name TEXT;
    v_result JSON;
BEGIN
    -- Check if user is staff
    IF NOT events.is_staff() THEN
        RAISE EXCEPTION 'Unauthorized: Only staff can create schedule blocks';
    END IF;

    -- Validate inputs
    IF p_days_of_week IS NULL OR array_length(p_days_of_week, 1) = 0 THEN
        RAISE EXCEPTION 'At least one day of week must be selected';
    END IF;

    IF p_effective_until IS NULL THEN
        RAISE EXCEPTION 'End date (effective_until) is required to prevent infinite schedules';
    END IF;

    IF p_effective_until < p_effective_from THEN
        RAISE EXCEPTION 'End date must be after start date';
    END IF;

    -- Loop through each selected day and create a schedule block
    FOREACH v_day IN ARRAY p_days_of_week
    LOOP
        -- Validate day of week
        IF v_day < 0 OR v_day > 6 THEN
            RAISE EXCEPTION 'Invalid day of week: %. Must be 0-6', v_day;
        END IF;

        -- Get day name for the block name
        v_day_name := CASE v_day
            WHEN 0 THEN 'Sunday'
            WHEN 1 THEN 'Monday'
            WHEN 2 THEN 'Tuesday'
            WHEN 3 THEN 'Wednesday'
            WHEN 4 THEN 'Thursday'
            WHEN 5 THEN 'Friday'
            WHEN 6 THEN 'Saturday'
        END;

        -- Create the schedule block for this day
        INSERT INTO events.open_play_schedule_blocks (
            name,
            description,
            day_of_week,
            start_time,
            end_time,
            session_type,
            special_event_name,
            dedicated_skill_min,
            dedicated_skill_max,
            dedicated_skill_label,
            price_member,
            price_guest,
            max_capacity,
            special_instructions,
            effective_from,
            effective_until,
            created_by
        ) VALUES (
            p_name,
            p_description,
            v_day,
            p_start_time,
            p_end_time,
            p_session_type,
            p_special_event_name,
            p_dedicated_skill_min,
            p_dedicated_skill_max,
            p_dedicated_skill_label,
            p_price_member,
            p_price_guest,
            p_max_capacity,
            p_special_instructions,
            p_effective_from,
            p_effective_until,
            auth.uid()
        ) RETURNING id INTO v_block_id;

        -- Add to created blocks array
        v_created_blocks := array_append(v_created_blocks, v_block_id);

        -- Insert court allocations for this block
        IF p_court_allocations IS NOT NULL AND jsonb_array_length(p_court_allocations) > 0 THEN
            FOR v_allocation IN SELECT * FROM jsonb_array_elements(p_court_allocations)
            LOOP
                INSERT INTO events.open_play_court_allocations (
                    schedule_block_id,
                    court_id,
                    skill_level_min,
                    skill_level_max,
                    skill_level_label,
                    is_mixed_level,
                    sort_order
                ) VALUES (
                    v_block_id,
                    (v_allocation->>'court_id')::UUID,
                    (v_allocation->>'skill_level_min')::NUMERIC,
                    (v_allocation->>'skill_level_max')::NUMERIC,
                    v_allocation->>'skill_level_label',
                    COALESCE((v_allocation->>'is_mixed_level')::BOOLEAN, false),
                    COALESCE((v_allocation->>'sort_order')::INTEGER, 0)
                );
            END LOOP;
        END IF;
    END LOOP;

    -- Generate instances for all created blocks within the date range
    DECLARE
        v_current_date DATE;
        v_day_of_week INTEGER;
        v_block RECORD;
    BEGIN
        v_current_date := p_effective_from;

        WHILE v_current_date <= p_effective_until LOOP
            v_day_of_week := EXTRACT(DOW FROM v_current_date)::INTEGER;

            -- Check if this day has a schedule block we just created
            IF v_day_of_week = ANY(p_days_of_week) THEN
                -- Find the block for this day
                FOR v_block IN
                    SELECT *
                    FROM events.open_play_schedule_blocks
                    WHERE id = ANY(v_created_blocks)
                    AND day_of_week = v_day_of_week
                LOOP
                    -- Create instance for this date
                    INSERT INTO events.open_play_instances (
                        schedule_block_id,
                        instance_date,
                        start_time,
                        end_time,
                        is_cancelled
                    ) VALUES (
                        v_block.id,
                        v_current_date,
                        timezone('America/Chicago', (v_current_date + v_block.start_time)::timestamp),
                        timezone('America/Chicago', (v_current_date + v_block.end_time)::timestamp),
                        false
                    )
                    ON CONFLICT (schedule_block_id, instance_date) DO NOTHING;

                    v_instances_created := v_instances_created + 1;
                END LOOP;
            END IF;

            v_current_date := v_current_date + INTERVAL '1 day';
        END LOOP;
    END;

    -- Return the results
    SELECT json_build_object(
        'success', true,
        'blocks_created', array_length(v_created_blocks, 1),
        'instances_created', v_instances_created,
        'effective_from', p_effective_from,
        'effective_until', p_effective_until,
        'days_of_week', p_days_of_week,
        'blocks', (
            SELECT json_agg(
                json_build_object(
                    'block_id', opsb.id,
                    'name', opsb.name,
                    'day_of_week', opsb.day_of_week,
                    'day_name', CASE opsb.day_of_week
                        WHEN 0 THEN 'Sunday'
                        WHEN 1 THEN 'Monday'
                        WHEN 2 THEN 'Tuesday'
                        WHEN 3 THEN 'Wednesday'
                        WHEN 4 THEN 'Thursday'
                        WHEN 5 THEN 'Friday'
                        WHEN 6 THEN 'Saturday'
                    END,
                    'start_time', opsb.start_time,
                    'end_time', opsb.end_time,
                    'court_allocations', (
                        SELECT json_agg(
                            json_build_object(
                                'court_id', opca.court_id,
                                'court_number', c.court_number,
                                'court_name', c.name,
                                'skill_level_label', opca.skill_level_label
                            ) ORDER BY opca.sort_order, c.court_number
                        )
                        FROM events.open_play_court_allocations opca
                        JOIN events.courts c ON opca.court_id = c.id
                        WHERE opca.schedule_block_id = opsb.id
                    )
                ) ORDER BY opsb.day_of_week
            )
            FROM events.open_play_schedule_blocks opsb
            WHERE opsb.id = ANY(v_created_blocks)
        )
    ) INTO v_result;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION api.create_schedule_blocks_multi_day IS 'Creates multiple schedule blocks for selected days within a date range';

-- ============================================================================
-- UPDATE SCHEDULE BLOCK
-- Updates an existing schedule block
-- ============================================================================

CREATE OR REPLACE FUNCTION api.update_schedule_block(
    p_block_id UUID,
    p_updates JSONB
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSON;
BEGIN
    -- Check if user is staff
    IF NOT events.is_staff() THEN
        RAISE EXCEPTION 'Unauthorized: Only staff can update schedule blocks';
    END IF;

    -- Update the schedule block
    UPDATE events.open_play_schedule_blocks
    SET
        name = COALESCE((p_updates->>'name'), name),
        description = COALESCE((p_updates->>'description'), description),
        start_time = COALESCE((p_updates->>'start_time')::TIME, start_time),
        end_time = COALESCE((p_updates->>'end_time')::TIME, end_time),
        session_type = COALESCE((p_updates->>'session_type')::events.open_play_session_type, session_type),
        special_event_name = COALESCE((p_updates->>'special_event_name'), special_event_name),
        price_member = COALESCE((p_updates->>'price_member')::DECIMAL, price_member),
        price_guest = COALESCE((p_updates->>'price_guest')::DECIMAL, price_guest),
        max_capacity = COALESCE((p_updates->>'max_capacity')::INTEGER, max_capacity),
        special_instructions = COALESCE((p_updates->>'special_instructions'), special_instructions),
        is_active = COALESCE((p_updates->>'is_active')::BOOLEAN, is_active),
        updated_by = auth.uid(),
        updated_at = NOW()
    WHERE id = p_block_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Schedule block not found';
    END IF;

    -- Return updated block
    SELECT json_build_object(
        'block_id', p_block_id,
        'updated', true
    ) INTO v_result;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION api.update_schedule_block IS 'Updates a schedule block';

-- ============================================================================
-- DELETE SCHEDULE BLOCK
-- Deletes a schedule block (and its allocations via CASCADE)
-- ============================================================================

CREATE OR REPLACE FUNCTION api.delete_schedule_block(
    p_block_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSON;
BEGIN
    -- Check if user is admin
    IF NOT events.is_admin_or_manager() THEN
        RAISE EXCEPTION 'Unauthorized: Only admins can delete schedule blocks';
    END IF;

    -- Delete the block (cascade will handle allocations and instances)
    DELETE FROM events.open_play_schedule_blocks
    WHERE id = p_block_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Schedule block not found';
    END IF;

    SELECT json_build_object(
        'block_id', p_block_id,
        'deleted', true
    ) INTO v_result;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION api.delete_schedule_block IS 'Deletes a schedule block';

-- ============================================================================
-- BULK DELETE SCHEDULE BLOCKS
-- Deletes multiple schedule blocks at once
-- ============================================================================

CREATE OR REPLACE FUNCTION api.bulk_delete_schedule_blocks(
    p_block_ids UUID[]
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_deleted_count INTEGER;
    v_result JSON;
BEGIN
    -- Check if user is admin
    IF NOT events.is_admin_or_manager() THEN
        RAISE EXCEPTION 'Unauthorized: Only admins can delete schedule blocks';
    END IF;

    -- Delete the blocks (cascade will handle allocations and instances)
    DELETE FROM events.open_play_schedule_blocks
    WHERE id = ANY(p_block_ids);

    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;

    SELECT json_build_object(
        'deleted_count', v_deleted_count,
        'block_ids', p_block_ids
    ) INTO v_result;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION api.bulk_delete_schedule_blocks IS 'Bulk deletes multiple schedule blocks';

-- ============================================================================
-- GET WEEKLY SCHEDULE
-- Returns the full weekly schedule with court allocations
-- ============================================================================

CREATE OR REPLACE FUNCTION api.get_weekly_schedule(
    p_include_inactive BOOLEAN DEFAULT false
)
RETURNS JSON
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_result JSON;
BEGIN
    SELECT json_build_object(
        'schedule', json_agg(
            json_build_object(
                'block_id', opsb.id,
                'name', opsb.name,
                'description', opsb.description,
                'day_of_week', opsb.day_of_week,
                'day_name', CASE opsb.day_of_week
                    WHEN 0 THEN 'Sunday'
                    WHEN 1 THEN 'Monday'
                    WHEN 2 THEN 'Tuesday'
                    WHEN 3 THEN 'Wednesday'
                    WHEN 4 THEN 'Thursday'
                    WHEN 5 THEN 'Friday'
                    WHEN 6 THEN 'Saturday'
                END,
                'start_time', opsb.start_time,
                'end_time', opsb.end_time,
                'session_type', opsb.session_type,
                'special_event_name', opsb.special_event_name,
                'dedicated_skill_min', opsb.dedicated_skill_min,
                'dedicated_skill_max', opsb.dedicated_skill_max,
                'dedicated_skill_label', opsb.dedicated_skill_label,
                'price_member', opsb.price_member,
                'price_guest', opsb.price_guest,
                'max_capacity', opsb.max_capacity,
                'is_active', opsb.is_active,
                'court_allocations', (
                    SELECT json_agg(
                        json_build_object(
                            'court_id', opca.court_id,
                            'court_number', c.court_number,
                            'court_name', c.name,
                            'skill_level_min', opca.skill_level_min,
                            'skill_level_max', opca.skill_level_max,
                            'skill_level_label', opca.skill_level_label,
                            'is_mixed_level', opca.is_mixed_level
                        ) ORDER BY opca.sort_order, c.court_number
                    )
                    FROM events.open_play_court_allocations opca
                    JOIN events.courts c ON opca.court_id = c.id
                    WHERE opca.schedule_block_id = opsb.id
                )
            ) ORDER BY opsb.day_of_week, opsb.start_time
        )
    ) INTO v_result
    FROM events.open_play_schedule_blocks opsb
    WHERE (p_include_inactive OR opsb.is_active = true);

    RETURN COALESCE(v_result, json_build_object('schedule', '[]'::json));
END;
$$;

COMMENT ON FUNCTION api.get_weekly_schedule IS 'Returns the full weekly open play schedule';

-- ============================================================================
-- CREATE SCHEDULE OVERRIDE
-- Creates a one-off override for a specific date
-- ============================================================================

CREATE OR REPLACE FUNCTION api.create_schedule_override(
    p_block_id UUID,
    p_override_date DATE,
    p_is_cancelled BOOLEAN,
    p_reason TEXT,
    p_replacement_details JSONB DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_override_id UUID;
    v_result JSON;
BEGIN
    -- Check if user is staff
    IF NOT events.is_staff() THEN
        RAISE EXCEPTION 'Unauthorized: Only staff can create schedule overrides';
    END IF;

    -- Create the override
    INSERT INTO events.open_play_schedule_overrides (
        schedule_block_id,
        override_date,
        is_cancelled,
        replacement_name,
        replacement_start_time,
        replacement_end_time,
        replacement_session_type,
        reason,
        special_instructions,
        created_by
    ) VALUES (
        p_block_id,
        p_override_date,
        p_is_cancelled,
        p_replacement_details->>'name',
        (p_replacement_details->>'start_time')::TIME,
        (p_replacement_details->>'end_time')::TIME,
        (p_replacement_details->>'session_type')::events.open_play_session_type,
        p_reason,
        p_replacement_details->>'special_instructions',
        auth.uid()
    ) RETURNING id INTO v_override_id;

    -- Mark any existing instance as cancelled or update it
    UPDATE events.open_play_instances
    SET
        is_cancelled = p_is_cancelled,
        override_id = v_override_id
    WHERE schedule_block_id = p_block_id
    AND instance_date = p_override_date;

    SELECT json_build_object(
        'override_id', v_override_id,
        'block_id', p_block_id,
        'override_date', p_override_date,
        'is_cancelled', p_is_cancelled
    ) INTO v_result;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION api.create_schedule_override IS 'Creates a schedule override for a specific date';

-- ============================================================================
-- GENERATE OPEN PLAY INSTANCES
-- Generates open play instances for a date range
-- ============================================================================

CREATE OR REPLACE FUNCTION api.generate_open_play_instances(
    p_start_date DATE,
    p_end_date DATE
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_date DATE;
    v_day_of_week INTEGER;
    v_block RECORD;
    v_override RECORD;
    v_instances_created INTEGER := 0;
BEGIN
    -- Check if user is staff
    IF NOT events.is_staff() THEN
        RAISE EXCEPTION 'Unauthorized: Only staff can generate instances';
    END IF;

    -- Loop through each date in range
    v_current_date := p_start_date;
    WHILE v_current_date <= p_end_date LOOP
        v_day_of_week := EXTRACT(DOW FROM v_current_date)::INTEGER;

        -- Find all active schedule blocks for this day
        FOR v_block IN
            SELECT *
            FROM events.open_play_schedule_blocks
            WHERE day_of_week = v_day_of_week
            AND is_active = true
            AND (effective_from IS NULL OR effective_from <= v_current_date)
            AND (effective_until IS NULL OR effective_until >= v_current_date)
        LOOP
            -- Check if there's an override for this date
            SELECT * INTO v_override
            FROM events.open_play_schedule_overrides
            WHERE schedule_block_id = v_block.id
            AND override_date = v_current_date;

            -- Insert or update instance
            INSERT INTO events.open_play_instances (
                schedule_block_id,
                instance_date,
                start_time,
                end_time,
                override_id,
                is_cancelled
            ) VALUES (
                v_block.id,
                v_current_date,
                timezone('America/Chicago', (v_current_date + v_block.start_time)::timestamp),
                timezone('America/Chicago', (v_current_date + v_block.end_time)::timestamp),
                v_override.id,
                COALESCE(v_override.is_cancelled, false)
            )
            ON CONFLICT (schedule_block_id, instance_date)
            DO UPDATE SET
                start_time = EXCLUDED.start_time,
                end_time = EXCLUDED.end_time,
                override_id = EXCLUDED.override_id,
                is_cancelled = EXCLUDED.is_cancelled,
                generated_at = NOW();

            v_instances_created := v_instances_created + 1;
        END LOOP;

        v_current_date := v_current_date + INTERVAL '1 day';
    END LOOP;

    RETURN json_build_object(
        'instances_created', v_instances_created,
        'start_date', p_start_date,
        'end_date', p_end_date
    );
END;
$$;

COMMENT ON FUNCTION api.generate_open_play_instances IS 'Generates open play instances for booking conflict detection';

-- ============================================================================
-- GET AVAILABLE BOOKING TIMES
-- Returns time slots available for player bookings (not blocked by open play)
-- ============================================================================

CREATE OR REPLACE FUNCTION api.get_available_booking_times(
    p_date DATE,
    p_court_id UUID DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_result JSON;
    v_open_time TIME := '06:00:00';
    v_close_time TIME := '22:00:00';
BEGIN
    WITH open_play_blocks AS (
        SELECT
            opi.start_time,
            opi.end_time,
            opca.court_id
        FROM events.open_play_instances opi
        JOIN events.open_play_court_allocations opca ON opca.schedule_block_id = opi.schedule_block_id
        WHERE opi.instance_date = p_date
        AND opi.is_cancelled = false
        AND (p_court_id IS NULL OR opca.court_id = p_court_id)
    ),
    time_slots AS (
        SELECT
            CASE
                WHEN prev_end IS NULL THEN p_date + v_open_time
                ELSE prev_end
            END AS slot_start,
            CASE
                WHEN next_start IS NULL THEN p_date + v_close_time
                ELSE next_start
            END AS slot_end
        FROM (
            SELECT
                start_time AS next_start,
                LAG(end_time) OVER (ORDER BY start_time) AS prev_end
            FROM open_play_blocks
            UNION ALL
            SELECT NULL AS next_start, MAX(end_time) AS prev_end
            FROM open_play_blocks
        ) slots
        WHERE (next_start IS NULL AND prev_end IS NOT NULL)
           OR (next_start > COALESCE(prev_end, p_date + v_open_time))
    )
    SELECT json_build_object(
        'date', p_date,
        'available_slots', (
            SELECT json_agg(
                json_build_object(
                    'start_time', slot_start,
                    'end_time', slot_end,
                    'duration_minutes', EXTRACT(EPOCH FROM (slot_end - slot_start)) / 60
                ) ORDER BY slot_start
            )
            FROM time_slots
            WHERE slot_end > slot_start
        )
    ) INTO v_result;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION api.get_available_booking_times IS 'Returns time slots available for player bookings';

-- ============================================================================
-- GET SCHEDULE FOR DATE
-- Returns the open play schedule for a specific date with overrides applied
-- ============================================================================

CREATE OR REPLACE FUNCTION api.get_schedule_for_date(
    p_date DATE
)
RETURNS JSON
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_result JSON;
    v_day_of_week INTEGER;
BEGIN
    v_day_of_week := EXTRACT(DOW FROM p_date)::INTEGER;

    SELECT json_build_object(
        'date', p_date,
        'day_of_week', v_day_of_week,
        'sessions', (
            SELECT json_agg(
                json_build_object(
                    'block_id', opsb.id,
                    'name', COALESCE(opso.replacement_name, opsb.name),
                    'start_time', p_date + COALESCE(opso.replacement_start_time, opsb.start_time),
                    'end_time', p_date + COALESCE(opso.replacement_end_time, opsb.end_time),
                    'session_type', COALESCE(opso.replacement_session_type, opsb.session_type),
                    'is_cancelled', COALESCE(opso.is_cancelled, false),
                    'special_event_name', opsb.special_event_name,
                    'price_member', opsb.price_member,
                    'price_guest', opsb.price_guest,
                    'court_allocations', (
                        SELECT json_agg(
                            json_build_object(
                                'court_number', c.court_number,
                                'court_name', c.name,
                                'skill_level_label', opca.skill_level_label,
                                'skill_level_min', opca.skill_level_min,
                                'skill_level_max', opca.skill_level_max
                            ) ORDER BY c.court_number
                        )
                        FROM events.open_play_court_allocations opca
                        JOIN events.courts c ON opca.court_id = c.id
                        WHERE opca.schedule_block_id = opsb.id
                    )
                ) ORDER BY COALESCE(opso.replacement_start_time, opsb.start_time)
            )
            FROM events.open_play_schedule_blocks opsb
            LEFT JOIN events.open_play_schedule_overrides opso
                ON opso.schedule_block_id = opsb.id
                AND opso.override_date = p_date
            WHERE opsb.day_of_week = v_day_of_week
            AND opsb.is_active = true
            AND (opsb.effective_from IS NULL OR opsb.effective_from <= p_date)
            AND (opsb.effective_until IS NULL OR opsb.effective_until >= p_date)
        )
    ) INTO v_result;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION api.get_schedule_for_date IS 'Returns the schedule for a specific date with overrides';

-- ============================================================================
-- GRANT EXECUTE PERMISSIONS
-- ============================================================================

GRANT EXECUTE ON FUNCTION api.create_schedule_block TO authenticated;
GRANT EXECUTE ON FUNCTION api.create_schedule_blocks_multi_day TO authenticated;
GRANT EXECUTE ON FUNCTION api.update_schedule_block TO authenticated;
GRANT EXECUTE ON FUNCTION api.delete_schedule_block TO authenticated;
GRANT EXECUTE ON FUNCTION api.bulk_delete_schedule_blocks TO authenticated;
GRANT EXECUTE ON FUNCTION api.get_weekly_schedule TO authenticated, anon;
GRANT EXECUTE ON FUNCTION api.create_schedule_override TO authenticated;
GRANT EXECUTE ON FUNCTION api.generate_open_play_instances TO authenticated;
GRANT EXECUTE ON FUNCTION api.get_available_booking_times TO authenticated, anon;
GRANT EXECUTE ON FUNCTION api.get_schedule_for_date TO authenticated, anon;
-- ============================================================================
-- OPEN PLAY SCHEDULE RLS POLICIES
-- Row Level Security policies for open play schedule system
-- ============================================================================

-- Enable RLS on all open play schedule tables
ALTER TABLE events.open_play_schedule_blocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE events.open_play_court_allocations ENABLE ROW LEVEL SECURITY;
ALTER TABLE events.open_play_schedule_overrides ENABLE ROW LEVEL SECURITY;
ALTER TABLE events.open_play_instances ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- SCHEDULE BLOCKS POLICIES
-- ============================================================================

-- Schedule Blocks: Everyone can view active blocks
CREATE POLICY "schedule_blocks_select_all" ON events.open_play_schedule_blocks
    FOR SELECT
    USING (
        is_active = true
        OR events.is_staff()
    );

-- Schedule Blocks: Staff can create
CREATE POLICY "schedule_blocks_insert_staff" ON events.open_play_schedule_blocks
    FOR INSERT
    WITH CHECK (
        events.is_staff()
        AND created_by = auth.uid()
    );

-- Schedule Blocks: Staff can update
CREATE POLICY "schedule_blocks_update_staff" ON events.open_play_schedule_blocks
    FOR UPDATE
    USING (events.is_staff())
    WITH CHECK (events.is_staff());

-- Schedule Blocks: Only admins can delete
CREATE POLICY "schedule_blocks_delete_admin" ON events.open_play_schedule_blocks
    FOR DELETE
    USING (events.is_admin_or_manager());

-- ============================================================================
-- COURT ALLOCATIONS POLICIES
-- ============================================================================

-- Court Allocations: Everyone can view
CREATE POLICY "court_allocations_select_all" ON events.open_play_court_allocations
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM events.open_play_schedule_blocks opsb
            WHERE opsb.id = open_play_court_allocations.schedule_block_id
            AND (opsb.is_active = true OR events.is_staff())
        )
    );

-- Court Allocations: Staff can create
CREATE POLICY "court_allocations_insert_staff" ON events.open_play_court_allocations
    FOR INSERT
    WITH CHECK (events.is_staff());

-- Court Allocations: Staff can update
CREATE POLICY "court_allocations_update_staff" ON events.open_play_court_allocations
    FOR UPDATE
    USING (events.is_staff())
    WITH CHECK (events.is_staff());

-- Court Allocations: Staff can delete
CREATE POLICY "court_allocations_delete_staff" ON events.open_play_court_allocations
    FOR DELETE
    USING (events.is_staff());

-- ============================================================================
-- SCHEDULE OVERRIDES POLICIES
-- ============================================================================

-- Overrides: Everyone can view (to see schedule changes)
CREATE POLICY "overrides_select_all" ON events.open_play_schedule_overrides
    FOR SELECT
    USING (true);

-- Overrides: Staff can create
CREATE POLICY "overrides_insert_staff" ON events.open_play_schedule_overrides
    FOR INSERT
    WITH CHECK (
        events.is_staff()
        AND created_by = auth.uid()
    );

-- Overrides: Staff can update
CREATE POLICY "overrides_update_staff" ON events.open_play_schedule_overrides
    FOR UPDATE
    USING (events.is_staff())
    WITH CHECK (events.is_staff());

-- Overrides: Admins can delete
CREATE POLICY "overrides_delete_admin" ON events.open_play_schedule_overrides
    FOR DELETE
    USING (events.is_admin_or_manager());

-- ============================================================================
-- OPEN PLAY INSTANCES POLICIES
-- ============================================================================

-- Instances: Everyone can view active instances
CREATE POLICY "instances_select_all" ON events.open_play_instances
    FOR SELECT
    USING (true);

-- Instances: Only system functions can insert/update (via SECURITY DEFINER functions)
-- No direct INSERT/UPDATE/DELETE policies - only through API functions

-- ============================================================================
-- GRANT ADDITIONAL PERMISSIONS
-- ============================================================================

-- Grant permissions on tables for direct querying (RLS will control actual access)
GRANT SELECT ON events.open_play_schedule_blocks TO authenticated, anon;
GRANT SELECT ON events.open_play_court_allocations TO authenticated, anon;
GRANT SELECT ON events.open_play_schedule_overrides TO authenticated, anon;
GRANT SELECT ON events.open_play_instances TO authenticated, anon;

-- Grant INSERT, UPDATE, DELETE to authenticated users (RLS policies will control who can actually perform these)
GRANT INSERT, UPDATE, DELETE ON events.open_play_schedule_blocks TO authenticated;
GRANT INSERT, UPDATE, DELETE ON events.open_play_court_allocations TO authenticated;
GRANT INSERT, UPDATE, DELETE ON events.open_play_schedule_overrides TO authenticated;

-- Staff need full access through functions (granted via SECURITY DEFINER)
GRANT ALL ON events.open_play_schedule_blocks TO service_role;
GRANT ALL ON events.open_play_court_allocations TO service_role;
GRANT ALL ON events.open_play_schedule_overrides TO service_role;
GRANT ALL ON events.open_play_instances TO service_role;

-- Grant sequence permissions for inserts
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA events TO authenticated;
-- ============================================================================
-- OPEN PLAY SCHEDULE ADMIN VIEWS
-- Convenient views for admin dashboard and schedule management
-- ============================================================================

-- ============================================================================
-- WEEKLY SCHEDULE OVERVIEW
-- Visual overview of the entire weekly schedule
-- ============================================================================

CREATE OR REPLACE VIEW events.admin_weekly_schedule_overview AS
SELECT
    opsb.id AS block_id,
    opsb.day_of_week,
    CASE opsb.day_of_week
        WHEN 0 THEN 'Sunday'
        WHEN 1 THEN 'Monday'
        WHEN 2 THEN 'Tuesday'
        WHEN 3 THEN 'Wednesday'
        WHEN 4 THEN 'Thursday'
        WHEN 5 THEN 'Friday'
        WHEN 6 THEN 'Saturday'
    END AS day_name,
    opsb.start_time,
    opsb.end_time,
    EXTRACT(EPOCH FROM (opsb.end_time - opsb.start_time)) / 3600 AS duration_hours,
    opsb.name,
    opsb.session_type,
    opsb.special_event_name,
    opsb.dedicated_skill_label,
    opsb.price_member,
    opsb.price_guest,
    opsb.max_capacity,
    opsb.is_active,
    COUNT(opca.id) AS courts_allocated,
    STRING_AGG(DISTINCT opca.skill_level_label, ', ' ORDER BY opca.skill_level_label) AS skill_levels,
    opsb.created_at,
    opsb.updated_at
FROM events.open_play_schedule_blocks opsb
LEFT JOIN events.open_play_court_allocations opca ON opca.schedule_block_id = opsb.id
GROUP BY
    opsb.id,
    opsb.day_of_week,
    opsb.start_time,
    opsb.end_time,
    opsb.name,
    opsb.session_type,
    opsb.special_event_name,
    opsb.dedicated_skill_label,
    opsb.price_member,
    opsb.price_guest,
    opsb.max_capacity,
    opsb.is_active,
    opsb.created_at,
    opsb.updated_at
ORDER BY opsb.day_of_week, opsb.start_time;

COMMENT ON VIEW events.admin_weekly_schedule_overview IS 'Weekly schedule overview for admin dashboard';

-- ============================================================================
-- COURT ALLOCATION MATRIX
-- Shows which courts are assigned to which skill levels by time block
-- ============================================================================

CREATE OR REPLACE VIEW events.admin_court_allocation_matrix AS
SELECT
    opsb.day_of_week,
    CASE opsb.day_of_week
        WHEN 0 THEN 'Sunday'
        WHEN 1 THEN 'Monday'
        WHEN 2 THEN 'Tuesday'
        WHEN 3 THEN 'Wednesday'
        WHEN 4 THEN 'Thursday'
        WHEN 5 THEN 'Friday'
        WHEN 6 THEN 'Saturday'
    END AS day_name,
    opsb.start_time,
    opsb.end_time,
    opsb.name AS block_name,
    c.court_number,
    c.name AS court_name,
    opca.skill_level_label,
    opca.skill_level_min,
    opca.skill_level_max,
    opca.is_mixed_level,
    opsb.session_type,
    opsb.is_active
FROM events.open_play_schedule_blocks opsb
JOIN events.open_play_court_allocations opca ON opca.schedule_block_id = opsb.id
JOIN events.courts c ON c.id = opca.court_id
ORDER BY
    opsb.day_of_week,
    opsb.start_time,
    c.court_number;

COMMENT ON VIEW events.admin_court_allocation_matrix IS 'Court allocation matrix for schedule planning';

-- ============================================================================
-- AVAILABLE BOOKING WINDOWS
-- Shows when player bookings are allowed (times not blocked by open play)
-- ============================================================================

CREATE OR REPLACE VIEW events.available_booking_windows AS
WITH daily_schedule AS (
    SELECT
        generate_series AS date,
        EXTRACT(DOW FROM generate_series)::INTEGER AS day_of_week
    FROM generate_series(
        CURRENT_DATE,
        CURRENT_DATE + INTERVAL '30 days',
        INTERVAL '1 day'
    )
),
open_play_times AS (
    SELECT
        ds.date,
        ds.day_of_week,
        opsb.start_time,
        opsb.end_time,
        opsb.name,
        opca.court_id,
        c.court_number
    FROM daily_schedule ds
    JOIN events.open_play_schedule_blocks opsb ON opsb.day_of_week = ds.day_of_week
    JOIN events.open_play_court_allocations opca ON opca.schedule_block_id = opsb.id
    JOIN events.courts c ON c.id = opca.court_id
    LEFT JOIN events.open_play_schedule_overrides opso
        ON opso.schedule_block_id = opsb.id
        AND opso.override_date = ds.date
    WHERE opsb.is_active = true
    AND (opso.is_cancelled IS NULL OR opso.is_cancelled = false)
)
SELECT
    date,
    day_of_week,
    court_id,
    court_number,
    COUNT(*) AS open_play_blocks,
    json_agg(
        json_build_object(
            'start', start_time,
            'end', end_time,
            'name', name
        ) ORDER BY start_time
    ) AS blocked_times
FROM open_play_times
GROUP BY date, day_of_week, court_id, court_number
ORDER BY date, court_number;

COMMENT ON VIEW events.available_booking_windows IS 'Shows available booking windows for the next 30 days';

-- ============================================================================
-- SCHEDULE CONFLICTS VIEW
-- Shows potential conflicts between player bookings and open play
-- ============================================================================

CREATE OR REPLACE VIEW events.admin_schedule_conflicts AS
SELECT
    e.id AS event_id,
    e.title AS event_title,
    e.start_time AS event_start,
    e.end_time AS event_end,
    ec.court_id,
    c.court_number,
    opi.schedule_block_id,
    opsb.name AS open_play_block_name,
    opi.start_time AS open_play_start,
    opi.end_time AS open_play_end,
    'Court conflict with open play' AS conflict_type
FROM events.events e
JOIN events.event_courts ec ON ec.event_id = e.id
JOIN events.courts c ON c.id = ec.court_id
JOIN events.open_play_instances opi ON opi.is_cancelled = false
JOIN events.open_play_court_allocations opca
    ON opca.schedule_block_id = opi.schedule_block_id
    AND opca.court_id = ec.court_id
JOIN events.open_play_schedule_blocks opsb ON opsb.id = opi.schedule_block_id
WHERE (e.start_time, e.end_time) OVERLAPS (opi.start_time, opi.end_time)
AND e.is_cancelled = false
AND e.start_time >= CURRENT_DATE
ORDER BY e.start_time, c.court_number;

COMMENT ON VIEW events.admin_schedule_conflicts IS 'Potential conflicts between player events and open play';

-- ============================================================================
-- SCHEDULE STATISTICS VIEW
-- Summary statistics for schedule management
-- ============================================================================

CREATE OR REPLACE VIEW events.schedule_statistics AS
WITH weekly_hours AS (
    SELECT
        session_type,
        SUM(EXTRACT(EPOCH FROM (end_time - start_time)) / 3600) AS hours_per_week
    FROM events.open_play_schedule_blocks
    WHERE is_active = true
    GROUP BY session_type
),
skill_level_hours AS (
    SELECT
        opca.skill_level_label,
        SUM(EXTRACT(EPOCH FROM (opsb.end_time - opsb.start_time)) / 3600) AS hours_per_week
    FROM events.open_play_schedule_blocks opsb
    JOIN events.open_play_court_allocations opca ON opca.schedule_block_id = opsb.id
    WHERE opsb.is_active = true
    GROUP BY opca.skill_level_label
)
SELECT
    'total_schedule_blocks' AS metric,
    COUNT(*)::TEXT AS value
FROM events.open_play_schedule_blocks
WHERE is_active = true
UNION ALL
SELECT
    'total_weekly_hours' AS metric,
    ROUND(SUM(hours_per_week)::NUMERIC, 2)::TEXT AS value
FROM weekly_hours
UNION ALL
SELECT
    'divided_sessions_hours' AS metric,
    ROUND(COALESCE(hours_per_week, 0)::NUMERIC, 2)::TEXT AS value
FROM weekly_hours
WHERE session_type = 'divided_by_skill'
UNION ALL
SELECT
    'dedicated_sessions_hours' AS metric,
    ROUND(COALESCE(hours_per_week, 0)::NUMERIC, 2)::TEXT AS value
FROM weekly_hours
WHERE session_type = 'dedicated_skill'
UNION ALL
SELECT
    'mixed_sessions_hours' AS metric,
    ROUND(COALESCE(hours_per_week, 0)::NUMERIC, 2)::TEXT AS value
FROM weekly_hours
WHERE session_type = 'mixed_levels'
UNION ALL
SELECT
    'special_events_hours' AS metric,
    ROUND(COALESCE(hours_per_week, 0)::NUMERIC, 2)::TEXT AS value
FROM weekly_hours
WHERE session_type = 'special_event'
UNION ALL
SELECT
    'beginner_court_hours' AS metric,
    ROUND(COALESCE(hours_per_week, 0)::NUMERIC, 2)::TEXT AS value
FROM skill_level_hours
WHERE skill_level_label = 'Beginner'
UNION ALL
SELECT
    'intermediate_court_hours' AS metric,
    ROUND(COALESCE(hours_per_week, 0)::NUMERIC, 2)::TEXT AS value
FROM skill_level_hours
WHERE skill_level_label = 'Intermediate'
UNION ALL
SELECT
    'advanced_court_hours' AS metric,
    ROUND(COALESCE(hours_per_week, 0)::NUMERIC, 2)::TEXT AS value
FROM skill_level_hours
WHERE skill_level_label = 'Advanced';

COMMENT ON VIEW events.schedule_statistics IS 'Summary statistics for open play schedule';

-- ============================================================================
-- UPCOMING OPEN PLAY VIEW
-- Shows upcoming open play sessions for the next 7 days
-- ============================================================================

CREATE OR REPLACE VIEW events.upcoming_open_play AS
SELECT
    opi.instance_date AS date,
    EXTRACT(DOW FROM opi.instance_date)::INTEGER AS day_of_week,
    CASE EXTRACT(DOW FROM opi.instance_date)::INTEGER
        WHEN 0 THEN 'Sunday'
        WHEN 1 THEN 'Monday'
        WHEN 2 THEN 'Tuesday'
        WHEN 3 THEN 'Wednesday'
        WHEN 4 THEN 'Thursday'
        WHEN 5 THEN 'Friday'
        WHEN 6 THEN 'Saturday'
    END AS day_name,
    opi.start_time,
    opi.end_time,
    opsb.name AS session_name,
    opsb.session_type,
    opsb.special_event_name,
    opsb.price_member,
    opsb.price_guest,
    opi.is_cancelled,
    COUNT(opca.id) AS courts_allocated,
    STRING_AGG(DISTINCT opca.skill_level_label, ', ' ORDER BY opca.skill_level_label) AS skill_levels
FROM events.open_play_instances opi
JOIN events.open_play_schedule_blocks opsb ON opsb.id = opi.schedule_block_id
LEFT JOIN events.open_play_court_allocations opca ON opca.schedule_block_id = opsb.id
WHERE opi.instance_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '7 days'
GROUP BY
    opi.instance_date,
    opi.start_time,
    opi.end_time,
    opsb.name,
    opsb.session_type,
    opsb.special_event_name,
    opsb.price_member,
    opsb.price_guest,
    opi.is_cancelled
ORDER BY opi.instance_date, opi.start_time;

COMMENT ON VIEW events.upcoming_open_play IS 'Upcoming open play sessions for the next 7 days';

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

-- Grant SELECT to authenticated users
GRANT SELECT ON events.admin_weekly_schedule_overview TO authenticated;
GRANT SELECT ON events.admin_court_allocation_matrix TO authenticated;
GRANT SELECT ON events.available_booking_windows TO authenticated;
GRANT SELECT ON events.admin_schedule_conflicts TO authenticated;
GRANT SELECT ON events.schedule_statistics TO authenticated;
GRANT SELECT ON events.upcoming_open_play TO authenticated, anon;

-- Grant SELECT on views to service_role
GRANT SELECT ON ALL TABLES IN SCHEMA events TO service_role;
-- ============================================================================
-- OPEN PLAY SCHEDULE SEED DATA
-- Seeds the weekly schedule based on the Dink House Complete Schedule
-- ============================================================================

-- First, ensure we have 5 courts in the system
-- Insert courts if they don't exist
INSERT INTO events.courts (court_number, name, surface_type, environment, status, location, max_capacity)
VALUES
    (1, 'Court 1', 'indoor', 'indoor', 'available', 'Main Facility', 4),
    (2, 'Court 2', 'indoor', 'indoor', 'available', 'Main Facility', 4),
    (3, 'Court 3', 'indoor', 'indoor', 'available', 'Main Facility', 4),
    (4, 'Court 4', 'indoor', 'indoor', 'available', 'Main Facility', 4),
    (5, 'Court 5', 'indoor', 'indoor', 'available', 'Main Facility', 4)
ON CONFLICT (court_number) DO NOTHING;

-- ============================================================================
-- MONDAY - "Advanced Focus"
-- ============================================================================

-- Monday 8-10 AM: Divided (Adv: Courts 1-2, Int: 3-4, Beg: 5)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Monday Morning Divided',
        'Morning open play divided by skill level',
        1, '08:00', '10:00',
        'divided_by_skill', 20.00, 25.00, 40, 8
    ) RETURNING id INTO v_block_id;

    -- Court allocations: Advanced 2 courts (16 max), Intermediate 2 courts (16 max), Beginner 1 court (8 max)
    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, sort_order)
    SELECT v_block_id, id, 4.5, 6.0, 'Advanced', 1 FROM events.courts WHERE court_number = 1
    UNION ALL SELECT v_block_id, id, 4.5, 6.0, 'Advanced', 2 FROM events.courts WHERE court_number = 2
    UNION ALL SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 3 FROM events.courts WHERE court_number = 3
    UNION ALL SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 4 FROM events.courts WHERE court_number = 4
    UNION ALL SELECT v_block_id, id, 0.0, 2.99, 'Beginner', 5 FROM events.courts WHERE court_number = 5;
END $$;

-- Monday 10 AM-12 PM: Mixed
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Monday Midday Mixed 1',
        'Mixed level open play',
        1, '10:00', '12:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    -- All courts available for mixed play (5 courts × 8 = 40 max)
    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Monday 12-2 PM: Mixed
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Monday Midday Mixed 2',
        'Mixed level open play',
        1, '12:00', '14:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Monday 2-4 PM: Mixed
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Monday Afternoon Mixed',
        'Mixed level open play',
        1, '14:00', '16:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Monday 4-6 PM: Mixed
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Monday Late Afternoon Mixed',
        'Mixed level open play',
        1, '16:00', '18:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Monday 6-8 PM: Divided (Adv: Courts 1-2, Int: 3-4, Beg: 5)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Monday Evening Divided',
        'Evening open play divided by skill level',
        1, '18:00', '20:00',
        'divided_by_skill', 20.00, 25.00, 40, 8
    ) RETURNING id INTO v_block_id;

    -- Advanced 2 courts (16 max), Intermediate 2 courts (16 max), Beginner 1 court (8 max)
    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, sort_order)
    SELECT v_block_id, id, 4.5, 6.0, 'Advanced', 1 FROM events.courts WHERE court_number = 1
    UNION ALL SELECT v_block_id, id, 4.5, 6.0, 'Advanced', 2 FROM events.courts WHERE court_number = 2
    UNION ALL SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 3 FROM events.courts WHERE court_number = 3
    UNION ALL SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 4 FROM events.courts WHERE court_number = 4
    UNION ALL SELECT v_block_id, id, 0.0, 2.99, 'Beginner', 5 FROM events.courts WHERE court_number = 5;
END $$;

-- Monday 8-9 PM: Mixed
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Monday Evening Mixed',
        'Wind down with mixed play',
        1, '20:00', '21:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- ============================================================================
-- TUESDAY - "Beginner Friendly"
-- ============================================================================

-- Tuesday 8-10 AM: Divided (Int: Courts 1-2, Adv: 3-4, Beg: 5)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Tuesday Morning Divided',
        'Morning open play divided by skill level',
        2, '08:00', '10:00',
        'divided_by_skill', 20.00, 25.00, 40, 8
    ) RETURNING id INTO v_block_id;

    -- Intermediate 2 courts (16 max), Advanced 2 courts (16 max), Beginner 1 court (8 max)
    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, sort_order)
    SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 1 FROM events.courts WHERE court_number = 1
    UNION ALL SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 2 FROM events.courts WHERE court_number = 2
    UNION ALL SELECT v_block_id, id, 4.5, 6.0, 'Advanced', 3 FROM events.courts WHERE court_number = 3
    UNION ALL SELECT v_block_id, id, 4.5, 6.0, 'Advanced', 4 FROM events.courts WHERE court_number = 4
    UNION ALL SELECT v_block_id, id, 0.0, 2.99, 'Beginner', 5 FROM events.courts WHERE court_number = 5;
END $$;

-- Tuesday 10 AM-12 PM: Mixed
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Tuesday Morning Mixed',
        'Mixed level open play',
        2, '10:00', '12:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Tuesday 12-2 PM: Beginner Dedicated (All 5 courts)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, dedicated_skill_min, dedicated_skill_max, dedicated_skill_label,
        price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Tuesday Beginner Focus',
        'All 5 courts dedicated to beginner players - perfect for newcomers!',
        2, '12:00', '14:00',
        'dedicated_skill', 0.0, 2.99, 'Beginner',
        15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    -- All 5 courts for Beginners (40 max)
    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, sort_order)
    SELECT v_block_id, id, 0.0, 2.99, 'Beginner', court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Tuesday 2-4 PM: Mixed
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Tuesday Afternoon Mixed',
        'Mixed level open play',
        2, '14:00', '16:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Tuesday 4-6 PM: Mixed
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Tuesday Late Afternoon Mixed',
        'Mixed level open play',
        2, '16:00', '18:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Tuesday 6-8 PM: Divided (Int: Courts 1-2, Beg: 3-4, Adv: 5)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Tuesday Evening Divided',
        'Evening open play divided by skill level',
        2, '18:00', '20:00',
        'divided_by_skill', 20.00, 25.00, 40, 8
    ) RETURNING id INTO v_block_id;

    -- Intermediate 2 courts (16 max), Beginner 2 courts (16 max), Advanced 1 court (8 max)
    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, sort_order)
    SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 1 FROM events.courts WHERE court_number = 1
    UNION ALL SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 2 FROM events.courts WHERE court_number = 2
    UNION ALL SELECT v_block_id, id, 0.0, 2.99, 'Beginner', 3 FROM events.courts WHERE court_number = 3
    UNION ALL SELECT v_block_id, id, 0.0, 2.99, 'Beginner', 4 FROM events.courts WHERE court_number = 4
    UNION ALL SELECT v_block_id, id, 4.5, 6.0, 'Advanced', 5 FROM events.courts WHERE court_number = 5;
END $$;

-- Tuesday 8-9 PM: Mixed
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Tuesday Evening Mixed',
        'Wind down with mixed play',
        2, '20:00', '21:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- ============================================================================
-- WEDNESDAY - "Intermediate Day"
-- ============================================================================

-- Wednesday 8-10 AM: Divided (Adv: Courts 1-2, Beg: 3-4, Int: 5)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Wednesday Morning Divided',
        'Morning open play divided by skill level',
        3, '08:00', '10:00',
        'divided_by_skill', 20.00, 25.00, 40, 8
    ) RETURNING id INTO v_block_id;

    -- Advanced 2 courts (16 max), Beginner 2 courts (16 max), Intermediate 1 court (8 max)
    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, sort_order)
    SELECT v_block_id, id, 4.5, 6.0, 'Advanced', 1 FROM events.courts WHERE court_number = 1
    UNION ALL SELECT v_block_id, id, 4.5, 6.0, 'Advanced', 2 FROM events.courts WHERE court_number = 2
    UNION ALL SELECT v_block_id, id, 0.0, 2.99, 'Beginner', 3 FROM events.courts WHERE court_number = 3
    UNION ALL SELECT v_block_id, id, 0.0, 2.99, 'Beginner', 4 FROM events.courts WHERE court_number = 4
    UNION ALL SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 5 FROM events.courts WHERE court_number = 5;
END $$;

-- Wednesday 10 AM-12 PM: Mixed
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Wednesday Morning Mixed',
        'Mixed level open play',
        3, '10:00', '12:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Wednesday 12-2 PM: Intermediate Dedicated (All 5 courts)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, dedicated_skill_min, dedicated_skill_max, dedicated_skill_label,
        price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Wednesday Intermediate Focus 1',
        'All 5 courts dedicated to intermediate players - skill-building paradise!',
        3, '12:00', '14:00',
        'dedicated_skill', 3.0, 4.49, 'Intermediate',
        15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    -- All 5 courts for Intermediate (40 max)
    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, sort_order)
    SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Wednesday 2-4 PM: Intermediate Dedicated (All 5 courts)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, dedicated_skill_min, dedicated_skill_max, dedicated_skill_label,
        price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Wednesday Intermediate Focus 2',
        'Continued intermediate focus time',
        3, '14:00', '16:00',
        'dedicated_skill', 3.0, 4.49, 'Intermediate',
        15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, sort_order)
    SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Wednesday 4-6 PM: Mixed
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Wednesday Late Afternoon Mixed',
        'Mixed level open play',
        3, '16:00', '18:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Wednesday 6-7 PM: Mixed (pre-Ladies Night)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Wednesday Early Evening Mixed',
        'Mixed play before Ladies Night',
        3, '18:00', '19:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Wednesday 7-9 PM: Ladies Dink Night (Special Event)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, special_event_name, price_member, price_guest, max_capacity, max_players_per_court,
        special_instructions
    ) VALUES (
        'Ladies Dink Night',
        'Women only, all skill levels welcome - community-building night!',
        3, '19:00', '21:00',
        'special_event', 'Ladies Dink Night', 15.00, 20.00, 40, 8,
        'Women only event. All skill levels welcome. Supportive environment, social play.'
    ) RETURNING id INTO v_block_id;

    -- All 5 courts for Ladies Night (40 max)
    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'All Levels', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- ============================================================================
-- THURSDAY - "Advanced Midday"
-- ============================================================================

-- Thursday 8-10 AM: Divided (Beg: Courts 1-2, Int: 3-4, Adv: 5)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Thursday Morning Divided',
        'Morning open play divided by skill level',
        4, '08:00', '10:00',
        'divided_by_skill', 20.00, 25.00, 40, 8
    ) RETURNING id INTO v_block_id;

    -- Beginner 2 courts (16 max), Intermediate 2 courts (16 max), Advanced 1 court (8 max)
    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, sort_order)
    SELECT v_block_id, id, 0.0, 2.99, 'Beginner', 1 FROM events.courts WHERE court_number = 1
    UNION ALL SELECT v_block_id, id, 0.0, 2.99, 'Beginner', 2 FROM events.courts WHERE court_number = 2
    UNION ALL SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 3 FROM events.courts WHERE court_number = 3
    UNION ALL SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 4 FROM events.courts WHERE court_number = 4
    UNION ALL SELECT v_block_id, id, 4.5, 6.0, 'Advanced', 5 FROM events.courts WHERE court_number = 5;
END $$;

-- Thursday 10 AM-12 PM: Mixed
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Thursday Morning Mixed',
        'Mixed level open play',
        4, '10:00', '12:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Thursday 12-2 PM: Advanced Dedicated (All 5 courts)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, dedicated_skill_min, dedicated_skill_max, dedicated_skill_label,
        price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Thursday Advanced Focus 1',
        'All 5 courts dedicated to advanced players - tournament-level intensity!',
        4, '12:00', '14:00',
        'dedicated_skill', 4.5, 6.0, 'Advanced',
        15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    -- All 5 courts for Advanced (40 max)
    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, sort_order)
    SELECT v_block_id, id, 4.5, 6.0, 'Advanced', court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Thursday 2-4 PM: Advanced Dedicated (All 5 courts)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, dedicated_skill_min, dedicated_skill_max, dedicated_skill_label,
        price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Thursday Advanced Focus 2',
        'Continued advanced focus time',
        4, '14:00', '16:00',
        'dedicated_skill', 4.5, 6.0, 'Advanced',
        15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, sort_order)
    SELECT v_block_id, id, 4.5, 6.0, 'Advanced', court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Thursday 4-6 PM: Mixed
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Thursday Late Afternoon Mixed',
        'Mixed level open play',
        4, '16:00', '18:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Thursday 6-8 PM: Divided (Beg: Courts 1-2, Int: 3-4, Adv: 5)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Thursday Evening Divided',
        'Evening open play divided by skill level',
        4, '18:00', '20:00',
        'divided_by_skill', 20.00, 25.00, 40, 8
    ) RETURNING id INTO v_block_id;

    -- Beginner 2 courts (16 max), Intermediate 2 courts (16 max), Advanced 1 court (8 max)
    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, sort_order)
    SELECT v_block_id, id, 0.0, 2.99, 'Beginner', 1 FROM events.courts WHERE court_number = 1
    UNION ALL SELECT v_block_id, id, 0.0, 2.99, 'Beginner', 2 FROM events.courts WHERE court_number = 2
    UNION ALL SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 3 FROM events.courts WHERE court_number = 3
    UNION ALL SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 4 FROM events.courts WHERE court_number = 4
    UNION ALL SELECT v_block_id, id, 4.5, 6.0, 'Advanced', 5 FROM events.courts WHERE court_number = 5;
END $$;

-- Thursday 8-9 PM: Mixed
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Thursday Evening Mixed',
        'Wind down with mixed play',
        4, '20:00', '21:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- ============================================================================
-- FRIDAY - "TGIF Social"
-- ============================================================================

-- Friday 8-10 AM: Divided (Int: Courts 1-2, Adv: 3-4, Beg: 5)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Friday Morning Divided',
        'Morning open play divided by skill level',
        5, '08:00', '10:00',
        'divided_by_skill', 20.00, 25.00, 40, 8
    ) RETURNING id INTO v_block_id;

    -- Intermediate 2 courts (16 max), Advanced 2 courts (16 max), Beginner 1 court (8 max)
    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, sort_order)
    SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 1 FROM events.courts WHERE court_number = 1
    UNION ALL SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 2 FROM events.courts WHERE court_number = 2
    UNION ALL SELECT v_block_id, id, 4.5, 6.0, 'Advanced', 3 FROM events.courts WHERE court_number = 3
    UNION ALL SELECT v_block_id, id, 4.5, 6.0, 'Advanced', 4 FROM events.courts WHERE court_number = 4
    UNION ALL SELECT v_block_id, id, 0.0, 2.99, 'Beginner', 5 FROM events.courts WHERE court_number = 5;
END $$;

-- Friday 10 AM-12 PM: Mixed
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Friday Morning Mixed',
        'Mixed level open play',
        5, '10:00', '12:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Friday 12-2 PM: Mixed
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Friday Midday Mixed',
        'Mixed level open play - flexible day!',
        5, '12:00', '14:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Friday 2-4 PM: Mixed
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Friday Afternoon Mixed',
        'Mixed level open play',
        5, '14:00', '16:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Friday 4-6 PM: Mixed
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Friday Late Afternoon Mixed',
        'Mixed level open play',
        5, '16:00', '18:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Friday 6-8 PM: Divided (Adv: Courts 1-2, Int: 3-4, Beg: 5)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Friday Evening Divided',
        'Evening open play divided by skill level',
        5, '18:00', '20:00',
        'divided_by_skill', 20.00, 25.00, 40, 8
    ) RETURNING id INTO v_block_id;

    -- Advanced 2 courts (16 max), Intermediate 2 courts (16 max), Beginner 1 court (8 max)
    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, sort_order)
    SELECT v_block_id, id, 4.5, 6.0, 'Advanced', 1 FROM events.courts WHERE court_number = 1
    UNION ALL SELECT v_block_id, id, 4.5, 6.0, 'Advanced', 2 FROM events.courts WHERE court_number = 2
    UNION ALL SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 3 FROM events.courts WHERE court_number = 3
    UNION ALL SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 4 FROM events.courts WHERE court_number = 4
    UNION ALL SELECT v_block_id, id, 0.0, 2.99, 'Beginner', 5 FROM events.courts WHERE court_number = 5;
END $$;

-- Friday 8-9 PM: Sunset Social (Special Event)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, special_event_name, price_member, price_guest, max_capacity, max_players_per_court,
        special_instructions
    ) VALUES (
        'Sunset Social',
        'End the week right with casual, social pickleball!',
        5, '20:00', '21:00',
        'special_event', 'Sunset Social', 15.00, 20.00, 40, 8,
        'Casual wind-down play. Mixed levels. Play with friends. No pressure!'
    ) RETURNING id INTO v_block_id;

    -- All 5 courts for Sunset Social (40 max)
    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- ============================================================================
-- SATURDAY - "Weekend Warrior"
-- ============================================================================

-- Saturday 8-10 AM: Divided (Adv: Courts 1-2, Int: 3-4, Beg: 5)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Saturday Morning Divided 1',
        'Early risers get prime morning play',
        6, '08:00', '10:00',
        'divided_by_skill', 20.00, 25.00, 40, 8
    ) RETURNING id INTO v_block_id;

    -- Advanced 2 courts (16 max), Intermediate 2 courts (16 max), Beginner 1 court (8 max)
    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, sort_order)
    SELECT v_block_id, id, 4.5, 6.0, 'Advanced', 1 FROM events.courts WHERE court_number = 1
    UNION ALL SELECT v_block_id, id, 4.5, 6.0, 'Advanced', 2 FROM events.courts WHERE court_number = 2
    UNION ALL SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 3 FROM events.courts WHERE court_number = 3
    UNION ALL SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 4 FROM events.courts WHERE court_number = 4
    UNION ALL SELECT v_block_id, id, 0.0, 2.99, 'Beginner', 5 FROM events.courts WHERE court_number = 5;
END $$;

-- Saturday 10 AM-12 PM: Divided (Adv: Courts 1-2, Int: 3-4, Beg: 5)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Saturday Morning Divided 2',
        'Continued morning divided play',
        6, '10:00', '12:00',
        'divided_by_skill', 20.00, 25.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, sort_order)
    SELECT v_block_id, id, 4.5, 6.0, 'Advanced', 1 FROM events.courts WHERE court_number = 1
    UNION ALL SELECT v_block_id, id, 4.5, 6.0, 'Advanced', 2 FROM events.courts WHERE court_number = 2
    UNION ALL SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 3 FROM events.courts WHERE court_number = 3
    UNION ALL SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 4 FROM events.courts WHERE court_number = 4
    UNION ALL SELECT v_block_id, id, 0.0, 2.99, 'Beginner', 5 FROM events.courts WHERE court_number = 5;
END $$;

-- Saturday 12-2 PM: Beginner Dedicated (All 5 courts)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, dedicated_skill_min, dedicated_skill_max, dedicated_skill_label,
        price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Saturday Beginner Focus',
        'Weekend beginner block - all 5 courts for newcomers!',
        6, '12:00', '14:00',
        'dedicated_skill', 0.0, 2.99, 'Beginner',
        15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    -- All 5 courts for Beginners (40 max)
    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, sort_order)
    SELECT v_block_id, id, 0.0, 2.99, 'Beginner', court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Saturday 2-4 PM: Mixed
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Saturday Afternoon Mixed 1',
        'Mixed level open play',
        6, '14:00', '16:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Saturday 4-6 PM: Mixed
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Saturday Afternoon Mixed 2',
        'Mixed level open play',
        6, '16:00', '18:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Saturday 6-8 PM: Divided (Int: Courts 1-2, Adv: 3-4, Beg: 5)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Saturday Evening Divided',
        'Evening open play divided by skill level',
        6, '18:00', '20:00',
        'divided_by_skill', 20.00, 25.00, 40, 8
    ) RETURNING id INTO v_block_id;

    -- Intermediate 2 courts (16 max), Advanced 2 courts (16 max), Beginner 1 court (8 max)
    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, sort_order)
    SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 1 FROM events.courts WHERE court_number = 1
    UNION ALL SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 2 FROM events.courts WHERE court_number = 2
    UNION ALL SELECT v_block_id, id, 4.5, 6.0, 'Advanced', 3 FROM events.courts WHERE court_number = 3
    UNION ALL SELECT v_block_id, id, 4.5, 6.0, 'Advanced', 4 FROM events.courts WHERE court_number = 4
    UNION ALL SELECT v_block_id, id, 0.0, 2.99, 'Beginner', 5 FROM events.courts WHERE court_number = 5;
END $$;

-- Saturday 8-9 PM: Mixed
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Saturday Evening Mixed',
        'Wind down the weekend',
        6, '20:00', '21:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- ============================================================================
-- SUNDAY - "Funday & Clinics"
-- ============================================================================

-- Sunday 8-10 AM: Divided (Int: Courts 1-2, Beg: 3-4, Adv: 5)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Sunday Morning Divided 1',
        'Active morning open play',
        0, '08:00', '10:00',
        'divided_by_skill', 20.00, 25.00, 40, 8
    ) RETURNING id INTO v_block_id;

    -- Intermediate 2 courts (16 max), Beginner 2 courts (16 max), Advanced 1 court (8 max)
    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, sort_order)
    SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 1 FROM events.courts WHERE court_number = 1
    UNION ALL SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 2 FROM events.courts WHERE court_number = 2
    UNION ALL SELECT v_block_id, id, 0.0, 2.99, 'Beginner', 3 FROM events.courts WHERE court_number = 3
    UNION ALL SELECT v_block_id, id, 0.0, 2.99, 'Beginner', 4 FROM events.courts WHERE court_number = 4
    UNION ALL SELECT v_block_id, id, 4.5, 6.0, 'Advanced', 5 FROM events.courts WHERE court_number = 5;
END $$;

-- Sunday 10 AM-12 PM: Divided (Int: Courts 1-2, Beg: 3-4, Adv: 5)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Sunday Morning Divided 2',
        'Continued morning divided play',
        0, '10:00', '12:00',
        'divided_by_skill', 20.00, 25.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, sort_order)
    SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 1 FROM events.courts WHERE court_number = 1
    UNION ALL SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 2 FROM events.courts WHERE court_number = 2
    UNION ALL SELECT v_block_id, id, 0.0, 2.99, 'Beginner', 3 FROM events.courts WHERE court_number = 3
    UNION ALL SELECT v_block_id, id, 0.0, 2.99, 'Beginner', 4 FROM events.courts WHERE court_number = 4
    UNION ALL SELECT v_block_id, id, 4.5, 6.0, 'Advanced', 5 FROM events.courts WHERE court_number = 5;
END $$;

-- Sunday 12-2 PM: Advanced Dedicated (All 5 courts)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, dedicated_skill_min, dedicated_skill_max, dedicated_skill_label,
        price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Sunday Advanced Focus',
        'Weekend advanced block - all 5 courts for high-level play!',
        0, '12:00', '14:00',
        'dedicated_skill', 4.5, 6.0, 'Advanced',
        15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    -- All 5 courts for Advanced (40 max)
    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, sort_order)
    SELECT v_block_id, id, 4.5, 6.0, 'Advanced', court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Sunday 2-4 PM: Mixed
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Sunday Afternoon Mixed 1',
        'Mixed level open play',
        0, '14:00', '16:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Sunday 4-6 PM: Mixed
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Sunday Afternoon Mixed 2',
        'Mixed level open play',
        0, '16:00', '18:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Sunday 6-8 PM: Dink & Drill Clinics (Special Event)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, special_event_name, price_member, price_guest, max_capacity, max_players_per_court,
        special_instructions
    ) VALUES (
        'Dink & Drill Clinics',
        'End the weekend with structured skill-building!',
        0, '18:00', '20:00',
        'special_event', 'Dink & Drill Clinics', 20.00, 25.00, 40, 8,
        'All 5 courts separated by skill level. Structured drills. Pro coaching. Skill development focus.'
    ) RETURNING id INTO v_block_id;

    -- Clinics: Beginner 2 courts (16 max), Intermediate 2 courts (16 max), Advanced 1 court (8 max)
    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, sort_order)
    SELECT v_block_id, id, 0.0, 2.99, 'Beginner', 1 FROM events.courts WHERE court_number = 1
    UNION ALL SELECT v_block_id, id, 0.0, 2.99, 'Beginner', 2 FROM events.courts WHERE court_number = 2
    UNION ALL SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 3 FROM events.courts WHERE court_number = 3
    UNION ALL SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 4 FROM events.courts WHERE court_number = 4
    UNION ALL SELECT v_block_id, id, 4.5, 6.0, 'Advanced', 5 FROM events.courts WHERE court_number = 5;
END $$;

-- Sunday 8-9 PM: Mixed
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Sunday Evening Mixed',
        'Wind down the weekend with mixed play',
        0, '20:00', '21:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- ============================================================================
-- SUMMARY
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '============================================================================';
    RAISE NOTICE 'OPEN PLAY SCHEDULE SEEDED SUCCESSFULLY';
    RAISE NOTICE '============================================================================';
    RAISE NOTICE 'Total schedule blocks created: %', (SELECT COUNT(*) FROM events.open_play_schedule_blocks);
    RAISE NOTICE 'Total court allocations: %', (SELECT COUNT(*) FROM events.open_play_court_allocations);
    RAISE NOTICE '';
    RAISE NOTICE 'Weekly breakdown by session type:';
    RAISE NOTICE '  Divided by skill: % blocks', (SELECT COUNT(*) FROM events.open_play_schedule_blocks WHERE session_type = 'divided_by_skill');
    RAISE NOTICE '  Mixed levels: % blocks', (SELECT COUNT(*) FROM events.open_play_schedule_blocks WHERE session_type = 'mixed_levels');
    RAISE NOTICE '  Dedicated skill: % blocks', (SELECT COUNT(*) FROM events.open_play_schedule_blocks WHERE session_type = 'dedicated_skill');
    RAISE NOTICE '  Special events: % blocks', (SELECT COUNT(*) FROM events.open_play_schedule_blocks WHERE session_type = 'special_event');
    RAISE NOTICE '';
    RAISE NOTICE 'Special events configured:';
    RAISE NOTICE '  - Ladies Dink Night (Wednesday 7-9 PM)';
    RAISE NOTICE '  - Sunset Social (Friday 9-10 PM)';
    RAISE NOTICE '  - Dink & Drill Clinics (Sunday 5-7 PM)';
    RAISE NOTICE '';
    RAISE NOTICE 'Next steps:';
    RAISE NOTICE '  1. Run: SELECT * FROM api.get_weekly_schedule();';
    RAISE NOTICE '  2. Generate instances: SELECT api.generate_open_play_instances(CURRENT_DATE, CURRENT_DATE + 30);';
    RAISE NOTICE '  3. View schedule: SELECT * FROM events.upcoming_open_play;';
    RAISE NOTICE '============================================================================';
END $$;
-- ============================================================================
-- OPEN PLAY PUBLIC WRAPPER FUNCTIONS
-- Creates public schema wrappers for api schema functions to enable PostgREST access
-- ============================================================================

-- Wrapper for get_weekly_schedule
CREATE OR REPLACE FUNCTION public.get_weekly_schedule(
    p_include_inactive BOOLEAN DEFAULT false
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN api.get_weekly_schedule(p_include_inactive);
END;
$$;

-- Wrapper for get_schedule_for_date
CREATE OR REPLACE FUNCTION public.get_schedule_for_date(
    p_date DATE
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN api.get_schedule_for_date(p_date);
END;
$$;

-- Wrapper for update_schedule_block
CREATE OR REPLACE FUNCTION public.update_schedule_block(
    p_block_id UUID,
    p_updates JSONB
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN api.update_schedule_block(p_block_id, p_updates);
END;
$$;

-- Wrapper for delete_schedule_block
CREATE OR REPLACE FUNCTION public.delete_schedule_block(
    p_block_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN api.delete_schedule_block(p_block_id);
END;
$$;

-- Wrapper for create_schedule_override
CREATE OR REPLACE FUNCTION public.create_schedule_override(
    p_block_id UUID,
    p_override_date DATE,
    p_is_cancelled BOOLEAN,
    p_reason TEXT DEFAULT NULL,
    p_replacement_details JSONB DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN api.create_schedule_override(
        p_block_id,
        p_override_date,
        p_is_cancelled,
        p_reason,
        p_replacement_details
    );
END;
$$;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION public.get_weekly_schedule TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_schedule_for_date TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.update_schedule_block TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.delete_schedule_block TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.create_schedule_override TO authenticated, service_role;

-- Add comments
COMMENT ON FUNCTION public.get_weekly_schedule IS 'Public wrapper for api.get_weekly_schedule';
COMMENT ON FUNCTION public.get_schedule_for_date IS 'Public wrapper for api.get_schedule_for_date';
COMMENT ON FUNCTION public.update_schedule_block IS 'Public wrapper for api.update_schedule_block';
COMMENT ON FUNCTION public.delete_schedule_block IS 'Public wrapper for api.delete_schedule_block';
COMMENT ON FUNCTION public.create_schedule_override IS 'Public wrapper for api.create_schedule_override';
-- ============================================================================
-- FIX SCHEDULE OVERRIDES FOREIGN KEY CONSTRAINT
-- Makes created_by nullable and adds better handling
-- ============================================================================

-- Drop the existing foreign key constraint
ALTER TABLE events.open_play_schedule_overrides
    DROP CONSTRAINT IF EXISTS open_play_schedule_overrides_created_by_fkey;

-- Make created_by nullable
ALTER TABLE events.open_play_schedule_overrides
    ALTER COLUMN created_by DROP NOT NULL;

-- Add a new foreign key constraint that allows NULL
ALTER TABLE events.open_play_schedule_overrides
    ADD CONSTRAINT open_play_schedule_overrides_created_by_fkey
    FOREIGN KEY (created_by) REFERENCES app_auth.admin_users(id)
    ON DELETE SET NULL;

-- Update the create_schedule_override function to handle missing admin users
CREATE OR REPLACE FUNCTION api.create_schedule_override(
    p_block_id UUID,
    p_override_date DATE,
    p_is_cancelled BOOLEAN,
    p_reason TEXT,
    p_replacement_details JSONB DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_override_id UUID;
    v_result JSON;
    v_admin_user_id UUID;
BEGIN
    -- Check if user is staff
    IF NOT events.is_staff() THEN
        RAISE EXCEPTION 'Unauthorized: Only staff can create schedule overrides';
    END IF;

    -- Try to get admin user ID (may be NULL if not in admin_users table)
    SELECT id INTO v_admin_user_id
    FROM app_auth.admin_users
    WHERE id = auth.uid();

    -- Create the override
    INSERT INTO events.open_play_schedule_overrides (
        schedule_block_id,
        override_date,
        is_cancelled,
        replacement_name,
        replacement_start_time,
        replacement_end_time,
        replacement_session_type,
        reason,
        special_instructions,
        created_by
    ) VALUES (
        p_block_id,
        p_override_date,
        p_is_cancelled,
        p_replacement_details->>'name',
        (p_replacement_details->>'start_time')::TIME,
        (p_replacement_details->>'end_time')::TIME,
        (p_replacement_details->>'session_type')::events.open_play_session_type,
        p_reason,
        p_replacement_details->>'special_instructions',
        v_admin_user_id  -- Use the admin user ID or NULL
    ) RETURNING id INTO v_override_id;

    -- Mark any existing instance as cancelled or update it
    UPDATE events.open_play_instances
    SET
        is_cancelled = p_is_cancelled,
        override_id = v_override_id
    WHERE schedule_block_id = p_block_id
      AND instance_date = p_override_date;

    -- Return success
    SELECT json_build_object(
        'success', true,
        'override_id', v_override_id,
        'message', 'Schedule override created successfully'
    ) INTO v_result;

    RETURN v_result;
END;
$$;

-- Update the public wrapper function
CREATE OR REPLACE FUNCTION public.create_schedule_override(
    p_block_id UUID,
    p_override_date DATE,
    p_is_cancelled BOOLEAN,
    p_reason TEXT DEFAULT NULL,
    p_replacement_details JSONB DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN api.create_schedule_override(
        p_block_id,
        p_override_date,
        p_is_cancelled,
        p_reason,
        p_replacement_details
    );
END;
$$;

-- Add comment
COMMENT ON TABLE events.open_play_schedule_overrides IS
    'Stores overrides for scheduled open play sessions. created_by may be NULL if user is not in admin_users table.';
-- ============================================================================
-- SCHEDULE OVERRIDE UPSERT FIX
-- Updates create_schedule_override to handle existing overrides
-- ============================================================================

CREATE OR REPLACE FUNCTION api.create_schedule_override(
    p_block_id UUID,
    p_override_date DATE,
    p_is_cancelled BOOLEAN,
    p_reason TEXT,
    p_replacement_details JSONB DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_override_id UUID;
    v_result JSON;
    v_admin_user_id UUID;
    v_is_new BOOLEAN;
BEGIN
    -- Check if user is staff
    IF NOT events.is_staff() THEN
        RAISE EXCEPTION 'Unauthorized: Only staff can create schedule overrides';
    END IF;

    -- Try to get admin user ID (may be NULL if not in admin_users table)
    SELECT id INTO v_admin_user_id
    FROM app_auth.admin_users
    WHERE id = auth.uid();

    -- Upsert the override (insert or update if already exists)
    INSERT INTO events.open_play_schedule_overrides (
        schedule_block_id,
        override_date,
        is_cancelled,
        replacement_name,
        replacement_start_time,
        replacement_end_time,
        replacement_session_type,
        reason,
        special_instructions,
        created_by
    ) VALUES (
        p_block_id,
        p_override_date,
        p_is_cancelled,
        p_replacement_details->>'name',
        (p_replacement_details->>'start_time')::TIME,
        (p_replacement_details->>'end_time')::TIME,
        (p_replacement_details->>'session_type')::events.open_play_session_type,
        p_reason,
        p_replacement_details->>'special_instructions',
        v_admin_user_id
    )
    ON CONFLICT (schedule_block_id, override_date)
    DO UPDATE SET
        is_cancelled = EXCLUDED.is_cancelled,
        replacement_name = EXCLUDED.replacement_name,
        replacement_start_time = EXCLUDED.replacement_start_time,
        replacement_end_time = EXCLUDED.replacement_end_time,
        replacement_session_type = EXCLUDED.replacement_session_type,
        reason = EXCLUDED.reason,
        special_instructions = EXCLUDED.special_instructions,
        updated_at = CURRENT_TIMESTAMP
    RETURNING id, (xmax = 0) INTO v_override_id, v_is_new;

    -- Mark any existing instance as cancelled or update it
    UPDATE events.open_play_instances
    SET
        is_cancelled = p_is_cancelled,
        override_id = v_override_id,
        updated_at = CURRENT_TIMESTAMP
    WHERE schedule_block_id = p_block_id
      AND instance_date = p_override_date;

    -- Return success
    SELECT json_build_object(
        'success', true,
        'override_id', v_override_id,
        'is_new', v_is_new,
        'message', CASE
            WHEN v_is_new THEN 'Schedule override created successfully'
            ELSE 'Schedule override updated successfully'
        END
    ) INTO v_result;

    RETURN v_result;
END;
$$;

-- Update public wrapper (no changes needed, just ensuring it's correct)
CREATE OR REPLACE FUNCTION public.create_schedule_override(
    p_block_id UUID,
    p_override_date DATE,
    p_is_cancelled BOOLEAN,
    p_reason TEXT DEFAULT NULL,
    p_replacement_details JSONB DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN api.create_schedule_override(
        p_block_id,
        p_override_date,
        p_is_cancelled,
        p_reason,
        p_replacement_details
    );
END;
$$;

-- Add comment
COMMENT ON FUNCTION api.create_schedule_override IS
    'Creates or updates a schedule override for a specific date. Uses UPSERT to handle existing overrides.';
-- ============================================================================
-- OPEN PLAY REGISTRATIONS MODULE
-- Player check-in and registration system for open play sessions
-- Members play FREE, guests pay per session
-- ============================================================================

SET search_path TO events, app_auth, public;

-- ============================================================================
-- OPEN PLAY REGISTRATIONS TABLE
-- Track player check-ins for open play sessions
-- ============================================================================

CREATE TABLE events.open_play_registrations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Session reference
    instance_id UUID NOT NULL REFERENCES events.open_play_instances(id) ON DELETE CASCADE,
    schedule_block_id UUID NOT NULL REFERENCES events.open_play_schedule_blocks(id) ON DELETE CASCADE,

    -- Player reference
    player_id UUID NOT NULL REFERENCES app_auth.players(id) ON DELETE CASCADE,

    -- Court/Skill level allocation
    court_id UUID REFERENCES events.courts(id) ON DELETE SET NULL,
    skill_level_label VARCHAR(100), -- Which skill bracket they're in
    assigned_skill_min NUMERIC(3, 2),
    assigned_skill_max NUMERIC(3, 2),

    -- Check-in details
    check_in_time TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    checked_out_at TIMESTAMPTZ,

    -- Player info snapshot (for historical reference)
    player_name VARCHAR(200) NOT NULL,
    player_email VARCHAR(255),
    player_phone VARCHAR(50),
    membership_level app_auth.membership_level NOT NULL,
    player_skill_level events.skill_level,
    player_dupr_rating NUMERIC(3, 2),

    -- Payment (guests only)
    fee_amount DECIMAL(10, 2) DEFAULT 0.00,
    fee_type VARCHAR(50) DEFAULT 'open_play_session', -- 'open_play_session', 'waived_member'
    payment_status VARCHAR(50) DEFAULT 'completed', -- 'pending', 'completed', 'waived', 'refunded'
    fee_id UUID REFERENCES app_auth.player_fees(id) ON DELETE SET NULL,
    waived_reason TEXT, -- For comped sessions

    -- Session details
    is_cancelled BOOLEAN DEFAULT false,
    cancelled_at TIMESTAMPTZ,
    cancellation_reason TEXT,
    refund_issued BOOLEAN DEFAULT false,
    refund_amount DECIMAL(10, 2),

    -- Notes
    notes TEXT,
    special_requests TEXT,

    -- Metadata
    registered_by UUID REFERENCES app_auth.admin_users(id), -- NULL if self-registration
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
    CONSTRAINT unique_instance_player UNIQUE(instance_id, player_id),
    CONSTRAINT valid_checkout CHECK (checked_out_at IS NULL OR checked_out_at >= check_in_time),
    CONSTRAINT valid_cancellation CHECK (
        (is_cancelled = false AND cancelled_at IS NULL) OR
        (is_cancelled = true AND cancelled_at IS NOT NULL)
    ),
    CONSTRAINT valid_refund CHECK (
        (refund_issued = false AND refund_amount IS NULL) OR
        (refund_issued = true AND refund_amount IS NOT NULL AND refund_amount >= 0)
    )
);

COMMENT ON TABLE events.open_play_registrations IS 'Player check-ins for open play sessions - members free, guests pay';

-- Create indexes
CREATE INDEX idx_open_play_reg_instance ON events.open_play_registrations(instance_id);
CREATE INDEX idx_open_play_reg_player ON events.open_play_registrations(player_id);
CREATE INDEX idx_open_play_reg_schedule_block ON events.open_play_registrations(schedule_block_id);
CREATE INDEX idx_open_play_reg_court ON events.open_play_registrations(court_id);
CREATE INDEX idx_open_play_reg_skill ON events.open_play_registrations(skill_level_label);
CREATE INDEX idx_open_play_reg_checkin ON events.open_play_registrations(check_in_time);
CREATE INDEX idx_open_play_reg_cancelled ON events.open_play_registrations(is_cancelled);
CREATE INDEX idx_open_play_reg_payment ON events.open_play_registrations(payment_status);

-- Composite index for attendance queries
CREATE INDEX idx_open_play_reg_instance_active ON events.open_play_registrations(instance_id, is_cancelled)
    WHERE is_cancelled = false;

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Calculate fee for a player based on membership and time
CREATE OR REPLACE FUNCTION events.calculate_open_play_fee(
    p_player_id UUID,
    p_schedule_block_id UUID
)
RETURNS TABLE (
    fee_amount DECIMAL,
    fee_type VARCHAR,
    payment_required BOOLEAN
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_membership_level app_auth.membership_level;
    v_price_member DECIMAL(10, 2);
    v_price_guest DECIMAL(10, 2);
BEGIN
    -- Get player's membership level
    SELECT membership_level INTO v_membership_level
    FROM app_auth.players
    WHERE id = p_player_id;

    IF v_membership_level IS NULL THEN
        RAISE EXCEPTION 'Player not found';
    END IF;

    -- Get pricing from schedule block
    SELECT price_member, price_guest INTO v_price_member, v_price_guest
    FROM events.open_play_schedule_blocks
    WHERE id = p_schedule_block_id;

    -- Members play for FREE (basic, premium, vip)
    IF v_membership_level IN ('basic', 'premium', 'vip') THEN
        RETURN QUERY SELECT
            0.00::DECIMAL(10, 2) as fee_amount,
            'waived_member'::VARCHAR as fee_type,
            false as payment_required;
    -- Guests pay per session
    ELSIF v_membership_level = 'guest' THEN
        RETURN QUERY SELECT
            COALESCE(v_price_guest, 15.00)::DECIMAL(10, 2) as fee_amount,
            'open_play_session'::VARCHAR as fee_type,
            true as payment_required;
    ELSE
        RAISE EXCEPTION 'Unknown membership level: %', v_membership_level;
    END IF;
END;
$$;

COMMENT ON FUNCTION events.calculate_open_play_fee IS 'Calculate fee for open play session based on membership level';

-- Get current capacity for a skill level in an instance
CREATE OR REPLACE FUNCTION events.get_skill_level_capacity(
    p_instance_id UUID,
    p_skill_level_label VARCHAR
)
RETURNS TABLE (
    skill_label VARCHAR,
    total_capacity INTEGER,
    current_registrations INTEGER,
    available_spots INTEGER,
    courts_allocated INTEGER
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_schedule_block_id UUID;
    v_max_per_court INTEGER;
    v_court_count INTEGER;
    v_total_capacity INTEGER;
    v_current_count INTEGER;
BEGIN
    -- Get schedule block and max players per court
    SELECT schedule_block_id INTO v_schedule_block_id
    FROM events.open_play_instances
    WHERE id = p_instance_id;

    SELECT max_players_per_court INTO v_max_per_court
    FROM events.open_play_schedule_blocks
    WHERE id = v_schedule_block_id;

    v_max_per_court := COALESCE(v_max_per_court, 8);

    -- Count courts allocated to this skill level
    SELECT COUNT(*) INTO v_court_count
    FROM events.open_play_court_allocations
    WHERE schedule_block_id = v_schedule_block_id
    AND skill_level_label = p_skill_level_label;

    -- Calculate total capacity
    v_total_capacity := v_court_count * v_max_per_court;

    -- Count current registrations
    SELECT COUNT(*) INTO v_current_count
    FROM events.open_play_registrations
    WHERE instance_id = p_instance_id
    AND skill_level_label = p_skill_level_label
    AND is_cancelled = false;

    RETURN QUERY SELECT
        p_skill_level_label,
        v_total_capacity,
        v_current_count::INTEGER,
        (v_total_capacity - v_current_count)::INTEGER as available_spots,
        v_court_count::INTEGER;
END;
$$;

COMMENT ON FUNCTION events.get_skill_level_capacity IS 'Get current capacity and availability for a skill level';

-- ============================================================================
-- API FUNCTIONS
-- ============================================================================

-- Register/Check-in player for open play session
CREATE OR REPLACE FUNCTION api.register_for_open_play(
    p_instance_id UUID,
    p_player_id UUID,
    p_skill_level_label VARCHAR,
    p_notes TEXT DEFAULT NULL,
    p_payment_intent_id TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_schedule_block_id UUID;
    v_instance_date DATE;
    v_is_cancelled BOOLEAN;
    v_player RECORD;
    v_fee RECORD;
    v_capacity RECORD;
    v_registration_id UUID;
    v_fee_id UUID;
    v_court_id UUID;
    v_skill_min NUMERIC(3, 2);
    v_skill_max NUMERIC(3, 2);
BEGIN
    -- Verify instance exists and is not cancelled
    SELECT schedule_block_id, instance_date, is_cancelled
    INTO v_schedule_block_id, v_instance_date, v_is_cancelled
    FROM events.open_play_instances
    WHERE id = p_instance_id;

    IF v_schedule_block_id IS NULL THEN
        RAISE EXCEPTION 'Open play instance not found';
    END IF;

    IF v_is_cancelled THEN
        RAISE EXCEPTION 'This open play session has been cancelled';
    END IF;

    -- Get player information
    SELECT
        p.id,
        p.first_name || ' ' || p.last_name as full_name,
        p.email,
        p.phone,
        p.membership_level,
        p.skill_level,
        p.dupr_rating
    INTO v_player
    FROM app_auth.players p
    WHERE p.id = p_player_id;

    IF v_player.id IS NULL THEN
        RAISE EXCEPTION 'Player not found';
    END IF;

    -- Check if already registered
    IF EXISTS (
        SELECT 1 FROM events.open_play_registrations
        WHERE instance_id = p_instance_id
        AND player_id = p_player_id
        AND is_cancelled = false
    ) THEN
        RAISE EXCEPTION 'Player is already registered for this session';
    END IF;

    -- Calculate fee
    SELECT * INTO v_fee
    FROM events.calculate_open_play_fee(p_player_id, v_schedule_block_id);

    -- Check capacity for this skill level
    SELECT * INTO v_capacity
    FROM events.get_skill_level_capacity(p_instance_id, p_skill_level_label);

    IF v_capacity.available_spots <= 0 THEN
        RAISE EXCEPTION 'No available spots for skill level: %', p_skill_level_label;
    END IF;

    -- Get court allocation details
    SELECT court_id, skill_level_min, skill_level_max
    INTO v_court_id, v_skill_min, v_skill_max
    FROM events.open_play_court_allocations
    WHERE schedule_block_id = v_schedule_block_id
    AND skill_level_label = p_skill_level_label
    LIMIT 1;

    -- Create fee record for guests if payment required
    IF v_fee.payment_required THEN
        IF p_payment_intent_id IS NULL THEN
            RAISE EXCEPTION 'Payment required for guest players';
        END IF;

        INSERT INTO app_auth.player_fees (
            player_id,
            fee_type,
            amount,
            stripe_payment_intent_id,
            payment_status,
            paid_at,
            notes
        ) VALUES (
            p_player_id,
            'open_play_session',
            v_fee.fee_amount,
            p_payment_intent_id,
            'paid',
            CURRENT_TIMESTAMP,
            'Open play session: ' || v_instance_date || ' - ' || p_skill_level_label
        )
        RETURNING id INTO v_fee_id;
    END IF;

    -- Create registration
    INSERT INTO events.open_play_registrations (
        instance_id,
        schedule_block_id,
        player_id,
        court_id,
        skill_level_label,
        assigned_skill_min,
        assigned_skill_max,
        player_name,
        player_email,
        player_phone,
        membership_level,
        player_skill_level,
        player_dupr_rating,
        fee_amount,
        fee_type,
        payment_status,
        fee_id,
        waived_reason,
        notes
    ) VALUES (
        p_instance_id,
        v_schedule_block_id,
        p_player_id,
        v_court_id,
        p_skill_level_label,
        v_skill_min,
        v_skill_max,
        v_player.full_name,
        v_player.email,
        v_player.phone,
        v_player.membership_level,
        v_player.skill_level,
        v_player.dupr_rating,
        v_fee.fee_amount,
        v_fee.fee_type,
        CASE WHEN v_fee.payment_required THEN 'completed' ELSE 'waived' END,
        v_fee_id,
        CASE WHEN NOT v_fee.payment_required THEN 'Member - free access' ELSE NULL END,
        p_notes
    )
    RETURNING id INTO v_registration_id;

    -- Return success response
    RETURN json_build_object(
        'success', true,
        'registration_id', v_registration_id,
        'player_name', v_player.full_name,
        'skill_level', p_skill_level_label,
        'fee_amount', v_fee.fee_amount,
        'payment_required', v_fee.payment_required,
        'check_in_time', CURRENT_TIMESTAMP,
        'capacity', json_build_object(
            'total', v_capacity.total_capacity,
            'current', v_capacity.current_registrations + 1,
            'available', v_capacity.available_spots - 1
        )
    );
END;
$$;

COMMENT ON FUNCTION api.register_for_open_play IS 'Register player for open play session - members free, guests pay';

-- Cancel open play registration
CREATE OR REPLACE FUNCTION api.cancel_open_play_registration(
    p_registration_id UUID,
    p_reason TEXT DEFAULT NULL,
    p_issue_refund BOOLEAN DEFAULT false
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_registration RECORD;
    v_refund_amount DECIMAL(10, 2);
BEGIN
    -- Get registration details
    SELECT
        opr.id,
        opr.player_id,
        opr.instance_id,
        opr.fee_amount,
        opr.fee_id,
        opr.payment_status,
        opr.is_cancelled,
        opi.start_time
    INTO v_registration
    FROM events.open_play_registrations opr
    JOIN events.open_play_instances opi ON opi.id = opr.instance_id
    WHERE opr.id = p_registration_id;

    IF v_registration.id IS NULL THEN
        RAISE EXCEPTION 'Registration not found';
    END IF;

    IF v_registration.is_cancelled THEN
        RAISE EXCEPTION 'Registration is already cancelled';
    END IF;

    -- Check if session has already started
    IF v_registration.start_time < CURRENT_TIMESTAMP THEN
        RAISE EXCEPTION 'Cannot cancel registration for a session that has already started';
    END IF;

    -- Calculate refund if applicable
    v_refund_amount := 0.00;
    IF p_issue_refund AND v_registration.fee_amount > 0 THEN
        -- Full refund if cancelled more than 24 hours before
        IF v_registration.start_time > CURRENT_TIMESTAMP + INTERVAL '24 hours' THEN
            v_refund_amount := v_registration.fee_amount;
        -- 50% refund if cancelled within 24 hours
        ELSIF v_registration.start_time > CURRENT_TIMESTAMP THEN
            v_refund_amount := v_registration.fee_amount * 0.5;
        END IF;
    END IF;

    -- Update registration
    UPDATE events.open_play_registrations
    SET
        is_cancelled = true,
        cancelled_at = CURRENT_TIMESTAMP,
        cancellation_reason = p_reason,
        refund_issued = (v_refund_amount > 0),
        refund_amount = CASE WHEN v_refund_amount > 0 THEN v_refund_amount ELSE NULL END,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_registration_id;

    -- Update fee record if refund issued
    IF v_refund_amount > 0 AND v_registration.fee_id IS NOT NULL THEN
        UPDATE app_auth.player_fees
        SET
            payment_status = 'refunded',
            notes = COALESCE(notes, '') || E'\nRefund issued: $' || v_refund_amount::TEXT,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = v_registration.fee_id;
    END IF;

    RETURN json_build_object(
        'success', true,
        'registration_id', p_registration_id,
        'cancelled_at', CURRENT_TIMESTAMP,
        'refund_issued', (v_refund_amount > 0),
        'refund_amount', v_refund_amount
    );
END;
$$;

COMMENT ON FUNCTION api.cancel_open_play_registration IS 'Cancel open play registration with optional refund';

-- Get registrations for an open play instance
CREATE OR REPLACE FUNCTION api.get_open_play_registrations(
    p_instance_id UUID,
    p_include_cancelled BOOLEAN DEFAULT false
)
RETURNS JSON
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_result JSON;
BEGIN
    WITH registration_data AS (
        SELECT
            opr.id,
            opr.player_id,
            opr.player_name,
            opr.membership_level::TEXT,
            opr.skill_level_label,
            opr.player_skill_level::TEXT,
            opr.player_dupr_rating,
            opr.check_in_time,
            opr.checked_out_at,
            opr.fee_amount,
            opr.payment_status,
            opr.is_cancelled,
            opr.cancelled_at,
            c.court_number,
            c.name as court_name
        FROM events.open_play_registrations opr
        LEFT JOIN events.courts c ON c.id = opr.court_id
        WHERE opr.instance_id = p_instance_id
        AND (p_include_cancelled OR opr.is_cancelled = false)
        ORDER BY opr.skill_level_label, opr.check_in_time
    ),
    capacity_data AS (
        SELECT
            opca.skill_level_label,
            COUNT(*) as court_count,
            opsb.max_players_per_court
        FROM events.open_play_instances opi
        JOIN events.open_play_court_allocations opca ON opca.schedule_block_id = opi.schedule_block_id
        JOIN events.open_play_schedule_blocks opsb ON opsb.id = opi.schedule_block_id
        WHERE opi.id = p_instance_id
        GROUP BY opca.skill_level_label, opsb.max_players_per_court
    )
    SELECT json_build_object(
        'instance_id', p_instance_id,
        'total_registrations', (SELECT COUNT(*) FROM registration_data WHERE NOT is_cancelled),
        'registrations', (
            SELECT json_agg(
                json_build_object(
                    'id', id,
                    'player_id', player_id,
                    'player_name', player_name,
                    'membership_level', membership_level,
                    'skill_level_label', skill_level_label,
                    'player_skill_level', player_skill_level,
                    'player_dupr_rating', player_dupr_rating,
                    'check_in_time', check_in_time,
                    'checked_out_at', checked_out_at,
                    'fee_amount', fee_amount,
                    'payment_status', payment_status,
                    'is_cancelled', is_cancelled,
                    'cancelled_at', cancelled_at,
                    'court_number', court_number,
                    'court_name', court_name
                )
            )
            FROM registration_data
        ),
        'capacity_by_skill', (
            SELECT json_agg(
                json_build_object(
                    'skill_level', cd.skill_level_label,
                    'total_capacity', cd.court_count * cd.max_players_per_court,
                    'current_count', (
                        SELECT COUNT(*) FROM registration_data rd
                        WHERE rd.skill_level_label = cd.skill_level_label
                        AND NOT rd.is_cancelled
                    ),
                    'available_spots', (cd.court_count * cd.max_players_per_court) - (
                        SELECT COUNT(*) FROM registration_data rd
                        WHERE rd.skill_level_label = cd.skill_level_label
                        AND NOT rd.is_cancelled
                    ),
                    'courts_allocated', cd.court_count
                )
            )
            FROM capacity_data cd
        )
    ) INTO v_result;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION api.get_open_play_registrations IS 'Get all registrations for an open play instance';

-- Get player's open play history
CREATE OR REPLACE FUNCTION api.get_player_open_play_history(
    p_player_id UUID,
    p_limit INTEGER DEFAULT 20,
    p_offset INTEGER DEFAULT 0
)
RETURNS JSON
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_result JSON;
BEGIN
    SELECT json_build_object(
        'player_id', p_player_id,
        'total_sessions', (
            SELECT COUNT(*)
            FROM events.open_play_registrations
            WHERE player_id = p_player_id
            AND is_cancelled = false
        ),
        'sessions', (
            SELECT json_agg(
                json_build_object(
                    'registration_id', opr.id,
                    'session_date', opi.instance_date,
                    'start_time', opi.start_time,
                    'end_time', opi.end_time,
                    'session_name', opsb.name,
                    'skill_level', opr.skill_level_label,
                    'check_in_time', opr.check_in_time,
                    'checked_out_at', opr.checked_out_at,
                    'fee_amount', opr.fee_amount,
                    'payment_status', opr.payment_status,
                    'court_number', c.court_number,
                    'is_cancelled', opr.is_cancelled
                ) ORDER BY opi.instance_date DESC, opi.start_time DESC
            )
            FROM events.open_play_registrations opr
            JOIN events.open_play_instances opi ON opi.id = opr.instance_id
            JOIN events.open_play_schedule_blocks opsb ON opsb.id = opr.schedule_block_id
            LEFT JOIN events.courts c ON c.id = opr.court_id
            WHERE opr.player_id = p_player_id
            LIMIT p_limit
            OFFSET p_offset
        )
    ) INTO v_result;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION api.get_player_open_play_history IS 'Get player open play session history';

-- Get upcoming open play schedule with availability
CREATE OR REPLACE FUNCTION api.get_upcoming_open_play_schedule(
    p_start_date DATE DEFAULT CURRENT_DATE,
    p_end_date DATE DEFAULT NULL,
    p_days_ahead INTEGER DEFAULT 7
)
RETURNS JSON
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_end_date DATE;
    v_result JSON;
BEGIN
    v_end_date := COALESCE(p_end_date, p_start_date + p_days_ahead);

    WITH instance_data AS (
        SELECT
            opi.id as instance_id,
            opi.instance_date,
            opi.start_time,
            opi.end_time,
            opi.is_cancelled,
            opsb.id as block_id,
            opsb.name,
            opsb.description,
            opsb.session_type::TEXT,
            opsb.special_event_name,
            opsb.price_member,
            opsb.price_guest,
            opsb.max_players_per_court,
            opsb.special_instructions
        FROM events.open_play_instances opi
        JOIN events.open_play_schedule_blocks opsb ON opsb.id = opi.schedule_block_id
        WHERE opi.instance_date >= p_start_date
        AND opi.instance_date <= v_end_date
        AND opsb.is_active = true
        ORDER BY opi.instance_date, opi.start_time
    )
    SELECT json_build_object(
        'start_date', p_start_date,
        'end_date', v_end_date,
        'sessions', (
            SELECT json_agg(
                json_build_object(
                    'instance_id', id.instance_id,
                    'date', id.instance_date,
                    'start_time', id.start_time,
                    'end_time', id.end_time,
                    'name', id.name,
                    'description', id.description,
                    'session_type', id.session_type,
                    'special_event_name', id.special_event_name,
                    'price_member', id.price_member,
                    'price_guest', id.price_guest,
                    'is_cancelled', id.is_cancelled,
                    'special_instructions', id.special_instructions,
                    'capacity_by_skill', (
                        SELECT json_agg(
                            json_build_object(
                                'skill_level', opca.skill_level_label,
                                'skill_min', opca.skill_level_min,
                                'skill_max', opca.skill_level_max,
                                'court_count', COUNT(*),
                                'total_capacity', COUNT(*) * id.max_players_per_court,
                                'current_registrations', (
                                    SELECT COUNT(*)
                                    FROM events.open_play_registrations opr
                                    WHERE opr.instance_id = id.instance_id
                                    AND opr.skill_level_label = opca.skill_level_label
                                    AND opr.is_cancelled = false
                                ),
                                'available_spots', (COUNT(*) * id.max_players_per_court) - (
                                    SELECT COUNT(*)
                                    FROM events.open_play_registrations opr
                                    WHERE opr.instance_id = id.instance_id
                                    AND opr.skill_level_label = opca.skill_level_label
                                    AND opr.is_cancelled = false
                                )
                            )
                        )
                        FROM events.open_play_court_allocations opca
                        WHERE opca.schedule_block_id = id.block_id
                        GROUP BY opca.skill_level_label, opca.skill_level_min, opca.skill_level_max
                    )
                ) ORDER BY id.instance_date, id.start_time
            )
            FROM instance_data id
        )
    ) INTO v_result;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION api.get_upcoming_open_play_schedule IS 'Get upcoming open play schedule with availability';

-- ============================================================================
-- ROW LEVEL SECURITY POLICIES
-- ============================================================================

-- Enable RLS on registrations table
ALTER TABLE events.open_play_registrations ENABLE ROW LEVEL SECURITY;

-- Policy: Staff can view all registrations
CREATE POLICY open_play_reg_staff_all ON events.open_play_registrations
    FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM app_auth.admin_users au
            WHERE au.id = auth.uid()
        )
    );

-- Policy: Players can view their own registrations
CREATE POLICY open_play_reg_player_own ON events.open_play_registrations
    FOR SELECT
    USING (
        player_id IN (
            SELECT id FROM app_auth.players
            WHERE account_id = auth.uid()
        )
    );

-- Policy: Authenticated users can insert their own registrations
CREATE POLICY open_play_reg_player_insert ON events.open_play_registrations
    FOR INSERT
    WITH CHECK (
        player_id IN (
            SELECT id FROM app_auth.players
            WHERE account_id = auth.uid()
        )
    );

-- Policy: Players can update (cancel) their own registrations
CREATE POLICY open_play_reg_player_update ON events.open_play_registrations
    FOR UPDATE
    USING (
        player_id IN (
            SELECT id FROM app_auth.players
            WHERE account_id = auth.uid()
        )
    );

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Update timestamp trigger
CREATE TRIGGER update_open_play_registrations_updated_at
    BEFORE UPDATE ON events.open_play_registrations
    FOR EACH ROW EXECUTE FUNCTION events.update_updated_at();

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

-- Grant SELECT to authenticated users
GRANT SELECT ON events.open_play_registrations TO authenticated;
GRANT INSERT, UPDATE ON events.open_play_registrations TO authenticated;

-- Grant all to service_role
GRANT ALL ON events.open_play_registrations TO service_role;

-- Grant execute on functions
GRANT EXECUTE ON FUNCTION events.calculate_open_play_fee TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION events.get_skill_level_capacity TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION api.register_for_open_play TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION api.cancel_open_play_registration TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION api.get_open_play_registrations TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION api.get_player_open_play_history TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION api.get_upcoming_open_play_schedule TO authenticated, anon, service_role;
-- ============================================================================
-- MAKE CREATED_BY NULLABLE IN OPEN PLAY TABLES
-- Allows schedule creation without requiring admin_users record
-- ============================================================================

-- Drop foreign key constraints on created_by/updated_by
ALTER TABLE events.open_play_schedule_blocks
    DROP CONSTRAINT IF EXISTS open_play_schedule_blocks_created_by_fkey,
    DROP CONSTRAINT IF EXISTS open_play_schedule_blocks_updated_by_fkey;

ALTER TABLE events.open_play_schedule_overrides
    DROP CONSTRAINT IF EXISTS open_play_schedule_overrides_created_by_fkey;

-- Make created_by and updated_by nullable in schedule blocks
ALTER TABLE events.open_play_schedule_blocks
    ALTER COLUMN created_by DROP NOT NULL,
    ALTER COLUMN updated_by DROP NOT NULL;

-- Make created_by nullable in schedule overrides
ALTER TABLE events.open_play_schedule_overrides
    ALTER COLUMN created_by DROP NOT NULL;

COMMENT ON COLUMN events.open_play_schedule_blocks.created_by IS 'Admin user who created this block (nullable, no FK constraint for Supabase Auth compatibility)';
COMMENT ON COLUMN events.open_play_schedule_blocks.updated_by IS 'Admin user who last updated this block (nullable, no FK constraint for Supabase Auth compatibility)';
COMMENT ON COLUMN events.open_play_schedule_overrides.created_by IS 'Admin user who created this override (nullable, no FK constraint for Supabase Auth compatibility)';
-- ============================================================================
-- SECURITY HARDENING
-- Ensure critical tables enforce RLS and views run as SECURITY INVOKER
-- ============================================================================

SET search_path TO public;

-- ============================================================================
-- ENABLE RLS ON PUBLIC-FACING TABLES
-- ============================================================================

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('crowdfunding', 'benefit_allocations'),
      ('crowdfunding', 'benefit_usage_log'),
      ('events', 'events'),
      ('events', 'event_courts'),
      ('events', 'dupr_brackets'),
      ('app_auth', 'player_transactions'),
      ('app_auth', 'player_fees'),
      ('app_auth', 'membership_transactions'),
      ('public', 'v_site_url')
    ) AS t(schema_name, table_name)
  LOOP
    IF EXISTS (
      SELECT 1
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = r.schema_name
        AND c.relname = r.table_name
        AND c.relkind IN ('r', 'p')
    ) THEN
      EXECUTE format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY;', r.schema_name, r.table_name);
    END IF;
  END LOOP;
END;
$$;

-- ============================================================================
-- ENSURE VIEWS RUN WITH SECURITY INVOKER
-- ============================================================================

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('public', 'marketing_emails'),
      ('crowdfunding', 'v_backer_benefits_detailed'),
      ('crowdfunding', 'v_pending_merchandise_pickups'),
      ('public', 'v_backer_benefits_detailed'),
      ('public', 'contributions'),
      ('public', 'marketing_email_recipients'),
      ('crowdfunding', 'v_merchandise_summary'),
      ('public', 'founders_wall'),
      ('public', 'marketing_top_performing_emails'),
      ('public', 'marketing_email_analytics'),
      ('public', 'v_fulfillment_summary'),
      ('public', 'campaign_types'),
      ('crowdfunding', 'v_backer_benefit_summary'),
      ('crowdfunding', 'v_upcoming_events'),
      ('api', 'user_profiles'),
      ('public', 'launch_subscribers'),
      ('crowdfunding', 'v_pending_recognition_items'),
      ('crowdfunding', 'v_backer_summary'),
      ('public', 'contribution_tiers'),
      ('crowdfunding', 'v_fulfillment_summary'),
      ('public', 'marketing_campaign_overview'),
      ('public', 'v_backer_summary'),
      ('public', 'recognition_items'),
      ('crowdfunding', 'v_pending_fulfillment'),
      ('public', 'v_pending_fulfillment'),
      ('public', 'v_active_backer_benefits'),
      ('crowdfunding', 'v_active_court_sponsorships'),
      ('public', 'v_refundable_contributions'),
      ('crowdfunding', 'v_active_backer_benefits'),
      ('crowdfunding', 'v_refundable_contributions'),
      ('public', 'players'),
      ('crowdfunding', 'v_event_rsvp_summary'),
      ('public', 'backers')
    ) AS t(schema_name, view_name)
  LOOP
    EXECUTE format(
      'ALTER VIEW IF EXISTS %I.%I SET (security_invoker = true);',
      r.schema_name,
      r.view_name
    );
  END LOOP;
END;
$$;
