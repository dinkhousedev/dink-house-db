-- ============================================================================
-- FIX EVENT COURTS SELECT POLICY
-- Allow authenticated users to see courts for published events
-- ============================================================================

-- Drop the existing restrictive SELECT policy
DROP POLICY IF EXISTS "event_courts_select" ON events.event_courts;

-- Create new policy: All authenticated users can see event_courts
-- This is a junction table, security is enforced on the events table
CREATE POLICY "event_courts_select" ON events.event_courts
    FOR SELECT
    USING (auth.uid() IS NOT NULL);

COMMENT ON POLICY "event_courts_select" ON events.event_courts IS
    'Allow all authenticated users to view event court assignments - security is enforced on events table';
