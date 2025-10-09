-- ============================================================================
-- COURT BOOKING CLOUD TEST
-- Simple test script for cloud Supabase database
-- ============================================================================

SET search_path TO events, api, app_auth, public;

\echo '============================================================================'
\echo 'CLOUD COURT BOOKING SYSTEM TEST'
\echo '============================================================================'

-- Test 1: Check Available Courts for Tomorrow 9am-11am
\echo ''
\echo 'TEST 1: Checking available courts for tomorrow 9:00 AM - 11:00 AM...'
SELECT api.get_available_courts(
    (CURRENT_DATE + INTERVAL '1 day' + TIME '09:00:00')::timestamptz,
    (CURRENT_DATE + INTERVAL '1 day' + TIME '11:00:00')::timestamptz,
    'indoor'::events.court_environment,
    2
);

-- Test 2: Create Open Play Event
\echo ''
\echo 'TEST 2: Creating Open Play event for tomorrow...'
SELECT api.create_event_with_courts(
    p_title := 'Cloud Test - Morning Open Play',
    p_event_type := 'event_scramble'::events.event_type,
    p_start_time := (CURRENT_DATE + INTERVAL '1 day' + TIME '09:00:00')::timestamptz,
    p_end_time := (CURRENT_DATE + INTERVAL '1 day' + TIME '11:00:00')::timestamptz,
    p_court_ids := ARRAY(
        SELECT id FROM events.courts WHERE court_number IN (1, 2) LIMIT 2
    ),
    p_description := 'Cloud test event',
    p_max_capacity := 16,
    p_min_capacity := 4,
    p_price_member := 5.00,
    p_price_guest := 10.00
);

-- Test 3: Verify Event Created
\echo ''
\echo 'TEST 3: Verifying event was created...'
SELECT
    e.id,
    e.title,
    e.start_time,
    e.end_time,
    e.max_capacity,
    array_agg(c.court_number ORDER BY c.court_number) as courts
FROM events.events e
LEFT JOIN events.event_courts ec ON e.id = ec.event_id
LEFT JOIN events.courts c ON ec.court_id = c.id
WHERE e.title ILIKE '%Cloud Test%'
GROUP BY e.id
ORDER BY e.created_at DESC
LIMIT 1;

-- Test 4: View Court Schedule
\echo ''
\echo 'TEST 4: Viewing court schedule for tomorrow...'
SELECT api.get_court_schedule(
    (CURRENT_DATE + INTERVAL '1 day' + TIME '08:00:00')::timestamptz,
    (CURRENT_DATE + INTERVAL '1 day' + TIME '12:00:00')::timestamptz,
    NULL,
    'indoor'::events.court_environment
);

-- Test 5: Summary
\echo ''
\echo 'TEST 5: Summary Report'
SELECT
    COUNT(*) as total_courts,
    SUM(CASE WHEN environment = 'indoor' THEN 1 ELSE 0 END) as indoor_courts,
    SUM(CASE WHEN environment = 'outdoor' THEN 1 ELSE 0 END) as outdoor_courts
FROM events.courts;

\echo ''
\echo '============================================================================'
\echo 'CLOUD TEST COMPLETE'
\echo '============================================================================'
