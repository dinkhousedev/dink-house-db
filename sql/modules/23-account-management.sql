-- ============================================================================
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
GRANT EXECUTE ON FUNCTION api.get_all_account_stats TO service_role;