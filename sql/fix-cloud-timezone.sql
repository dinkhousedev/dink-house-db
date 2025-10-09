-- ============================================================================
-- FIX TIMEZONE ISSUE FOR SUPABASE CLOUD
-- This fixes timestamps to display correctly in local timezone (Pacific Time)
-- ============================================================================

-- Step 1: Update the instance generation function to use timezone-aware timestamps
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
    v_start_timestamp TIMESTAMPTZ;
    v_end_timestamp TIMESTAMPTZ;
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

            -- Create timestamps in America/Los_Angeles timezone
            -- This ensures 8:00 AM means 8:00 AM Pacific, stored as UTC
            v_start_timestamp := timezone('America/Los_Angeles',
                (v_current_date || ' ' || v_block.start_time)::TIMESTAMP
            );
            v_end_timestamp := timezone('America/Los_Angeles',
                (v_current_date || ' ' || v_block.end_time)::TIMESTAMP
            );

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

-- Step 2: Delete old instances with incorrect times
DELETE FROM events.open_play_instances;

-- Step 3: Regenerate with correct timezone
SELECT api.generate_open_play_instances(
    (CURRENT_DATE - INTERVAL '30 days')::DATE,
    (CURRENT_DATE + INTERVAL '90 days')::DATE
);

-- Step 4: Verify - should show 08:00, 10:00, etc (not 01:00, 04:00)
SELECT
    instance_date,
    start_time AT TIME ZONE 'America/Los_Angeles' as start_local,
    end_time AT TIME ZONE 'America/Los_Angeles' as end_local,
    TO_CHAR(start_time AT TIME ZONE 'America/Los_Angeles', 'HH24:MI') as start_formatted,
    TO_CHAR(end_time AT TIME ZONE 'America/Los_Angeles', 'HH24:MI') as end_formatted
FROM events.open_play_instances
WHERE instance_date = '2025-10-08'
ORDER BY start_time
LIMIT 10;
