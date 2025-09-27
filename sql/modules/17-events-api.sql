-- ============================================================================
-- EVENTS API VIEWS MODULE
-- API views for the events system
-- ============================================================================

-- ============================================================================
-- CALENDAR VIEW
-- Main view for displaying events on the calendar
-- ============================================================================

CREATE OR REPLACE VIEW api.events_calendar_view AS
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
    e.current_registrations,
    e.waitlist_capacity,
    e.skill_levels,
    e.member_only,
    e.price_member,
    e.price_guest,
    e.is_published,
    e.is_cancelled,
    e.cancellation_reason,
    e.equipment_provided,
    e.special_instructions,

    -- Template info
    et.name AS template_name,

    -- Court information
    COALESCE(
        json_agg(
            json_build_object(
                'id', c.id,
                'court_number', c.court_number,
                'name', c.name,
                'surface_type', c.surface_type,
                'is_primary', ec.is_primary
            ) ORDER BY ec.is_primary DESC, c.court_number
        ) FILTER (WHERE c.id IS NOT NULL),
        '[]'::json
    ) AS courts,

    -- Registration status
    CASE
        WHEN e.current_registrations >= e.max_capacity THEN 'full'
        WHEN e.current_registrations >= e.max_capacity * 0.8 THEN 'almost_full'
        WHEN e.current_registrations < e.min_capacity THEN 'needs_players'
        ELSE 'open'
    END AS registration_status,

    -- Series information
    esi.series_id,
    es.series_name,
    rp.frequency AS recurrence_frequency,

    -- Metadata
    e.created_by,
    e.created_at,
    e.updated_at
FROM
    events.events e
    LEFT JOIN events.event_templates et ON e.template_id = et.id
    LEFT JOIN events.event_courts ec ON e.id = ec.event_id
    LEFT JOIN events.courts c ON ec.court_id = c.id
    LEFT JOIN events.event_series_instances esi ON e.id = esi.event_id
    LEFT JOIN events.event_series es ON esi.series_id = es.id
    LEFT JOIN events.recurrence_patterns rp ON es.recurrence_pattern_id = rp.id
GROUP BY
    e.id, et.name, esi.series_id, es.series_name, rp.frequency;

COMMENT ON VIEW api.events_calendar_view IS 'Main calendar view with event details and court assignments';

-- ============================================================================
-- COURT AVAILABILITY VIEW
-- Shows court availability for scheduling
-- ============================================================================

CREATE OR REPLACE VIEW api.court_availability_view AS
WITH court_bookings AS (
    SELECT
        ec.court_id,
        e.start_time,
        e.end_time,
        e.title AS event_title,
        e.event_type
    FROM
        events.event_courts ec
        INNER JOIN events.events e ON ec.event_id = e.id
    WHERE
        e.is_cancelled = false
)
SELECT
    c.id,
    c.court_number,
    c.name,
    c.surface_type,
    c.status,
    c.location,
    c.features,
    c.max_capacity,

    -- Current bookings
    COALESCE(
        json_agg(
            json_build_object(
                'start_time', cb.start_time,
                'end_time', cb.end_time,
                'event_title', cb.event_title,
                'event_type', cb.event_type
            ) ORDER BY cb.start_time
        ) FILTER (WHERE cb.court_id IS NOT NULL),
        '[]'::json
    ) AS bookings,

    -- Availability overrides
    COALESCE(
        json_agg(
            json_build_object(
                'date', ca.date,
                'start_time', ca.start_time,
                'end_time', ca.end_time,
                'is_available', ca.is_available,
                'reason', ca.reason
            ) ORDER BY ca.date, ca.start_time
        ) FILTER (WHERE ca.court_id IS NOT NULL),
        '[]'::json
    ) AS availability_schedule
FROM
    events.courts c
    LEFT JOIN court_bookings cb ON c.id = cb.court_id
    LEFT JOIN events.court_availability ca ON c.id = ca.court_id
GROUP BY
    c.id;

COMMENT ON VIEW api.court_availability_view IS 'Court availability with current bookings';

-- ============================================================================
-- EVENT TEMPLATES VIEW
-- Available templates for quick event creation
-- ============================================================================

CREATE OR REPLACE VIEW api.event_templates_view AS
SELECT
    et.id,
    et.name,
    et.description,
    et.event_type,
    et.duration_minutes,
    et.max_capacity,
    et.min_capacity,
    et.skill_levels,
    et.price_member,
    et.price_guest,
    et.court_preferences,
    et.equipment_provided,
    et.settings,
    et.is_active,

    -- Usage statistics
    COUNT(e.id) AS times_used,
    MAX(e.created_at) AS last_used,

    et.created_by,
    et.created_at,
    et.updated_at
