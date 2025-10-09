-- ============================================================================
-- CROWDFUNDING MODULE
-- Campaign management, backer tracking, and Stripe integration
-- ============================================================================

-- Create crowdfunding schema
CREATE SCHEMA IF NOT EXISTS crowdfunding;

-- Set search path for crowdfunding schema
SET search_path TO crowdfunding, public;

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================================
-- CORE TABLES
-- ============================================================================

-- Backers/Supporters Table
CREATE TABLE IF NOT EXISTS crowdfunding.backers (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    email public.CITEXT UNIQUE NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_initial VARCHAR(1) NOT NULL,
    phone VARCHAR(30),
    city VARCHAR(100),
    state VARCHAR(2),
    stripe_customer_id TEXT UNIQUE,
    total_contributed DECIMAL(10, 2) DEFAULT 0,
    contribution_count INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Campaign Types (Main, Equipment, etc.)
CREATE TABLE IF NOT EXISTS crowdfunding.campaign_types (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(255) UNIQUE NOT NULL,
    description TEXT,
    goal_amount DECIMAL(10, 2) NOT NULL,
    current_amount DECIMAL(10, 2) DEFAULT 0,
    backer_count INTEGER DEFAULT 0,
    display_order INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Contribution Tiers
CREATE TABLE IF NOT EXISTS crowdfunding.contribution_tiers (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    campaign_type_id UUID NOT NULL REFERENCES crowdfunding.campaign_types(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    amount DECIMAL(10, 2) NOT NULL,
    description TEXT,
    benefits JSONB DEFAULT '[]',
    stripe_price_id TEXT UNIQUE,
    max_backers INTEGER,
    current_backers INTEGER DEFAULT 0,
    display_order INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Contributions/Pledges
CREATE TABLE IF NOT EXISTS crowdfunding.contributions (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    backer_id UUID NOT NULL REFERENCES crowdfunding.backers(id) ON DELETE CASCADE,
    campaign_type_id UUID NOT NULL REFERENCES crowdfunding.campaign_types(id) ON DELETE CASCADE,
    tier_id UUID REFERENCES crowdfunding.contribution_tiers(id) ON DELETE SET NULL,
    amount DECIMAL(10, 2) NOT NULL,
    stripe_payment_intent_id TEXT UNIQUE,
    stripe_charge_id TEXT,
    stripe_checkout_session_id TEXT UNIQUE,
    status VARCHAR(50) NOT NULL DEFAULT 'pending',
    payment_method VARCHAR(50),
    is_public BOOLEAN DEFAULT true,
    show_amount BOOLEAN DEFAULT true,
    custom_message TEXT,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP WITH TIME ZONE,
    refunded_at TIMESTAMP WITH TIME ZONE,
    CONSTRAINT valid_status CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'refunded', 'cancelled'))
);

-- Benefits Tracking (for lifetime benefits)
CREATE TABLE IF NOT EXISTS crowdfunding.backer_benefits (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    backer_id UUID NOT NULL REFERENCES crowdfunding.backers(id) ON DELETE CASCADE,
    contribution_id UUID NOT NULL REFERENCES crowdfunding.contributions(id) ON DELETE CASCADE,
    benefit_type VARCHAR(100) NOT NULL,
    benefit_details JSONB DEFAULT '{}',
    is_active BOOLEAN DEFAULT true,
    activated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP WITH TIME ZONE,
    redeemed_count INTEGER DEFAULT 0,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT valid_benefit_type CHECK (benefit_type IN (
        'lifetime_dink_board', 'lifetime_ball_machine', 'founding_membership',
        'court_sponsor', 'pro_shop_discount', 'priority_booking', 'name_on_wall',
        'free_lessons', 'vip_events', 'custom'
    ))
);

-- Court Sponsors (for $1,000+ tiers)
CREATE TABLE IF NOT EXISTS crowdfunding.court_sponsors (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    backer_id UUID NOT NULL REFERENCES crowdfunding.backers(id) ON DELETE CASCADE,
    contribution_id UUID NOT NULL REFERENCES crowdfunding.contributions(id) ON DELETE CASCADE,
    sponsor_name VARCHAR(255) NOT NULL,
    sponsor_type VARCHAR(50) DEFAULT 'individual',
    logo_url TEXT,
    court_number INTEGER,
    sponsorship_start DATE NOT NULL DEFAULT CURRENT_DATE,
    sponsorship_end DATE,
    is_active BOOLEAN DEFAULT true,
    display_order INTEGER,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT valid_sponsor_type CHECK (sponsor_type IN ('individual', 'business', 'memorial'))
);

-- Founders Wall (Public Display)
CREATE TABLE IF NOT EXISTS crowdfunding.founders_wall (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    backer_id UUID UNIQUE NOT NULL REFERENCES crowdfunding.backers(id) ON DELETE CASCADE,
    display_name VARCHAR(255) NOT NULL,
    location VARCHAR(255),
    contribution_tier VARCHAR(255),
    total_contributed DECIMAL(10, 2) NOT NULL DEFAULT 0,
    is_featured BOOLEAN DEFAULT false,
    display_order INTEGER,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- INDEXES
-- ============================================================================

CREATE INDEX idx_backers_email ON crowdfunding.backers(email);
CREATE INDEX idx_backers_stripe_customer ON crowdfunding.backers(stripe_customer_id);

CREATE INDEX idx_campaign_types_slug ON crowdfunding.campaign_types(slug);
CREATE INDEX idx_campaign_types_active ON crowdfunding.campaign_types(is_active);
CREATE INDEX idx_campaign_types_display_order ON crowdfunding.campaign_types(display_order);

CREATE INDEX idx_tiers_campaign ON crowdfunding.contribution_tiers(campaign_type_id);
CREATE INDEX idx_tiers_active ON crowdfunding.contribution_tiers(is_active);
CREATE INDEX idx_tiers_price_id ON crowdfunding.contribution_tiers(stripe_price_id);

CREATE INDEX idx_contributions_backer ON crowdfunding.contributions(backer_id);
CREATE INDEX idx_contributions_campaign ON crowdfunding.contributions(campaign_type_id);
CREATE INDEX idx_contributions_tier ON crowdfunding.contributions(tier_id);
CREATE INDEX idx_contributions_status ON crowdfunding.contributions(status);
CREATE INDEX idx_contributions_completed_at ON crowdfunding.contributions(completed_at);
CREATE INDEX idx_contributions_stripe_payment_intent ON crowdfunding.contributions(stripe_payment_intent_id);
CREATE INDEX idx_contributions_stripe_session ON crowdfunding.contributions(stripe_checkout_session_id);

CREATE INDEX idx_benefits_backer ON crowdfunding.backer_benefits(backer_id);
CREATE INDEX idx_benefits_contribution ON crowdfunding.backer_benefits(contribution_id);
CREATE INDEX idx_benefits_type ON crowdfunding.backer_benefits(benefit_type);
CREATE INDEX idx_benefits_active ON crowdfunding.backer_benefits(is_active);

CREATE INDEX idx_sponsors_backer ON crowdfunding.court_sponsors(backer_id);
CREATE INDEX idx_sponsors_active ON crowdfunding.court_sponsors(is_active);

CREATE INDEX idx_founders_wall_display_order ON crowdfunding.founders_wall(display_order);
CREATE INDEX idx_founders_wall_featured ON crowdfunding.founders_wall(is_featured);

-- ============================================================================
-- TRIGGERS & FUNCTIONS
-- ============================================================================

-- Function to update campaign totals when contribution is completed
CREATE OR REPLACE FUNCTION crowdfunding.update_campaign_total()
RETURNS TRIGGER AS $$
BEGIN
    -- Only process when status changes to 'completed'
    IF NEW.status = 'completed' AND (OLD IS NULL OR OLD.status != 'completed') THEN
        -- Update campaign type current amount
        UPDATE crowdfunding.campaign_types
        SET
            current_amount = current_amount + NEW.amount,
            backer_count = backer_count + 1,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = NEW.campaign_type_id;

        -- Update tier backer count
        IF NEW.tier_id IS NOT NULL THEN
            UPDATE crowdfunding.contribution_tiers
            SET
                current_backers = current_backers + 1,
                updated_at = CURRENT_TIMESTAMP
            WHERE id = NEW.tier_id;
        END IF;

        -- Update backer totals
        UPDATE crowdfunding.backers
        SET
            total_contributed = total_contributed + NEW.amount,
            contribution_count = contribution_count + 1,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = NEW.backer_id;
    END IF;

    -- Handle refunds
    IF NEW.status = 'refunded' AND OLD.status = 'completed' THEN
        -- Reverse campaign type amounts
        UPDATE crowdfunding.campaign_types
        SET
            current_amount = GREATEST(0, current_amount - NEW.amount),
            backer_count = GREATEST(0, backer_count - 1),
            updated_at = CURRENT_TIMESTAMP
        WHERE id = NEW.campaign_type_id;

        -- Reverse tier backer count
        IF NEW.tier_id IS NOT NULL THEN
            UPDATE crowdfunding.contribution_tiers
            SET
                current_backers = GREATEST(0, current_backers - 1),
                updated_at = CURRENT_TIMESTAMP
            WHERE id = NEW.tier_id;
        END IF;

        -- Reverse backer totals
        UPDATE crowdfunding.backers
        SET
            total_contributed = GREATEST(0, total_contributed - NEW.amount),
            contribution_count = GREATEST(0, contribution_count - 1),
            updated_at = CURRENT_TIMESTAMP
        WHERE id = NEW.backer_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_campaign_total
    AFTER INSERT OR UPDATE ON crowdfunding.contributions
    FOR EACH ROW
    EXECUTE FUNCTION crowdfunding.update_campaign_total();

-- Function to create or update founders wall entry
CREATE OR REPLACE FUNCTION crowdfunding.upsert_founders_wall()
RETURNS TRIGGER AS $$
DECLARE
    v_display_name VARCHAR(255);
    v_location VARCHAR(255);
    v_tier_name VARCHAR(255);
    v_backer RECORD;
BEGIN
    -- Only process completed contributions that are public
    IF NEW.status = 'completed' AND NEW.is_public = true THEN
        -- Get backer info
        SELECT first_name, last_initial, city, state
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

        -- Insert or update founders wall
        INSERT INTO crowdfunding.founders_wall (
            backer_id,
            display_name,
            location,
            contribution_tier,
            total_contributed,
            is_featured
        )
        VALUES (
            NEW.backer_id,
            v_display_name,
            v_location,
            v_tier_name,
            NEW.amount,
            (NEW.amount >= 1000.00) -- Featured for $1000+ contributions
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
            updated_at = CURRENT_TIMESTAMP;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_upsert_founders_wall
    AFTER INSERT OR UPDATE ON crowdfunding.contributions
    FOR EACH ROW
    EXECUTE FUNCTION crowdfunding.upsert_founders_wall();

-- ============================================================================
-- ROW LEVEL SECURITY
-- ============================================================================

ALTER TABLE crowdfunding.backers ENABLE ROW LEVEL SECURITY;
ALTER TABLE crowdfunding.campaign_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE crowdfunding.contribution_tiers ENABLE ROW LEVEL SECURITY;
ALTER TABLE crowdfunding.contributions ENABLE ROW LEVEL SECURITY;
ALTER TABLE crowdfunding.backer_benefits ENABLE ROW LEVEL SECURITY;
ALTER TABLE crowdfunding.court_sponsors ENABLE ROW LEVEL SECURITY;
ALTER TABLE crowdfunding.founders_wall ENABLE ROW LEVEL SECURITY;

-- Campaign types are public
CREATE POLICY "Campaign types are viewable by everyone"
    ON crowdfunding.campaign_types FOR SELECT
    USING (is_active = true);

-- Contribution tiers are public
CREATE POLICY "Contribution tiers are viewable by everyone"
    ON crowdfunding.contribution_tiers FOR SELECT
    USING (is_active = true);

-- Public contributions are viewable
CREATE POLICY "Public contributions are viewable by everyone"
    ON crowdfunding.contributions FOR SELECT
    USING (is_public = true AND status = 'completed');

-- Founders wall is public
CREATE POLICY "Founders wall is public"
    ON crowdfunding.founders_wall FOR SELECT
    USING (true);

-- Court sponsors are public
CREATE POLICY "Court sponsors are public"
    ON crowdfunding.court_sponsors FOR SELECT
    USING (is_active = true);

-- Service role has full access to all tables
CREATE POLICY "Service role has full access to backers"
    ON crowdfunding.backers FOR ALL
    USING (current_setting('request.jwt.claims', true)::json->>'role' = 'service_role');

CREATE POLICY "Service role has full access to contributions"
    ON crowdfunding.contributions FOR ALL
    USING (current_setting('request.jwt.claims', true)::json->>'role' = 'service_role');

CREATE POLICY "Service role has full access to benefits"
    ON crowdfunding.backer_benefits FOR ALL
    USING (current_setting('request.jwt.claims', true)::json->>'role' = 'service_role');

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Function to get campaign progress
CREATE OR REPLACE FUNCTION crowdfunding.get_campaign_progress(p_campaign_id UUID)
RETURNS TABLE(
    campaign_id UUID,
    campaign_name VARCHAR(255),
    current_amount DECIMAL(10, 2),
    goal_amount DECIMAL(10, 2),
    percentage DECIMAL(5, 2),
    backer_count INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        ct.id,
        ct.name,
        ct.current_amount,
        ct.goal_amount,
        CASE
            WHEN ct.goal_amount > 0 THEN ROUND((ct.current_amount / ct.goal_amount * 100)::NUMERIC, 2)
            ELSE 0
        END AS percentage,
        ct.backer_count
    FROM crowdfunding.campaign_types ct
    WHERE ct.id = p_campaign_id AND ct.is_active = true;
END;
$$ LANGUAGE plpgsql;

-- Function to get available tiers for a campaign
CREATE OR REPLACE FUNCTION crowdfunding.get_available_tiers(p_campaign_id UUID)
RETURNS TABLE(
    tier_id UUID,
    tier_name VARCHAR(255),
    amount DECIMAL(10, 2),
    description TEXT,
    benefits JSONB,
    available_spots INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        t.id,
        t.name,
        t.amount,
        t.description,
        t.benefits,
        CASE
            WHEN t.max_backers IS NULL THEN NULL
            ELSE t.max_backers - t.current_backers
        END AS available_spots
    FROM crowdfunding.contribution_tiers t
    WHERE t.campaign_type_id = p_campaign_id
        AND t.is_active = true
        AND (t.max_backers IS NULL OR t.current_backers < t.max_backers)
    ORDER BY t.display_order, t.amount;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

-- Grant usage on schema
GRANT USAGE ON SCHEMA crowdfunding TO anon, authenticated, service_role;

-- Grant select on tables (public read)
GRANT SELECT ON crowdfunding.campaign_types TO anon, authenticated;
GRANT SELECT ON crowdfunding.contribution_tiers TO anon, authenticated;
GRANT SELECT ON crowdfunding.contributions TO anon, authenticated;
GRANT SELECT ON crowdfunding.founders_wall TO anon, authenticated;
GRANT SELECT ON crowdfunding.court_sponsors TO anon, authenticated;

-- Grant all to service role
GRANT ALL ON ALL TABLES IN SCHEMA crowdfunding TO service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA crowdfunding TO service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA crowdfunding TO service_role;

-- Grant execute on functions
GRANT EXECUTE ON FUNCTION crowdfunding.get_campaign_progress(UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION crowdfunding.get_available_tiers(UUID) TO anon, authenticated;

COMMENT ON SCHEMA crowdfunding IS 'Crowdfunding campaign management with Stripe integration';
