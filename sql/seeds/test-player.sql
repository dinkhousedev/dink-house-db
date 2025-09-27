-- Create a test player account
-- This script creates a player account for testing

-- First, create the player account
DO $$
DECLARE
    v_result JSON;
BEGIN
    -- Create player account
    v_result := api.player_signup(
        p_email := 'john.player@example.com',
        p_password := 'PlayerTest123!',
        p_first_name := 'John',
        p_last_name := 'Player',
        p_display_name := 'John P',
        p_phone := '555-1234'
    );

    RAISE NOTICE 'Player signup result: %', v_result;

    -- Also create an admin account for comparison
    -- First add to allowed emails
    INSERT INTO app_auth.allowed_emails (email, first_name, last_name, role, is_active)
    VALUES ('jane.admin@example.com', 'Jane', 'Admin', 'admin', true)
    ON CONFLICT (email) DO UPDATE SET is_active = true;

    -- Create admin account
    v_result := api.register_user(
        p_email := 'jane.admin@example.com',
        p_username := 'janeadmin',
        p_password := 'AdminTest123!',
        p_first_name := 'Jane',
        p_last_name := 'Admin'
    );

    RAISE NOTICE 'Admin signup result: %', v_result;

    -- Verify the admin account (since they need email verification)
    UPDATE app_auth.user_accounts
    SET is_verified = true
    WHERE email = 'jane.admin@example.com';

    RAISE NOTICE '';
    RAISE NOTICE '=== Test Accounts Created ===';
    RAISE NOTICE '';
    RAISE NOTICE 'PLAYER ACCOUNT:';
    RAISE NOTICE 'Email: john.player@example.com';
    RAISE NOTICE 'Password: PlayerTest123!';
    RAISE NOTICE 'Expected: Should see "Players cannot access the admin platform"';
    RAISE NOTICE '';
    RAISE NOTICE 'ADMIN ACCOUNT:';
    RAISE NOTICE 'Email: jane.admin@example.com';
    RAISE NOTICE 'Password: AdminTest123!';
    RAISE NOTICE 'Expected: Should login successfully';

EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error: %', SQLERRM;
END;
$$;

-- Check the created accounts
SELECT
    ua.email,
    ua.user_type,
    ua.is_active,
    ua.is_verified,
    CASE
        WHEN au.id IS NOT NULL THEN 'Admin: ' || au.role
        WHEN p.id IS NOT NULL THEN 'Player: ' || p.membership_level
        ELSE 'Unknown'
    END as user_details
FROM app_auth.user_accounts ua
LEFT JOIN app_auth.admin_users au ON au.account_id = ua.id
LEFT JOIN app_auth.players p ON p.account_id = ua.id
WHERE ua.email IN ('john.player@example.com', 'jane.admin@example.com');