-- ============================================================================
-- CROWDFUNDING SEED DATA
-- Sample campaigns, tiers, and test data
-- ============================================================================

SET search_path TO crowdfunding, public;

-- ============================================================================
-- CAMPAIGN TYPES
-- ============================================================================

INSERT INTO crowdfunding.campaign_types (name, slug, description, goal_amount, display_order, is_active, metadata) VALUES
(
    'Build the Courts Campaign',
    'main-membership',
    'Help us build Bell County''s first premier indoor pickleball facility with 10 championship courts.',
    50000.00,
    1,
    true,
    '{"icon": "solar:home-bold", "color": "#B3FF00"}'::jsonb
),
(
    'Dink Practice Boards',
    'dink-boards',
    'Equip the facility with 3 professional-grade dink practice boards for skill development.',
    1500.00,
    2,
    true,
    '{"icon": "solar:target-bold", "color": "#B3FF00"}'::jsonb
),
(
    'Ball Machine Equipment',
    'ball-machines',
    'Bring 2 state-of-the-art ball machines to The Dink House for advanced training.',
    8000.00,
    3,
    true,
    '{"icon": "solar:smart-speaker-bold", "color": "#B3FF00"}'::jsonb
),
(
    'Community Support Fund',
    'community-support',
    'Support our community with rental paddles, ball holders, nets, vending machines, and operational equipment. Every dollar helps make pickleball accessible to everyone.',
    5000.00,
    4,
    true,
    '{"icon": "solar:hand-heart-bold", "color": "#B3FF00", "allows_custom_amount": true}'::jsonb
);

-- ============================================================================
-- CONTRIBUTION TIERS - MAIN CAMPAIGN
-- ============================================================================

-- Get the main campaign ID
DO $$
DECLARE
    v_main_campaign_id UUID;
    v_boards_campaign_id UUID;
    v_machines_campaign_id UUID;
    v_community_campaign_id UUID;
