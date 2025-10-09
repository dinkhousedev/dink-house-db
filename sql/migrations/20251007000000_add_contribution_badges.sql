-- ============================================================================
-- ADD CONTRIBUTION BADGE TIERS
-- Adds badge classification system for contribution tiers and backers
-- ============================================================================

SET search_path TO crowdfunding, public;

-- ============================================================================
-- CREATE BADGE TIER ENUM
-- ============================================================================

CREATE TYPE crowdfunding.badge_tier AS ENUM ('bronze', 'silver', 'gold', 'platinum', 'founding_pillar');

-- ============================================================================
-- ADD BADGE COLUMNS
-- ============================================================================

-- Add badge_tier to contribution_tiers table
ALTER TABLE crowdfunding.contribution_tiers
ADD COLUMN IF NOT EXISTS badge_tier crowdfunding.badge_tier;

-- Add badge columns to backers table
ALTER TABLE crowdfunding.backers
ADD COLUMN IF NOT EXISTS badge_level crowdfunding.badge_tier,
ADD COLUMN IF NOT EXISTS badge_earned_at TIMESTAMP WITH TIME ZONE;

-- Add badge to founders_wall table
ALTER TABLE crowdfunding.founders_wall
ADD COLUMN IF NOT EXISTS badge_tier crowdfunding.badge_tier;

-- ============================================================================
-- CREATE BADGE CALCULATION FUNCTION
-- ============================================================================

-- Function to determine badge tier based on contribution amount
CREATE OR REPLACE FUNCTION crowdfunding.calculate_badge_tier(amount DECIMAL)
RETURNS crowdfunding.badge_tier AS $$
BEGIN
    CASE
        WHEN amount >= 5000 THEN RETURN 'founding_pillar';
        WHEN amount >= 1000 THEN RETURN 'platinum';
        WHEN amount >= 250 THEN RETURN 'gold';
        WHEN amount >= 100 THEN RETURN 'silver';
        WHEN amount >= 25 THEN RETURN 'bronze';
        ELSE RETURN NULL;
    END CASE;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ============================================================================
-- UPDATE EXISTING DATA WITH BADGES
-- ============================================================================

-- Update contribution_tiers with appropriate badges based on amount
UPDATE crowdfunding.contribution_tiers
SET badge_tier = crowdfunding.calculate_badge_tier(amount)
WHERE badge_tier IS NULL;

-- Update backers with badge level based on total contributed
UPDATE crowdfunding.backers
SET
    badge_level = crowdfunding.calculate_badge_tier(total_contributed),
    badge_earned_at = updated_at
WHERE badge_level IS NULL AND total_contributed > 0;

-- Update founders_wall with badges
UPDATE crowdfunding.founders_wall fw
SET badge_tier = crowdfunding.calculate_badge_tier(fw.total_contributed)
WHERE badge_tier IS NULL;

-- ============================================================================
-- CREATE TRIGGER TO AUTO-UPDATE BACKER BADGES
-- ============================================================================

-- Function to update backer badge when total_contributed changes
CREATE OR REPLACE FUNCTION crowdfunding.update_backer_badge()
RETURNS TRIGGER AS $$
DECLARE
    v_new_badge crowdfunding.badge_tier;
    v_old_badge crowdfunding.badge_tier;
BEGIN
    -- Calculate new badge tier
    v_new_badge := crowdfunding.calculate_badge_tier(NEW.total_contributed);
    v_old_badge := OLD.badge_level;

    -- Only update if badge has changed (and new badge is higher or different)
    IF v_new_badge IS DISTINCT FROM v_old_badge THEN
        NEW.badge_level := v_new_badge;
        NEW.badge_earned_at := CURRENT_TIMESTAMP;

        -- Also update founders_wall if entry exists
        UPDATE crowdfunding.founders_wall
        SET
            badge_tier = v_new_badge,
            updated_at = CURRENT_TIMESTAMP
        WHERE backer_id = NEW.id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_backer_badge
    BEFORE UPDATE OF total_contributed ON crowdfunding.backers
    FOR EACH ROW
    WHEN (OLD.total_contributed IS DISTINCT FROM NEW.total_contributed)
    EXECUTE FUNCTION crowdfunding.update_backer_badge();

-- ============================================================================
-- UPDATE FOUNDERS WALL TRIGGER TO INCLUDE BADGE
-- ============================================================================

-- Recreate the upsert_founders_wall function to include badge_tier
CREATE OR REPLACE FUNCTION crowdfunding.upsert_founders_wall()
RETURNS TRIGGER AS $$
DECLARE
    v_display_name VARCHAR(255);
    v_location VARCHAR(255);
    v_tier_name VARCHAR(255);
    v_badge crowdfunding.badge_tier;
    v_backer RECORD;
