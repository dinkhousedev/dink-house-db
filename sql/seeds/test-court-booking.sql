-- ============================================================================
-- COURT BOOKING TEST SCRIPT
-- Tests court availability, event creation, and conflict prevention
-- ============================================================================

-- Set search path
SET search_path TO events, api, app_auth, public;

\echo '============================================================================'
\echo 'COURT BOOKING SYSTEM TEST'
\echo '============================================================================'
\echo ''

-- ============================================================================
-- STEP 1: Check Available Courts for Tomorrow 9am-11am
-- ============================================================================

\echo '1. Checking available courts for tomorrow 9:00 AM - 11:00 AM...'
\echo ''

SELECT api.get_available_courts(
    (CURRENT_DATE + INTERVAL '1 day' + TIME '09:00:00')::timestamptz,
    (CURRENT_DATE + INTERVAL '1 day' + TIME '11:00:00')::timestamptz,
    NULL, -- all environments
    2     -- need at least 2 courts
) AS availability_check;

\echo ''

-- ============================================================================
-- STEP 2: Get Court IDs for Booking
-- ============================================================================

\echo '2. Getting court IDs for indoor courts 1 and 2...'
\echo ''

SELECT
    id,
    court_number,
    name,
    environment,
    status
FROM events.courts
WHERE court_number IN (1, 2)
ORDER BY court_number;

\echo ''

-- Store court IDs in variables for later use
DO $$
DECLARE
    v_court_1_id UUID;
    v_court_2_id UUID;
    v_event_id UUID;
BEGIN
    -- Get court IDs
    SELECT id INTO v_court_1_id FROM events.courts WHERE court_number = 1;
    SELECT id INTO v_court_2_id FROM events.courts WHERE court_number = 2;

    RAISE NOTICE 'Court 1 ID: %', v_court_1_id;
    RAISE NOTICE 'Court 2 ID: %', v_court_2_id;
END $$;

\echo ''

-- ============================================================================
-- STEP 3: Create Open Play Event for Tomorrow
-- ============================================================================

\echo '3. Creating Open Play event for tomorrow 9:00 AM - 11:00 AM...'
\echo ''

-- Note: This requires authentication. For testing, you may need to:
-- 1. Run this as service_role
-- 2. Or create via the admin API with proper auth token

-- Example of creating event (will fail if not authenticated as staff)
SELECT api.create_event_with_courts(
    p_title := 'Morning Open Play - Test Event',
    p_event_type := 'event_scramble'::events.event_type,
    p_start_time := (CURRENT_DATE + INTERVAL '1 day' + TIME '09:00:00')::timestamptz,
    p_end_time := (CURRENT_DATE + INTERVAL '1 day' + TIME '11:00:00')::timestamptz,
    p_court_ids := ARRAY(
        SELECT id FROM events.courts WHERE court_number IN (1, 2)
    ),
    p_description := 'Test open play session for court booking verification',
    p_max_capacity := 16,
    p_min_capacity := 4,
    p_price_member := 5.00,
    p_price_guest := 10.00
) AS event_created;

\echo ''

-- ============================================================================
-- STEP 4: Verify Event Was Created
-- ============================================================================

\echo '4. Verifying event was created...'
\echo ''

SELECT
    e.id,
    e.title,
    e.event_type,
    e.start_time,
    e.end_time,
    e.max_capacity,
    e.current_registrations,
    array_agg(c.court_number ORDER BY c.court_number) as booked_courts
FROM events.events e
LEFT JOIN events.event_courts ec ON e.id = ec.event_id
LEFT JOIN events.courts c ON ec.court_id = c.id
WHERE e.start_time >= CURRENT_DATE + INTERVAL '1 day'
    AND e.start_time < CURRENT_DATE + INTERVAL '2 days'
GROUP BY e.id
ORDER BY e.start_time;

\echo ''

-- ============================================================================
-- STEP 5: Test Conflict Detection (Try to Book Same Courts)
-- ============================================================================

\echo '5. Testing conflict detection - attempting to book same courts...'
\echo 'This should FAIL with a court conflict error:'
\echo ''

-- This should fail because courts 1 and 2 are already booked
SELECT api.create_event_with_courts(
    p_title := 'Conflicting Event - Should Fail',
    p_event_type := 'clinic'::events.event_type,
    p_start_time := (CURRENT_DATE + INTERVAL '1 day' + TIME '09:30:00')::timestamptz,
    p_end_time := (CURRENT_DATE + INTERVAL '1 day' + TIME '10:30:00')::timestamptz,
    p_court_ids := ARRAY(
        SELECT id FROM events.courts WHERE court_number IN (1, 2)
    ),
    p_description := 'This should fail due to court conflict',
    p_max_capacity := 12
) AS conflict_test;

