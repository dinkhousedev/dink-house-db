-- ============================================================================
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
GRANT EXECUTE ON FUNCTION api.update_user_avatar TO postgres;