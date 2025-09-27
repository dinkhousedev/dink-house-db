-- ============================================================================
-- EVENTS API FUNCTIONS MODULE
-- Database functions for complex event operations
-- ============================================================================

-- ============================================================================
-- CREATE EVENT WITH COURTS
-- Creates an event and assigns courts in a single transaction
-- ============================================================================

CREATE OR REPLACE FUNCTION api.create_event_with_courts(
    p_title VARCHAR,
    p_event_type events.event_type,
    p_start_time TIMESTAMPTZ,
    p_end_time TIMESTAMPTZ,
    p_court_ids UUID[],
    p_description TEXT DEFAULT NULL,
    p_template_id UUID DEFAULT NULL,
    p_max_capacity INTEGER DEFAULT 16,
    p_min_capacity INTEGER DEFAULT 4,
    p_skill_levels events.skill_level[] DEFAULT NULL,
    p_price_member DECIMAL DEFAULT 0,
    p_price_guest DECIMAL DEFAULT 0,
    p_member_only BOOLEAN DEFAULT false,
    p_equipment_provided BOOLEAN DEFAULT false,
    p_special_instructions TEXT DEFAULT NULL,
    p_dupr_bracket_id UUID DEFAULT NULL,
    p_dupr_range_label VARCHAR DEFAULT NULL,
    p_dupr_min_rating NUMERIC DEFAULT NULL,
    p_dupr_max_rating NUMERIC DEFAULT NULL,
    p_dupr_open_ended BOOLEAN DEFAULT false,
    p_dupr_min_inclusive BOOLEAN DEFAULT true,
    p_dupr_max_inclusive BOOLEAN DEFAULT true
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_event_id UUID;
    v_court_id UUID;
    v_result JSON;
    v_dupr_bracket events.dupr_brackets%ROWTYPE;
    v_dupr_bracket_id UUID := p_dupr_bracket_id;
    v_dupr_range_label VARCHAR := p_dupr_range_label;
    v_dupr_min_rating NUMERIC(3, 2) := p_dupr_min_rating;
    v_dupr_max_rating NUMERIC(3, 2) := p_dupr_max_rating;
    v_dupr_open_ended BOOLEAN := p_dupr_open_ended;
    v_dupr_min_inclusive BOOLEAN := p_dupr_min_inclusive;
    v_dupr_max_inclusive BOOLEAN := p_dupr_max_inclusive;
BEGIN
    -- Check if user is staff
    IF NOT events.is_staff() THEN
        RAISE EXCEPTION 'Unauthorized: Only staff can create events';
    END IF;

    -- Validate DUPR configuration for DUPR-centric events
    IF p_event_type IN ('dupr_open_play', 'dupr_tournament') THEN
        IF v_dupr_bracket_id IS NOT NULL THEN
            SELECT *
            INTO v_dupr_bracket
            FROM events.dupr_brackets
            WHERE id = v_dupr_bracket_id;

            IF NOT FOUND THEN
                RAISE EXCEPTION 'Invalid DUPR bracket provided';
            END IF;

            v_dupr_range_label := COALESCE(v_dupr_range_label, v_dupr_bracket.label);
            v_dupr_min_rating := COALESCE(v_dupr_bracket.min_rating, v_dupr_min_rating);
            v_dupr_max_rating := COALESCE(v_dupr_bracket.max_rating, v_dupr_max_rating);
            v_dupr_min_inclusive := v_dupr_bracket.min_inclusive;
            v_dupr_max_inclusive := COALESCE(v_dupr_bracket.max_inclusive, true);
            v_dupr_open_ended := v_dupr_bracket.max_rating IS NULL;
        END IF;

        IF v_dupr_open_ended THEN
            v_dupr_max_rating := NULL;
            v_dupr_max_inclusive := true;
        END IF;

        IF v_dupr_range_label IS NULL THEN
            RAISE EXCEPTION 'DUPR range label is required for DUPR events';
        END IF;

        IF v_dupr_min_rating IS NULL THEN
            RAISE EXCEPTION 'Minimum DUPR rating is required for DUPR events';
        END IF;

        IF NOT v_dupr_open_ended AND v_dupr_max_rating IS NULL THEN
            RAISE EXCEPTION 'Maximum DUPR rating is required unless the range is open ended';
        END IF;

        IF v_dupr_max_rating IS NOT NULL AND v_dupr_max_rating < v_dupr_min_rating THEN
            RAISE EXCEPTION 'DUPR maximum rating must be greater than or equal to minimum rating';
        END IF;
    ELSE
        v_dupr_bracket_id := NULL;
        v_dupr_range_label := NULL;
        v_dupr_min_rating := NULL;
        v_dupr_max_rating := NULL;
        v_dupr_open_ended := false;
        v_dupr_min_inclusive := true;
        v_dupr_max_inclusive := true;
    END IF;

    -- Check for court conflicts
    IF EXISTS (
        SELECT 1
        FROM events.event_courts ec
        JOIN events.events e ON ec.event_id = e.id
        WHERE ec.court_id = ANY(p_court_ids)
        AND e.is_cancelled = false
        AND (
            (e.start_time, e.end_time) OVERLAPS (p_start_time, p_end_time)
        )
    ) THEN
        RAISE EXCEPTION 'Court conflict: One or more courts are already booked for this time';
    END IF;

    -- Create the event
    INSERT INTO events.events (
        title,
        event_type,
        start_time,
        end_time,
        description,
        template_id,
        max_capacity,
        min_capacity,
        skill_levels,
        dupr_bracket_id,
        dupr_range_label,
        dupr_min_rating,
        dupr_max_rating,
        dupr_open_ended,
        dupr_min_inclusive,
        dupr_max_inclusive,
        price_member,
        price_guest,
        member_only,
        equipment_provided,
        special_instructions,
        created_by
    ) VALUES (
        p_title,
        p_event_type,
        p_start_time,
        p_end_time,
        p_description,
        p_template_id,
        p_max_capacity,
        p_min_capacity,
        COALESCE(p_skill_levels, ARRAY['2.0', '2.5', '3.0', '3.5', '4.0', '4.5', '5.0']::events.skill_level[]),
        v_dupr_bracket_id,
        v_dupr_range_label,
        v_dupr_min_rating,
        v_dupr_max_rating,
        v_dupr_open_ended,
        v_dupr_min_inclusive,
        v_dupr_max_inclusive,
        p_price_member,
        p_price_guest,
        p_member_only,
        p_equipment_provided,
        p_special_instructions,
        auth.uid()
    ) RETURNING id INTO v_event_id;

    -- Assign courts
    IF p_court_ids IS NOT NULL AND array_length(p_court_ids, 1) > 0 THEN
        FOREACH v_court_id IN ARRAY p_court_ids
        LOOP
            INSERT INTO events.event_courts (event_id, court_id, is_primary)
            VALUES (v_event_id, v_court_id, v_court_id = p_court_ids[1]);
        END LOOP;
    END IF;

    -- Return the created event with courts
    SELECT json_build_object(
        'event_id', v_event_id,
        'title', p_title,
        'event_type', p_event_type,
        'start_time', p_start_time,
        'end_time', p_end_time,
        'dupr_bracket_id', v_dupr_bracket_id,
        'dupr_range', CASE
            WHEN p_event_type IN ('dupr_open_play', 'dupr_tournament') THEN json_build_object(
                'label', v_dupr_range_label,
                'min_rating', v_dupr_min_rating,
                'max_rating', v_dupr_max_rating,
                'min_inclusive', v_dupr_min_inclusive,
                'max_inclusive', v_dupr_max_inclusive,
                'open_ended', v_dupr_open_ended,
                'source', CASE WHEN v_dupr_bracket_id IS NOT NULL THEN 'catalog' ELSE 'custom' END
            )
            ELSE NULL
        END,
        'courts', (
            SELECT json_agg(json_build_object(
                'court_id', ec.court_id,
                'court_number', c.court_number,
                'court_name', c.name
            ) ORDER BY c.court_number)
            FROM events.event_courts ec
            JOIN events.courts c ON ec.court_id = c.id
            WHERE ec.event_id = v_event_id
        )
    ) INTO v_result;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION api.create_event_with_courts IS 'Creates an event with court assignments';

-- ============================================================================
-- CREATE RECURRING EVENTS
-- Creates a series of recurring events
-- ============================================================================

CREATE OR REPLACE FUNCTION api.create_recurring_events(
    p_base_event JSON,
    p_frequency events.recurrence_frequency,
    p_start_date DATE,
    p_end_date DATE,
    p_days_of_week INTEGER[] DEFAULT NULL,
    p_interval_count INTEGER DEFAULT 1,
    p_exceptions DATE[] DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_series_id UUID;
    v_pattern_id UUID;
    v_parent_event_id UUID;
    v_current_date DATE;
    v_event_id UUID;
    v_event_count INTEGER := 0;
    v_start_time TIME;
    v_end_time TIME;
    v_duration INTERVAL;
BEGIN
    -- Check if user is staff
    IF NOT events.is_staff() THEN
        RAISE EXCEPTION 'Unauthorized: Only staff can create recurring events';
    END IF;

    -- Extract time components from base event
    v_start_time := (p_base_event->>'start_time')::TIME;
    v_end_time := (p_base_event->>'end_time')::TIME;
    v_duration := v_end_time - v_start_time;

    -- Create parent event (first occurrence)
    v_parent_event_id := (api.create_event_with_courts(
        p_title := p_base_event->>'title',
        p_event_type := (p_base_event->>'event_type')::events.event_type,
        p_start_time := p_start_date + v_start_time,
        p_end_time := p_start_date + v_end_time,
        p_court_ids := ARRAY(SELECT json_array_elements_text(p_base_event->'court_ids'))::UUID[],
        p_description := p_base_event->>'description',
        p_template_id := (p_base_event->>'template_id')::UUID,
        p_max_capacity := (p_base_event->>'max_capacity')::INTEGER,
        p_min_capacity := (p_base_event->>'min_capacity')::INTEGER,
        p_skill_levels := ARRAY(SELECT json_array_elements_text(p_base_event->'skill_levels'))::events.skill_level[],
        p_price_member := (p_base_event->>'price_member')::DECIMAL,
        p_price_guest := (p_base_event->>'price_guest')::DECIMAL,
        p_member_only := (p_base_event->>'member_only')::BOOLEAN,
        p_equipment_provided := (p_base_event->>'equipment_provided')::BOOLEAN,
        p_special_instructions := p_base_event->>'special_instructions',
        p_dupr_bracket_id := (p_base_event->>'dupr_bracket_id')::UUID,
        p_dupr_range_label := p_base_event->>'dupr_range_label',
        p_dupr_min_rating := (p_base_event->>'dupr_min_rating')::NUMERIC,
        p_dupr_max_rating := (p_base_event->>'dupr_max_rating')::NUMERIC,
        p_dupr_open_ended := COALESCE((p_base_event->>'dupr_open_ended')::BOOLEAN, false),
        p_dupr_min_inclusive := COALESCE((p_base_event->>'dupr_min_inclusive')::BOOLEAN, true),
        p_dupr_max_inclusive := COALESCE((p_base_event->>'dupr_max_inclusive')::BOOLEAN, true)
    )->>'event_id')::UUID;

    v_event_count := 1;

    -- Create recurrence pattern
    INSERT INTO events.recurrence_patterns (
        event_id,
        frequency,
        interval_count,
        days_of_week,
        series_start_date,
        series_end_date
    ) VALUES (
        v_parent_event_id,
        p_frequency,
        p_interval_count,
        p_days_of_week,
        p_start_date,
        p_end_date
    ) RETURNING id INTO v_pattern_id;

    -- Create series
    INSERT INTO events.event_series (
        series_name,
        parent_event_id,
        recurrence_pattern_id,
        created_by
    ) VALUES (
        p_base_event->>'title' || ' Series',
        v_parent_event_id,
        v_pattern_id,
        auth.uid()
    ) RETURNING id INTO v_series_id;

    -- Add parent event to series
    INSERT INTO events.event_series_instances (series_id, event_id, original_start_time)
    VALUES (v_series_id, v_parent_event_id, p_start_date + v_start_time);

    -- Add exceptions
    IF p_exceptions IS NOT NULL THEN
        INSERT INTO events.event_exceptions (recurrence_pattern_id, exception_date)
        SELECT v_pattern_id, unnest(p_exceptions);
    END IF;

    -- Generate recurring events
    v_current_date := p_start_date;

    WHILE v_current_date <= p_end_date LOOP
        -- Move to next occurrence based on frequency
        CASE p_frequency
            WHEN 'daily' THEN
                v_current_date := v_current_date + (p_interval_count || ' days')::INTERVAL;
            WHEN 'weekly' THEN
                v_current_date := v_current_date + (p_interval_count || ' weeks')::INTERVAL;
            WHEN 'biweekly' THEN
                v_current_date := v_current_date + (p_interval_count * 2 || ' weeks')::INTERVAL;
            WHEN 'monthly' THEN
                v_current_date := v_current_date + (p_interval_count || ' months')::INTERVAL;
        END CASE;

        -- Check if date is valid
        IF v_current_date > p_end_date THEN
            EXIT;
        END IF;

        -- Skip if date is in exceptions
        IF p_exceptions IS NOT NULL AND v_current_date = ANY(p_exceptions) THEN
            CONTINUE;
        END IF;

        -- Check day of week for weekly recurrence
        IF p_frequency = 'weekly' AND p_days_of_week IS NOT NULL THEN
            IF NOT (EXTRACT(DOW FROM v_current_date)::INTEGER = ANY(p_days_of_week)) THEN
                CONTINUE;
            END IF;
        END IF;

        -- Create the event
        v_event_id := (api.create_event_with_courts(
            p_title := p_base_event->>'title',
            p_event_type := (p_base_event->>'event_type')::events.event_type,
            p_start_time := v_current_date + v_start_time,
            p_end_time := v_current_date + v_end_time,
            p_court_ids := ARRAY(SELECT json_array_elements_text(p_base_event->'court_ids'))::UUID[],
            p_description := p_base_event->>'description',
            p_template_id := (p_base_event->>'template_id')::UUID,
            p_max_capacity := (p_base_event->>'max_capacity')::INTEGER,
            p_min_capacity := (p_base_event->>'min_capacity')::INTEGER,
            p_skill_levels := ARRAY(SELECT json_array_elements_text(p_base_event->'skill_levels'))::events.skill_level[],
            p_price_member := (p_base_event->>'price_member')::DECIMAL,
            p_price_guest := (p_base_event->>'price_guest')::DECIMAL,
            p_member_only := (p_base_event->>'member_only')::BOOLEAN,
            p_equipment_provided := (p_base_event->>'equipment_provided')::BOOLEAN,
            p_special_instructions := p_base_event->>'special_instructions',
            p_dupr_bracket_id := (p_base_event->>'dupr_bracket_id')::UUID,
            p_dupr_range_label := p_base_event->>'dupr_range_label',
            p_dupr_min_rating := (p_base_event->>'dupr_min_rating')::NUMERIC,
            p_dupr_max_rating := (p_base_event->>'dupr_max_rating')::NUMERIC,
            p_dupr_open_ended := COALESCE((p_base_event->>'dupr_open_ended')::BOOLEAN, false),
            p_dupr_min_inclusive := COALESCE((p_base_event->>'dupr_min_inclusive')::BOOLEAN, true),
            p_dupr_max_inclusive := COALESCE((p_base_event->>'dupr_max_inclusive')::BOOLEAN, true)
        )->>'event_id')::UUID;

        -- Add to series
        INSERT INTO events.event_series_instances (series_id, event_id, original_start_time)
        VALUES (v_series_id, v_event_id, v_current_date + v_start_time);

        v_event_count := v_event_count + 1;
    END LOOP;

    RETURN json_build_object(
        'series_id', v_series_id,
        'pattern_id', v_pattern_id,
        'events_created', v_event_count,
        'start_date', p_start_date,
        'end_date', p_end_date
    );
END;
$$;

COMMENT ON FUNCTION api.create_recurring_events IS 'Creates a series of recurring events';

-- ============================================================================
-- CHECK COURT AVAILABILITY
-- Checks if courts are available for a given time range
-- ============================================================================

CREATE OR REPLACE FUNCTION api.check_court_availability(
    p_court_ids UUID[],
    p_start_time TIMESTAMPTZ,
    p_end_time TIMESTAMPTZ,
    p_exclude_event_id UUID DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
STABLE
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
    SELECT json_build_object(
        'available_courts', (
            SELECT json_agg(json_build_object(
                'court_id', court_id,
                'court_number', court_number,
                'court_name', court_name
            ))
            FROM availability
            WHERE is_available = true
        ),
        'unavailable_courts', (
            SELECT json_agg(json_build_object(
                'court_id', court_id,
                'court_number', court_number,
                'court_name', court_name,
                'status', status,
                'conflicts', conflicts
            ))
            FROM availability
            WHERE is_available = false
        ),
        'all_available', NOT EXISTS (SELECT 1 FROM availability WHERE is_available = false)
    ) INTO v_result;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION api.check_court_availability IS 'Checks court availability for a time range';

-- ============================================================================
-- DUPLICATE EVENT TEMPLATE
-- Creates a copy of an event template
-- ============================================================================

CREATE OR REPLACE FUNCTION api.duplicate_event_template(
    p_template_id UUID,
    p_new_name VARCHAR DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_new_template_id UUID;
    v_original_name VARCHAR;
BEGIN
    -- Check if user is staff
    IF NOT events.is_staff() THEN
        RAISE EXCEPTION 'Unauthorized: Only staff can duplicate templates';
    END IF;

    -- Get original name if not provided
    IF p_new_name IS NULL THEN
        SELECT name || ' (Copy)' INTO v_original_name
        FROM events.event_templates
        WHERE id = p_template_id;

        p_new_name := v_original_name;
    END IF;

    -- Duplicate the template
    INSERT INTO events.event_templates (
        name,
        description,
        event_type,
        duration_minutes,
        max_capacity,
        min_capacity,
        skill_levels,
        price_member,
        price_guest,
        court_preferences,
        equipment_provided,
        settings,
        created_by
    )
    SELECT
        p_new_name,
        description,
        event_type,
        duration_minutes,
        max_capacity,
        min_capacity,
        skill_levels,
        price_member,
        price_guest,
        court_preferences,
        equipment_provided,
        settings,
        auth.uid()
    FROM events.event_templates
    WHERE id = p_template_id
    RETURNING id INTO v_new_template_id;

    RETURN v_new_template_id;
END;
$$;

COMMENT ON FUNCTION api.duplicate_event_template IS 'Creates a copy of an event template';

-- ============================================================================
-- UPDATE EVENT SERIES
-- Updates all or future events in a series
-- ============================================================================

CREATE OR REPLACE FUNCTION api.update_event_series(
    p_series_id UUID,
    p_update_scope VARCHAR, -- 'all', 'future', 'single'
    p_event_id UUID,
    p_updates JSON
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_affected_count INTEGER := 0;
    v_current_time TIMESTAMPTZ;
BEGIN
    -- Check if user is staff
    IF NOT events.is_staff() THEN
        RAISE EXCEPTION 'Unauthorized: Only staff can update event series';
    END IF;

    -- Determine scope
    IF p_update_scope = 'single' THEN
        -- Update single event
        UPDATE events.events
        SET
            title = COALESCE(p_updates->>'title', title),
            description = COALESCE(p_updates->>'description', description),
            max_capacity = COALESCE((p_updates->>'max_capacity')::INTEGER, max_capacity),
            min_capacity = COALESCE((p_updates->>'min_capacity')::INTEGER, min_capacity),
            price_member = COALESCE((p_updates->>'price_member')::DECIMAL, price_member),
            price_guest = COALESCE((p_updates->>'price_guest')::DECIMAL, price_guest),
            special_instructions = COALESCE(p_updates->>'special_instructions', special_instructions),
            updated_by = auth.uid(),
            updated_at = NOW()
        WHERE id = p_event_id;

        -- Mark as exception in series
        UPDATE events.event_series_instances
        SET is_exception = true
        WHERE event_id = p_event_id AND series_id = p_series_id;

        v_affected_count := 1;

    ELSIF p_update_scope = 'future' THEN
        -- Get current event time
        SELECT start_time INTO v_current_time
        FROM events.events
        WHERE id = p_event_id;

        -- Update future events
        UPDATE events.events e
        SET
            title = COALESCE(p_updates->>'title', title),
            description = COALESCE(p_updates->>'description', description),
            max_capacity = COALESCE((p_updates->>'max_capacity')::INTEGER, max_capacity),
            min_capacity = COALESCE((p_updates->>'min_capacity')::INTEGER, min_capacity),
            price_member = COALESCE((p_updates->>'price_member')::DECIMAL, price_member),
            price_guest = COALESCE((p_updates->>'price_guest')::DECIMAL, price_guest),
            special_instructions = COALESCE(p_updates->>'special_instructions', special_instructions),
            updated_by = auth.uid(),
            updated_at = NOW()
        FROM events.event_series_instances esi
        WHERE e.id = esi.event_id
        AND esi.series_id = p_series_id
        AND e.start_time >= v_current_time
        AND e.is_cancelled = false;

        GET DIAGNOSTICS v_affected_count = ROW_COUNT;

    ELSE -- 'all'
        -- Update all events in series
        UPDATE events.events e
        SET
            title = COALESCE(p_updates->>'title', title),
            description = COALESCE(p_updates->>'description', description),
            max_capacity = COALESCE((p_updates->>'max_capacity')::INTEGER, max_capacity),
            min_capacity = COALESCE((p_updates->>'min_capacity')::INTEGER, min_capacity),
            price_member = COALESCE((p_updates->>'price_member')::DECIMAL, price_member),
            price_guest = COALESCE((p_updates->>'price_guest')::DECIMAL, price_guest),
            special_instructions = COALESCE(p_updates->>'special_instructions', special_instructions),
            updated_by = auth.uid(),
            updated_at = NOW()
        FROM events.event_series_instances esi
        WHERE e.id = esi.event_id
        AND esi.series_id = p_series_id
        AND e.is_cancelled = false;

        GET DIAGNOSTICS v_affected_count = ROW_COUNT;
    END IF;

    RETURN json_build_object(
        'series_id', p_series_id,
        'update_scope', p_update_scope,
        'affected_events', v_affected_count
    );
END;
$$;

COMMENT ON FUNCTION api.update_event_series IS 'Updates events in a series';

-- ============================================================================
-- REGISTER FOR EVENT
-- Registers a user for an event
-- ============================================================================

CREATE OR REPLACE FUNCTION api.register_for_event(
    p_event_id UUID,
    p_player_name VARCHAR DEFAULT NULL,
    p_player_email VARCHAR DEFAULT NULL,
    p_player_phone VARCHAR DEFAULT NULL,
    p_skill_level events.skill_level DEFAULT NULL,
    p_dupr_rating NUMERIC DEFAULT NULL,
    p_notes TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_registration_id UUID;
    v_status events.registration_status;
    v_current_registrations INTEGER;
    v_max_capacity INTEGER;
    v_waitlist_capacity INTEGER;
    v_result JSON;
    v_player_id UUID;
    v_player_first_name TEXT;
    v_player_last_name TEXT;
    v_player_email TEXT;
    v_event_type events.event_type;
    v_dupr_min_rating NUMERIC(3, 2);
    v_dupr_max_rating NUMERIC(3, 2);
    v_dupr_open_ended BOOLEAN;
    v_dupr_min_inclusive BOOLEAN;
    v_dupr_max_inclusive BOOLEAN;
    v_required_dupr BOOLEAN := false;
    v_player_dupr_rating NUMERIC(3, 2);
    v_effective_dupr_rating NUMERIC(3, 2);
BEGIN
    -- Get event details
    SELECT
        current_registrations,
        max_capacity,
        waitlist_capacity,
        event_type,
        dupr_min_rating,
        dupr_max_rating,
        dupr_open_ended,
        dupr_min_inclusive,
        dupr_max_inclusive
    INTO
        v_current_registrations,
        v_max_capacity,
        v_waitlist_capacity,
        v_event_type,
        v_dupr_min_rating,
        v_dupr_max_rating,
        v_dupr_open_ended,
        v_dupr_min_inclusive,
        v_dupr_max_inclusive
    FROM events.events
    WHERE id = p_event_id
    AND is_published = true
    AND is_cancelled = false
    AND start_time > NOW();

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Event not found or registration closed';
    END IF;

    v_required_dupr := v_event_type IN ('dupr_open_play', 'dupr_tournament');

    -- Resolve authenticated player profile if available
    IF auth.uid() IS NOT NULL THEN
        SELECT p.id, p.first_name, p.last_name, ua.email, p.dupr_rating
        INTO v_player_id, v_player_first_name, v_player_last_name, v_player_email, v_player_dupr_rating
        FROM app_auth.players p
        JOIN app_auth.user_accounts ua ON ua.id = p.account_id
        WHERE p.account_id = auth.uid();
    END IF;

    -- Check if already registered
    IF EXISTS (
        SELECT 1 FROM events.event_registrations
        WHERE event_id = p_event_id
        AND (
            (v_player_id IS NOT NULL AND user_id = v_player_id)
            OR (p_player_email IS NOT NULL AND player_email = p_player_email)
        )
        AND status IN ('registered', 'waitlisted')
    ) THEN
        RAISE EXCEPTION 'Already registered for this event';
    END IF;

    -- Validate DUPR requirements when applicable
    IF v_required_dupr THEN
        v_effective_dupr_rating := COALESCE(v_player_dupr_rating, p_dupr_rating);

        IF v_effective_dupr_rating IS NULL THEN
            RAISE EXCEPTION 'DUPR rating is required to register for this event';
        END IF;

        IF v_dupr_min_rating IS NOT NULL THEN
            IF v_dupr_min_inclusive THEN
                IF v_effective_dupr_rating < v_dupr_min_rating THEN
                    RAISE EXCEPTION 'Player DUPR rating % is below the minimum % for this event', v_effective_dupr_rating, v_dupr_min_rating;
                END IF;
            ELSE
                IF v_effective_dupr_rating <= v_dupr_min_rating THEN
                    RAISE EXCEPTION 'Player DUPR rating % must be greater than % for this event', v_effective_dupr_rating, v_dupr_min_rating;
                END IF;
            END IF;
        END IF;

        IF NOT v_dupr_open_ended AND v_dupr_max_rating IS NOT NULL THEN
            IF v_dupr_max_inclusive THEN
                IF v_effective_dupr_rating > v_dupr_max_rating THEN
                    RAISE EXCEPTION 'Player DUPR rating % exceeds the maximum % for this event', v_effective_dupr_rating, v_dupr_max_rating;
                END IF;
            ELSE
                IF v_effective_dupr_rating >= v_dupr_max_rating THEN
                    RAISE EXCEPTION 'Player DUPR rating % must be less than % for this event', v_effective_dupr_rating, v_dupr_max_rating;
                END IF;
            END IF;
        END IF;
    ELSE
        v_effective_dupr_rating := COALESCE(v_player_dupr_rating, p_dupr_rating);
    END IF;

    -- Determine registration status
    IF v_current_registrations < v_max_capacity THEN
        v_status := 'registered';
    ELSIF v_current_registrations < v_max_capacity + v_waitlist_capacity THEN
        v_status := 'waitlisted';
    ELSE
        RAISE EXCEPTION 'Event is full';
    END IF;

    -- Create registration
    INSERT INTO events.event_registrations (
        event_id,
        user_id,
        player_name,
        player_email,
        player_phone,
        skill_level,
        dupr_rating,
        status,
        notes
    ) VALUES (
        p_event_id,
        v_player_id,
        COALESCE(
            p_player_name,
            NULLIF(CONCAT_WS(' ', v_player_first_name, v_player_last_name), '')
        ),
        COALESCE(p_player_email, v_player_email),
        p_player_phone,
        p_skill_level,
        v_effective_dupr_rating,
        v_status,
        p_notes
    ) RETURNING id INTO v_registration_id;

    -- Return result
    SELECT json_build_object(
        'registration_id', v_registration_id,
        'event_id', p_event_id,
        'status', v_status,
        'dupr_rating', v_effective_dupr_rating,
        'position', CASE
            WHEN v_status = 'registered' THEN v_current_registrations + 1
            ELSE v_current_registrations - v_max_capacity + 1
        END
    ) INTO v_result;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION api.register_for_event IS 'Registers a user for an event';

-- ============================================================================
-- CANCEL EVENT REGISTRATION
-- Cancels a user's event registration
-- ============================================================================

CREATE OR REPLACE FUNCTION api.cancel_event_registration(
    p_registration_id UUID,
    p_reason TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_event_id UUID;
    v_user_id UUID;
    v_was_registered BOOLEAN;
    v_next_waitlist_id UUID;
    v_result JSON;
BEGIN
    -- Get registration details
    SELECT event_id, user_id, (status = 'registered')
    INTO v_event_id, v_user_id, v_was_registered
    FROM events.event_registrations
    WHERE id = p_registration_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Registration not found';
    END IF;

    -- Check permissions
    IF v_user_id != auth.uid() AND NOT events.is_staff() THEN
        RAISE EXCEPTION 'Unauthorized to cancel this registration';
    END IF;

    -- Update registration status
    UPDATE events.event_registrations
    SET
        status = 'cancelled',
        notes = COALESCE(notes || E'\n', '') || 'Cancelled: ' || COALESCE(p_reason, 'User requested'),
        updated_at = NOW()
    WHERE id = p_registration_id;

    -- If was registered, promote from waitlist
    IF v_was_registered THEN
        SELECT id INTO v_next_waitlist_id
        FROM events.event_registrations
        WHERE event_id = v_event_id
        AND status = 'waitlisted'
        ORDER BY registration_time
        LIMIT 1;

        IF v_next_waitlist_id IS NOT NULL THEN
            UPDATE events.event_registrations
            SET status = 'registered', updated_at = NOW()
            WHERE id = v_next_waitlist_id;
        END IF;
    END IF;

    -- Return result
    SELECT json_build_object(
        'registration_id', p_registration_id,
        'cancelled', true,
        'promoted_from_waitlist', v_next_waitlist_id
    ) INTO v_result;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION api.cancel_event_registration IS 'Cancels an event registration';

-- ============================================================================
-- GET EVENT CALENDAR
-- Returns events for calendar display
-- ============================================================================

CREATE OR REPLACE FUNCTION api.get_event_calendar(
    p_start_date DATE,
    p_end_date DATE,
    p_event_types events.event_type[] DEFAULT NULL,
    p_court_ids UUID[] DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_result JSON;
BEGIN
    SELECT json_build_object(
        'events', json_agg(
            json_build_object(
                'id', e.id,
                'title', e.title,
                'event_type', e.event_type,
                'start', e.start_time,
                'end', e.end_time,
                'color', CASE e.event_type
                    WHEN 'event_scramble' THEN '#B3FF00'
                    WHEN 'dupr_open_play' THEN '#0EA5E9'
                    WHEN 'dupr_tournament' THEN '#1D4ED8'
                    WHEN 'non_dupr_tournament' THEN '#EF4444'
                    WHEN 'league' THEN '#8B5CF6'
                    WHEN 'clinic' THEN '#10B981'
                    WHEN 'private_lesson' THEN '#64748B'
                    ELSE '#6B7280'
                END,
                'capacity', e.max_capacity,
                'registered', e.current_registrations,
                'dupr_range', CASE
                    WHEN e.event_type IN ('dupr_open_play', 'dupr_tournament') THEN json_build_object(
                        'label', e.dupr_range_label,
                        'min_rating', e.dupr_min_rating,
                        'max_rating', e.dupr_max_rating,
                        'min_inclusive', e.dupr_min_inclusive,
                        'max_inclusive', e.dupr_max_inclusive,
                        'open_ended', e.dupr_open_ended
                    )
                    ELSE NULL
                END,
                'courts', (
                    SELECT array_agg(c.court_number ORDER BY c.court_number)
                    FROM events.event_courts ec
                    JOIN events.courts c ON ec.court_id = c.id
                    WHERE ec.event_id = e.id
                )
            ) ORDER BY e.start_time
        ),
        'summary', json_build_object(
            'total_events', COUNT(e.id),
            'total_capacity', SUM(e.max_capacity),
            'total_registered', SUM(e.current_registrations)
        )
    ) INTO v_result
    FROM events.events e
    WHERE e.is_published = true
    AND e.is_cancelled = false
    AND DATE(e.start_time) >= p_start_date
    AND DATE(e.start_time) <= p_end_date
    AND (p_event_types IS NULL OR e.event_type = ANY(p_event_types))
    AND (p_court_ids IS NULL OR EXISTS (
        SELECT 1 FROM events.event_courts ec
        WHERE ec.event_id = e.id
        AND ec.court_id = ANY(p_court_ids)
    ));

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION api.get_event_calendar IS 'Returns events for calendar display';

-- ============================================================================
-- GRANT EXECUTE PERMISSIONS
-- ============================================================================

GRANT EXECUTE ON FUNCTION api.create_event_with_courts TO authenticated;
GRANT EXECUTE ON FUNCTION api.create_recurring_events TO authenticated;
GRANT EXECUTE ON FUNCTION api.check_court_availability TO authenticated;
GRANT EXECUTE ON FUNCTION api.duplicate_event_template TO authenticated;
GRANT EXECUTE ON FUNCTION api.update_event_series TO authenticated;
GRANT EXECUTE ON FUNCTION api.register_for_event TO authenticated;
GRANT EXECUTE ON FUNCTION api.cancel_event_registration TO authenticated;
GRANT EXECUTE ON FUNCTION api.get_event_calendar TO authenticated, anon;
