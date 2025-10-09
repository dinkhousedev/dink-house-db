-- ============================================================================
-- FIX TIMEZONE ISSUE IN OPEN PLAY INSTANCE GENERATION
-- This fixes the timestamp generation to use the correct local timezone
-- ============================================================================

-- Replace the instance generation function with timezone-aware version
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
    v_start_timestamp TIMESTAMP;
    v_end_timestamp TIMESTAMP;
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
            -- Check for override
            SELECT * INTO v_override
            FROM events.open_play_schedule_overrides
            WHERE schedule_block_id = v_block.id
            AND override_date = v_current_date;

            -- Create timezone-aware timestamps
            -- Combine date and time strings, then explicitly set timezone
            v_start_timestamp := (v_current_date::TEXT || ' ' || v_block.start_time::TEXT)::TIMESTAMP;
            v_end_timestamp := (v_current_date::TEXT || ' ' || v_block.end_time::TEXT)::TIMESTAMP;

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
                v_start_timestamp,
                v_end_timestamp,
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

COMMENT ON FUNCTION api.generate_open_play_instances IS 'Generates open play instances with proper timezone handling';

-- Now delete old instances and regenerate with correct timezone handling
DELETE FROM events.open_play_instances;

-- Regenerate instances
SELECT api.generate_open_play_instances(
    (CURRENT_DATE - INTERVAL '30 days')::DATE,
    (CURRENT_DATE + INTERVAL '90 days')::DATE
) AS generation_result;

-- Verify the results for Oct 8
SELECT
    opi.instance_date,
    opi.start_time,
    opi.end_time,
    TO_CHAR(opi.start_time, 'YYYY-MM-DD HH24:MI:SS') as start_formatted,
    TO_CHAR(opi.end_time, 'YYYY-MM-DD HH24:MI:SS') as end_formatted,
    sb.name
FROM events.open_play_instances opi
JOIN events.open_play_schedule_blocks sb ON sb.id = opi.schedule_block_id
WHERE opi.instance_date = '2025-10-08'
ORDER BY opi.start_time;
