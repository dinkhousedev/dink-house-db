-- ============================================================================
-- EVENTS RLS POLICIES MODULE
-- Row Level Security policies for events system
-- ============================================================================

-- Enable RLS on all events tables
ALTER TABLE events.courts ENABLE ROW LEVEL SECURITY;
ALTER TABLE events.event_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE events.events ENABLE ROW LEVEL SECURITY;
ALTER TABLE events.event_courts ENABLE ROW LEVEL SECURITY;
ALTER TABLE events.recurrence_patterns ENABLE ROW LEVEL SECURITY;
ALTER TABLE events.event_series ENABLE ROW LEVEL SECURITY;
ALTER TABLE events.event_series_instances ENABLE ROW LEVEL SECURITY;
ALTER TABLE events.event_exceptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE events.event_registrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE events.court_availability ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Check if user is admin or manager
CREATE OR REPLACE FUNCTION events.is_admin_or_manager()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1
        FROM app_auth.users
        WHERE id = auth.uid()
        AND (
            raw_user_meta_data->>'role' IN ('admin', 'manager')
            OR raw_user_meta_data->>'is_admin' = 'true'
        )
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Check if user is staff (admin, manager, or coach)
CREATE OR REPLACE FUNCTION events.is_staff()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1
        FROM app_auth.users
        WHERE id = auth.uid()
        AND raw_user_meta_data->>'role' IN ('admin', 'manager', 'coach')
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- COURTS POLICIES
-- ============================================================================

-- Courts: Everyone can view
CREATE POLICY "courts_select_all" ON events.courts
    FOR SELECT
    USING (true);

-- Courts: Only admins can insert
CREATE POLICY "courts_insert_admin" ON events.courts
    FOR INSERT
    WITH CHECK (events.is_admin_or_manager());

-- Courts: Only admins can update
CREATE POLICY "courts_update_admin" ON events.courts
    FOR UPDATE
    USING (events.is_admin_or_manager())
    WITH CHECK (events.is_admin_or_manager());

-- Courts: Only admins can delete
CREATE POLICY "courts_delete_admin" ON events.courts
    FOR DELETE
    USING (events.is_admin_or_manager());

-- ============================================================================
-- EVENT TEMPLATES POLICIES
-- ============================================================================

-- Templates: Staff can view all active templates
CREATE POLICY "templates_select_staff" ON events.event_templates
    FOR SELECT
    USING (
        is_active = true
        OR created_by = auth.uid()
        OR events.is_staff()
    );

-- Templates: Staff can create
CREATE POLICY "templates_insert_staff" ON events.event_templates
    FOR INSERT
    WITH CHECK (
        events.is_staff()
        AND created_by = auth.uid()
    );

-- Templates: Creators and admins can update
CREATE POLICY "templates_update_owner_admin" ON events.event_templates
    FOR UPDATE
    USING (
        created_by = auth.uid()
        OR events.is_admin_or_manager()
    )
    WITH CHECK (
        created_by = auth.uid()
        OR events.is_admin_or_manager()
    );

-- Templates: Only admins can delete
CREATE POLICY "templates_delete_admin" ON events.event_templates
    FOR DELETE
    USING (events.is_admin_or_manager());

-- ============================================================================
-- EVENTS POLICIES
-- ============================================================================

-- Events: Everyone can view published events
CREATE POLICY "events_select_published" ON events.events
    FOR SELECT
    USING (
        is_published = true
        OR created_by = auth.uid()
        OR events.is_staff()
    );

-- Events: Staff can create
CREATE POLICY "events_insert_staff" ON events.events
    FOR INSERT
    WITH CHECK (
        events.is_staff()
        AND created_by = auth.uid()
    );

-- Events: Creators and admins can update
CREATE POLICY "events_update_owner_admin" ON events.events
    FOR UPDATE
    USING (
        created_by = auth.uid()
        OR events.is_admin_or_manager()
    )
    WITH CHECK (
        created_by = auth.uid()
        OR events.is_admin_or_manager()
    );

-- Events: Only admins can delete
CREATE POLICY "events_delete_admin" ON events.events
    FOR DELETE
    USING (events.is_admin_or_manager());

-- ============================================================================
-- EVENT COURTS POLICIES
-- ============================================================================

-- Event Courts: View if can view event
CREATE POLICY "event_courts_select" ON events.event_courts
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM events.events e
            WHERE e.id = event_courts.event_id
            AND (
                e.is_published = true
                OR e.created_by = auth.uid()
                OR events.is_staff()
            )
        )
    );

-- Event Courts: Staff can manage
CREATE POLICY "event_courts_insert_staff" ON events.event_courts
    FOR INSERT
    WITH CHECK (events.is_staff());

CREATE POLICY "event_courts_update_staff" ON events.event_courts
    FOR UPDATE
    USING (events.is_staff())
    WITH CHECK (events.is_staff());

CREATE POLICY "event_courts_delete_staff" ON events.event_courts
    FOR DELETE
    USING (events.is_staff());

-- ============================================================================
-- RECURRENCE PATTERNS POLICIES
-- ============================================================================

-- Recurrence: Staff only
CREATE POLICY "recurrence_select_staff" ON events.recurrence_patterns
    FOR SELECT
    USING (events.is_staff());

CREATE POLICY "recurrence_insert_staff" ON events.recurrence_patterns
    FOR INSERT
    WITH CHECK (events.is_staff());

