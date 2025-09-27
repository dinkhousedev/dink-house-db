-- ============================================================================
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
    date_of_birth DATE,
    membership_level app_auth.membership_level DEFAULT 'guest',
    membership_started_on DATE,
    membership_expires_on DATE,
    skill_level app_auth.skill_level,
    club_id UUID,
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
