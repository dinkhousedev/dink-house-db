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
        RETURN json_build_object('success', false, 'error', 'Invalid credentials');
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
    ELSIF v_account.user_type = 'player' THEN
        SELECT * INTO v_player
        FROM app_auth.players
        WHERE account_id = v_account.id;

        IF v_player IS NULL THEN
            RETURN json_build_object('success', false, 'error', 'Player profile not found');
        END IF;

        v_user_profile := jsonb_build_object(
            'id', v_player.id,
            'first_name', v_player.first_name,
            'last_name', v_player.last_name,
            'display_name', v_player.display_name,
            'membership_level', v_player.membership_level,
            'skill_level', v_player.skill_level
        );
    ELSE
        SELECT * INTO v_guest
        FROM app_auth.guest_users
        WHERE account_id = v_account.id;

        IF v_guest IS NULL THEN
            RETURN json_build_object('success', false, 'error', 'Guest profile not found');
        END IF;

        v_user_profile := jsonb_build_object(
            'id', v_guest.id,
            'display_name', v_guest.display_name,
            'expires_at', v_guest.expires_at
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

    -- Check if account is verified (guests are exempt)
    IF v_account.user_type <> 'guest' AND NOT v_account.is_verified THEN
        RETURN json_build_object('success', false, 'error', 'Please verify your email address');
    END IF;

    -- Guest-specific checks
    IF v_account.user_type = 'guest' THEN
        IF v_account.temporary_expires_at IS NULL OR v_account.temporary_expires_at < CURRENT_TIMESTAMP THEN
            RETURN json_build_object('success', false, 'error', 'Guest access has expired');
        END IF;

        IF v_guest IS NULL OR v_guest.expires_at < CURRENT_TIMESTAMP THEN
            RETURN json_build_object('success', false, 'error', 'Guest access has expired');
        END IF;

        v_session_ttl := INTERVAL '6 hours';
        v_refresh_ttl := INTERVAL '12 hours';
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
GRANT EXECUTE ON FUNCTION api.upsert_content TO authenticated;

-- Admin functions
GRANT EXECUTE ON FUNCTION api.get_system_stats TO authenticated;
