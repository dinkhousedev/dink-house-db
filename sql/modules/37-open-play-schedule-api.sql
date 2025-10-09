-- ============================================================================
-- OPEN PLAY SCHEDULE API FUNCTIONS
-- API functions for managing open play schedule
-- ============================================================================

-- ============================================================================
-- CREATE SCHEDULE BLOCK WITH COURT ALLOCATIONS
-- Creates a recurring schedule block and assigns courts in one transaction
-- ============================================================================

CREATE OR REPLACE FUNCTION api.create_schedule_block(
    p_name VARCHAR,
    p_day_of_week INTEGER,
    p_start_time TIME,
    p_end_time TIME,
    p_session_type events.open_play_session_type,
    p_court_allocations JSONB, -- Array of {court_id, skill_min, skill_max, skill_label}
    p_description TEXT DEFAULT NULL,
    p_special_event_name VARCHAR DEFAULT NULL,
    p_dedicated_skill_min NUMERIC DEFAULT NULL,
    p_dedicated_skill_max NUMERIC DEFAULT NULL,
    p_dedicated_skill_label VARCHAR DEFAULT NULL,
    p_price_member DECIMAL DEFAULT 15.00,
    p_price_guest DECIMAL DEFAULT 20.00,
    p_max_capacity INTEGER DEFAULT 20,
    p_special_instructions TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_block_id UUID;
    v_allocation JSONB;
    v_result JSON;
BEGIN
    -- Check if user is staff
    IF NOT events.is_staff() THEN
        RAISE EXCEPTION 'Unauthorized: Only staff can create schedule blocks';
    END IF;

    -- Validate day of week
    IF p_day_of_week < 0 OR p_day_of_week > 6 THEN
        RAISE EXCEPTION 'Invalid day of week: must be 0-6';
    END IF;

    -- Create the schedule block
    INSERT INTO events.open_play_schedule_blocks (
        name,
        description,
        day_of_week,
        start_time,
        end_time,
        session_type,
        special_event_name,
        dedicated_skill_min,
        dedicated_skill_max,
        dedicated_skill_label,
        price_member,
        price_guest,
        max_capacity,
        special_instructions,
        created_by
    ) VALUES (
        p_name,
        p_description,
        p_day_of_week,
        p_start_time,
        p_end_time,
        p_session_type,
        p_special_event_name,
        p_dedicated_skill_min,
        p_dedicated_skill_max,
        p_dedicated_skill_label,
        p_price_member,
        p_price_guest,
        p_max_capacity,
        p_special_instructions,
        auth.uid()
    ) RETURNING id INTO v_block_id;

    -- Insert court allocations
    IF p_court_allocations IS NOT NULL AND jsonb_array_length(p_court_allocations) > 0 THEN
        FOR v_allocation IN SELECT * FROM jsonb_array_elements(p_court_allocations)
        LOOP
            INSERT INTO events.open_play_court_allocations (
                schedule_block_id,
                court_id,
                skill_level_min,
                skill_level_max,
                skill_level_label,
                is_mixed_level,
                sort_order
            ) VALUES (
                v_block_id,
                (v_allocation->>'court_id')::UUID,
                (v_allocation->>'skill_level_min')::NUMERIC,
                (v_allocation->>'skill_level_max')::NUMERIC,
                v_allocation->>'skill_level_label',
                COALESCE((v_allocation->>'is_mixed_level')::BOOLEAN, false),
                COALESCE((v_allocation->>'sort_order')::INTEGER, 0)
            );
        END LOOP;
    END IF;

    -- Return the created block with allocations
    SELECT json_build_object(
        'block_id', v_block_id,
        'name', p_name,
        'day_of_week', p_day_of_week,
        'start_time', p_start_time,
        'end_time', p_end_time,
        'session_type', p_session_type,
        'court_allocations', (
            SELECT json_agg(
                json_build_object(
                    'court_id', opca.court_id,
                    'court_number', c.court_number,
                    'court_name', c.name,
                    'skill_level_min', opca.skill_level_min,
                    'skill_level_max', opca.skill_level_max,
                    'skill_level_label', opca.skill_level_label
                ) ORDER BY opca.sort_order, c.court_number
            )
            FROM events.open_play_court_allocations opca
            JOIN events.courts c ON opca.court_id = c.id
            WHERE opca.schedule_block_id = v_block_id
        )
    ) INTO v_result;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION api.create_schedule_block IS 'Creates a recurring schedule block with court allocations';

-- ============================================================================
-- CREATE SCHEDULE BLOCKS WITH DATE RANGE (MULTIPLE DAYS)
-- Creates multiple schedule blocks for selected days within a date range
-- and automatically generates instances
-- ============================================================================

CREATE OR REPLACE FUNCTION api.create_schedule_blocks_multi_day(
    p_name VARCHAR,
    p_days_of_week INTEGER[], -- Array of days: [1, 3, 5] for Mon, Wed, Fri
    p_start_time TIME,
    p_end_time TIME,
    p_session_type events.open_play_session_type,
    p_court_allocations JSONB, -- Array of {court_id, skill_min, skill_max, skill_label}
    p_effective_from DATE DEFAULT CURRENT_DATE,
    p_effective_until DATE DEFAULT NULL, -- Required to prevent infinite schedules
    p_description TEXT DEFAULT NULL,
    p_special_event_name VARCHAR DEFAULT NULL,
    p_dedicated_skill_min NUMERIC DEFAULT NULL,
    p_dedicated_skill_max NUMERIC DEFAULT NULL,
    p_dedicated_skill_label VARCHAR DEFAULT NULL,
    p_price_member DECIMAL DEFAULT 15.00,
    p_price_guest DECIMAL DEFAULT 20.00,
    p_max_capacity INTEGER DEFAULT 20,
    p_special_instructions TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_day INTEGER;
    v_block_id UUID;
    v_allocation JSONB;
    v_created_blocks UUID[] := ARRAY[]::UUID[];
    v_instances_created INTEGER := 0;
    v_day_name TEXT;
    v_result JSON;
BEGIN
    -- Check if user is staff
    IF NOT events.is_staff() THEN
        RAISE EXCEPTION 'Unauthorized: Only staff can create schedule blocks';
    END IF;

    -- Validate inputs
    IF p_days_of_week IS NULL OR array_length(p_days_of_week, 1) = 0 THEN
        RAISE EXCEPTION 'At least one day of week must be selected';
    END IF;

    IF p_effective_until IS NULL THEN
        RAISE EXCEPTION 'End date (effective_until) is required to prevent infinite schedules';
    END IF;

    IF p_effective_until < p_effective_from THEN
        RAISE EXCEPTION 'End date must be after start date';
    END IF;

    -- Loop through each selected day and create a schedule block
    FOREACH v_day IN ARRAY p_days_of_week
    LOOP
        -- Validate day of week
        IF v_day < 0 OR v_day > 6 THEN
            RAISE EXCEPTION 'Invalid day of week: %. Must be 0-6', v_day;
        END IF;

        -- Get day name for the block name
        v_day_name := CASE v_day
            WHEN 0 THEN 'Sunday'
            WHEN 1 THEN 'Monday'
            WHEN 2 THEN 'Tuesday'
            WHEN 3 THEN 'Wednesday'
            WHEN 4 THEN 'Thursday'
            WHEN 5 THEN 'Friday'
            WHEN 6 THEN 'Saturday'
        END;

        -- Create the schedule block for this day
        INSERT INTO events.open_play_schedule_blocks (
            name,
            description,
            day_of_week,
            start_time,
            end_time,
            session_type,
            special_event_name,
            dedicated_skill_min,
            dedicated_skill_max,
            dedicated_skill_label,
            price_member,
            price_guest,
            max_capacity,
            special_instructions,
            effective_from,
            effective_until,
            created_by
        ) VALUES (
            p_name,
            p_description,
            v_day,
            p_start_time,
            p_end_time,
            p_session_type,
            p_special_event_name,
            p_dedicated_skill_min,
            p_dedicated_skill_max,
            p_dedicated_skill_label,
            p_price_member,
            p_price_guest,
            p_max_capacity,
            p_special_instructions,
            p_effective_from,
            p_effective_until,
            auth.uid()
        ) RETURNING id INTO v_block_id;

        -- Add to created blocks array
        v_created_blocks := array_append(v_created_blocks, v_block_id);

        -- Insert court allocations for this block
        IF p_court_allocations IS NOT NULL AND jsonb_array_length(p_court_allocations) > 0 THEN
            FOR v_allocation IN SELECT * FROM jsonb_array_elements(p_court_allocations)
            LOOP
                INSERT INTO events.open_play_court_allocations (
                    schedule_block_id,
                    court_id,
                    skill_level_min,
                    skill_level_max,
                    skill_level_label,
                    is_mixed_level,
                    sort_order
                ) VALUES (
                    v_block_id,
                    (v_allocation->>'court_id')::UUID,
                    (v_allocation->>'skill_level_min')::NUMERIC,
                    (v_allocation->>'skill_level_max')::NUMERIC,
                    v_allocation->>'skill_level_label',
                    COALESCE((v_allocation->>'is_mixed_level')::BOOLEAN, false),
                    COALESCE((v_allocation->>'sort_order')::INTEGER, 0)
                );
            END LOOP;
        END IF;
    END LOOP;

    -- Generate instances for all created blocks within the date range
    DECLARE
        v_current_date DATE;
        v_day_of_week INTEGER;
        v_block RECORD;
    BEGIN
        v_current_date := p_effective_from;

        WHILE v_current_date <= p_effective_until LOOP
            v_day_of_week := EXTRACT(DOW FROM v_current_date)::INTEGER;

            -- Check if this day has a schedule block we just created
            IF v_day_of_week = ANY(p_days_of_week) THEN
                -- Find the block for this day
                FOR v_block IN
                    SELECT *
                    FROM events.open_play_schedule_blocks
                    WHERE id = ANY(v_created_blocks)
                    AND day_of_week = v_day_of_week
                LOOP
                    -- Create instance for this date
                    INSERT INTO events.open_play_instances (
                        schedule_block_id,
                        instance_date,
                        start_time,
                        end_time,
                        is_cancelled
                    ) VALUES (
                        v_block.id,
                        v_current_date,
                        timezone('America/Chicago', (v_current_date + v_block.start_time)::timestamp),
                        timezone('America/Chicago', (v_current_date + v_block.end_time)::timestamp),
                        false
                    )
                    ON CONFLICT (schedule_block_id, instance_date) DO NOTHING;

                    v_instances_created := v_instances_created + 1;
                END LOOP;
            END IF;

            v_current_date := v_current_date + INTERVAL '1 day';
        END LOOP;
    END;

    -- Return the results
    SELECT json_build_object(
        'success', true,
        'blocks_created', array_length(v_created_blocks, 1),
        'instances_created', v_instances_created,
        'effective_from', p_effective_from,
        'effective_until', p_effective_until,
        'days_of_week', p_days_of_week,
        'blocks', (
            SELECT json_agg(
                json_build_object(
                    'block_id', opsb.id,
                    'name', opsb.name,
                    'day_of_week', opsb.day_of_week,
                    'day_name', CASE opsb.day_of_week
                        WHEN 0 THEN 'Sunday'
                        WHEN 1 THEN 'Monday'
                        WHEN 2 THEN 'Tuesday'
                        WHEN 3 THEN 'Wednesday'
                        WHEN 4 THEN 'Thursday'
                        WHEN 5 THEN 'Friday'
                        WHEN 6 THEN 'Saturday'
                    END,
                    'start_time', opsb.start_time,
                    'end_time', opsb.end_time,
                    'court_allocations', (
                        SELECT json_agg(
                            json_build_object(
                                'court_id', opca.court_id,
                                'court_number', c.court_number,
                                'court_name', c.name,
                                'skill_level_label', opca.skill_level_label
                            ) ORDER BY opca.sort_order, c.court_number
                        )
                        FROM events.open_play_court_allocations opca
                        JOIN events.courts c ON opca.court_id = c.id
                        WHERE opca.schedule_block_id = opsb.id
                    )
                ) ORDER BY opsb.day_of_week
            )
            FROM events.open_play_schedule_blocks opsb
            WHERE opsb.id = ANY(v_created_blocks)
        )
    ) INTO v_result;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION api.create_schedule_blocks_multi_day IS 'Creates multiple schedule blocks for selected days within a date range';

-- ============================================================================
-- UPDATE SCHEDULE BLOCK
-- Updates an existing schedule block
-- ============================================================================

CREATE OR REPLACE FUNCTION api.update_schedule_block(
    p_block_id UUID,
    p_updates JSONB
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSON;
BEGIN
    -- Check if user is staff
    IF NOT events.is_staff() THEN
        RAISE EXCEPTION 'Unauthorized: Only staff can update schedule blocks';
    END IF;

    -- Update the schedule block
    UPDATE events.open_play_schedule_blocks
    SET
        name = COALESCE((p_updates->>'name'), name),
        description = COALESCE((p_updates->>'description'), description),
        start_time = COALESCE((p_updates->>'start_time')::TIME, start_time),
        end_time = COALESCE((p_updates->>'end_time')::TIME, end_time),
        session_type = COALESCE((p_updates->>'session_type')::events.open_play_session_type, session_type),
        special_event_name = COALESCE((p_updates->>'special_event_name'), special_event_name),
        price_member = COALESCE((p_updates->>'price_member')::DECIMAL, price_member),
        price_guest = COALESCE((p_updates->>'price_guest')::DECIMAL, price_guest),
        max_capacity = COALESCE((p_updates->>'max_capacity')::INTEGER, max_capacity),
        special_instructions = COALESCE((p_updates->>'special_instructions'), special_instructions),
        is_active = COALESCE((p_updates->>'is_active')::BOOLEAN, is_active),
        updated_by = auth.uid(),
        updated_at = NOW()
    WHERE id = p_block_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Schedule block not found';
    END IF;

    -- Return updated block
    SELECT json_build_object(
        'block_id', p_block_id,
        'updated', true
    ) INTO v_result;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION api.update_schedule_block IS 'Updates a schedule block';

-- ============================================================================
-- DELETE SCHEDULE BLOCK
-- Deletes a schedule block (and its allocations via CASCADE)
-- ============================================================================

CREATE OR REPLACE FUNCTION api.delete_schedule_block(
    p_block_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSON;
BEGIN
    -- Check if user is admin
    IF NOT events.is_admin_or_manager() THEN
        RAISE EXCEPTION 'Unauthorized: Only admins can delete schedule blocks';
    END IF;

    -- Delete the block (cascade will handle allocations and instances)
    DELETE FROM events.open_play_schedule_blocks
    WHERE id = p_block_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Schedule block not found';
    END IF;

    SELECT json_build_object(
        'block_id', p_block_id,
        'deleted', true
    ) INTO v_result;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION api.delete_schedule_block IS 'Deletes a schedule block';

-- ============================================================================
-- BULK DELETE SCHEDULE BLOCKS
-- Deletes multiple schedule blocks at once
-- ============================================================================

CREATE OR REPLACE FUNCTION api.bulk_delete_schedule_blocks(
    p_block_ids UUID[]
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_deleted_count INTEGER;
    v_result JSON;
BEGIN
    -- Check if user is admin
    IF NOT events.is_admin_or_manager() THEN
        RAISE EXCEPTION 'Unauthorized: Only admins can delete schedule blocks';
    END IF;

    -- Delete the blocks (cascade will handle allocations and instances)
    DELETE FROM events.open_play_schedule_blocks
    WHERE id = ANY(p_block_ids);

    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;

    SELECT json_build_object(
        'deleted_count', v_deleted_count,
        'block_ids', p_block_ids
    ) INTO v_result;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION api.bulk_delete_schedule_blocks IS 'Bulk deletes multiple schedule blocks';

-- ============================================================================
-- GET WEEKLY SCHEDULE
-- Returns the full weekly schedule with court allocations
-- ============================================================================

CREATE OR REPLACE FUNCTION api.get_weekly_schedule(
    p_include_inactive BOOLEAN DEFAULT false
)
RETURNS JSON
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_result JSON;
BEGIN
    SELECT json_build_object(
        'schedule', json_agg(
            json_build_object(
                'block_id', opsb.id,
                'name', opsb.name,
                'description', opsb.description,
                'day_of_week', opsb.day_of_week,
                'day_name', CASE opsb.day_of_week
                    WHEN 0 THEN 'Sunday'
                    WHEN 1 THEN 'Monday'
                    WHEN 2 THEN 'Tuesday'
                    WHEN 3 THEN 'Wednesday'
                    WHEN 4 THEN 'Thursday'
                    WHEN 5 THEN 'Friday'
                    WHEN 6 THEN 'Saturday'
                END,
                'start_time', opsb.start_time,
                'end_time', opsb.end_time,
                'session_type', opsb.session_type,
                'special_event_name', opsb.special_event_name,
                'dedicated_skill_min', opsb.dedicated_skill_min,
                'dedicated_skill_max', opsb.dedicated_skill_max,
                'dedicated_skill_label', opsb.dedicated_skill_label,
                'price_member', opsb.price_member,
                'price_guest', opsb.price_guest,
                'max_capacity', opsb.max_capacity,
                'is_active', opsb.is_active,
                'court_allocations', (
                    SELECT json_agg(
                        json_build_object(
                            'court_id', opca.court_id,
                            'court_number', c.court_number,
                            'court_name', c.name,
                            'skill_level_min', opca.skill_level_min,
                            'skill_level_max', opca.skill_level_max,
                            'skill_level_label', opca.skill_level_label,
                            'is_mixed_level', opca.is_mixed_level
                        ) ORDER BY opca.sort_order, c.court_number
                    )
                    FROM events.open_play_court_allocations opca
                    JOIN events.courts c ON opca.court_id = c.id
                    WHERE opca.schedule_block_id = opsb.id
                )
            ) ORDER BY opsb.day_of_week, opsb.start_time
        )
    ) INTO v_result
    FROM events.open_play_schedule_blocks opsb
    WHERE (p_include_inactive OR opsb.is_active = true);

    RETURN COALESCE(v_result, json_build_object('schedule', '[]'::json));
END;
$$;

COMMENT ON FUNCTION api.get_weekly_schedule IS 'Returns the full weekly open play schedule';

-- ============================================================================
-- CREATE SCHEDULE OVERRIDE
-- Creates a one-off override for a specific date
-- ============================================================================

CREATE OR REPLACE FUNCTION api.create_schedule_override(
    p_block_id UUID,
    p_override_date DATE,
    p_is_cancelled BOOLEAN,
    p_reason TEXT,
    p_replacement_details JSONB DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_override_id UUID;
    v_result JSON;
BEGIN
    -- Check if user is staff
    IF NOT events.is_staff() THEN
        RAISE EXCEPTION 'Unauthorized: Only staff can create schedule overrides';
    END IF;

    -- Create the override
    INSERT INTO events.open_play_schedule_overrides (
        schedule_block_id,
        override_date,
        is_cancelled,
        replacement_name,
        replacement_start_time,
        replacement_end_time,
        replacement_session_type,
        reason,
        special_instructions,
        created_by
    ) VALUES (
        p_block_id,
        p_override_date,
        p_is_cancelled,
        p_replacement_details->>'name',
        (p_replacement_details->>'start_time')::TIME,
        (p_replacement_details->>'end_time')::TIME,
        (p_replacement_details->>'session_type')::events.open_play_session_type,
        p_reason,
        p_replacement_details->>'special_instructions',
        auth.uid()
    ) RETURNING id INTO v_override_id;

    -- Mark any existing instance as cancelled or update it
    UPDATE events.open_play_instances
    SET
        is_cancelled = p_is_cancelled,
        override_id = v_override_id
    WHERE schedule_block_id = p_block_id
    AND instance_date = p_override_date;

    SELECT json_build_object(
        'override_id', v_override_id,
        'block_id', p_block_id,
        'override_date', p_override_date,
        'is_cancelled', p_is_cancelled
    ) INTO v_result;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION api.create_schedule_override IS 'Creates a schedule override for a specific date';

-- ============================================================================
-- GENERATE OPEN PLAY INSTANCES
-- Generates open play instances for a date range
-- ============================================================================

CREATE OR REPLACE FUNCTION api.generate_open_play_instances(
    p_start_date DATE,
    p_end_date DATE
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_date DATE;
    v_day_of_week INTEGER;
    v_block RECORD;
    v_override RECORD;
    v_instances_created INTEGER := 0;
BEGIN
    -- Check if user is staff
    IF NOT events.is_staff() THEN
        RAISE EXCEPTION 'Unauthorized: Only staff can generate instances';
    END IF;

    -- Loop through each date in range
    v_current_date := p_start_date;
    WHILE v_current_date <= p_end_date LOOP
        v_day_of_week := EXTRACT(DOW FROM v_current_date)::INTEGER;

        -- Find all active schedule blocks for this day
        FOR v_block IN
            SELECT *
            FROM events.open_play_schedule_blocks
            WHERE day_of_week = v_day_of_week
            AND is_active = true
            AND (effective_from IS NULL OR effective_from <= v_current_date)
            AND (effective_until IS NULL OR effective_until >= v_current_date)
        LOOP
            -- Check if there's an override for this date
            SELECT * INTO v_override
            FROM events.open_play_schedule_overrides
            WHERE schedule_block_id = v_block.id
            AND override_date = v_current_date;

            -- Insert or update instance
            INSERT INTO events.open_play_instances (
                schedule_block_id,
                instance_date,
                start_time,
                end_time,
                override_id,
                is_cancelled
            ) VALUES (
                v_block.id,
                v_current_date,
                timezone('America/Chicago', (v_current_date + v_block.start_time)::timestamp),
                timezone('America/Chicago', (v_current_date + v_block.end_time)::timestamp),
                v_override.id,
                COALESCE(v_override.is_cancelled, false)
            )
            ON CONFLICT (schedule_block_id, instance_date)
            DO UPDATE SET
                start_time = EXCLUDED.start_time,
                end_time = EXCLUDED.end_time,
                override_id = EXCLUDED.override_id,
                is_cancelled = EXCLUDED.is_cancelled,
                generated_at = NOW();

            v_instances_created := v_instances_created + 1;
        END LOOP;

        v_current_date := v_current_date + INTERVAL '1 day';
    END LOOP;

    RETURN json_build_object(
        'instances_created', v_instances_created,
        'start_date', p_start_date,
        'end_date', p_end_date
    );
END;
$$;

COMMENT ON FUNCTION api.generate_open_play_instances IS 'Generates open play instances for booking conflict detection';

-- ============================================================================
-- GET AVAILABLE BOOKING TIMES
-- Returns time slots available for player bookings (not blocked by open play)
-- ============================================================================

CREATE OR REPLACE FUNCTION api.get_available_booking_times(
    p_date DATE,
    p_court_id UUID DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_result JSON;
    v_open_time TIME := '06:00:00';
    v_close_time TIME := '22:00:00';
BEGIN
    WITH open_play_blocks AS (
        SELECT
            opi.start_time,
            opi.end_time,
            opca.court_id
        FROM events.open_play_instances opi
        JOIN events.open_play_court_allocations opca ON opca.schedule_block_id = opi.schedule_block_id
        WHERE opi.instance_date = p_date
        AND opi.is_cancelled = false
        AND (p_court_id IS NULL OR opca.court_id = p_court_id)
    ),
    time_slots AS (
        SELECT
            CASE
                WHEN prev_end IS NULL THEN p_date + v_open_time
                ELSE prev_end
            END AS slot_start,
            CASE
                WHEN next_start IS NULL THEN p_date + v_close_time
                ELSE next_start
            END AS slot_end
        FROM (
            SELECT
                start_time AS next_start,
                LAG(end_time) OVER (ORDER BY start_time) AS prev_end
            FROM open_play_blocks
            UNION ALL
            SELECT NULL AS next_start, MAX(end_time) AS prev_end
            FROM open_play_blocks
        ) slots
        WHERE (next_start IS NULL AND prev_end IS NOT NULL)
           OR (next_start > COALESCE(prev_end, p_date + v_open_time))
    )
    SELECT json_build_object(
        'date', p_date,
        'available_slots', (
            SELECT json_agg(
                json_build_object(
                    'start_time', slot_start,
                    'end_time', slot_end,
                    'duration_minutes', EXTRACT(EPOCH FROM (slot_end - slot_start)) / 60
                ) ORDER BY slot_start
            )
            FROM time_slots
            WHERE slot_end > slot_start
        )
    ) INTO v_result;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION api.get_available_booking_times IS 'Returns time slots available for player bookings';

-- ============================================================================
-- GET SCHEDULE FOR DATE
-- Returns the open play schedule for a specific date with overrides applied
-- ============================================================================

CREATE OR REPLACE FUNCTION api.get_schedule_for_date(
    p_date DATE
)
RETURNS JSON
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_result JSON;
    v_day_of_week INTEGER;
BEGIN
    v_day_of_week := EXTRACT(DOW FROM p_date)::INTEGER;

    SELECT json_build_object(
        'date', p_date,
        'day_of_week', v_day_of_week,
        'sessions', (
            SELECT json_agg(
                json_build_object(
                    'block_id', opsb.id,
                    'name', COALESCE(opso.replacement_name, opsb.name),
                    'start_time', p_date + COALESCE(opso.replacement_start_time, opsb.start_time),
                    'end_time', p_date + COALESCE(opso.replacement_end_time, opsb.end_time),
                    'session_type', COALESCE(opso.replacement_session_type, opsb.session_type),
                    'is_cancelled', COALESCE(opso.is_cancelled, false),
                    'special_event_name', opsb.special_event_name,
                    'price_member', opsb.price_member,
                    'price_guest', opsb.price_guest,
                    'court_allocations', (
                        SELECT json_agg(
                            json_build_object(
                                'court_number', c.court_number,
                                'court_name', c.name,
                                'skill_level_label', opca.skill_level_label,
                                'skill_level_min', opca.skill_level_min,
                                'skill_level_max', opca.skill_level_max
                            ) ORDER BY c.court_number
                        )
                        FROM events.open_play_court_allocations opca
                        JOIN events.courts c ON opca.court_id = c.id
                        WHERE opca.schedule_block_id = opsb.id
                    )
                ) ORDER BY COALESCE(opso.replacement_start_time, opsb.start_time)
            )
            FROM events.open_play_schedule_blocks opsb
            LEFT JOIN events.open_play_schedule_overrides opso
                ON opso.schedule_block_id = opsb.id
                AND opso.override_date = p_date
            WHERE opsb.day_of_week = v_day_of_week
            AND opsb.is_active = true
            AND (opsb.effective_from IS NULL OR opsb.effective_from <= p_date)
            AND (opsb.effective_until IS NULL OR opsb.effective_until >= p_date)
        )
    ) INTO v_result;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION api.get_schedule_for_date IS 'Returns the schedule for a specific date with overrides';

-- ============================================================================
-- GRANT EXECUTE PERMISSIONS
-- ============================================================================

GRANT EXECUTE ON FUNCTION api.create_schedule_block TO authenticated;
GRANT EXECUTE ON FUNCTION api.create_schedule_blocks_multi_day TO authenticated;
GRANT EXECUTE ON FUNCTION api.update_schedule_block TO authenticated;
GRANT EXECUTE ON FUNCTION api.delete_schedule_block TO authenticated;
GRANT EXECUTE ON FUNCTION api.bulk_delete_schedule_blocks TO authenticated;
GRANT EXECUTE ON FUNCTION api.get_weekly_schedule TO authenticated, anon;
GRANT EXECUTE ON FUNCTION api.create_schedule_override TO authenticated;
GRANT EXECUTE ON FUNCTION api.generate_open_play_instances TO authenticated;
GRANT EXECUTE ON FUNCTION api.get_available_booking_times TO authenticated, anon;
GRANT EXECUTE ON FUNCTION api.get_schedule_for_date TO authenticated, anon;
