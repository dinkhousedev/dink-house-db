-- ============================================================================
-- OPEN PLAY SCHEDULE SEED DATA
-- Seeds the weekly schedule based on the Dink House Complete Schedule
-- ============================================================================

-- First, ensure we have 5 courts in the system
-- Insert courts if they don't exist
INSERT INTO events.courts (court_number, name, surface_type, environment, status, location, max_capacity)
VALUES
    (1, 'Court 1', 'indoor', 'indoor', 'available', 'Main Facility', 4),
    (2, 'Court 2', 'indoor', 'indoor', 'available', 'Main Facility', 4),
    (3, 'Court 3', 'indoor', 'indoor', 'available', 'Main Facility', 4),
    (4, 'Court 4', 'indoor', 'indoor', 'available', 'Main Facility', 4),
    (5, 'Court 5', 'indoor', 'indoor', 'available', 'Main Facility', 4)
ON CONFLICT (court_number) DO NOTHING;

-- ============================================================================
-- MONDAY - "Advanced Focus"
-- ============================================================================

-- Monday 8-10 AM: Divided (Adv: Courts 1-2, Int: 3-4, Beg: 5)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Monday Morning Divided',
        'Morning open play divided by skill level',
        1, '08:00', '10:00',
        'divided_by_skill', 20.00, 25.00, 40, 8
    ) RETURNING id INTO v_block_id;

    -- Court allocations: Advanced 2 courts (16 max), Intermediate 2 courts (16 max), Beginner 1 court (8 max)
    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, sort_order)
    SELECT v_block_id, id, 4.5, 6.0, 'Advanced', 1 FROM events.courts WHERE court_number = 1
    UNION ALL SELECT v_block_id, id, 4.5, 6.0, 'Advanced', 2 FROM events.courts WHERE court_number = 2
    UNION ALL SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 3 FROM events.courts WHERE court_number = 3
    UNION ALL SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 4 FROM events.courts WHERE court_number = 4
    UNION ALL SELECT v_block_id, id, 0.0, 2.99, 'Beginner', 5 FROM events.courts WHERE court_number = 5;
END $$;

-- Monday 10 AM-12 PM: Mixed
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Monday Midday Mixed 1',
        'Mixed level open play',
        1, '10:00', '12:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    -- All courts available for mixed play (5 courts × 8 = 40 max)
    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Monday 12-2 PM: Mixed
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Monday Midday Mixed 2',
        'Mixed level open play',
        1, '12:00', '14:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Monday 2-4 PM: Mixed
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Monday Afternoon Mixed',
        'Mixed level open play',
        1, '14:00', '16:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Monday 4-6 PM: Mixed
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Monday Late Afternoon Mixed',
        'Mixed level open play',
        1, '16:00', '18:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Monday 6-8 PM: Divided (Adv: Courts 1-2, Int: 3-4, Beg: 5)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Monday Evening Divided',
        'Evening open play divided by skill level',
        1, '18:00', '20:00',
        'divided_by_skill', 20.00, 25.00, 40, 8
    ) RETURNING id INTO v_block_id;

    -- Advanced 2 courts (16 max), Intermediate 2 courts (16 max), Beginner 1 court (8 max)
    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, sort_order)
    SELECT v_block_id, id, 4.5, 6.0, 'Advanced', 1 FROM events.courts WHERE court_number = 1
    UNION ALL SELECT v_block_id, id, 4.5, 6.0, 'Advanced', 2 FROM events.courts WHERE court_number = 2
    UNION ALL SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 3 FROM events.courts WHERE court_number = 3
    UNION ALL SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 4 FROM events.courts WHERE court_number = 4
    UNION ALL SELECT v_block_id, id, 0.0, 2.99, 'Beginner', 5 FROM events.courts WHERE court_number = 5;
END $$;

-- Monday 8-9 PM: Mixed
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Monday Evening Mixed',
        'Wind down with mixed play',
        1, '20:00', '21:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- ============================================================================
-- TUESDAY - "Beginner Friendly"
-- ============================================================================