BEGIN
    SELECT id INTO v_main_campaign_id FROM crowdfunding.campaign_types WHERE slug = 'main-membership';
    SELECT id INTO v_boards_campaign_id FROM crowdfunding.campaign_types WHERE slug = 'dink-boards';
    SELECT id INTO v_machines_campaign_id FROM crowdfunding.campaign_types WHERE slug = 'ball-machines';
    SELECT id INTO v_community_campaign_id FROM crowdfunding.campaign_types WHERE slug = 'community-support';

    -- Main Campaign Tiers (REALISTIC VERSION)
    INSERT INTO crowdfunding.contribution_tiers (campaign_type_id, name, amount, description, benefits, display_order, is_active, max_backers) VALUES
    (
        v_main_campaign_id,
        'Baseline Supporter',
        25.00,
        'Show your support for the Dink House and get recognized on our digital Founders Wall.',
        '[
            {"type": "name_on_wall", "text": "Name on digital Founders Wall"},
            {"type": "custom", "text": "Opening Day invitation"},
            {"type": "custom", "text": "Dink House sticker"}
        ]'::jsonb,
        1,
        true,
        NULL
    ),
    (
        v_main_campaign_id,
        'Rally Member',
        50.00,
        'Get premium recognition and exclusive early access to the facility.',
        '[
            {"type": "name_on_wall", "text": "Prominent placement on Founders Wall"},
            {"type": "custom", "text": "Dink House t-shirt ($25 value)"},
            {"type": "custom", "text": "Opening Day VIP early access (30 min before public)"},
            {"type": "custom", "text": "2 guest passes ($20 value)"}
        ]'::jsonb,
        2,
        true,
        NULL
    ),
    (
        v_main_campaign_id,
        'Net Contributor',
        100.00,
        'Make a real impact with tangible court time and exclusive updates.',
        '[
            {"type": "name_on_wall", "text": "Featured placement on Founders Wall"},
            {"type": "custom", "text": "4 hours of court time ($40 value)"},
            {"type": "custom", "text": "Dink House t-shirt and water bottle"},
            {"type": "pro_shop_discount", "text": "10% Pro Shop discount for 3 months", "duration_months": 3},
            {"type": "custom", "text": "Exclusive construction updates with photos"}
        ]'::jsonb,
        3,
        true,
        NULL
    ),
    (
        v_main_campaign_id,
        'Court Builder',
        250.00,
        'Become a key builder with permanent recognition and membership benefits.',
        '[
            {"type": "name_on_wall", "text": "Name engraved on permanent donor recognition plaque"},
            {"type": "founding_membership", "text": "1 month free membership ($60 value)", "duration_months": 1},
            {"type": "custom", "text": "10 hours of court time ($100 value)"},
            {"type": "pro_shop_discount", "text": "15% Pro Shop discount for 6 months", "duration_months": 6},
            {"type": "custom", "text": "Private soft opening event invitation (bring 1 guest)"},
            {"type": "custom", "text": "Founding Member package (t-shirt, water bottle, towel)"}
        ]'::jsonb,
        4,
        true,
        NULL
    ),
    (
        v_main_campaign_id,
        'Founding Member',
        500.00,
        'Founding Member status with priority access and exclusive merchandise.',
        '[
            {"type": "name_on_wall", "text": "Name engraved on permanent Founding Member plaque"},
            {"type": "founding_membership", "text": "2 months free membership ($120 value)", "duration_months": 2},
            {"type": "custom", "text": "20 hours of court time ($200 value)"},
            {"type": "free_lessons", "text": "1 free private lesson ($50 value)"},
            {"type": "pro_shop_discount", "text": "15% Pro Shop discount for 1 year", "duration_months": 12},
            {"type": "priority_booking", "text": "Priority court booking for 6 months", "duration_months": 6},
            {"type": "custom", "text": "Founding Member exclusive hoodie and gear package"}
        ]'::jsonb,
        5,
        true,
        NULL
    ),
    (
        v_main_campaign_id,
        'Court Sponsor',
        1000.00,
        'Best value tier! Get your name or business on a court banner for 1 year plus premium membership benefits.',
        '[
            {"type": "court_sponsor", "text": "Your name/business on a court banner for 1 year", "duration_years": 1},
            {"type": "name_on_wall", "text": "Name engraved on premium sponsor plaque"},
            {"type": "founding_membership", "text": "3 months free membership ($180 value)", "duration_months": 3},
            {"type": "custom", "text": "40 hours of court time ($400 value)"},
            {"type": "free_lessons", "text": "2 free private lessons ($100 value)"},
            {"type": "pro_shop_discount", "text": "15% Pro Shop discount for 1 year", "duration_months": 12},
            {"type": "priority_booking", "text": "Priority court booking for 1 year", "duration_months": 12},
            {"type": "custom", "text": "Premium Founding Member package (hoodie, water bottle, towel, bag)"}
        ]'::jsonb,
        6,
        true,
        NULL
    ),
    (
        v_main_campaign_id,
        'Legacy Sponsor',
        2500.00,
        'Limited to 4 backers! Legacy status with 3-year court banner and premium benefits.',
        '[
            {"type": "court_sponsor", "text": "Your name/business on a court banner for 3 years", "duration_years": 3},
            {"type": "name_on_wall", "text": "Name permanently on lobby legacy donor wall"},
            {"type": "founding_membership", "text": "6 months free membership ($360 value)", "duration_months": 6},
            {"type": "custom", "text": "100 hours of court time ($1000 value)"},
            {"type": "free_lessons", "text": "5 free private lessons ($250 value)"},
            {"type": "pro_shop_discount", "text": "20% Pro Shop discount for 2 years", "duration_months": 24},
            {"type": "priority_booking", "text": "Priority court booking for 2 years", "duration_months": 24},
            {"type": "custom", "text": "24 guest passes (2 per month for 1 year)"},
            {"type": "custom", "text": "Elite Founding Member gear package"}
        ]'::jsonb,
        7,
        true,
        4
    ),
    (
        v_main_campaign_id,
        'Founding Pillar',
        5000.00,
        'Limited to 2 backers only! Court naming rights for 3 years and elite benefits.',
        '[
            {"type": "court_sponsor", "text": "Court naming rights for 3 years (e.g., Court 1 - Sponsored by Smith Family)", "duration_years": 3},
            {"type": "name_on_wall", "text": "Permanent legacy plaque in main lobby (premium placement)"},
            {"type": "founding_membership", "text": "1 year free membership ($720 value)", "duration_months": 12},
            {"type": "custom", "text": "250 hours of court time ($2500 value)"},
            {"type": "free_lessons", "text": "10 free private lessons ($500 value)"},
            {"type": "pro_shop_discount", "text": "25% Pro Shop discount for 2 years", "duration_months": 24},
            {"type": "priority_booking", "text": "VIP priority booking for 2 years", "duration_months": 24},
            {"type": "custom", "text": "48 guest passes (4 per month for 1 year)"},
            {"type": "custom", "text": "Premium gear package (paddle, bag, complete apparel set)"},
            {"type": "custom", "text": "Advisory input on facility decisions (1 year)"}
        ]'::jsonb,
        8,
        true,
        2
    );

    -- ============================================================================
    -- CONTRIBUTION TIERS - DINK BOARDS CAMPAIGN (REALISTIC VERSION)
    -- ============================================================================

    INSERT INTO crowdfunding.contribution_tiers (campaign_type_id, name, amount, description, benefits, display_order, is_active, max_backers) VALUES
    (
        v_boards_campaign_id,
        'Board Supporter',
        25.00,
        'Support dink practice equipment and get recognized.',
        '[
            {"type": "name_on_wall", "text": "Name listed as supporter"},
            {"type": "custom", "text": "3 dink board sessions ($30 value)"}
        ]'::jsonb,
        1,
        true,
        NULL
    ),
    (
        v_boards_campaign_id,
        'Board Contributor',
        75.00,
        'Make a meaningful contribution to skill development equipment.',
        '[
            {"type": "custom", "text": "10 dink board sessions ($100 value)"},
            {"type": "name_on_wall", "text": "Name on board supporter plaque"},
            {"type": "custom", "text": "1 free dink clinic session"},
            {"type": "custom", "text": "Dink technique guide (PDF)"}
        ]'::jsonb,
        2,
        true,
        NULL
    ),
    (
        v_boards_campaign_id,
        'Board Founder',
        150.00,
        'Premium package with extensive practice time and recognition.',
        '[
            {"type": "custom", "text": "25 dink board sessions ($250 value)"},
            {"type": "name_on_wall", "text": "Name on board supporter plaque (prominent display)"},
            {"type": "custom", "text": "3 free dink clinics"},
            {"type": "pro_shop_discount", "text": "10% Pro Shop discount for 6 months", "duration_months": 6},
            {"type": "priority_booking", "text": "Priority board reservations for 6 months", "duration_months": 6}
        ]'::jsonb,
        3,
        true,
        NULL
    ),
    (
        v_boards_campaign_id,
        'Board Champion',
        300.00,
        'Limited to 3 backers (one per board)! Your name engraved on equipment with premium benefits.',
        '[
            {"type": "custom", "text": "50 dink board sessions ($500 value)"},
            {"type": "custom", "text": "Your name engraved on one of the boards (permanent)"},
            {"type": "custom", "text": "5 free dink clinics"},
            {"type": "priority_booking", "text": "Priority board reservations for 1 year", "duration_months": 12},
            {"type": "pro_shop_discount", "text": "15% Pro Shop discount for 1 year", "duration_months": 12}
        ]'::jsonb,
        4,
        true,
        3
    );

    -- ============================================================================
    -- CONTRIBUTION TIERS - BALL MACHINES CAMPAIGN (REALISTIC VERSION)
    -- ============================================================================

    INSERT INTO crowdfunding.contribution_tiers (campaign_type_id, name, amount, description, benefits, display_order, is_active, max_backers) VALUES
    (
        v_machines_campaign_id,
        'Machine Supporter',
        50.00,
        'Help bring advanced training equipment to The Dink House.',
        '[
            {"type": "name_on_wall", "text": "Name listed as supporter"},
            {"type": "custom", "text": "3 ball machine sessions ($45 value)"},
            {"type": "custom", "text": "Ball machine quick-start guide (PDF)"}
        ]'::jsonb,
        1,
        true,
        NULL
    ),
    (
        v_machines_campaign_id,
        'Training Advocate',
        100.00,
        'Support professional training equipment with meaningful benefits.',
        '[
            {"type": "custom", "text": "8 ball machine sessions ($120 value)"},
            {"type": "name_on_wall", "text": "Name on machine supporter plaque"},
            {"type": "custom", "text": "Ball machine training guide (PDF with drills & techniques)"},
            {"type": "custom", "text": "1 complimentary ball machine tutorial session"}
        ]'::jsonb,
        2,
        true,
        NULL
    ),
    (
        v_machines_campaign_id,
        'Machine Contributor',
        250.00,
        'Make a significant impact on training capabilities.',
        '[
            {"type": "custom", "text": "20 ball machine sessions ($300 value)"},
            {"type": "free_lessons", "text": "1 private ball machine lesson with a pro"},
            {"type": "name_on_wall", "text": "Name on machine supporter plaque (larger display)"},
            {"type": "pro_shop_discount", "text": "10% Pro Shop discount for 6 months", "duration_months": 6},
            {"type": "custom", "text": "Advanced drill program (custom PDF)"}
        ]'::jsonb,
        3,
        true,
        NULL
    ),
    (
        v_machines_campaign_id,
        'Machine Founder',
        500.00,
        'Premium package with extensive training time and priority access.',
        '[
            {"type": "custom", "text": "50 ball machine sessions ($750 value)"},
            {"type": "name_on_wall", "text": "Name on machine supporter plaque (prominent display)"},
            {"type": "free_lessons", "text": "2 private ball machine lessons ($100 value)"},
            {"type": "priority_booking", "text": "Priority machine reservations for 1 year", "duration_months": 12},
            {"type": "pro_shop_discount", "text": "15% Pro Shop discount for 1 year", "duration_months": 12},
            {"type": "custom", "text": "Personalized training program"}
        ]'::jsonb,
        4,
        true,
        NULL
    ),
    (
        v_machines_campaign_id,
        'Machine Champion',
        1000.00,
        'Limited to 2 backers (one per machine)! Your name engraved on equipment with elite benefits.',
        '[
            {"type": "custom", "text": "100 ball machine sessions ($1500 value)"},
            {"type": "custom", "text": "Your name engraved on one of the machines (permanent)"},
            {"type": "free_lessons", "text": "5 private ball machine lessons ($250 value)"},
            {"type": "priority_booking", "text": "VIP priority machine reservations for 2 years", "duration_months": 24},
            {"type": "pro_shop_discount", "text": "20% Pro Shop discount for 2 years", "duration_months": 24},
            {"type": "custom", "text": "Custom training program with quarterly updates (1 year)"}
        ]'::jsonb,
        5,
        true,
        2
    );

    -- ============================================================================
    -- CONTRIBUTION TIERS - COMMUNITY SUPPORT CAMPAIGN (FLEXIBLE AMOUNTS)
    -- ============================================================================

    INSERT INTO crowdfunding.contribution_tiers (campaign_type_id, name, amount, description, benefits, display_order, is_active, max_backers, metadata) VALUES
    (
        v_community_campaign_id,
        'Community Supporter',
        10.00,
        'Contribute any amount to help equip our facility with community essentials. Every dollar makes a difference!',
        '[
            {"type": "name_on_wall", "text": "Recognition on Community Supporters Wall"},
            {"type": "custom", "text": "Know you made pickleball more accessible to everyone"}
        ]'::jsonb,
        1,
        true,
        NULL,
        '{"allows_custom_amount": true, "min_amount": 5.00}'::jsonb
    ),
    (
        v_community_campaign_id,
        'Equipment Champion',
        100.00,
        'Make a significant impact on our community equipment fund.',
        '[
            {"type": "name_on_wall", "text": "Featured recognition on Community Supporters Wall"},
            {"type": "custom", "text": "Opening Day community celebration invitation"},
            {"type": "custom", "text": "Dink House community supporter sticker"}
        ]'::jsonb,
        2,
        true,
        NULL
    ),
    (
        v_community_campaign_id,
        'Operations Benefactor',
        250.00,
        'Help sustain our operations and community programs.',
        '[
            {"type": "name_on_wall", "text": "Prominent recognition on Community Supporters Wall"},
            {"type": "custom", "text": "4 guest passes for friends or family ($40 value)"},
            {"type": "custom", "text": "Opening Day VIP community celebration access"},
            {"type": "custom", "text": "Dink House community package (t-shirt, sticker, water bottle)"}
        ]'::jsonb,
        3,
        true,
        NULL
    );