FROM
    events.event_templates et
    LEFT JOIN events.events e ON et.id = e.template_id
WHERE
    et.is_active = true
GROUP BY
    et.id
ORDER BY
    COUNT(e.id) DESC, et.name;

COMMENT ON VIEW api.event_templates_view IS 'Active event templates with usage stats';

-- ============================================================================
-- EVENT REGISTRATIONS VIEW
-- Player registrations with details
-- ============================================================================

CREATE OR REPLACE VIEW api.event_registrations_view AS
SELECT
    er.id,
    er.event_id,
    er.user_id,
    er.player_name,
    er.player_email,
    er.player_phone,
    er.skill_level,
    er.status,
    er.registration_time,
    er.check_in_time,
    er.amount_paid,
    er.payment_method,
    er.notes,
    er.special_requests,

    -- Event details
    e.title AS event_title,
    e.event_type,
    e.start_time AS event_start_time,
    e.end_time AS event_end_time,

    -- Player details (if registered user)
    COALESCE(ua.email, er.player_email) AS user_email,
    COALESCE(p.first_name || ' ' || p.last_name, er.player_name) AS user_full_name,

    er.created_at,
    er.updated_at
FROM
    events.event_registrations er
    INNER JOIN events.events e ON er.event_id = e.id
    LEFT JOIN app_auth.players p ON er.user_id = p.id
    LEFT JOIN app_auth.user_accounts ua ON ua.id = p.account_id
ORDER BY
    er.registration_time DESC;

COMMENT ON VIEW api.event_registrations_view IS 'Event registrations with player and event details';

-- ============================================================================
-- COURT SCHEDULE VIEW
-- Timeline view of court usage
-- ============================================================================

CREATE OR REPLACE VIEW api.court_schedule_view AS
SELECT
    c.id AS court_id,
    c.court_number,
    c.name AS court_name,
    e.id AS event_id,
    e.title AS event_title,
    e.event_type,
    e.start_time,
    e.end_time,
    e.current_registrations,
    e.max_capacity,
    ec.is_primary,

    -- Duration in minutes
    EXTRACT(EPOCH FROM (e.end_time - e.start_time)) / 60 AS duration_minutes,

    -- Time slot info
    DATE(e.start_time AT TIME ZONE 'America/New_York') AS event_date,
    TO_CHAR(e.start_time AT TIME ZONE 'America/New_York', 'HH24:MI') AS start_time_formatted,
    TO_CHAR(e.end_time AT TIME ZONE 'America/New_York', 'HH24:MI') AS end_time_formatted
FROM
    events.courts c
    LEFT JOIN events.event_courts ec ON c.id = ec.court_id
    LEFT JOIN events.events e ON ec.event_id = e.id AND e.is_cancelled = false
WHERE
    c.status = 'available'
ORDER BY
    c.court_number, e.start_time;

COMMENT ON VIEW api.court_schedule_view IS 'Court schedule timeline view';

-- ============================================================================
-- UPCOMING EVENTS VIEW
-- Events happening in the near future
-- ============================================================================

CREATE OR REPLACE VIEW api.upcoming_events_view AS
SELECT
    e.id,
    e.title,
    e.event_type,
    e.start_time,
    e.end_time,
    e.max_capacity,
    e.current_registrations,
    e.skill_levels,
    e.price_member,
    e.price_guest,

    -- Registration availability
    e.max_capacity - e.current_registrations AS spots_available,
    CASE
        WHEN e.current_registrations >= e.max_capacity THEN 'full'
        WHEN e.start_time <= NOW() THEN 'in_progress'
        WHEN e.start_time <= NOW() + INTERVAL '24 hours' THEN 'starting_soon'
        ELSE 'open'
    END AS status,

    -- Courts
    STRING_AGG(c.name, ', ' ORDER BY c.court_number) AS court_names,

    -- Time until event
    e.start_time - NOW() AS time_until_start
FROM
    events.events e
    LEFT JOIN events.event_courts ec ON e.id = ec.event_id
    LEFT JOIN events.courts c ON ec.court_id = c.id
WHERE
    e.is_published = true
    AND e.is_cancelled = false
    AND e.start_time > NOW()
    AND e.start_time <= NOW() + INTERVAL '7 days'