BEGIN
    -- Only process completed contributions that are public
    IF NEW.status = 'completed' AND NEW.is_public = true THEN
        -- Get backer info
        SELECT first_name, last_initial, city, state, badge_level
        INTO v_backer
        FROM crowdfunding.backers
        WHERE id = NEW.backer_id;

        -- Format display name as "First L."
        v_display_name := v_backer.first_name || ' ' || v_backer.last_initial || '.';

        -- Format location as "City, ST" if available
        IF v_backer.city IS NOT NULL AND v_backer.state IS NOT NULL THEN
            v_location := v_backer.city || ', ' || v_backer.state;
        ELSIF v_backer.city IS NOT NULL THEN
            v_location := v_backer.city;
        ELSIF v_backer.state IS NOT NULL THEN
            v_location := v_backer.state;
        ELSE
            v_location := NULL;
        END IF;

        -- Get tier name
        IF NEW.tier_id IS NOT NULL THEN
            SELECT name INTO v_tier_name
            FROM crowdfunding.contribution_tiers
            WHERE id = NEW.tier_id;
        ELSE
            v_tier_name := 'Supporter';
        END IF;

        -- Calculate badge tier for this contribution
        v_badge := crowdfunding.calculate_badge_tier(NEW.amount);

        -- Insert or update founders wall
        INSERT INTO crowdfunding.founders_wall (
            backer_id,
            display_name,
            location,
            contribution_tier,
            total_contributed,
            is_featured,
            badge_tier
        )
        VALUES (
            NEW.backer_id,
            v_display_name,
            v_location,
            v_tier_name,
            NEW.amount,
            (NEW.amount >= 1000.00), -- Featured for $1000+ contributions
            v_badge
        )
        ON CONFLICT (backer_id)
        DO UPDATE SET
            total_contributed = crowdfunding.founders_wall.total_contributed + NEW.amount,
            contribution_tier = CASE
                WHEN NEW.amount >= 1000.00 THEN v_tier_name
                WHEN crowdfunding.founders_wall.total_contributed + NEW.amount >= 1000.00 THEN v_tier_name
                ELSE crowdfunding.founders_wall.contribution_tier
            END,
            is_featured = (crowdfunding.founders_wall.total_contributed + NEW.amount >= 1000.00),
            badge_tier = crowdfunding.calculate_badge_tier(crowdfunding.founders_wall.total_contributed + NEW.amount),
            updated_at = CURRENT_TIMESTAMP;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- CREATE HELPER FUNCTIONS FOR BADGES
-- ============================================================================

