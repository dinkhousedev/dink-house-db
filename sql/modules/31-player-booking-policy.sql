-- ============================================================================
-- PLAYER BOOKING RLS POLICY
-- Allow authenticated players to create private lesson bookings
-- ============================================================================

-- Drop existing restrictive INSERT policy for events
DROP POLICY IF EXISTS "events_insert_staff" ON events.events;

-- Create new policy: Staff can create any event type
CREATE POLICY "events_insert_staff" ON events.events
    FOR INSERT
    WITH CHECK (
        events.is_staff()
        AND created_by = auth.uid()
    );

-- Create new policy: Players can create private bookings only
CREATE POLICY "events_insert_players_private_booking" ON events.events
    FOR INSERT
    WITH CHECK (
        auth.uid() IS NOT NULL
        AND event_type = 'private_booking'
        AND created_by = auth.uid()
        AND is_published = true  -- Player bookings are auto-published
    );

-- Drop existing restrictive INSERT policy for event_courts
DROP POLICY IF EXISTS "event_courts_insert_staff" ON events.event_courts;

-- Create new policy: Staff can assign any courts
CREATE POLICY "event_courts_insert_staff" ON events.event_courts
    FOR INSERT
    WITH CHECK (events.is_staff());

-- Create new policy: Players can assign courts to their own private booking events
CREATE POLICY "event_courts_insert_players" ON events.event_courts
    FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM events.events e
            WHERE e.id = event_courts.event_id
            AND e.created_by = auth.uid()
            AND e.event_type = 'private_booking'
        )
    );

COMMENT ON POLICY "events_insert_players_private_booking" ON events.events IS
    'Allow authenticated players to create private court bookings';

COMMENT ON POLICY "event_courts_insert_players" ON events.event_courts IS
    'Allow players to assign courts to their own private court bookings';
