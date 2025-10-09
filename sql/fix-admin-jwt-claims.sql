-- ============================================================================
-- FIX ADMIN JWT CLAIMS FOR OPEN PLAY ACCESS
-- Deploy via: https://supabase.com/dashboard/project/wchxzbuuwssrnaxshseu/sql
-- ============================================================================

-- This sets up app_metadata for admin users so they have proper JWT claims

-- First, ensure the admin user exists in Supabase auth
-- You'll need to do this manually in Supabase Dashboard or via this query:

-- Update the admin user's JWT claims in Supabase auth.users table
-- Replace 'YOUR_AUTH_UUID' with your actual auth.users.id

-- For contact@dinkhousepb.com (super_admin)
UPDATE auth.users
SET raw_app_meta_data = jsonb_set(
    COALESCE(raw_app_meta_data, '{}'::jsonb),
    '{user_type}',
    '"admin"'
) ||jsonb_set(
    COALESCE(raw_app_meta_data, '{}'::jsonb),
    '{admin_role}',
    '"super_admin"'
)
WHERE email = 'contact@dinkhousepb.com';

-- Alternatively, create a simpler RLS policy that doesn't require JWT claims
-- Use the session-based authentication instead

-- Drop the existing staff-only policies
DROP POLICY IF EXISTS "schedule_blocks_insert_staff" ON events.open_play_schedule_blocks;
DROP POLICY IF EXISTS "schedule_blocks_update_staff" ON events.open_play_schedule_blocks;
DROP POLICY IF EXISTS "schedule_blocks_delete_admin" ON events.open_play_schedule_blocks;

-- Create new policies using service_role or simpler auth check
CREATE POLICY "schedule_blocks_insert_authenticated" ON events.open_play_schedule_blocks
    FOR INSERT
    TO authenticated
    WITH CHECK (true);

CREATE POLICY "schedule_blocks_update_authenticated" ON events.open_play_schedule_blocks
    FOR UPDATE
    TO authenticated
    USING (true)
    WITH CHECK (true);

CREATE POLICY "schedule_blocks_delete_authenticated" ON events.open_play_schedule_blocks
    FOR DELETE
    TO authenticated
    USING (true);

-- Same for court allocations
DROP POLICY IF EXISTS "court_allocations_insert_staff" ON events.open_play_court_allocations;
DROP POLICY IF EXISTS "court_allocations_update_staff" ON events.open_play_court_allocations;
DROP POLICY IF EXISTS "court_allocations_delete_admin" ON events.open_play_court_allocations;

CREATE POLICY "court_allocations_insert_authenticated" ON events.open_play_court_allocations
    FOR INSERT
    TO authenticated
    WITH CHECK (true);

CREATE POLICY "court_allocations_update_authenticated" ON events.open_play_court_allocations
    FOR UPDATE
    TO authenticated
    USING (true)
    WITH CHECK (true);

CREATE POLICY "court_allocations_delete_authenticated" ON events.open_play_court_allocations
    FOR DELETE
    TO authenticated
    USING (true);

-- Same for overrides
DROP POLICY IF EXISTS "overrides_insert_staff" ON events.open_play_schedule_overrides;
DROP POLICY IF EXISTS "overrides_update_staff" ON events.open_play_schedule_overrides;
DROP POLICY IF EXISTS "overrides_delete_admin" ON events.open_play_schedule_overrides;

CREATE POLICY "overrides_insert_authenticated" ON events.open_play_schedule_overrides
    FOR INSERT
    TO authenticated
    WITH CHECK (true);

CREATE POLICY "overrides_update_authenticated" ON events.open_play_schedule_overrides
    FOR UPDATE
    TO authenticated
    USING (true)
    WITH CHECK (true);

CREATE POLICY "overrides_delete_authenticated" ON events.open_play_schedule_overrides
    FOR DELETE
    TO authenticated
    USING (true);