-- Function to get badge statistics
CREATE OR REPLACE FUNCTION crowdfunding.get_badge_stats()
RETURNS TABLE(
    badge crowdfunding.badge_tier,
    backer_count BIGINT,
    total_amount DECIMAL(10, 2),
    avg_contribution DECIMAL(10, 2)
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        b.badge_level,
        COUNT(*) as backer_count,
        SUM(b.total_contributed) as total_amount,
        AVG(b.total_contributed) as avg_contribution
    FROM crowdfunding.backers b
    WHERE b.badge_level IS NOT NULL
    GROUP BY b.badge_level
    ORDER BY
        CASE b.badge_level
            WHEN 'founding_pillar' THEN 5
            WHEN 'platinum' THEN 4
            WHEN 'gold' THEN 3
            WHEN 'silver' THEN 2
            WHEN 'bronze' THEN 1
        END DESC;
END;
$$ LANGUAGE plpgsql;

-- Function to get backers by badge tier
CREATE OR REPLACE FUNCTION crowdfunding.get_backers_by_badge(p_badge crowdfunding.badge_tier)
RETURNS TABLE(
    backer_id UUID,
    display_name VARCHAR(255),
    location VARCHAR(255),
    total_contributed DECIMAL(10, 2),
    contribution_count INTEGER,
    badge_earned_at TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        b.id,
        b.first_name || ' ' || b.last_initial || '.',
        CASE
            WHEN b.city IS NOT NULL AND b.state IS NOT NULL THEN b.city || ', ' || b.state
            WHEN b.city IS NOT NULL THEN b.city
            WHEN b.state IS NOT NULL THEN b.state
            ELSE NULL
        END as location,
        b.total_contributed,
        b.contribution_count,
        b.badge_earned_at
    FROM crowdfunding.backers b
    WHERE b.badge_level = p_badge
    ORDER BY b.total_contributed DESC, b.created_at ASC;
END;
$$ LANGUAGE plpgsql;

-- Function to get badge tier information
CREATE OR REPLACE FUNCTION crowdfunding.get_badge_tier_info()
RETURNS TABLE(
    badge crowdfunding.badge_tier,
    min_amount DECIMAL(10, 2),
    badge_name TEXT,
    badge_color TEXT,
    badge_icon TEXT,
    badge_image_url TEXT
) AS $$
    SELECT * FROM (VALUES
        ('bronze'::crowdfunding.badge_tier, 25.00, 'Bronze Supporter', '#CD7F32', '🥉', 'https://wchxzbuuwssrnaxshseu.supabase.co/storage/v1/object/public/dink-files/bronze_badge.png'),
        ('silver'::crowdfunding.badge_tier, 100.00, 'Silver Contributor', '#C0C0C0', '🥈', 'https://wchxzbuuwssrnaxshseu.supabase.co/storage/v1/object/public/dink-files/silver_badge.png'),
        ('gold'::crowdfunding.badge_tier, 250.00, 'Gold Benefactor', '#FFD700', '🥇', 'https://wchxzbuuwssrnaxshseu.supabase.co/storage/v1/object/public/dink-files/gold_badge.png'),
        ('platinum'::crowdfunding.badge_tier, 1000.00, 'Diamond Sponsor', '#B9F2FF', '💎', 'https://wchxzbuuwssrnaxshseu.supabase.co/storage/v1/object/public/dink-files/diamond_badge.png'),
        ('founding_pillar'::crowdfunding.badge_tier, 5000.00, 'Founding Pillar', '#B3FF00', '👑', 'https://wchxzbuuwssrnaxshseu.supabase.co/storage/v1/object/public/dink-files/Founder_badge.png')
    ) AS t(badge, min_amount, badge_name, badge_color, badge_icon, badge_image_url);
$$ LANGUAGE sql IMMUTABLE;

-- Function to get backer badge info with image URL
CREATE OR REPLACE FUNCTION crowdfunding.get_backer_badge_info(p_backer_id UUID)
RETURNS TABLE(
    badge_tier crowdfunding.badge_tier,
    badge_name TEXT,
    badge_color TEXT,
    badge_icon TEXT,
    badge_image_url TEXT,
    total_contributed DECIMAL(10, 2),
    badge_earned_at TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        b.badge_level,
        bti.badge_name,
        bti.badge_color,
        bti.badge_icon,
        bti.badge_image_url,
        b.total_contributed,
        b.badge_earned_at
    FROM crowdfunding.backers b
    LEFT JOIN crowdfunding.get_badge_tier_info() bti ON b.badge_level = bti.badge
    WHERE b.id = p_backer_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- CREATE INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_backers_badge_level ON crowdfunding.backers(badge_level);
CREATE INDEX IF NOT EXISTS idx_founders_wall_badge ON crowdfunding.founders_wall(badge_tier);
CREATE INDEX IF NOT EXISTS idx_tiers_badge ON crowdfunding.contribution_tiers(badge_tier);

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

GRANT EXECUTE ON FUNCTION crowdfunding.calculate_badge_tier(DECIMAL) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION crowdfunding.get_badge_stats() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION crowdfunding.get_backers_by_badge(crowdfunding.badge_tier) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION crowdfunding.get_badge_tier_info() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION crowdfunding.get_backer_badge_info(UUID) TO anon, authenticated;

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON TYPE crowdfunding.badge_tier IS 'Badge tiers for contribution levels: bronze ($25+), silver ($100+), gold ($250+), platinum ($1000+), founding_pillar ($5000+)';
COMMENT ON COLUMN crowdfunding.contribution_tiers.badge_tier IS 'Badge tier classification for this contribution level';
COMMENT ON COLUMN crowdfunding.backers.badge_level IS 'Highest badge tier achieved by backer based on total contributions';
COMMENT ON COLUMN crowdfunding.backers.badge_earned_at IS 'Timestamp when current badge was earned';
COMMENT ON COLUMN crowdfunding.founders_wall.badge_tier IS 'Badge tier displayed on founders wall';
COMMENT ON FUNCTION crowdfunding.calculate_badge_tier(DECIMAL) IS 'Calculate badge tier based on contribution amount';
COMMENT ON FUNCTION crowdfunding.get_badge_stats() IS 'Get statistics for each badge tier';
COMMENT ON FUNCTION crowdfunding.get_backers_by_badge(crowdfunding.badge_tier) IS 'Get all backers with a specific badge tier';
COMMENT ON FUNCTION crowdfunding.get_badge_tier_info() IS 'Get badge tier information including colors and icons';