-- Tuesday 8-10 AM: Divided (Int: Courts 1-2, Adv: 3-4, Beg: 5)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Tuesday Morning Divided',
        'Morning open play divided by skill level',
        2, '08:00', '10:00',
        'divided_by_skill', 20.00, 25.00, 40, 8
    ) RETURNING id INTO v_block_id;

    -- Intermediate 2 courts (16 max), Advanced 2 courts (16 max), Beginner 1 court (8 max)
    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, sort_order)
    SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 1 FROM events.courts WHERE court_number = 1
    UNION ALL SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 2 FROM events.courts WHERE court_number = 2
    UNION ALL SELECT v_block_id, id, 4.5, 6.0, 'Advanced', 3 FROM events.courts WHERE court_number = 3
    UNION ALL SELECT v_block_id, id, 4.5, 6.0, 'Advanced', 4 FROM events.courts WHERE court_number = 4
    UNION ALL SELECT v_block_id, id, 0.0, 2.99, 'Beginner', 5 FROM events.courts WHERE court_number = 5;
END $$;

-- Tuesday 10 AM-12 PM: Mixed
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Tuesday Morning Mixed',
        'Mixed level open play',
        2, '10:00', '12:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Tuesday 12-2 PM: Beginner Dedicated (All 5 courts)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, dedicated_skill_min, dedicated_skill_max, dedicated_skill_label,
        price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Tuesday Beginner Focus',
        'All 5 courts dedicated to beginner players - perfect for newcomers!',
        2, '12:00', '14:00',
        'dedicated_skill', 0.0, 2.99, 'Beginner',
        15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    -- All 5 courts for Beginners (40 max)
    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, sort_order)
    SELECT v_block_id, id, 0.0, 2.99, 'Beginner', court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Tuesday 2-4 PM: Mixed
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Tuesday Afternoon Mixed',
        'Mixed level open play',
        2, '14:00', '16:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Tuesday 4-6 PM: Mixed
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Tuesday Late Afternoon Mixed',
        'Mixed level open play',
        2, '16:00', '18:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Tuesday 6-8 PM: Divided (Int: Courts 1-2, Beg: 3-4, Adv: 5)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Tuesday Evening Divided',
        'Evening open play divided by skill level',
        2, '18:00', '20:00',
        'divided_by_skill', 20.00, 25.00, 40, 8
    ) RETURNING id INTO v_block_id;

    -- Intermediate 2 courts (16 max), Beginner 2 courts (16 max), Advanced 1 court (8 max)
    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, sort_order)
    SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 1 FROM events.courts WHERE court_number = 1
    UNION ALL SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 2 FROM events.courts WHERE court_number = 2
    UNION ALL SELECT v_block_id, id, 0.0, 2.99, 'Beginner', 3 FROM events.courts WHERE court_number = 3
    UNION ALL SELECT v_block_id, id, 0.0, 2.99, 'Beginner', 4 FROM events.courts WHERE court_number = 4
    UNION ALL SELECT v_block_id, id, 4.5, 6.0, 'Advanced', 5 FROM events.courts WHERE court_number = 5;
END $$;

-- Tuesday 8-9 PM: Mixed
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Tuesday Evening Mixed',
        'Wind down with mixed play',
        2, '20:00', '21:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- ============================================================================
-- WEDNESDAY - "Intermediate Day"
-- ============================================================================

-- Wednesday 8-10 AM: Divided (Adv: Courts 1-2, Beg: 3-4, Int: 5)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Wednesday Morning Divided',
        'Morning open play divided by skill level',
        3, '08:00', '10:00',
        'divided_by_skill', 20.00, 25.00, 40, 8
    ) RETURNING id INTO v_block_id;

    -- Advanced 2 courts (16 max), Beginner 2 courts (16 max), Intermediate 1 court (8 max)
    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, sort_order)
    SELECT v_block_id, id, 4.5, 6.0, 'Advanced', 1 FROM events.courts WHERE court_number = 1
    UNION ALL SELECT v_block_id, id, 4.5, 6.0, 'Advanced', 2 FROM events.courts WHERE court_number = 2
    UNION ALL SELECT v_block_id, id, 0.0, 2.99, 'Beginner', 3 FROM events.courts WHERE court_number = 3
    UNION ALL SELECT v_block_id, id, 0.0, 2.99, 'Beginner', 4 FROM events.courts WHERE court_number = 4
    UNION ALL SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 5 FROM events.courts WHERE court_number = 5;
