-- ============================================================================
-- FIX OPEN PLAY INSTANCE TIMES
-- This script regenerates open play instances with the updated schedule times
--
-- ISSUE: Admin dashboard showing old times (6 AM) instead of new times (8 AM)
-- CAUSE: open_play_instances table contains stale data from before seed update
-- SOLUTION: Delete old instances and regenerate from updated schedule blocks
-- ============================================================================

-- STEP 1: Delete all existing instances
-- This removes all stale data with old times
DELETE FROM events.open_play_instances;

-- STEP 2: Regenerate instances for a reasonable date range
-- Generates instances for 30 days in the past and 90 days in the future
-- This ensures the admin dashboard has data to display immediately
SELECT api.generate_open_play_instances(
    (CURRENT_DATE - INTERVAL '30 days')::DATE,  -- Start 30 days ago
    (CURRENT_DATE + INTERVAL '90 days')::DATE   -- Generate for next 90 days (4 months)
) AS generation_result;

-- STEP 3: Verify the regeneration
-- This query shows a sample of the new instances with correct times
SELECT
    opi.instance_date,
    TO_CHAR(opi.start_time, 'HH24:MI') as start_time,
    TO_CHAR(opi.end_time, 'HH24:MI') as end_time,
    sb.name,
    CASE sb.day_of_week
        WHEN 0 THEN 'Sunday'
        WHEN 1 THEN 'Monday'
        WHEN 2 THEN 'Tuesday'
        WHEN 3 THEN 'Wednesday'
        WHEN 4 THEN 'Thursday'
        WHEN 5 THEN 'Friday'
        WHEN 6 THEN 'Saturday'
    END as day_name
FROM events.open_play_instances opi
JOIN events.open_play_schedule_blocks sb ON sb.id = opi.schedule_block_id
WHERE opi.instance_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '7 days'
ORDER BY opi.instance_date, opi.start_time
LIMIT 20;

-- STEP 4: Show summary statistics
SELECT
    COUNT(*) as total_instances,
    MIN(instance_date) as earliest_date,
    MAX(instance_date) as latest_date,
    MIN(TO_CHAR(start_time, 'HH24:MI')) as earliest_time,
    MAX(TO_CHAR(end_time, 'HH24:MI')) as latest_time
FROM events.open_play_instances;

-- Expected results:
-- - earliest_time should be 08:00:00 (not 06:00:00 or 01:00:00)
-- - latest_time should be 21:00:00 (9 PM)
-- - All instances should have 2-hour durations (or 1-hour for final sessions)
