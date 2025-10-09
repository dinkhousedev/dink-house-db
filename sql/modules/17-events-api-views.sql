-- ============================================================================
-- EVENTS API VIEWS
-- Create API views for courts and events in the api schema
-- ============================================================================

-- Switch to public schema
SET search_path TO public, events;

-- ============================================================================
-- COURTS VIEW (in public schema for Supabase API access)
-- ============================================================================

CREATE OR REPLACE VIEW public.courts_view AS
SELECT
    id,
    court_number,
    name,
    surface_type,
    environment,
    status,
    location,
    features,
    max_capacity,
    notes,
    created_at,
    updated_at
FROM events.courts
WHERE status IN ('available', 'reserved');

COMMENT ON VIEW public.courts_view IS 'Courts available via API';

-- Also create in api schema for consistency
CREATE OR REPLACE VIEW api.courts AS
SELECT * FROM public.courts_view;

-- ============================================================================
-- EVENTS CALENDAR VIEW (in public schema for Supabase API access)
-- ============================================================================

CREATE OR REPLACE VIEW public.events_view AS
SELECT
    e.id,
    e.title,
    e.description,
    e.event_type,
    e.start_time,
    e.end_time,
    e.check_in_time,
    e.max_capacity,
    e.min_capacity,
    e.price_member,
    e.price_guest,
    e.skill_levels,
    e.member_only,
    e.dupr_bracket_id,
    e.dupr_range_label,
    e.dupr_min_rating,
    e.dupr_max_rating,
    e.is_published,
    e.is_cancelled,
    e.equipment_provided,
    e.special_instructions,
    COALESCE((
        SELECT COUNT(*)
        FROM events.event_registrations er
        WHERE er.event_id = e.id
          AND er.status = 'registered'
    ), 0) AS current_registrations,
    (
        SELECT json_agg(
            json_build_object(
                'court_id', c.id,
                'court_number', c.court_number,
                'name', c.name,
                'environment', c.environment
            )
        )
        FROM events.event_courts ec
        JOIN events.courts c ON c.id = ec.court_id
        WHERE ec.event_id = e.id
    ) AS courts,
    e.created_at,
    e.updated_at
FROM events.events e
WHERE e.is_published = true
  AND e.is_cancelled = false;

COMMENT ON VIEW public.events_view IS 'Published events for calendar and player app';

-- Also create in api schema
CREATE OR REPLACE VIEW api.events_calendar_view AS
SELECT * FROM public.events_view;

-- ============================================================================
-- EVENT TEMPLATES VIEW
-- ============================================================================

CREATE OR REPLACE VIEW api.event_templates AS
SELECT
    id,
    name,
    description,
    event_type,
    duration_minutes,
    max_capacity,
    min_capacity,
    skill_levels,
    price_member,
    price_guest,
    equipment_provided,
    is_active,
    times_used,
    created_at,
    updated_at
FROM events.event_templates
WHERE is_active = true;

COMMENT ON VIEW api.event_templates IS 'Active event templates';

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

-- Grant SELECT to authenticated users
GRANT SELECT ON public.courts_view TO authenticated;
GRANT SELECT ON public.events_view TO authenticated;
GRANT SELECT ON api.courts TO authenticated;
GRANT SELECT ON api.events_calendar_view TO authenticated;
GRANT SELECT ON api.event_templates TO authenticated;

-- Grant SELECT on courts to anonymous users (for public booking pages)
GRANT SELECT ON public.courts_view TO anon;
GRANT SELECT ON public.events_view TO anon;
GRANT SELECT ON api.courts TO anon;
GRANT SELECT ON api.events_calendar_view TO anon;

-- ============================================================================
-- RPC FUNCTIONS (in public schema for Supabase API access)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.check_court_availability(
    p_court_ids UUID[],
    p_start_time TIMESTAMPTZ,
    p_end_time TIMESTAMPTZ,
    p_exclude_event_id UUID DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
    v_result JSON;
BEGIN
    WITH conflicts AS (
        SELECT
            ec.court_id,
            c.court_number,
            c.name AS court_name,
            e.id AS event_id,
            e.title AS event_title,
            e.start_time,
            e.end_time
        FROM events.event_courts ec
        JOIN events.events e ON ec.event_id = e.id
        JOIN events.courts c ON ec.court_id = c.id
        WHERE ec.court_id = ANY(p_court_ids)
        AND e.is_cancelled = false
        AND (p_exclude_event_id IS NULL OR e.id != p_exclude_event_id)
        AND (e.start_time, e.end_time) OVERLAPS (p_start_time, p_end_time)
    ),
    availability AS (
        SELECT
            c.id AS court_id,
            c.court_number,
            c.name AS court_name,
            c.status,
            CASE
                WHEN c.status != 'available' THEN false
                WHEN EXISTS (SELECT 1 FROM conflicts cf WHERE cf.court_id = c.id) THEN false
                ELSE true
            END AS is_available,
            (
                SELECT json_agg(json_build_object(
                    'event_id', cf.event_id,
                    'event_title', cf.event_title,
                    'start_time', cf.start_time,
                    'end_time', cf.end_time
                ))
                FROM conflicts cf
                WHERE cf.court_id = c.id
            ) AS conflicts
        FROM events.courts c
        WHERE c.id = ANY(p_court_ids)
    )
    SELECT json_object_agg(
        a.court_id,
        json_build_object(
            'court_id', a.court_id,
            'court_number', a.court_number,
            'court_name', a.court_name,
            'status', a.status,
            'available', a.is_available,
            'conflicts', COALESCE(a.conflicts, '[]'::json)
        )
    ) INTO v_result
    FROM availability a;

    RETURN COALESCE(v_result, '{}'::json);
END;
$$;

COMMENT ON FUNCTION public.check_court_availability IS 'Check court availability for booking';

-- Grant execute to authenticated and anonymous users
GRANT EXECUTE ON FUNCTION public.check_court_availability TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_court_availability TO anon;

-- Create court booking function
CREATE OR REPLACE FUNCTION public.create_court_booking(
    p_event_id UUID,
    p_player_id UUID,
    p_amount DECIMAL,
    p_booking_source VARCHAR DEFAULT 'player_app'
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_registration_id UUID;
    v_result JSON;
BEGIN
    -- Create event registration
    INSERT INTO events.event_registrations (
        event_id,
        user_id,
        amount_paid,
        payment_status,
        status,
        registration_source
    ) VALUES (
        p_event_id,
        p_player_id,
        p_amount,
        'pending',
        'registered',
        p_booking_source
    )
    RETURNING id INTO v_registration_id;

    -- Return registration details
    SELECT json_build_object(
        'id', v_registration_id,
        'event_id', p_event_id,
        'player_id', p_player_id,
        'amount', p_amount,
        'status', 'pending'
    ) INTO v_result;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.create_court_booking IS 'Create a court booking/event registration';

GRANT EXECUTE ON FUNCTION public.create_court_booking TO authenticated;