CREATE POLICY "recurrence_update_staff" ON events.recurrence_patterns
    FOR UPDATE
    USING (events.is_staff())
    WITH CHECK (events.is_staff());

CREATE POLICY "recurrence_delete_admin" ON events.recurrence_patterns
    FOR DELETE
    USING (events.is_admin_or_manager());

-- ============================================================================
-- EVENT SERIES POLICIES
-- ============================================================================

-- Series: Staff only
CREATE POLICY "series_select_staff" ON events.event_series
    FOR SELECT
    USING (events.is_staff());

CREATE POLICY "series_insert_staff" ON events.event_series
    FOR INSERT
    WITH CHECK (
        events.is_staff()
        AND created_by = auth.uid()
    );

CREATE POLICY "series_update_admin" ON events.event_series
    FOR UPDATE
    USING (events.is_admin_or_manager())
    WITH CHECK (events.is_admin_or_manager());

CREATE POLICY "series_delete_admin" ON events.event_series
    FOR DELETE
    USING (events.is_admin_or_manager());

-- ============================================================================
-- EVENT SERIES INSTANCES POLICIES
-- ============================================================================

-- Series Instances: Staff only
CREATE POLICY "series_instances_select_staff" ON events.event_series_instances
    FOR SELECT
    USING (events.is_staff());

CREATE POLICY "series_instances_insert_staff" ON events.event_series_instances
    FOR INSERT
    WITH CHECK (events.is_staff());

CREATE POLICY "series_instances_update_staff" ON events.event_series_instances
    FOR UPDATE
    USING (events.is_staff())
    WITH CHECK (events.is_staff());

CREATE POLICY "series_instances_delete_admin" ON events.event_series_instances
    FOR DELETE
    USING (events.is_admin_or_manager());

-- ============================================================================
-- EVENT EXCEPTIONS POLICIES
-- ============================================================================

-- Exceptions: Staff only
CREATE POLICY "exceptions_select_staff" ON events.event_exceptions
    FOR SELECT
    USING (events.is_staff());

CREATE POLICY "exceptions_insert_staff" ON events.event_exceptions
    FOR INSERT
    WITH CHECK (events.is_staff());

CREATE POLICY "exceptions_update_staff" ON events.event_exceptions
    FOR UPDATE
    USING (events.is_staff())
    WITH CHECK (events.is_staff());

CREATE POLICY "exceptions_delete_staff" ON events.event_exceptions
    FOR DELETE
    USING (events.is_staff());

-- ============================================================================
-- EVENT REGISTRATIONS POLICIES
-- ============================================================================

-- Registrations: View own or if staff
CREATE POLICY "registrations_select_own_or_staff" ON events.event_registrations
    FOR SELECT
    USING (
        user_id = auth.uid()
        OR events.is_staff()
        OR EXISTS (
            SELECT 1 FROM events.events e
            WHERE e.id = event_registrations.event_id
            AND e.created_by = auth.uid()
        )
    );

-- Registrations: Anyone can register (with business logic checks)
CREATE POLICY "registrations_insert_authenticated" ON events.event_registrations
    FOR INSERT
    WITH CHECK (
        -- User registering themselves
        (user_id = auth.uid() OR user_id IS NULL)
        -- Event must be published and not cancelled
        AND EXISTS (
            SELECT 1 FROM events.events e
            WHERE e.id = event_registrations.event_id
            AND e.is_published = true
            AND e.is_cancelled = false
            AND e.start_time > NOW()
        )
    );

-- Registrations: Update own or if staff
CREATE POLICY "registrations_update_own_or_staff" ON events.event_registrations
    FOR UPDATE
    USING (
        user_id = auth.uid()
        OR events.is_staff()
    )
    WITH CHECK (
        user_id = auth.uid()
        OR events.is_staff()
    );

-- Registrations: Delete own or if staff
CREATE POLICY "registrations_delete_own_or_staff" ON events.event_registrations
    FOR DELETE
    USING (
        user_id = auth.uid()
        OR events.is_staff()
    );

-- ============================================================================
-- COURT AVAILABILITY POLICIES
-- ============================================================================

-- Court Availability: Everyone can view
CREATE POLICY "availability_select_all" ON events.court_availability
    FOR SELECT
    USING (true);

-- Court Availability: Staff can manage
CREATE POLICY "availability_insert_staff" ON events.court_availability
    FOR INSERT
    WITH CHECK (
        events.is_staff()
        AND created_by = auth.uid()
    );

CREATE POLICY "availability_update_staff" ON events.court_availability
    FOR UPDATE
    USING (events.is_staff())
    WITH CHECK (events.is_staff());

CREATE POLICY "availability_delete_admin" ON events.court_availability
    FOR DELETE
    USING (events.is_admin_or_manager());

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

-- Grant usage on events schema
GRANT USAGE ON SCHEMA events TO authenticated;
GRANT USAGE ON SCHEMA events TO anon;

-- Grant permissions on tables
GRANT SELECT ON ALL TABLES IN SCHEMA events TO authenticated;
GRANT SELECT ON events.courts, events.events TO anon;

-- Grant permissions for authenticated users to manage their registrations
GRANT INSERT, UPDATE, DELETE ON events.event_registrations TO authenticated;

-- Grant sequence permissions
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA events TO authenticated;