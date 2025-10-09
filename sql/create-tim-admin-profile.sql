-- ============================================================================
-- CREATE ADMIN PROFILE FOR contact@dinkhousepb.com
-- ============================================================================

-- First, check if user_accounts record exists
DO $$
DECLARE
    v_account_id UUID;
    v_admin_id UUID;
    v_auth_id UUID := 'f6bf49ca-142a-4088-aa51-30f3bf5ba922';
BEGIN
    -- Check if user_accounts exists
    SELECT id INTO v_account_id
    FROM app_auth.user_accounts
    WHERE auth_id = v_auth_id;

    -- If no user_accounts record, create it
    IF v_account_id IS NULL THEN
        INSERT INTO app_auth.user_accounts (
            auth_id,
            email,
            user_type,
            is_active,
            is_verified
        ) VALUES (
            v_auth_id,
            'contact@dinkhousepb.com',
            'admin',
            true,
            true
        )
        RETURNING id INTO v_account_id;

        RAISE NOTICE 'Created user_accounts record: %', v_account_id;
    ELSE
        RAISE NOTICE 'user_accounts already exists: %', v_account_id;
    END IF;

    -- Check if admin_users record exists
    SELECT id INTO v_admin_id
    FROM app_auth.admin_users
    WHERE account_id = v_account_id;

    -- If no admin_users record, create it
    IF v_admin_id IS NULL THEN
        INSERT INTO app_auth.admin_users (
            account_id,
            username,
            first_name,
            last_name,
            role
        ) VALUES (
            v_account_id,
            'tim.carrender',
            'Tim',
            'Carrender',
            'super_admin'
        )
        RETURNING id INTO v_admin_id;

        RAISE NOTICE 'Created admin_users record: %', v_admin_id;
    ELSE
        RAISE NOTICE 'admin_users already exists: %', v_admin_id;
    END IF;
END $$;

-- Verify the complete profile
SELECT
    u.id as auth_id,
    u.email,
    u.raw_app_meta_data->>'user_type' as jwt_user_type,
    u.raw_app_meta_data->>'admin_role' as jwt_admin_role,
    ua.id as account_id,
    ua.user_type as account_user_type,
    au.id as admin_id,
    au.username,
    au.first_name,
    au.last_name,
    au.role as admin_role
FROM auth.users u
LEFT JOIN app_auth.user_accounts ua ON ua.auth_id = u.id
LEFT JOIN app_auth.admin_users au ON au.account_id = ua.id
WHERE u.email = 'contact@dinkhousepb.com';