GROUP BY
    e.id
ORDER BY
    e.start_time;

COMMENT ON VIEW api.upcoming_events_view IS 'Events happening in the next 7 days';

-- ============================================================================
-- EVENT SERIES VIEW
-- Recurring event series with patterns
-- ============================================================================

CREATE OR REPLACE VIEW api.event_series_view AS
SELECT
    es.id AS series_id,
    es.series_name,
    es.parent_event_id,
    rp.frequency,
    rp.interval_count,
    rp.days_of_week,
    rp.day_of_month,
    rp.week_of_month,
    rp.series_start_date,
    rp.series_end_date,
    rp.occurrences_count,

    -- Parent event details
    pe.title AS parent_event_title,
    pe.event_type,
    EXTRACT(EPOCH FROM (pe.end_time - pe.start_time))/60 AS duration_minutes,

    -- Instance count
    COUNT(esi.id) AS total_instances,
    COUNT(esi.id) FILTER (WHERE esi.is_exception = false) AS regular_instances,
    COUNT(esi.id) FILTER (WHERE esi.is_exception = true) AS exception_instances,

    -- Next occurrence
    MIN(e.start_time) FILTER (WHERE e.start_time > NOW()) AS next_occurrence,

    es.created_by,
    es.created_at
FROM
    events.event_series es
    LEFT JOIN events.recurrence_patterns rp ON es.recurrence_pattern_id = rp.id
    LEFT JOIN events.events pe ON es.parent_event_id = pe.id
    LEFT JOIN events.event_series_instances esi ON es.id = esi.series_id
    LEFT JOIN events.events e ON esi.event_id = e.id
GROUP BY
    es.id, rp.id, pe.id, pe.start_time, pe.end_time;

COMMENT ON VIEW api.event_series_view IS 'Recurring event series with pattern details';

-- ============================================================================
-- DAILY SCHEDULE VIEW
-- Simplified view for daily schedules
-- ============================================================================

CREATE OR REPLACE VIEW api.daily_schedule_view AS
SELECT
    DATE(e.start_time AT TIME ZONE 'America/New_York') AS schedule_date,
    e.id,
    e.title,
    e.event_type,
    e.start_time,
    e.end_time,
    TO_CHAR(e.start_time AT TIME ZONE 'America/New_York', 'HH12:MI AM') AS start_time_display,
    TO_CHAR(e.end_time AT TIME ZONE 'America/New_York', 'HH12:MI AM') AS end_time_display,
    e.current_registrations,
    e.max_capacity,
    e.skill_levels,

    -- Courts
    ARRAY_AGG(c.court_number ORDER BY c.court_number) AS court_numbers,

    -- Color coding helper
    CASE e.event_type
        WHEN 'scramble' THEN '#B3FF00'      -- Lime
        WHEN 'dupr' THEN '#0EA5E9'          -- Blue
        WHEN 'open_play' THEN '#FB923C'     -- Orange
        WHEN 'tournament' THEN '#EF4444'     -- Red
        WHEN 'league' THEN '#8B5CF6'        -- Purple
        WHEN 'clinic' THEN '#10B981'        -- Green
        WHEN 'private_lesson' THEN '#64748B' -- Gray
        ELSE '#6B7280'
    END AS event_color
FROM
    events.events e
    LEFT JOIN events.event_courts ec ON e.id = ec.event_id
    LEFT JOIN events.courts c ON ec.court_id = c.id
WHERE
    e.is_published = true
    AND e.is_cancelled = false
GROUP BY
    e.id
ORDER BY
    e.start_time;

COMMENT ON VIEW api.daily_schedule_view IS 'Daily event schedule with display formatting';

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

-- Grant select on all views to authenticated users
GRANT SELECT ON api.events_calendar_view TO authenticated;
GRANT SELECT ON api.court_availability_view TO authenticated;
GRANT SELECT ON api.event_templates_view TO authenticated;
GRANT SELECT ON api.event_registrations_view TO authenticated;
GRANT SELECT ON api.court_schedule_view TO authenticated;
GRANT SELECT ON api.upcoming_events_view TO authenticated;
GRANT SELECT ON api.event_series_view TO authenticated;
GRANT SELECT ON api.daily_schedule_view TO authenticated;

-- Grant select on views to anon for public events
GRANT SELECT ON api.upcoming_events_view TO anon;
GRANT SELECT ON api.daily_schedule_view TO anon;
