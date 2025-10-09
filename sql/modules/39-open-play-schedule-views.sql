-- ============================================================================
-- OPEN PLAY SCHEDULE ADMIN VIEWS
-- Convenient views for admin dashboard and schedule management
-- ============================================================================

-- ============================================================================
-- WEEKLY SCHEDULE OVERVIEW
-- Visual overview of the entire weekly schedule
-- ============================================================================

CREATE OR REPLACE VIEW events.admin_weekly_schedule_overview AS
SELECT
    opsb.id AS block_id,
    opsb.day_of_week,
    CASE opsb.day_of_week
        WHEN 0 THEN 'Sunday'
        WHEN 1 THEN 'Monday'
        WHEN 2 THEN 'Tuesday'
        WHEN 3 THEN 'Wednesday'
        WHEN 4 THEN 'Thursday'
        WHEN 5 THEN 'Friday'
        WHEN 6 THEN 'Saturday'
    END AS day_name,
    opsb.start_time,
    opsb.end_time,
    EXTRACT(EPOCH FROM (opsb.end_time - opsb.start_time)) / 3600 AS duration_hours,
    opsb.name,
    opsb.session_type,
    opsb.special_event_name,
    opsb.dedicated_skill_label,
    opsb.price_member,
    opsb.price_guest,
    opsb.max_capacity,
    opsb.is_active,
    COUNT(opca.id) AS courts_allocated,
    STRING_AGG(DISTINCT opca.skill_level_label, ', ' ORDER BY opca.skill_level_label) AS skill_levels,
    opsb.created_at,
    opsb.updated_at
FROM events.open_play_schedule_blocks opsb
LEFT JOIN events.open_play_court_allocations opca ON opca.schedule_block_id = opsb.id
GROUP BY
    opsb.id,
    opsb.day_of_week,
    opsb.start_time,
    opsb.end_time,
    opsb.name,
    opsb.session_type,
    opsb.special_event_name,
    opsb.dedicated_skill_label,
    opsb.price_member,
    opsb.price_guest,
    opsb.max_capacity,
    opsb.is_active,
    opsb.created_at,
    opsb.updated_at
ORDER BY opsb.day_of_week, opsb.start_time;

COMMENT ON VIEW events.admin_weekly_schedule_overview IS 'Weekly schedule overview for admin dashboard';

-- ============================================================================
-- COURT ALLOCATION MATRIX
-- Shows which courts are assigned to which skill levels by time block
-- ============================================================================

CREATE OR REPLACE VIEW events.admin_court_allocation_matrix AS
SELECT
    opsb.day_of_week,
    CASE opsb.day_of_week
        WHEN 0 THEN 'Sunday'
        WHEN 1 THEN 'Monday'
        WHEN 2 THEN 'Tuesday'
        WHEN 3 THEN 'Wednesday'
        WHEN 4 THEN 'Thursday'
        WHEN 5 THEN 'Friday'
        WHEN 6 THEN 'Saturday'
    END AS day_name,
    opsb.start_time,
    opsb.end_time,
    opsb.name AS block_name,
    c.court_number,
    c.name AS court_name,
    opca.skill_level_label,
    opca.skill_level_min,
    opca.skill_level_max,
    opca.is_mixed_level,
    opsb.session_type,
    opsb.is_active
FROM events.open_play_schedule_blocks opsb
JOIN events.open_play_court_allocations opca ON opca.schedule_block_id = opsb.id
JOIN events.courts c ON c.id = opca.court_id
ORDER BY
    opsb.day_of_week,
    opsb.start_time,
    c.court_number;

COMMENT ON VIEW events.admin_court_allocation_matrix IS 'Court allocation matrix for schedule planning';

-- ============================================================================
-- AVAILABLE BOOKING WINDOWS
-- Shows when player bookings are allowed (times not blocked by open play)
-- ============================================================================

