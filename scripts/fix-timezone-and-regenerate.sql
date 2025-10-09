-- Fix timezone for open play instances
-- Run this after applying the updated 37-open-play-schedule-api.sql

-- Step 1: Delete all existing instances
DELETE FROM events.open_play_instances;

-- Step 2: Regenerate instances for the next 30 days using the updated function
SELECT api.generate_open_play_instances(
    CURRENT_DATE,
    (CURRENT_DATE + INTERVAL '30 days')::DATE
);

-- Step 3: Verify the timestamps are correct
SELECT
    instance_date,
    start_time,
    end_time,
    start_time AT TIME ZONE 'America/Chicago' as start_time_cst,
    end_time AT TIME ZONE 'America/Chicago' as end_time_cst
FROM events.open_play_instances
ORDER BY instance_date, start_time
LIMIT 10;