END $$;

-- ============================================================================
-- SAMPLE TEST DATA (OPTIONAL - Remove for production)
-- ============================================================================

-- Sample backer (test data)
-- INSERT INTO crowdfunding.backers (email, first_name, last_initial, city, state, stripe_customer_id) VALUES
-- ('test@example.com', 'John', 'S', 'Belton', 'TX', 'cus_test123');

-- Sample contribution (test data)
-- INSERT INTO crowdfunding.contributions (
--     backer_id,
--     campaign_type_id,
--     tier_id,
--     amount,
--     status,
--     is_public,
--     show_amount,
--     completed_at
-- )
-- SELECT
--     b.id,
--     ct.id,
--     tier.id,
--     tier.amount,
--     'completed',
--     true,
--     true,
--     CURRENT_TIMESTAMP
-- FROM crowdfunding.backers b
-- CROSS JOIN crowdfunding.campaign_types ct
-- CROSS JOIN crowdfunding.contribution_tiers tier
-- WHERE b.email = 'test@example.com'
--     AND ct.slug = 'main-membership'
--     AND tier.name = 'Kitchen Contributor'
-- LIMIT 1;

COMMENT ON TABLE crowdfunding.campaign_types IS 'Crowdfunding campaigns seeded with Build the Courts, Dink Boards, and Ball Machines';
COMMENT ON TABLE crowdfunding.contribution_tiers IS 'Contribution tiers ranging from $25 to $5000 with various benefits';
