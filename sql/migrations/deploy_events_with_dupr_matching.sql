-- ============================================================================
-- Deploy Events API Views and DUPR Matching (Complete)
-- ============================================================================
-- This migration ensures all dependencies are in place and creates the
-- events_with_dupr_matching view with DUPR bracket support
-- ============================================================================

-- ============================================================================
-- PART 1: Ensure Events API Views Exist
-- ============================================================================

SET search_path TO public, events;

-- COURTS VIEW (in public schema for Supabase API access)
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

-- EVENTS CALENDAR VIEW (in public schema for Supabase API access)
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
-- PART 2: Update DUPR Brackets Table
-- ============================================================================

-- Drop the old constraint that prevents NULL min and max
ALTER TABLE events.dupr_brackets DROP CONSTRAINT IF EXISTS dupr_bracket_presence;

-- Clear existing limited brackets
DELETE FROM events.dupr_brackets;

-- Insert comprehensive DUPR brackets covering all skill levels
INSERT INTO events.dupr_brackets (label, min_rating, min_inclusive, max_rating, max_inclusive) VALUES
    -- Beginner levels
    ('Beginner (2.0-2.5)', 2.0, true, 2.5, true),
    ('Novice (2.5-3.0)', 2.5, false, 3.0, true),

    -- Intermediate levels
    ('Lower Intermediate (3.0-3.5)', 3.0, false, 3.5, true),
    ('Upper Intermediate (3.5-4.0)', 3.5, false, 4.0, true),

    -- Advanced levels
    ('Advanced (4.0-4.5)', 4.0, false, 4.5, true),
    ('Expert (4.5-5.0)', 4.5, false, 5.0, true),
    ('Pro (5.0+)', 5.0, false, NULL, true),

    -- Mixed skill brackets for inclusive play
    ('Beginner/Novice (2.0-3.0)', 2.0, true, 3.0, true),
    ('Novice/Intermediate (2.5-3.5)', 2.5, true, 3.5, true),
    ('Intermediate (3.0-4.0)', 3.0, true, 4.0, true),
    ('Intermediate/Advanced (3.5-4.5)', 3.5, true, 4.5, true),
    ('Advanced/Expert (4.0-5.0)', 4.0, true, 5.0, true),
    ('Open Play (3.0+)', 3.0, true, NULL, true),
    ('All Levels', NULL, true, NULL, true),

    -- Specific tournament brackets
    ('Tournament 2.5-3.5', 2.5, true, 3.5, true),
    ('Tournament 3.0-4.0', 3.0, true, 4.0, true),
    ('Tournament 3.5-4.5', 3.5, true, 4.5, true),
    ('Tournament 4.0+', 4.0, true, NULL, true)
ON CONFLICT (label) DO UPDATE
SET
    min_rating = EXCLUDED.min_rating,
    min_inclusive = EXCLUDED.min_inclusive,
    max_rating = EXCLUDED.max_rating,
    max_inclusive = EXCLUDED.max_inclusive,
    updated_at = CURRENT_TIMESTAMP;

-- ============================================================================
-- PART 3: Create DUPR Matching Functions
-- ============================================================================

-- Function to check if a player's DUPR rating matches an event's requirements
CREATE OR REPLACE FUNCTION events.player_matches_event_dupr(
    player_dupr NUMERIC(3, 2),
    event_dupr_min NUMERIC(3, 2),
    event_dupr_max NUMERIC(3, 2),
    event_min_inclusive BOOLEAN DEFAULT true,
    event_max_inclusive BOOLEAN DEFAULT true
) RETURNS BOOLEAN AS $$
BEGIN
    -- If player has no DUPR, they can only join beginner events
    IF player_dupr IS NULL THEN
        -- Allow only events with max rating <= 2.5 or no DUPR requirement
        RETURN (event_dupr_min IS NULL AND event_dupr_max IS NULL)
            OR (event_dupr_max IS NOT NULL AND event_dupr_max <= 2.5);
    END IF;

    -- Check if player's DUPR is within the event's range
    IF event_dupr_min IS NOT NULL THEN
        IF event_min_inclusive THEN
            IF player_dupr < event_dupr_min THEN
                RETURN false;
            END IF;
        ELSE
            IF player_dupr <= event_dupr_min THEN
                RETURN false;
            END IF;
        END IF;
    END IF;

    IF event_dupr_max IS NOT NULL THEN
        IF event_max_inclusive THEN
            IF player_dupr > event_dupr_max THEN
                RETURN false;
            END IF;
        ELSE
            IF player_dupr >= event_dupr_max THEN
                RETURN false;
            END IF;
        END IF;
    END IF;

    RETURN true;