CREATE OR REPLACE VIEW events.available_booking_windows AS
WITH daily_schedule AS (
    SELECT
        generate_series AS date,
        EXTRACT(DOW FROM generate_series)::INTEGER AS day_of_week
    FROM generate_series(
        CURRENT_DATE,
        CURRENT_DATE + INTERVAL '30 days',
        INTERVAL '1 day'
    )
),
open_play_times AS (
    SELECT
        ds.date,
        ds.day_of_week,
        opsb.start_time,
        opsb.end_time,
        opsb.name,
        opca.court_id,
        c.court_number
    FROM daily_schedule ds
    JOIN events.open_play_schedule_blocks opsb ON opsb.day_of_week = ds.day_of_week
    JOIN events.open_play_court_allocations opca ON opca.schedule_block_id = opsb.id
    JOIN events.courts c ON c.id = opca.court_id
    LEFT JOIN events.open_play_schedule_overrides opso
        ON opso.schedule_block_id = opsb.id
        AND opso.override_date = ds.date
    WHERE opsb.is_active = true
    AND (opso.is_cancelled IS NULL OR opso.is_cancelled = false)
)
SELECT
    date,
    day_of_week,
    court_id,
    court_number,
    COUNT(*) AS open_play_blocks,
    json_agg(
        json_build_object(
            'start', start_time,
            'end', end_time,
            'name', name
        ) ORDER BY start_time
    ) AS blocked_times
FROM open_play_times
GROUP BY date, day_of_week, court_id, court_number
ORDER BY date, court_number;

COMMENT ON VIEW events.available_booking_windows IS 'Shows available booking windows for the next 30 days';

-- ============================================================================
-- SCHEDULE CONFLICTS VIEW
-- Shows potential conflicts between player bookings and open play
-- ============================================================================

CREATE OR REPLACE VIEW events.admin_schedule_conflicts AS
SELECT
    e.id AS event_id,
    e.title AS event_title,
    e.start_time AS event_start,
    e.end_time AS event_end,
    ec.court_id,
    c.court_number,
    opi.schedule_block_id,
    opsb.name AS open_play_block_name,
    opi.start_time AS open_play_start,
    opi.end_time AS open_play_end,
    'Court conflict with open play' AS conflict_type
FROM events.events e
JOIN events.event_courts ec ON ec.event_id = e.id
JOIN events.courts c ON c.id = ec.court_id
JOIN events.open_play_instances opi ON opi.is_cancelled = false
JOIN events.open_play_court_allocations opca
    ON opca.schedule_block_id = opi.schedule_block_id
    AND opca.court_id = ec.court_id
JOIN events.open_play_schedule_blocks opsb ON opsb.id = opi.schedule_block_id
WHERE (e.start_time, e.end_time) OVERLAPS (opi.start_time, opi.end_time)
AND e.is_cancelled = false
AND e.start_time >= CURRENT_DATE
ORDER BY e.start_time, c.court_number;

COMMENT ON VIEW events.admin_schedule_conflicts IS 'Potential conflicts between player events and open play';

-- ============================================================================
-- SCHEDULE STATISTICS VIEW
-- Summary statistics for schedule management
-- ============================================================================

CREATE OR REPLACE VIEW events.schedule_statistics AS
WITH weekly_hours AS (
    SELECT
        session_type,
        SUM(EXTRACT(EPOCH FROM (end_time - start_time)) / 3600) AS hours_per_week
    FROM events.open_play_schedule_blocks
    WHERE is_active = true
    GROUP BY session_type
),
skill_level_hours AS (
    SELECT
        opca.skill_level_label,
        SUM(EXTRACT(EPOCH FROM (opsb.end_time - opsb.start_time)) / 3600) AS hours_per_week
    FROM events.open_play_schedule_blocks opsb
    JOIN events.open_play_court_allocations opca ON opca.schedule_block_id = opsb.id
    WHERE opsb.is_active = true
    GROUP BY opca.skill_level_label
)
SELECT
    'total_schedule_blocks' AS metric,
    COUNT(*)::TEXT AS value
FROM events.open_play_schedule_blocks
WHERE is_active = true
UNION ALL
SELECT
    'total_weekly_hours' AS metric,
    ROUND(SUM(hours_per_week)::NUMERIC, 2)::TEXT AS value
FROM weekly_hours
UNION ALL
SELECT
    'divided_sessions_hours' AS metric,
    ROUND(COALESCE(hours_per_week, 0)::NUMERIC, 2)::TEXT AS value