END $$;

-- Wednesday 10 AM-12 PM: Mixed
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Wednesday Morning Mixed',
        'Mixed level open play',
        3, '10:00', '12:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Wednesday 12-2 PM: Intermediate Dedicated (All 5 courts)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, dedicated_skill_min, dedicated_skill_max, dedicated_skill_label,
        price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Wednesday Intermediate Focus 1',
        'All 5 courts dedicated to intermediate players - skill-building paradise!',
        3, '12:00', '14:00',
        'dedicated_skill', 3.0, 4.49, 'Intermediate',
        15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    -- All 5 courts for Intermediate (40 max)
    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, sort_order)
    SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Wednesday 2-4 PM: Intermediate Dedicated (All 5 courts)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, dedicated_skill_min, dedicated_skill_max, dedicated_skill_label,
        price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Wednesday Intermediate Focus 2',
        'Continued intermediate focus time',
        3, '14:00', '16:00',
        'dedicated_skill', 3.0, 4.49, 'Intermediate',
        15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, sort_order)
    SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Wednesday 4-6 PM: Mixed
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Wednesday Late Afternoon Mixed',
        'Mixed level open play',
        3, '16:00', '18:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Wednesday 6-7 PM: Mixed (pre-Ladies Night)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Wednesday Early Evening Mixed',
        'Mixed play before Ladies Night',
        3, '18:00', '19:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Wednesday 7-9 PM: Ladies Dink Night (Special Event)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, special_event_name, price_member, price_guest, max_capacity, max_players_per_court,
        special_instructions
    ) VALUES (
        'Ladies Dink Night',
        'Women only, all skill levels welcome - community-building night!',
        3, '19:00', '21:00',
        'special_event', 'Ladies Dink Night', 15.00, 20.00, 40, 8,
        'Women only event. All skill levels welcome. Supportive environment, social play.'
    ) RETURNING id INTO v_block_id;

    -- All 5 courts for Ladies Night (40 max)
    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'All Levels', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- ============================================================================
-- THURSDAY - "Advanced Midday"
-- ============================================================================

-- Thursday 8-10 AM: Divided (Beg: Courts 1-2, Int: 3-4, Adv: 5)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Thursday Morning Divided',
        'Morning open play divided by skill level',
        4, '08:00', '10:00',
        'divided_by_skill', 20.00, 25.00, 40, 8
    ) RETURNING id INTO v_block_id;

    -- Beginner 2 courts (16 max), Intermediate 2 courts (16 max), Advanced 1 court (8 max)
    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, sort_order)
    SELECT v_block_id, id, 0.0, 2.99, 'Beginner', 1 FROM events.courts WHERE court_number = 1
    UNION ALL SELECT v_block_id, id, 0.0, 2.99, 'Beginner', 2 FROM events.courts WHERE court_number = 2
    UNION ALL SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 3 FROM events.courts WHERE court_number = 3
    UNION ALL SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 4 FROM events.courts WHERE court_number = 4
    UNION ALL SELECT v_block_id, id, 4.5, 6.0, 'Advanced', 5 FROM events.courts WHERE court_number = 5;
END $$;