\echo ''

-- ============================================================================
-- STEP 6: Book Different Courts (Should Succeed)
-- ============================================================================

\echo '6. Booking different courts (3, 4) - should succeed...'
\echo ''

SELECT api.create_event_with_courts(
    p_title := 'Afternoon Clinic - Different Courts',
    p_event_type := 'clinic'::events.event_type,
    p_start_time := (CURRENT_DATE + INTERVAL '1 day' + TIME '09:00:00')::timestamptz,
    p_end_time := (CURRENT_DATE + INTERVAL '1 day' + TIME '11:00:00')::timestamptz,
    p_court_ids := ARRAY(
        SELECT id FROM events.courts WHERE court_number IN (3, 4)
    ),
    p_description := 'This should succeed - different courts',
    p_max_capacity := 12,
    p_price_member := 20.00
) AS different_courts_event;

\echo ''

-- ============================================================================
-- STEP 7: View Court Schedule for Tomorrow
-- ============================================================================

\echo '7. Viewing complete court schedule for tomorrow...'
\echo ''

SELECT api.get_court_schedule(
    (CURRENT_DATE + INTERVAL '1 day' + TIME '08:00:00')::timestamptz,
    (CURRENT_DATE + INTERVAL '1 day' + TIME '12:00:00')::timestamptz,
    NULL, -- all courts
    'indoor'::events.court_environment -- indoor courts only
) AS court_schedule;

\echo ''

-- ============================================================================
-- STEP 8: Check Available Courts Again
-- ============================================================================

\echo '8. Checking remaining available courts for same time slot...'
\echo ''

SELECT api.get_available_courts(
    (CURRENT_DATE + INTERVAL '1 day' + TIME '09:00:00')::timestamptz,
    (CURRENT_DATE + INTERVAL '1 day' + TIME '11:00:00')::timestamptz,
    'indoor'::events.court_environment,
    1
) AS remaining_availability;

\echo ''

-- ============================================================================
-- STEP 9: Test Player Registration (If authenticated)
-- ============================================================================

\echo '9. Testing player registration for the first event...'
\echo ''

-- Get the event ID
DO $$
DECLARE
    v_event_id UUID;
    v_registration_result JSON;
BEGIN
    -- Get the first event created today for tomorrow
    SELECT id INTO v_event_id
    FROM events.events
    WHERE title = 'Morning Open Play - Test Event'
        AND start_time >= CURRENT_DATE + INTERVAL '1 day'
        AND start_time < CURRENT_DATE + INTERVAL '2 days'
    LIMIT 1;

    IF v_event_id IS NOT NULL THEN
        -- Try to register (will fail if not authenticated)
        BEGIN
            SELECT api.register_for_event(
                p_event_id := v_event_id,
                p_player_name := 'Test Player',
                p_player_email := 'testplayer@example.com',
                p_skill_level := '3.5'::events.skill_level
            ) INTO v_registration_result;

            RAISE NOTICE 'Registration successful: %', v_registration_result;
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'Registration requires authentication: %', SQLERRM;
        END;
    ELSE
        RAISE NOTICE 'No test event found to register for';
    END IF;
END $$;

\echo ''

-- ============================================================================
-- STEP 10: Summary Report
-- ============================================================================

\echo '10. TEST SUMMARY REPORT'
\echo '============================================================================'
\echo ''

SELECT
    'Total Courts' as metric,
    COUNT(*)::text as value
FROM events.courts
UNION ALL
SELECT
    'Indoor Courts',
    COUNT(*)::text
FROM events.courts
WHERE environment = 'indoor'
UNION ALL
SELECT
    'Outdoor Courts',
    COUNT(*)::text
FROM events.courts
WHERE environment = 'outdoor'
UNION ALL
SELECT
    'Events for Tomorrow',
    COUNT(*)::text
FROM events.events
WHERE start_time >= CURRENT_DATE + INTERVAL '1 day'
    AND start_time < CURRENT_DATE + INTERVAL '2 days'
UNION ALL
SELECT
    'Courts Booked Tomorrow 9-11am',
    COUNT(DISTINCT ec.court_id)::text
FROM events.event_courts ec
JOIN events.events e ON ec.event_id = e.id
WHERE (e.start_time, e.end_time) OVERLAPS (
    (CURRENT_DATE + INTERVAL '1 day' + TIME '09:00:00')::timestamptz,
    (CURRENT_DATE + INTERVAL '1 day' + TIME '11:00:00')::timestamptz
)
AND e.is_cancelled = false;

\echo ''
\echo '============================================================================'
\echo 'TEST COMPLETE'
\echo '============================================================================'