FROM weekly_hours
WHERE session_type = 'divided_by_skill'
UNION ALL
SELECT
    'dedicated_sessions_hours' AS metric,
    ROUND(COALESCE(hours_per_week, 0)::NUMERIC, 2)::TEXT AS value
FROM weekly_hours
WHERE session_type = 'dedicated_skill'
UNION ALL
SELECT
    'mixed_sessions_hours' AS metric,
    ROUND(COALESCE(hours_per_week, 0)::NUMERIC, 2)::TEXT AS value
FROM weekly_hours
WHERE session_type = 'mixed_levels'
UNION ALL
SELECT
    'special_events_hours' AS metric,
    ROUND(COALESCE(hours_per_week, 0)::NUMERIC, 2)::TEXT AS value
FROM weekly_hours
WHERE session_type = 'special_event'
UNION ALL
SELECT
    'beginner_court_hours' AS metric,
    ROUND(COALESCE(hours_per_week, 0)::NUMERIC, 2)::TEXT AS value
FROM skill_level_hours
WHERE skill_level_label = 'Beginner'
UNION ALL
SELECT
    'intermediate_court_hours' AS metric,
    ROUND(COALESCE(hours_per_week, 0)::NUMERIC, 2)::TEXT AS value
FROM skill_level_hours
WHERE skill_level_label = 'Intermediate'
UNION ALL
SELECT
    'advanced_court_hours' AS metric,
    ROUND(COALESCE(hours_per_week, 0)::NUMERIC, 2)::TEXT AS value
FROM skill_level_hours
WHERE skill_level_label = 'Advanced';

COMMENT ON VIEW events.schedule_statistics IS 'Summary statistics for open play schedule';

-- ============================================================================
-- UPCOMING OPEN PLAY VIEW
-- Shows upcoming open play sessions for the next 7 days
-- ============================================================================

CREATE OR REPLACE VIEW events.upcoming_open_play AS
SELECT
    opi.instance_date AS date,
    EXTRACT(DOW FROM opi.instance_date)::INTEGER AS day_of_week,
    CASE EXTRACT(DOW FROM opi.instance_date)::INTEGER
        WHEN 0 THEN 'Sunday'
        WHEN 1 THEN 'Monday'
        WHEN 2 THEN 'Tuesday'
        WHEN 3 THEN 'Wednesday'
        WHEN 4 THEN 'Thursday'
        WHEN 5 THEN 'Friday'
        WHEN 6 THEN 'Saturday'
    END AS day_name,
    opi.start_time,
    opi.end_time,
    opsb.name AS session_name,
    opsb.session_type,
    opsb.special_event_name,
    opsb.price_member,
    opsb.price_guest,
    opi.is_cancelled,
    COUNT(opca.id) AS courts_allocated,
    STRING_AGG(DISTINCT opca.skill_level_label, ', ' ORDER BY opca.skill_level_label) AS skill_levels
FROM events.open_play_instances opi
JOIN events.open_play_schedule_blocks opsb ON opsb.id = opi.schedule_block_id
LEFT JOIN events.open_play_court_allocations opca ON opca.schedule_block_id = opsb.id
WHERE opi.instance_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '7 days'
GROUP BY
    opi.instance_date,
    opi.start_time,
    opi.end_time,
    opsb.name,
    opsb.session_type,
    opsb.special_event_name,
    opsb.price_member,
    opsb.price_guest,
    opi.is_cancelled
ORDER BY opi.instance_date, opi.start_time;

COMMENT ON VIEW events.upcoming_open_play IS 'Upcoming open play sessions for the next 7 days';

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

-- Grant SELECT to authenticated users
GRANT SELECT ON events.admin_weekly_schedule_overview TO authenticated;
GRANT SELECT ON events.admin_court_allocation_matrix TO authenticated;
GRANT SELECT ON events.available_booking_windows TO authenticated;
GRANT SELECT ON events.admin_schedule_conflicts TO authenticated;
GRANT SELECT ON events.schedule_statistics TO authenticated;
GRANT SELECT ON events.upcoming_open_play TO authenticated, anon;

-- Grant SELECT on views to service_role
GRANT SELECT ON ALL TABLES IN SCHEMA events TO service_role;