-- Thursday 10 AM-12 PM: Mixed
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Thursday Morning Mixed',
        'Mixed level open play',
        4, '10:00', '12:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Thursday 12-2 PM: Advanced Dedicated (All 5 courts)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, dedicated_skill_min, dedicated_skill_max, dedicated_skill_label,
        price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Thursday Advanced Focus 1',
        'All 5 courts dedicated to advanced players - tournament-level intensity!',
        4, '12:00', '14:00',
        'dedicated_skill', 4.5, 6.0, 'Advanced',
        15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    -- All 5 courts for Advanced (40 max)
    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, sort_order)
    SELECT v_block_id, id, 4.5, 6.0, 'Advanced', court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Thursday 2-4 PM: Advanced Dedicated (All 5 courts)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, dedicated_skill_min, dedicated_skill_max, dedicated_skill_label,
        price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Thursday Advanced Focus 2',
        'Continued advanced focus time',
        4, '14:00', '16:00',
        'dedicated_skill', 4.5, 6.0, 'Advanced',
        15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, sort_order)
    SELECT v_block_id, id, 4.5, 6.0, 'Advanced', court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Thursday 4-6 PM: Mixed
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Thursday Late Afternoon Mixed',
        'Mixed level open play',
        4, '16:00', '18:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Thursday 6-8 PM: Divided (Beg: Courts 1-2, Int: 3-4, Adv: 5)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Thursday Evening Divided',
        'Evening open play divided by skill level',
        4, '18:00', '20:00',
        'divided_by_skill', 20.00, 25.00, 40, 8
    ) RETURNING id INTO v_block_id;

    -- Beginner 2 courts (16 max), Intermediate 2 courts (16 max), Advanced 1 court (8 max)
    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, sort_order)
    SELECT v_block_id, id, 0.0, 2.99, 'Beginner', 1 FROM events.courts WHERE court_number = 1
    UNION ALL SELECT v_block_id, id, 0.0, 2.99, 'Beginner', 2 FROM events.courts WHERE court_number = 2
    UNION ALL SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 3 FROM events.courts WHERE court_number = 3
    UNION ALL SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 4 FROM events.courts WHERE court_number = 4
    UNION ALL SELECT v_block_id, id, 4.5, 6.0, 'Advanced', 5 FROM events.courts WHERE court_number = 5;
END $$;

-- Thursday 8-9 PM: Mixed
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Thursday Evening Mixed',
        'Wind down with mixed play',
        4, '20:00', '21:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- ============================================================================
-- FRIDAY - "TGIF Social"
-- ============================================================================

-- Friday 8-10 AM: Divided (Int: Courts 1-2, Adv: 3-4, Beg: 5)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Friday Morning Divided',
        'Morning open play divided by skill level',
        5, '08:00', '10:00',
        'divided_by_skill', 20.00, 25.00, 40, 8
    ) RETURNING id INTO v_block_id;

    -- Intermediate 2 courts (16 max), Advanced 2 courts (16 max), Beginner 1 court (8 max)
    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, sort_order)
    SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 1 FROM events.courts WHERE court_number = 1
    UNION ALL SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 2 FROM events.courts WHERE court_number = 2
    UNION ALL SELECT v_block_id, id, 4.5, 6.0, 'Advanced', 3 FROM events.courts WHERE court_number = 3
    UNION ALL SELECT v_block_id, id, 4.5, 6.0, 'Advanced', 4 FROM events.courts WHERE court_number = 4
    UNION ALL SELECT v_block_id, id, 0.0, 2.99, 'Beginner', 5 FROM events.courts WHERE court_number = 5;
END $$;

-- Friday 10 AM-12 PM: Mixed
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Friday Morning Mixed',
        'Mixed level open play',
        5, '10:00', '12:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Friday 12-2 PM: Mixed
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Friday Midday Mixed',
        'Mixed level open play - flexible day!',
        5, '12:00', '14:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Friday 2-4 PM: Mixed
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Friday Afternoon Mixed',
        'Mixed level open play',
        5, '14:00', '16:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Friday 4-6 PM: Mixed
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Friday Late Afternoon Mixed',
        'Mixed level open play',
        5, '16:00', '18:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Friday 6-8 PM: Divided (Adv: Courts 1-2, Int: 3-4, Beg: 5)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Friday Evening Divided',
        'Evening open play divided by skill level',
        5, '18:00', '20:00',
        'divided_by_skill', 20.00, 25.00, 40, 8
    ) RETURNING id INTO v_block_id;

    -- Advanced 2 courts (16 max), Intermediate 2 courts (16 max), Beginner 1 court (8 max)
    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, sort_order)
    SELECT v_block_id, id, 4.5, 6.0, 'Advanced', 1 FROM events.courts WHERE court_number = 1
    UNION ALL SELECT v_block_id, id, 4.5, 6.0, 'Advanced', 2 FROM events.courts WHERE court_number = 2
    UNION ALL SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 3 FROM events.courts WHERE court_number = 3
    UNION ALL SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 4 FROM events.courts WHERE court_number = 4
    UNION ALL SELECT v_block_id, id, 0.0, 2.99, 'Beginner', 5 FROM events.courts WHERE court_number = 5;
