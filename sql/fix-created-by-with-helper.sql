-- ============================================================================
-- FIX created_by FOREIGN KEY ISSUE WITH HELPER FUNCTION
-- Deploy via: https://supabase.com/dashboard/project/wchxzbuuwssrnaxshseu/sql
-- ============================================================================

-- ============================================================================
-- STEP 1: Create helper function to get admin_users.id from auth.uid()
-- ============================================================================

CREATE OR REPLACE FUNCTION events.get_current_admin_id()
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
DECLARE
    v_admin_id UUID;
BEGIN
    -- Get admin_users.id from account_id matching auth.uid()
    SELECT au.id INTO v_admin_id
    FROM app_auth.admin_users au
    WHERE au.account_id = auth.uid();

    RETURN v_admin_id;
END;
$$;

COMMENT ON FUNCTION events.get_current_admin_id IS 'Get admin_users.id for current authenticated user';

-- ============================================================================
-- STEP 2: Update create_schedule_block function
-- ============================================================================

CREATE OR REPLACE FUNCTION api.create_schedule_block(
    p_name VARCHAR,
    p_day_of_week INTEGER,
    p_start_time TIME,
    p_end_time TIME,
    p_session_type events.open_play_session_type,
    p_court_allocations JSONB,
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
    IF NOT events.is_staff() THEN
        RAISE EXCEPTION 'Unauthorized: Only staff can create schedule blocks';
    END IF;

    IF p_day_of_week < 0 OR p_day_of_week > 6 THEN
        RAISE EXCEPTION 'Invalid day of week: must be 0-6';
    END IF;

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
        events.get_current_admin_id()  -- Use helper function
    ) RETURNING id INTO v_block_id;

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

-- ============================================================================
-- STEP 3: Update create_schedule_blocks_multi_day function
-- ============================================================================

CREATE OR REPLACE FUNCTION api.create_schedule_blocks_multi_day(
    p_name VARCHAR,
    p_days_of_week INTEGER[],
    p_start_time TIME,
    p_end_time TIME,
    p_session_type events.open_play_session_type,
    p_court_allocations JSONB,
    p_effective_from DATE DEFAULT CURRENT_DATE,
    p_effective_until DATE DEFAULT NULL,
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
    v_admin_id UUID;
BEGIN
    IF NOT events.is_staff() THEN
        RAISE EXCEPTION 'Unauthorized: Only staff can create schedule blocks';
    END IF;

    -- Get admin ID using helper function
    v_admin_id := events.get_current_admin_id();

    IF p_days_of_week IS NULL OR array_length(p_days_of_week, 1) = 0 THEN
        RAISE EXCEPTION 'At least one day of week must be selected';
    END IF;

    IF p_effective_until IS NULL THEN
        RAISE EXCEPTION 'End date (effective_until) is required to prevent infinite schedules';
    END IF;

    IF p_effective_until < p_effective_from THEN
        RAISE EXCEPTION 'End date must be after start date';
    END IF;

    FOREACH v_day IN ARRAY p_days_of_week
    LOOP
        IF v_day < 0 OR v_day > 6 THEN
            RAISE EXCEPTION 'Invalid day of week: %. Must be 0-6', v_day;
        END IF;

        v_day_name := CASE v_day
            WHEN 0 THEN 'Sunday'
            WHEN 1 THEN 'Monday'
            WHEN 2 THEN 'Tuesday'
            WHEN 3 THEN 'Wednesday'
            WHEN 4 THEN 'Thursday'
            WHEN 5 THEN 'Friday'
            WHEN 6 THEN 'Saturday'
        END;

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
            v_admin_id  -- Use admin ID from helper function
        ) RETURNING id INTO v_block_id;

        v_created_blocks := array_append(v_created_blocks, v_block_id);

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

    -- Generate instances for the date range
    DECLARE
        v_current_date DATE;
        v_day_of_week INTEGER;
        v_block RECORD;
    BEGIN
        v_current_date := p_effective_from;

        WHILE v_current_date <= p_effective_until LOOP
            v_day_of_week := EXTRACT(DOW FROM v_current_date)::INTEGER;

            IF v_day_of_week = ANY(p_days_of_week) THEN
                FOR v_block IN
                    SELECT *
                    FROM events.open_play_schedule_blocks
                    WHERE id = ANY(v_created_blocks)
                    AND day_of_week = v_day_of_week
                LOOP
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

-- ============================================================================
-- STEP 4: Update create_schedule_override function
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
    IF NOT events.is_staff() THEN
        RAISE EXCEPTION 'Unauthorized: Only staff can create schedule overrides';
    END IF;

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
        events.get_current_admin_id()  -- Use helper function
    ) RETURNING id INTO v_override_id;

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

-- ============================================================================
-- VERIFICATION
-- ============================================================================

-- Verify helper function exists
SELECT
    proname as function_name,
    prosrc as source
FROM pg_proc
WHERE proname = 'get_current_admin_id';

-- Test the helper function (should return your admin ID)
SELECT events.get_current_admin_id() as my_admin_id;