END;
$$ LANGUAGE plpgsql;

-- Function to get the match quality for a player and event
CREATE OR REPLACE FUNCTION events.get_dupr_match_quality(
    player_dupr NUMERIC(3, 2),
    event_dupr_min NUMERIC(3, 2),
    event_dupr_max NUMERIC(3, 2)
) RETURNS TEXT AS $$
DECLARE
    event_center NUMERIC(3, 2);
    distance NUMERIC(3, 2);
BEGIN
    -- Handle null player DUPR
    IF player_dupr IS NULL THEN
        IF event_dupr_max IS NOT NULL AND event_dupr_max <= 2.5 THEN
            RETURN 'good'; -- Beginner events are good for unrated players
        ELSE
            RETURN 'poor'; -- Other events are poor match for unrated
        END IF;
    END IF;

    -- Check if player is within range
    IF NOT events.player_matches_event_dupr(
        player_dupr,
        event_dupr_min,
        event_dupr_max,
        true,
        true
    ) THEN
        RETURN 'outside_range';
    END IF;

    -- Calculate match quality based on distance from event center
    IF event_dupr_min IS NULL AND event_dupr_max IS NULL THEN
        RETURN 'perfect'; -- Open events
    ELSIF event_dupr_min IS NULL THEN
        event_center := event_dupr_max - 0.5;
    ELSIF event_dupr_max IS NULL THEN
        event_center := event_dupr_min + 0.5;
    ELSE
        event_center := (event_dupr_min + event_dupr_max) / 2;
    END IF;

    distance := ABS(player_dupr - event_center);

    IF distance <= 0.25 THEN
        RETURN 'perfect';
    ELSIF distance <= 0.5 THEN
        RETURN 'excellent';
    ELSIF distance <= 0.75 THEN
        RETURN 'good';
    ELSIF distance <= 1.0 THEN
        RETURN 'fair';
    ELSE
        RETURN 'poor';
    END IF;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- PART 4: Create Enhanced Events View with DUPR Matching
-- ============================================================================

CREATE OR REPLACE VIEW api.events_with_dupr_matching AS
SELECT
    e.*,
    db.label as dupr_bracket_label
FROM api.events_calendar_view e
LEFT JOIN events.dupr_brackets db ON db.id = e.dupr_bracket_id
WHERE e.is_published = true
  AND e.is_cancelled = false;

COMMENT ON VIEW api.events_with_dupr_matching IS 'Events with DUPR bracket information for player matching';

-- ============================================================================
-- PART 5: Grant Permissions
-- ============================================================================

-- Grant on courts views
GRANT SELECT ON public.courts_view TO authenticated;
GRANT SELECT ON public.courts_view TO anon;
GRANT SELECT ON api.courts TO authenticated;
GRANT SELECT ON api.courts TO anon;

-- Grant on events views
GRANT SELECT ON public.events_view TO authenticated;
GRANT SELECT ON public.events_view TO anon;
GRANT SELECT ON api.events_calendar_view TO authenticated;
GRANT SELECT ON api.events_calendar_view TO anon;

-- Grant on DUPR matching view
GRANT SELECT ON api.events_with_dupr_matching TO service_role;
GRANT SELECT ON api.events_with_dupr_matching TO authenticated;
GRANT SELECT ON api.events_with_dupr_matching TO anon;

-- Grant on DUPR functions
GRANT EXECUTE ON FUNCTION events.player_matches_event_dupr TO service_role;
GRANT EXECUTE ON FUNCTION events.player_matches_event_dupr TO authenticated;
GRANT EXECUTE ON FUNCTION events.get_dupr_match_quality TO service_role;
GRANT EXECUTE ON FUNCTION events.get_dupr_match_quality TO authenticated;
