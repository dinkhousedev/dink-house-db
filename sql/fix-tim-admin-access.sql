-- ============================================================================
-- FIX ADMIN ACCESS FOR contact@dinkhousepb.com
-- Deploy via: https://supabase.com/dashboard/project/wchxzbuuwssrnaxshseu/sql
-- ============================================================================

-- Step 1: Update JWT claims in Supabase auth.users
-- This adds the required app_metadata for role-based access
UPDATE auth.users
SET
  raw_app_meta_data = COALESCE(raw_app_meta_data, '{}'::jsonb) ||
  jsonb_build_object(
    'user_type', 'admin',
    'admin_role', 'super_admin',
    'email', 'contact@dinkhousepb.com'
  )
WHERE email = 'contact@dinkhousepb.com';

-- Step 2: Update the admin_users role to super_admin if needed
UPDATE app_auth.admin_users
SET role = 'super_admin'
WHERE email = 'contact@dinkhousepb.com';

-- Step 3: Verify the update
SELECT
  id,
  email,
  raw_app_meta_data,
  raw_user_meta_data
FROM auth.users
WHERE email = 'contact@dinkhousepb.com';

-- You should see app_metadata with:
-- {
--   "user_type": "admin",
--   "admin_role": "super_admin",
--   "email": "contact@dinkhousepb.com"
-- }

-- IMPORTANT: After running this, you MUST log out and log back in
-- for the new JWT claims to take effect!
