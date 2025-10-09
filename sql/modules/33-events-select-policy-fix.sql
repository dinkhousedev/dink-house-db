-- ============================================================================
-- FIX EVENTS SELECT POLICY
-- Allow authenticated users to see all published events
-- ============================================================================

-- Drop the existing restrictive SELECT policy
DROP POLICY IF EXISTS "events_select_published" ON events.events;

-- Create new policy: Authenticated users can see published events and their own events
-- This avoids the admin_users permission issue
CREATE POLICY "events_select_published" ON events.events
    FOR SELECT
    USING (
        -- Anyone authenticated can see published events
        (auth.uid() IS NOT NULL AND is_published = true)
        -- Event creators can see their own events
        OR created_by = auth.uid()
    );

COMMENT ON POLICY "events_select_published" ON events.events IS
    'Allow viewing of published events by all authenticated users, and own events by creators';