END $$;

-- Friday 8-9 PM: Sunset Social (Special Event)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, special_event_name, price_member, price_guest, max_capacity, max_players_per_court,
        special_instructions
    ) VALUES (
        'Sunset Social',
        'End the week right with casual, social pickleball!',
        5, '20:00', '21:00',
        'special_event', 'Sunset Social', 15.00, 20.00, 40, 8,
        'Casual wind-down play. Mixed levels. Play with friends. No pressure!'
    ) RETURNING id INTO v_block_id;

    -- All 5 courts for Sunset Social (40 max)
    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- ============================================================================
-- SATURDAY - "Weekend Warrior"
-- ============================================================================

-- Saturday 8-10 AM: Divided (Adv: Courts 1-2, Int: 3-4, Beg: 5)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Saturday Morning Divided 1',
        'Early risers get prime morning play',
        6, '08:00', '10:00',
        'divided_by_skill', 20.00, 25.00, 40, 8
    ) RETURNING id INTO v_block_id;

    -- Advanced 2 courts (16 max), Intermediate 2 courts (16 max), Beginner 1 court (8 max)
    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, sort_order)
    SELECT v_block_id, id, 4.5, 6.0, 'Advanced', 1 FROM events.courts WHERE court_number = 1
    UNION ALL SELECT v_block_id, id, 4.5, 6.0, 'Advanced', 2 FROM events.courts WHERE court_number = 2
    UNION ALL SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 3 FROM events.courts WHERE court_number = 3
    UNION ALL SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 4 FROM events.courts WHERE court_number = 4
    UNION ALL SELECT v_block_id, id, 0.0, 2.99, 'Beginner', 5 FROM events.courts WHERE court_number = 5;
END $$;

-- Saturday 10 AM-12 PM: Divided (Adv: Courts 1-2, Int: 3-4, Beg: 5)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Saturday Morning Divided 2',
        'Continued morning divided play',
        6, '10:00', '12:00',
        'divided_by_skill', 20.00, 25.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, sort_order)
    SELECT v_block_id, id, 4.5, 6.0, 'Advanced', 1 FROM events.courts WHERE court_number = 1
    UNION ALL SELECT v_block_id, id, 4.5, 6.0, 'Advanced', 2 FROM events.courts WHERE court_number = 2
    UNION ALL SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 3 FROM events.courts WHERE court_number = 3
    UNION ALL SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 4 FROM events.courts WHERE court_number = 4
    UNION ALL SELECT v_block_id, id, 0.0, 2.99, 'Beginner', 5 FROM events.courts WHERE court_number = 5;
END $$;

-- Saturday 12-2 PM: Beginner Dedicated (All 5 courts)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, dedicated_skill_min, dedicated_skill_max, dedicated_skill_label,
        price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Saturday Beginner Focus',
        'Weekend beginner block - all 5 courts for newcomers!',
        6, '12:00', '14:00',
        'dedicated_skill', 0.0, 2.99, 'Beginner',
        15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    -- All 5 courts for Beginners (40 max)
    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, sort_order)
    SELECT v_block_id, id, 0.0, 2.99, 'Beginner', court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Saturday 2-4 PM: Mixed
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Saturday Afternoon Mixed 1',
        'Mixed level open play',
        6, '14:00', '16:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Saturday 4-6 PM: Mixed
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Saturday Afternoon Mixed 2',
        'Mixed level open play',
        6, '16:00', '18:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Saturday 6-8 PM: Divided (Int: Courts 1-2, Adv: 3-4, Beg: 5)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Saturday Evening Divided',
        'Evening open play divided by skill level',
        6, '18:00', '20:00',
        'divided_by_skill', 20.00, 25.00, 40, 8
    ) RETURNING id INTO v_block_id;

    -- Intermediate 2 courts (16 max), Advanced 2 courts (16 max), Beginner 1 court (8 max)
    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, sort_order)
    SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 1 FROM events.courts WHERE court_number = 1
    UNION ALL SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 2 FROM events.courts WHERE court_number = 2
    UNION ALL SELECT v_block_id, id, 4.5, 6.0, 'Advanced', 3 FROM events.courts WHERE court_number = 3
    UNION ALL SELECT v_block_id, id, 4.5, 6.0, 'Advanced', 4 FROM events.courts WHERE court_number = 4
    UNION ALL SELECT v_block_id, id, 0.0, 2.99, 'Beginner', 5 FROM events.courts WHERE court_number = 5;
