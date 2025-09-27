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
GRANT EXECUTE ON FUNCTION api.get_current_user TO service_role;