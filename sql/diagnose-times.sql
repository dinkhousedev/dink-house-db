-- ============================================================================
-- DIAGNOSE TIME DISPLAY ISSUES
-- This script checks for timezone and data issues in open play instances
-- ============================================================================

-- STEP 1: Check what's currently in the instances table for Oct 8
SELECT
    'Current Instances for Oct 8' as check_type,
    opi.instance_date,
    opi.start_time,
    opi.end_time,
    TO_CHAR(opi.start_time, 'YYYY-MM-DD HH24:MI:SS TZ') as formatted_start,
    TO_CHAR(opi.end_time, 'YYYY-MM-DD HH24:MI:SS TZ') as formatted_end,
    sb.name as block_name,
    sb.start_time as template_start,
    sb.end_time as template_end
FROM events.open_play_instances opi
JOIN events.open_play_schedule_blocks sb ON sb.id = opi.schedule_block_id
WHERE opi.instance_date = '2025-10-08'
ORDER BY opi.start_time
LIMIT 10;

-- STEP 2: Check timezone settings
SELECT
    'Database Timezone Settings' as check_type,
    name,
    setting
FROM pg_settings
WHERE name IN ('TimeZone', 'timezone', 'log_timezone');

-- STEP 3: Check schedule blocks for Wednesday (day 3)
SELECT
    'Wednesday Schedule Blocks' as check_type,
    id,
    name,
    start_time,
    end_time,
    TO_CHAR(start_time, 'HH24:MI') as start_formatted,
    TO_CHAR(end_time, 'HH24:MI') as end_formatted,
    is_active
FROM events.open_play_schedule_blocks
WHERE day_of_week = 3
ORDER BY start_time;

-- STEP 4: Check if there are ANY instances for Oct 8
SELECT
    'Instance Count' as check_type,
    COUNT(*) as total_instances,
    MIN(start_time) as earliest_start,
    MAX(end_time) as latest_end
FROM events.open_play_instances
WHERE instance_date = '2025-10-08';

-- STEP 5: Show the data type of the timestamp columns
SELECT
    'Column Data Types' as check_type,
    column_name,
    data_type,
    datetime_precision
FROM information_schema.columns
WHERE table_schema = 'events'
  AND table_name = 'open_play_instances'
  AND column_name IN ('start_time', 'end_time');