END $$;

-- Saturday 8-9 PM: Mixed
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Saturday Evening Mixed',
        'Wind down the weekend',
        6, '20:00', '21:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- ============================================================================
-- SUNDAY - "Funday & Clinics"
-- ============================================================================

-- Sunday 8-10 AM: Divided (Int: Courts 1-2, Beg: 3-4, Adv: 5)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Sunday Morning Divided 1',
        'Active morning open play',
        0, '08:00', '10:00',
        'divided_by_skill', 20.00, 25.00, 40, 8
    ) RETURNING id INTO v_block_id;

    -- Intermediate 2 courts (16 max), Beginner 2 courts (16 max), Advanced 1 court (8 max)
    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, sort_order)
    SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 1 FROM events.courts WHERE court_number = 1
    UNION ALL SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 2 FROM events.courts WHERE court_number = 2
    UNION ALL SELECT v_block_id, id, 0.0, 2.99, 'Beginner', 3 FROM events.courts WHERE court_number = 3
    UNION ALL SELECT v_block_id, id, 0.0, 2.99, 'Beginner', 4 FROM events.courts WHERE court_number = 4
    UNION ALL SELECT v_block_id, id, 4.5, 6.0, 'Advanced', 5 FROM events.courts WHERE court_number = 5;
END $$;

-- Sunday 10 AM-12 PM: Divided (Int: Courts 1-2, Beg: 3-4, Adv: 5)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Sunday Morning Divided 2',
        'Continued morning divided play',
        0, '10:00', '12:00',
        'divided_by_skill', 20.00, 25.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, sort_order)
    SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 1 FROM events.courts WHERE court_number = 1
    UNION ALL SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 2 FROM events.courts WHERE court_number = 2
    UNION ALL SELECT v_block_id, id, 0.0, 2.99, 'Beginner', 3 FROM events.courts WHERE court_number = 3
    UNION ALL SELECT v_block_id, id, 0.0, 2.99, 'Beginner', 4 FROM events.courts WHERE court_number = 4
    UNION ALL SELECT v_block_id, id, 4.5, 6.0, 'Advanced', 5 FROM events.courts WHERE court_number = 5;
END $$;

-- Sunday 12-2 PM: Advanced Dedicated (All 5 courts)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, dedicated_skill_min, dedicated_skill_max, dedicated_skill_label,
        price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Sunday Advanced Focus',
        'Weekend advanced block - all 5 courts for high-level play!',
        0, '12:00', '14:00',
        'dedicated_skill', 4.5, 6.0, 'Advanced',
        15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    -- All 5 courts for Advanced (40 max)
    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, sort_order)
    SELECT v_block_id, id, 4.5, 6.0, 'Advanced', court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Sunday 2-4 PM: Mixed
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Sunday Afternoon Mixed 1',
        'Mixed level open play',
        0, '14:00', '16:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Sunday 4-6 PM: Mixed
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Sunday Afternoon Mixed 2',
        'Mixed level open play',
        0, '16:00', '18:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- Sunday 6-8 PM: Dink & Drill Clinics (Special Event)
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, special_event_name, price_member, price_guest, max_capacity, max_players_per_court,
        special_instructions
    ) VALUES (
        'Dink & Drill Clinics',
        'End the weekend with structured skill-building!',
        0, '18:00', '20:00',
        'special_event', 'Dink & Drill Clinics', 20.00, 25.00, 40, 8,
        'All 5 courts separated by skill level. Structured drills. Pro coaching. Skill development focus.'
    ) RETURNING id INTO v_block_id;

    -- Clinics: Beginner 2 courts (16 max), Intermediate 2 courts (16 max), Advanced 1 court (8 max)
    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, sort_order)
    SELECT v_block_id, id, 0.0, 2.99, 'Beginner', 1 FROM events.courts WHERE court_number = 1
    UNION ALL SELECT v_block_id, id, 0.0, 2.99, 'Beginner', 2 FROM events.courts WHERE court_number = 2
    UNION ALL SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 3 FROM events.courts WHERE court_number = 3
    UNION ALL SELECT v_block_id, id, 3.0, 4.49, 'Intermediate', 4 FROM events.courts WHERE court_number = 4
    UNION ALL SELECT v_block_id, id, 4.5, 6.0, 'Advanced', 5 FROM events.courts WHERE court_number = 5;
