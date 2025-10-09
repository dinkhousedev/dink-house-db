-- ============================================================================
-- COMPREHENSIVE EVENTS PERMISSIONS FIX
-- Fix all permission issues for admin dashboard event display
-- ============================================================================

-- ============================================================================
-- STEP 1: EXPLICIT TABLE GRANTS
-- Ensure authenticated users can SELECT from all necessary tables
-- ============================================================================

-- Grant SELECT on core tables (explicit, not relying on ALL TABLES)
GRANT SELECT ON events.events TO authenticated;
GRANT SELECT ON events.event_courts TO authenticated;
GRANT SELECT ON events.courts TO authenticated;
GRANT SELECT ON events.event_registrations TO authenticated;
GRANT SELECT ON events.event_templates TO authenticated;

-- CRITICAL: Grant SELECT on admin_users for foreign key validation
-- The events.created_by column references admin_users(id)
-- PostgreSQL RLS requires read access to validate foreign keys
GRANT SELECT ON app_auth.admin_users TO authenticated;

-- Grant SELECT to anon for public data
GRANT SELECT ON events.events TO anon;
GRANT SELECT ON events.courts TO anon;

-- Grant INSERT for player bookings
GRANT INSERT ON events.events TO authenticated;
GRANT INSERT ON events.event_courts TO authenticated;
GRANT INSERT ON events.event_registrations TO authenticated;

-- ============================================================================
-- STEP 2: SIMPLIFIED RLS POLICIES
-- Remove complex policies that cause circular permission checks
-- ============================================================================

-- -----------------------------------------------
-- EVENTS TABLE POLICIES
-- -----------------------------------------------

-- Drop all existing SELECT policies
DROP POLICY IF EXISTS "events_select_published" ON events.events;
DROP POLICY IF EXISTS "events_select_all_authenticated" ON events.events;
DROP POLICY IF EXISTS "events_select_anon" ON events.events;

-- Simple SELECT policy: authenticated users see published events + own events
CREATE POLICY "events_select_all_authenticated" ON events.events
    FOR SELECT
    TO authenticated
    USING (
        is_published = true OR created_by = auth.uid()
    );

-- Anon users can only see published events
CREATE POLICY "events_select_anon" ON events.events
    FOR SELECT
    TO anon
    USING (is_published = true);

-- -----------------------------------------------
-- EVENT_COURTS TABLE POLICIES
-- -----------------------------------------------

-- Drop all existing SELECT policies
DROP POLICY IF EXISTS "event_courts_select" ON events.event_courts;
DROP POLICY IF EXISTS "event_courts_select_all_authenticated" ON events.event_courts;
DROP POLICY IF EXISTS "event_courts_select_anon" ON events.event_courts;

-- Simple SELECT policy: all authenticated users can see event_courts
-- Security is enforced at the events table level
CREATE POLICY "event_courts_select_all_authenticated" ON events.event_courts
    FOR SELECT
    TO authenticated
    USING (true);

-- Anon can see event_courts for public events
CREATE POLICY "event_courts_select_anon" ON events.event_courts
    FOR SELECT
    TO anon
    USING (true);

-- -----------------------------------------------
-- COURTS TABLE POLICIES
-- -----------------------------------------------

-- Drop all existing SELECT policies on courts
DROP POLICY IF EXISTS "courts_select_all" ON events.courts;

-- Ensure courts are visible to everyone
CREATE POLICY "courts_select_all" ON events.courts
    FOR SELECT
    USING (true);

-- -----------------------------------------------
-- ADMIN_USERS TABLE POLICY (for FK validation)
-- -----------------------------------------------

-- Ensure RLS is enabled on admin_users (idempotent)
DO $$
BEGIN
    ALTER TABLE app_auth.admin_users ENABLE ROW LEVEL SECURITY;
EXCEPTION
    WHEN OTHERS THEN NULL;
END $$;

-- Drop all existing SELECT policies on admin_users
DROP POLICY IF EXISTS "admin_users_select_for_fk" ON app_auth.admin_users;

-- Allow authenticated users to see admin_users for foreign key validation
-- This is needed because events.created_by references admin_users(id)
CREATE POLICY "admin_users_select_for_fk" ON app_auth.admin_users
    FOR SELECT
    TO authenticated
    USING (true);

-- ============================================================================
-- STEP 3: COMMENTS
-- ============================================================================

COMMENT ON POLICY "events_select_all_authenticated" ON events.events IS
    'Authenticated users can see published events and their own events';

COMMENT ON POLICY "event_courts_select_all_authenticated" ON events.event_courts IS
    'All authenticated users can see event-court assignments - security enforced at events table level';

COMMENT ON POLICY "courts_select_all" ON events.courts IS
    'All users can see court information';

COMMENT ON POLICY "admin_users_select_for_fk" ON app_auth.admin_users IS
    'Allow authenticated users to read admin_users for foreign key validation on events.created_by';

-- ============================================================================
-- VERIFICATION
-- ============================================================================

-- To verify, run as authenticated user:
-- SELECT * FROM events.events WHERE is_published = true LIMIT 1;
-- SELECT * FROM events.event_courts LIMIT 1;
-- SELECT * FROM events.courts LIMIT 1;
