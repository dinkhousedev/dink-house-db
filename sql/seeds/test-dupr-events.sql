-- ============================================================================
-- Test DUPR Events - Sample events for different skill levels
-- ============================================================================

-- Get an admin user ID for created_by (use the first admin)
DO $$
DECLARE
    admin_id UUID;
    beginner_bracket_id UUID;
    novice_bracket_id UUID;
    intermediate_bracket_id UUID;
    advanced_bracket_id UUID;
    open_bracket_id UUID;
BEGIN
    -- Get first admin user
    SELECT id INTO admin_id FROM app_auth.admin_users LIMIT 1;

    -- Get bracket IDs
    SELECT id INTO beginner_bracket_id FROM events.dupr_brackets WHERE label = 'Beginner (2.0-2.5)' LIMIT 1;
    SELECT id INTO novice_bracket_id FROM events.dupr_brackets WHERE label = 'Novice (2.5-3.0)' LIMIT 1;
    SELECT id INTO intermediate_bracket_id FROM events.dupr_brackets WHERE label = 'Intermediate (3.0-4.0)' LIMIT 1;
    SELECT id INTO advanced_bracket_id FROM events.dupr_brackets WHERE label = 'Advanced (4.0-4.5)' LIMIT 1;
    SELECT id INTO open_bracket_id FROM events.dupr_brackets WHERE label = 'All Levels' LIMIT 1;

    -- Insert test events
    INSERT INTO events.events (
        title,
        description,
        event_type,
        start_time,
        end_time,
        max_capacity,
        min_capacity,
        dupr_bracket_id,
        dupr_min_rating,
        dupr_max_rating,
        dupr_range_label,
        price_member,
        price_guest,
        is_published,
        created_by
    ) VALUES
    -- Beginner Events
    (
        'Beginner Open Play Session',
        'Perfect for new players! Learn the basics and have fun in a supportive environment.',
        'dupr_open_play',
        NOW() + INTERVAL '2 days',
        NOW() + INTERVAL '2 days' + INTERVAL '2 hours',
        16,
        4,
        beginner_bracket_id,
        2.0,
        2.5,
        'Beginner (2.0-2.5)',
        10.00,
        15.00,
        true,
        admin_id
    ),
    (
        'Introduction to Pickleball Clinic',
        'Learn fundamentals from our experienced coaches. All equipment provided!',
        'clinic',
        NOW() + INTERVAL '3 days',
        NOW() + INTERVAL '3 days' + INTERVAL '1 hour',
        12,
        4,
        beginner_bracket_id,
        2.0,
        2.5,
        'Beginner (2.0-2.5)',
        20.00,
        25.00,
        true,
        admin_id
    ),

    -- Novice/Intermediate Events
    (
        'Novice DUPR Open Play',
        'For players with some experience looking to improve their game.',
        'dupr_open_play',
        NOW() + INTERVAL '2 days' + INTERVAL '3 hours',
        NOW() + INTERVAL '2 days' + INTERVAL '5 hours',
        16,
        4,
        novice_bracket_id,
        2.5,
        3.0,
        'Novice (2.5-3.0)',
        10.00,
        15.00,
        true,
        admin_id
    ),
    (
        'Intermediate Weekend Tournament',
        'Competitive play for intermediate level players. DUPR-rated event!',
        'dupr_tournament',
        NOW() + INTERVAL '5 days',
        NOW() + INTERVAL '5 days' + INTERVAL '4 hours',
        32,
        8,
        intermediate_bracket_id,
        3.0,
        4.0,
        'Intermediate (3.0-4.0)',
        25.00,
        35.00,
        true,
        admin_id
    ),
    (
        'Skills Development Clinic - Intermediate',
        'Work on dinking, volleys, and court positioning with expert coaches.',
        'clinic',
        NOW() + INTERVAL '4 days',
        NOW() + INTERVAL '4 days' + INTERVAL '90 minutes',
        16,
        6,
        intermediate_bracket_id,
        3.0,
        4.0,
        'Intermediate (3.0-4.0)',
        30.00,
        40.00,
        true,
        admin_id
    ),

    -- Advanced Events
    (
        'Advanced DUPR Open Play',
        'Fast-paced competitive play for advanced players. Bring your A-game!',
        'dupr_open_play',
        NOW() + INTERVAL '3 days',
        NOW() + INTERVAL '3 days' + INTERVAL '2 hours',
        16,
        4,
        advanced_bracket_id,
        4.0,
        4.5,
        'Advanced (4.0-4.5)',
        15.00,
        20.00,
        true,
        admin_id
    ),
    (
        'Pro-Am Tournament',
        'Elite level tournament. Test yourself against the best!',
        'dupr_tournament',
        NOW() + INTERVAL '7 days',
        NOW() + INTERVAL '7 days' + INTERVAL '5 hours',
        32,
        8,
        NULL,
        4.5,
        NULL,
        'Pro (4.5+)',
        50.00,
        75.00,
        true,
        admin_id
    ),

    -- Open/All Levels Events
    (
        'Friday Night Social Play',
        'All skill levels welcome! Mix and match for fun social pickleball.',
        'event_scramble',
        NOW() + INTERVAL '6 days',
        NOW() + INTERVAL '6 days' + INTERVAL '3 hours',
        24,
        8,
        open_bracket_id,
        NULL,
        NULL,
        'All Levels',
        5.00,
        10.00,
        true,
        admin_id
    ),
    (
        'Sunday Morning Open Play',
        'Start your Sunday with pickleball! Open to all skill levels.',
        'dupr_open_play',
        NOW() + INTERVAL '8 days',
        NOW() + INTERVAL '8 days' + INTERVAL '2 hours',
        20,
        4,
        open_bracket_id,
        NULL,
        NULL,
        'All Levels',
        8.00,
        12.00,
        true,
        admin_id
    ),

    -- Mixed skill brackets for testing filter edge cases
    (
        'Beginner to Intermediate Mixer',
        'Great opportunity to play with different skill levels!',
        'dupr_open_play',
        NOW() + INTERVAL '4 days' + INTERVAL '2 hours',
        NOW() + INTERVAL '4 days' + INTERVAL '4 hours',
        20,
        8,
        NULL,
        2.0,
        3.5,
        'Beginner/Intermediate Mix',
        12.00,
        18.00,
        true,
        admin_id
    );

    RAISE NOTICE 'Created % test events for different DUPR levels', 10;
END $$;