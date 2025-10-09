-- ============================================================================
-- FIX ADMIN ACCESS FOR contact@dinkhousepb.com (CORRECTED)
-- Deploy via: https://supabase.com/dashboard/project/wchxzbuuwssrnaxshseu/sql
-- ============================================================================

-- Step 1: Update JWT claims in Supabase auth.users
UPDATE auth.users
SET raw_app_meta_data = COALESCE(raw_app_meta_data, '{}'::jsonb) ||
    jsonb_build_object(
        'user_type', 'admin',
        'admin_role', 'super_admin'
    )
WHERE email = 'contact@dinkhousepb.com';

-- Step 2: Update the admin_users role to super_admin
UPDATE app_auth.admin_users
SET role = 'super_admin'
WHERE account_id IN (
    SELECT id FROM app_auth.user_accounts
    WHERE email = 'contact@dinkhousepb.com'
);

-- Step 3: Verify the updates
SELECT
    u.id as auth_id,
    u.email,
    u.raw_app_meta_data,
    au.id as admin_id,
    au.username,
    au.first_name,
    au.last_name,
    au.role
FROM auth.users u
LEFT JOIN app_auth.user_accounts ua ON ua.email = u.email
LEFT JOIN app_auth.admin_users au ON au.account_id = ua.id
WHERE u.email = 'contact@dinkhousepb.com';

-- You should see:
-- - raw_app_meta_data with user_type and admin_role
-- - role = 'super_admin'
