-- ============================================================================
-- APPLICATION AUTHENTICATION MODULE
-- User management and session handling in app_auth schema
-- Note: This is separate from Supabase's auth schema
-- ============================================================================

-- Switch to app_auth schema
SET search_path TO app_auth, public;

-- Users table for authentication
CREATE TABLE IF NOT EXISTS app_auth.users (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    username public.CITEXT UNIQUE NOT NULL,
    email public.CITEXT UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    role VARCHAR(50) NOT NULL DEFAULT 'viewer'
        CHECK (role IN ('super_admin', 'admin', 'editor', 'viewer')),
    is_active BOOLEAN DEFAULT true,
    is_verified BOOLEAN DEFAULT false,
    verification_token VARCHAR(255),
    password_reset_token VARCHAR(255),
    password_reset_expires TIMESTAMP WITH TIME ZONE,
    last_login TIMESTAMP WITH TIME ZONE,
    failed_login_attempts INT DEFAULT 0,
    locked_until TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Sessions for authentication
CREATE TABLE IF NOT EXISTS app_auth.sessions (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES app_auth.users(id) ON DELETE CASCADE,
    token_hash VARCHAR(255) UNIQUE NOT NULL,
    ip_address INET,
    user_agent TEXT,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Refresh tokens for JWT
CREATE TABLE IF NOT EXISTS app_auth.refresh_tokens (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES app_auth.users(id) ON DELETE CASCADE,
    token_hash VARCHAR(255) UNIQUE NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    revoked_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- API keys for service authentication
CREATE TABLE IF NOT EXISTS app_auth.api_keys (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    user_id UUID REFERENCES app_auth.users(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    key_hash VARCHAR(255) UNIQUE NOT NULL,
    permissions JSONB DEFAULT '[]',
    last_used_at TIMESTAMP WITH TIME ZONE,
    expires_at TIMESTAMP WITH TIME ZONE,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for auth tables
CREATE INDEX idx_users_email ON app_auth.users(email);
CREATE INDEX idx_users_username ON app_auth.users(username);
CREATE INDEX idx_users_role ON app_auth.users(role);
CREATE INDEX idx_sessions_token_hash ON app_auth.sessions(token_hash);
CREATE INDEX idx_sessions_user_id ON app_auth.sessions(user_id);
CREATE INDEX idx_sessions_expires_at ON app_auth.sessions(expires_at);
CREATE INDEX idx_refresh_tokens_token_hash ON app_auth.refresh_tokens(token_hash);
CREATE INDEX idx_refresh_tokens_user_id ON app_auth.refresh_tokens(user_id);
CREATE INDEX idx_api_keys_key_hash ON app_auth.api_keys(key_hash);