END $$;

-- Sunday 8-9 PM: Mixed
DO $$
DECLARE
    v_block_id UUID;
BEGIN
    INSERT INTO events.open_play_schedule_blocks (
        name, description, day_of_week, start_time, end_time,
        session_type, price_member, price_guest, max_capacity, max_players_per_court
    ) VALUES (
        'Sunday Evening Mixed',
        'Wind down the weekend with mixed play',
        0, '20:00', '21:00',
        'mixed_levels', 15.00, 20.00, 40, 8
    ) RETURNING id INTO v_block_id;

    INSERT INTO events.open_play_court_allocations (schedule_block_id, court_id, skill_level_min, skill_level_max, skill_level_label, is_mixed_level, sort_order)
    SELECT v_block_id, id, 0.0, 6.0, 'Mixed', true, court_number
    FROM events.courts
    WHERE court_number BETWEEN 1 AND 5;
END $$;

-- ============================================================================
-- SUMMARY
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '============================================================================';
    RAISE NOTICE 'OPEN PLAY SCHEDULE SEEDED SUCCESSFULLY';
    RAISE NOTICE '============================================================================';
    RAISE NOTICE 'Total schedule blocks created: %', (SELECT COUNT(*) FROM events.open_play_schedule_blocks);
    RAISE NOTICE 'Total court allocations: %', (SELECT COUNT(*) FROM events.open_play_court_allocations);
    RAISE NOTICE '';
    RAISE NOTICE 'Weekly breakdown by session type:';
    RAISE NOTICE '  Divided by skill: % blocks', (SELECT COUNT(*) FROM events.open_play_schedule_blocks WHERE session_type = 'divided_by_skill');
    RAISE NOTICE '  Mixed levels: % blocks', (SELECT COUNT(*) FROM events.open_play_schedule_blocks WHERE session_type = 'mixed_levels');
    RAISE NOTICE '  Dedicated skill: % blocks', (SELECT COUNT(*) FROM events.open_play_schedule_blocks WHERE session_type = 'dedicated_skill');
    RAISE NOTICE '  Special events: % blocks', (SELECT COUNT(*) FROM events.open_play_schedule_blocks WHERE session_type = 'special_event');
    RAISE NOTICE '';
    RAISE NOTICE 'Special events configured:';
    RAISE NOTICE '  - Ladies Dink Night (Wednesday 7-9 PM)';
    RAISE NOTICE '  - Sunset Social (Friday 9-10 PM)';
    RAISE NOTICE '  - Dink & Drill Clinics (Sunday 5-7 PM)';
    RAISE NOTICE '';
    RAISE NOTICE 'Next steps:';
    RAISE NOTICE '  1. Run: SELECT * FROM api.get_weekly_schedule();';
    RAISE NOTICE '  2. Generate instances: SELECT api.generate_open_play_instances(CURRENT_DATE, CURRENT_DATE + 30);';
    RAISE NOTICE '  3. View schedule: SELECT * FROM events.upcoming_open_play;';
    RAISE NOTICE '============================================================================';
END $$;
