-- ============================================================================
-- TEST BADGE SYSTEM
-- Sample queries to demonstrate badge functionality
-- ============================================================================

-- Set search path
SET search_path TO crowdfunding, public;

-- ============================================================================
-- 1. VIEW ALL CONTRIBUTION TIERS WITH BADGES
-- ============================================================================

SELECT
    ct.name,
    ct.amount,
    ct.badge_tier,
    CASE ct.badge_tier
        WHEN 'bronze' THEN '🥉 Bronze'
        WHEN 'silver' THEN '🥈 Silver'
        WHEN 'gold' THEN '🥇 Gold'
        WHEN 'platinum' THEN '💎 Platinum'
        WHEN 'founding_pillar' THEN '👑 Founding Pillar'
        ELSE 'No Badge'
    END as badge_display,
    camp.name as campaign_type,
    ct.current_backers,
    ct.max_backers
FROM crowdfunding.contribution_tiers ct
JOIN crowdfunding.campaign_types camp ON ct.campaign_type_id = camp.id
WHERE ct.is_active = true
ORDER BY ct.amount ASC;

-- ============================================================================
-- 2. VIEW BADGE TIER INFORMATION
-- ============================================================================

SELECT * FROM crowdfunding.get_badge_tier_info()
ORDER BY min_amount ASC;

-- ============================================================================
-- 3. GET BADGE STATISTICS
-- ============================================================================

SELECT
    badge,
    backer_count,
    total_amount,
    ROUND(avg_contribution, 2) as avg_contribution,
    CASE badge
        WHEN 'bronze' THEN '🥉'
        WHEN 'silver' THEN '🥈'
        WHEN 'gold' THEN '🥇'
        WHEN 'platinum' THEN '💎'
        WHEN 'founding_pillar' THEN '👑'
    END as icon
FROM crowdfunding.get_badge_stats();

-- ============================================================================
-- 4. VIEW BACKERS WITH BADGES
-- ============================================================================

SELECT
    b.first_name || ' ' || b.last_initial || '.' as name,
    b.total_contributed,
    b.contribution_count,
    b.badge_level,
    CASE b.badge_level
        WHEN 'bronze' THEN '🥉 Bronze'
        WHEN 'silver' THEN '🥈 Silver'
        WHEN 'gold' THEN '🥇 Gold'
        WHEN 'platinum' THEN '💎 Platinum'
        WHEN 'founding_pillar' THEN '👑 Founding Pillar'
        ELSE 'No Badge'
    END as badge_display,
    b.badge_earned_at,
    b.city || ', ' || b.state as location
FROM crowdfunding.backers b
WHERE b.badge_level IS NOT NULL
ORDER BY
    CASE b.badge_level
        WHEN 'founding_pillar' THEN 5
        WHEN 'platinum' THEN 4
        WHEN 'gold' THEN 3
        WHEN 'silver' THEN 2
        WHEN 'bronze' THEN 1
    END DESC,
    b.total_contributed DESC;

-- ============================================================================
-- 5. VIEW FOUNDERS WALL WITH BADGES
-- ============================================================================

SELECT
    fw.display_name,
    fw.location,
    fw.total_contributed,
    fw.badge_tier,
    CASE fw.badge_tier
        WHEN 'bronze' THEN '🥉'
        WHEN 'silver' THEN '🥈'
        WHEN 'gold' THEN '🥇'
        WHEN 'platinum' THEN '💎'
        WHEN 'founding_pillar' THEN '👑'
    END as badge_icon,
    fw.contribution_tier,
    fw.is_featured
FROM crowdfunding.founders_wall fw
ORDER BY
    fw.is_featured DESC,
    CASE fw.badge_tier
        WHEN 'founding_pillar' THEN 5
        WHEN 'platinum' THEN 4
        WHEN 'gold' THEN 3
        WHEN 'silver' THEN 2
        WHEN 'bronze' THEN 1
    END DESC,
    fw.total_contributed DESC;

-- ============================================================================
-- 6. TEST BADGE CALCULATION
-- ============================================================================

SELECT
    amount,
    crowdfunding.calculate_badge_tier(amount) as badge_tier,
    CASE crowdfunding.calculate_badge_tier(amount)
        WHEN 'bronze' THEN '🥉 Bronze ($25-$99)'
        WHEN 'silver' THEN '🥈 Silver ($100-$249)'
        WHEN 'gold' THEN '🥇 Gold ($250-$999)'
        WHEN 'platinum' THEN '💎 Platinum ($1,000-$4,999)'
        WHEN 'founding_pillar' THEN '👑 Founding Pillar ($5,000+)'
        ELSE 'None (< $25)'
    END as badge_description
FROM (VALUES
    (10.00),
    (25.00),
    (50.00),
    (100.00),
    (250.00),
    (500.00),
    (1000.00),
    (2500.00),
    (5000.00)
) AS t(amount)
ORDER BY amount;

-- ============================================================================
-- 7. GET PLATINUM BACKERS (Example of filtering by badge)
-- ============================================================================

SELECT * FROM crowdfunding.get_backers_by_badge('platinum');

-- ============================================================================
-- 8. BADGE DISTRIBUTION CHART DATA
-- ============================================================================

-- Get counts for each badge tier (for pie/bar chart)
SELECT
    COALESCE(b.badge_level::text, 'no_badge') as badge,
    COUNT(*) as count,
    SUM(b.total_contributed) as total_contributed
FROM crowdfunding.backers b
GROUP BY b.badge_level
ORDER BY
    CASE b.badge_level
        WHEN 'founding_pillar' THEN 5
        WHEN 'platinum' THEN 4
        WHEN 'gold' THEN 3
        WHEN 'silver' THEN 2
        WHEN 'bronze' THEN 1
        ELSE 0
    END DESC;

-- ============================================================================
-- 9. RECENT BADGE ACHIEVEMENTS
-- ============================================================================

-- Show recent backers who earned badges
SELECT
    b.first_name || ' ' || b.last_initial || '.' as name,
    b.badge_level,
    CASE b.badge_level
        WHEN 'bronze' THEN '🥉 Bronze'
        WHEN 'silver' THEN '🥈 Silver'
        WHEN 'gold' THEN '🥇 Gold'
        WHEN 'platinum' THEN '💎 Platinum'
        WHEN 'founding_pillar' THEN '👑 Founding Pillar'
    END as badge_display,
    b.total_contributed,
    b.badge_earned_at
FROM crowdfunding.backers b
WHERE b.badge_level IS NOT NULL
ORDER BY b.badge_earned_at DESC
LIMIT 10;

-- ============================================================================
-- 10. BADGE PROGRESS SIMULATION
-- ============================================================================

-- Show how much more is needed for next badge tier
WITH badge_thresholds AS (
    SELECT * FROM (VALUES
        ('bronze', 25.00),
        ('silver', 100.00),
        ('gold', 250.00),
        ('platinum', 1000.00),
        ('founding_pillar', 5000.00)
    ) AS t(tier, min_amount)
)
SELECT
    b.first_name || ' ' || b.last_initial || '.' as name,
    b.total_contributed,
    b.badge_level as current_badge,
    bt.tier as next_badge,
    bt.min_amount - b.total_contributed as amount_needed
FROM crowdfunding.backers b
CROSS JOIN badge_thresholds bt
WHERE b.total_contributed > 0
    AND b.total_contributed < bt.min_amount
    AND NOT EXISTS (
        SELECT 1 FROM badge_thresholds bt2
        WHERE bt2.min_amount > b.total_contributed
        AND bt2.min_amount < bt.min_amount
    )
ORDER BY b.total_contributed DESC
LIMIT 10;
