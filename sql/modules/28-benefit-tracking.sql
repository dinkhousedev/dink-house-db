-- ============================================================================
-- BENEFIT TRACKING SYSTEM
-- Tables, views, and functions for tracking benefit allocations and usage
-- ============================================================================

SET search_path TO crowdfunding, public;

-- ============================================================================
-- TABLES
-- ============================================================================

-- Benefit Allocations - Individual benefit items allocated to backers
CREATE TABLE IF NOT EXISTS crowdfunding.benefit_allocations (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    backer_id UUID NOT NULL REFERENCES crowdfunding.backers(id) ON DELETE CASCADE,
    contribution_id UUID NOT NULL REFERENCES crowdfunding.contributions(id) ON DELETE CASCADE,
    tier_id UUID REFERENCES crowdfunding.contribution_tiers(id) ON DELETE SET NULL,

    -- Benefit details
    benefit_type VARCHAR(100) NOT NULL,
    benefit_name TEXT NOT NULL,
    benefit_description TEXT,

    -- Quantity tracking
    quantity_allocated DECIMAL(10, 2), -- NULL for unlimited/one-time benefits
    quantity_used DECIMAL(10, 2) DEFAULT 0,
    quantity_remaining DECIMAL(10, 2), -- Auto-calculated

    -- Validity period
    valid_from TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    valid_until TIMESTAMP WITH TIME ZONE, -- NULL for lifetime benefits

    -- Fulfillment tracking
    fulfillment_status VARCHAR(50) DEFAULT 'allocated',
    fulfillment_notes TEXT,
    fulfilled_at TIMESTAMP WITH TIME ZONE,
    fulfilled_by UUID, -- References staff user who fulfilled

    -- Metadata
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT valid_fulfillment_status CHECK (fulfillment_status IN (
        'allocated', 'in_progress', 'fulfilled', 'expired', 'cancelled'
    )),
    CONSTRAINT valid_benefit_type CHECK (benefit_type IN (
        'court_time_hours', 'dink_board_sessions', 'ball_machine_sessions',
        'pro_shop_discount', 'membership_months', 'private_lessons',
        'guest_passes', 'priority_booking', 'recognition', 'custom'
    ))
);

-- Benefit Usage Log - Track each redemption/usage
CREATE TABLE IF NOT EXISTS crowdfunding.benefit_usage_log (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    allocation_id UUID NOT NULL REFERENCES crowdfunding.benefit_allocations(id) ON DELETE CASCADE,

    -- Usage details
    quantity_used DECIMAL(10, 2) NOT NULL,
    usage_date DATE NOT NULL DEFAULT CURRENT_DATE,
    usage_time TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    used_for TEXT, -- Description of what it was used for

    -- Staff verification
    staff_id UUID, -- References staff user who processed
    staff_verified BOOLEAN DEFAULT false,
    notes TEXT,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- INDEXES
-- ============================================================================

CREATE INDEX idx_allocations_backer ON crowdfunding.benefit_allocations(backer_id);
CREATE INDEX idx_allocations_contribution ON crowdfunding.benefit_allocations(contribution_id);
CREATE INDEX idx_allocations_tier ON crowdfunding.benefit_allocations(tier_id);
CREATE INDEX idx_allocations_status ON crowdfunding.benefit_allocations(fulfillment_status);
CREATE INDEX idx_allocations_type ON crowdfunding.benefit_allocations(benefit_type);
CREATE INDEX idx_allocations_valid_until ON crowdfunding.benefit_allocations(valid_until);

CREATE INDEX idx_usage_allocation ON crowdfunding.benefit_usage_log(allocation_id);
CREATE INDEX idx_usage_date ON crowdfunding.benefit_usage_log(usage_date);
CREATE INDEX idx_usage_staff ON crowdfunding.benefit_usage_log(staff_id);

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Auto-calculate quantity_remaining
CREATE OR REPLACE FUNCTION crowdfunding.update_benefit_remaining()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.quantity_allocated IS NOT NULL THEN
        NEW.quantity_remaining := NEW.quantity_allocated - NEW.quantity_used;
    ELSE
        NEW.quantity_remaining := NULL; -- Unlimited
    END IF;

    NEW.updated_at := CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_benefit_remaining
    BEFORE INSERT OR UPDATE ON crowdfunding.benefit_allocations
    FOR EACH ROW
    EXECUTE FUNCTION crowdfunding.update_benefit_remaining();

-- ============================================================================
-- VIEWS
-- ============================================================================

-- View: All backers with summary of contributions and benefits
CREATE OR REPLACE VIEW crowdfunding.v_backer_summary AS
SELECT
    b.id AS backer_id,
    b.email,
    b.first_name,
    b.last_initial,
    b.phone,
    b.city,
    b.state,
    b.total_contributed,
    b.contribution_count,
    b.created_at AS backer_since,

    -- Benefit summary
    COUNT(DISTINCT ba.id) AS total_benefits,
    COUNT(DISTINCT ba.id) FILTER (WHERE ba.fulfillment_status = 'allocated') AS benefits_unclaimed,
    COUNT(DISTINCT ba.id) FILTER (WHERE ba.fulfillment_status = 'fulfilled') AS benefits_claimed,
    COUNT(DISTINCT ba.id) FILTER (WHERE ba.fulfillment_status = 'expired') AS benefits_expired,
    COUNT(DISTINCT ba.id) FILTER (WHERE ba.valid_until IS NOT NULL AND ba.valid_until < CURRENT_TIMESTAMP) AS benefits_expiring_soon,

    -- Latest contribution
    MAX(c.completed_at) AS last_contribution_date,

    -- Highest tier
    MAX(ct.amount) AS highest_tier_amount
FROM crowdfunding.backers b
LEFT JOIN crowdfunding.contributions c ON c.backer_id = b.id AND c.status = 'completed'
LEFT JOIN crowdfunding.contribution_tiers ct ON ct.id = c.tier_id
LEFT JOIN crowdfunding.benefit_allocations ba ON ba.backer_id = b.id
GROUP BY b.id, b.email, b.first_name, b.last_initial, b.phone, b.city, b.state,
         b.total_contributed, b.contribution_count, b.created_at
ORDER BY b.total_contributed DESC, b.created_at DESC;

-- View: Detailed backer benefits with claim status
CREATE OR REPLACE VIEW crowdfunding.v_backer_benefits_detailed AS
SELECT
    ba.id AS allocation_id,
    ba.backer_id,
    b.email,
    b.first_name,
    b.last_initial,
    ba.contribution_id,
    c.completed_at AS contribution_date,
    ct.name AS tier_name,
    c.amount AS contribution_amount,

    -- Benefit details
    ba.benefit_type,
    ba.benefit_name,
    ba.benefit_description,
    ba.quantity_allocated,
    ba.quantity_used,
    ba.quantity_remaining,

    -- Status
    ba.fulfillment_status,
    ba.valid_from,
    ba.valid_until,
    CASE
        WHEN ba.valid_until IS NULL THEN true
        WHEN ba.valid_until > CURRENT_TIMESTAMP THEN true
        ELSE false
    END AS is_valid,

    CASE
        WHEN ba.valid_until IS NOT NULL THEN
            EXTRACT(DAY FROM (ba.valid_until - CURRENT_TIMESTAMP))::INTEGER
        ELSE NULL
    END AS days_until_expiration,

    ba.fulfilled_at,
    ba.fulfillment_notes,
    ba.metadata,
    ba.created_at
FROM crowdfunding.benefit_allocations ba
JOIN crowdfunding.backers b ON b.id = ba.backer_id
JOIN crowdfunding.contributions c ON c.id = ba.contribution_id
LEFT JOIN crowdfunding.contribution_tiers ct ON ct.id = ba.tier_id
ORDER BY b.email, ba.created_at DESC;

-- View: Pending fulfillment (for staff)
CREATE OR REPLACE VIEW crowdfunding.v_pending_fulfillment AS
SELECT
    ba.id AS allocation_id,
    ba.backer_id,
    b.email,
    b.first_name,
    b.last_initial,
    b.phone,
    ba.benefit_type,
    ba.benefit_name,
    ba.quantity_allocated AS total_allocated,
    ba.quantity_remaining AS remaining,
    ba.valid_until,
    ba.fulfillment_status,
    ba.created_at,
    ct.name AS tier_name,
    c.amount AS contribution_amount,

    CASE
        WHEN ba.valid_until IS NOT NULL THEN
            EXTRACT(DAY FROM (ba.valid_until - CURRENT_TIMESTAMP))::INTEGER
        ELSE NULL
    END AS days_until_expiration
FROM crowdfunding.benefit_allocations ba
JOIN crowdfunding.backers b ON b.id = ba.backer_id
JOIN crowdfunding.contributions c ON c.id = ba.contribution_id
LEFT JOIN crowdfunding.contribution_tiers ct ON ct.id = c.tier_id
WHERE ba.fulfillment_status IN ('allocated', 'in_progress')
  AND (ba.valid_until IS NULL OR ba.valid_until > CURRENT_TIMESTAMP)
  AND (ba.quantity_remaining IS NULL OR ba.quantity_remaining > 0)
ORDER BY
    CASE WHEN ba.valid_until IS NOT NULL THEN EXTRACT(DAY FROM (ba.valid_until - CURRENT_TIMESTAMP)) END ASC NULLS LAST,
    ba.created_at ASC;

-- View: Fulfillment summary by benefit type
CREATE OR REPLACE VIEW crowdfunding.v_fulfillment_summary AS
SELECT
    ba.benefit_type,
    COUNT(*) AS total_allocations,
    COUNT(*) FILTER (WHERE ba.fulfillment_status = 'allocated') AS pending_count,
    COUNT(*) FILTER (WHERE ba.fulfillment_status = 'in_progress') AS in_progress_count,
    COUNT(*) FILTER (WHERE ba.fulfillment_status = 'fulfilled') AS fulfilled_count,
    COUNT(*) FILTER (WHERE ba.fulfillment_status = 'expired') AS expired_count,
    SUM(ba.quantity_allocated) AS total_units_allocated,
    SUM(ba.quantity_used) AS total_units_used,
    SUM(ba.quantity_remaining) AS total_units_remaining
FROM crowdfunding.benefit_allocations ba
GROUP BY ba.benefit_type
ORDER BY total_allocations DESC;

-- View: Active backer benefits (for redemption)
-- Aggregates multiple allocations of the same benefit type for each backer
CREATE OR REPLACE VIEW crowdfunding.v_active_backer_benefits AS
SELECT
    (array_agg(ba.id ORDER BY ba.created_at))[1] AS id,  -- Use first allocation ID as reference
    ba.backer_id,
    b.email,
    b.first_name,
    b.last_initial,
    ba.benefit_type,
    ba.benefit_name,
    SUM(ba.quantity_allocated)::numeric(10,2) AS total_allocated,  -- SUM and cast to maintain type
    SUM(ba.quantity_used)::numeric(10,2) AS total_used,            -- SUM and cast to maintain type
    SUM(ba.quantity_remaining)::numeric(10,2) AS remaining,        -- SUM and cast to maintain type
    MIN(ba.valid_from) AS valid_from,
    MAX(ba.valid_until) AS valid_until,
    MAX(ba.valid_until) IS NULL OR MAX(ba.valid_until) > CURRENT_TIMESTAMP AS is_valid,
    jsonb_agg(ba.metadata) AS metadata,
    MIN(ba.created_at) AS created_at
FROM crowdfunding.benefit_allocations ba
JOIN crowdfunding.backers b ON b.id = ba.backer_id
WHERE ba.fulfillment_status IN ('allocated', 'in_progress', 'fulfilled')
  AND (ba.valid_until IS NULL OR ba.valid_until > CURRENT_TIMESTAMP)
  AND (ba.quantity_remaining IS NULL OR ba.quantity_remaining > 0)
GROUP BY ba.backer_id, b.email, b.first_name, b.last_initial, ba.benefit_type, ba.benefit_name
ORDER BY MIN(ba.created_at) DESC;

-- ============================================================================
-- FUNCTIONS
-- ============================================================================

-- Allocate benefits from tier (called after contribution is completed)
CREATE OR REPLACE FUNCTION crowdfunding.allocate_benefits_from_tier(
    p_contribution_id UUID,
    p_tier_id UUID,
    p_backer_id UUID
)
RETURNS INTEGER AS $$
DECLARE
    v_tier RECORD;
    v_benefit JSONB;
    v_benefit_count INTEGER := 0;
    v_existing_count INTEGER := 0;
    v_quantity DECIMAL(10, 2);
    v_valid_until TIMESTAMP WITH TIME ZONE;
    v_duration_months INTEGER;
    v_duration_years INTEGER;
BEGIN
    -- Check if benefits have already been allocated for this contribution
    SELECT COUNT(*) INTO v_existing_count
    FROM crowdfunding.benefit_allocations
    WHERE contribution_id = p_contribution_id;

    -- If allocations already exist, return early to prevent duplicates
    IF v_existing_count > 0 THEN
        RETURN v_existing_count;
    END IF;

    -- Get tier details
    SELECT * INTO v_tier
    FROM crowdfunding.contribution_tiers
    WHERE id = p_tier_id;

    IF v_tier IS NULL THEN
        RAISE EXCEPTION 'Tier not found: %', p_tier_id;
    END IF;

    -- Parse benefits JSON and create allocations
    FOR v_benefit IN SELECT * FROM jsonb_array_elements(v_tier.benefits)
    LOOP
        v_quantity := NULL;
        v_valid_until := NULL;

        -- Extract quantity if specified in benefit metadata
        IF v_benefit ? 'quantity' THEN
            v_quantity := (v_benefit->>'quantity')::DECIMAL(10, 2);
        END IF;

        -- Calculate expiration based on duration
        IF v_benefit ? 'duration_months' THEN
            v_duration_months := (v_benefit->>'duration_months')::INTEGER;
            v_valid_until := CURRENT_TIMESTAMP + (v_duration_months || ' months')::INTERVAL;
        ELSIF v_benefit ? 'duration_years' THEN
            v_duration_years := (v_benefit->>'duration_years')::INTEGER;
            v_valid_until := CURRENT_TIMESTAMP + (v_duration_years || ' years')::INTERVAL;
        ELSIF v_benefit ? 'lifetime' AND (v_benefit->>'lifetime')::BOOLEAN THEN
            v_valid_until := NULL; -- Lifetime benefit
        END IF;

        -- Determine benefit type
        DECLARE
            v_benefit_type VARCHAR(100);
        BEGIN
            v_benefit_type := v_benefit->>'type';

            -- Map tier benefit types to allocation benefit types
            CASE v_benefit_type
                WHEN 'court_time_hours' THEN v_benefit_type := 'court_time_hours';
                WHEN 'dink_board_sessions' THEN v_benefit_type := 'dink_board_sessions';
                WHEN 'ball_machine_sessions' THEN v_benefit_type := 'ball_machine_sessions';
                WHEN 'pro_shop_discount' THEN v_benefit_type := 'pro_shop_discount';
                WHEN 'founding_membership', 'membership_months' THEN v_benefit_type := 'membership_months';
                WHEN 'free_lessons', 'private_lessons' THEN v_benefit_type := 'private_lessons';
                WHEN 'guest_passes' THEN v_benefit_type := 'guest_passes';
                WHEN 'priority_booking' THEN v_benefit_type := 'priority_booking';
                WHEN 'name_on_wall', 'court_sponsor' THEN v_benefit_type := 'recognition';
                ELSE v_benefit_type := 'custom';
            END CASE;

            -- Create benefit allocation
            INSERT INTO crowdfunding.benefit_allocations (
                backer_id,
                contribution_id,
                tier_id,
                benefit_type,
                benefit_name,
                benefit_description,
                quantity_allocated,
                valid_until,
                fulfillment_status,
                metadata
            )
            VALUES (
                p_backer_id,
                p_contribution_id,
                p_tier_id,
                v_benefit_type,
                COALESCE(v_benefit->>'text', v_tier.name || ' Benefit'),
                v_benefit->>'text',
                v_quantity,
                v_valid_until,
                'allocated',
                v_benefit
            );

            v_benefit_count := v_benefit_count + 1;
        END;
    END LOOP;

    RETURN v_benefit_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Redeem/use a benefit
CREATE OR REPLACE FUNCTION crowdfunding.redeem_benefit(
    p_allocation_id UUID,
    p_quantity DECIMAL(10, 2),
    p_used_for TEXT DEFAULT NULL,
    p_staff_id UUID DEFAULT NULL,
    p_notes TEXT DEFAULT NULL
)
RETURNS VOID AS $$
DECLARE
    v_allocation RECORD;
BEGIN
    -- Get allocation
    SELECT * INTO v_allocation
    FROM crowdfunding.benefit_allocations
    WHERE id = p_allocation_id;

    IF v_allocation IS NULL THEN
        RAISE EXCEPTION 'Benefit allocation not found: %', p_allocation_id;
    END IF;

    -- Check if valid
    IF v_allocation.valid_until IS NOT NULL AND v_allocation.valid_until < CURRENT_TIMESTAMP THEN
        RAISE EXCEPTION 'Benefit has expired';
    END IF;

    -- Check if enough remaining
    IF v_allocation.quantity_remaining IS NOT NULL AND v_allocation.quantity_remaining < p_quantity THEN
        RAISE EXCEPTION 'Insufficient quantity remaining. Available: %, Requested: %',
            v_allocation.quantity_remaining, p_quantity;
    END IF;

    -- Update allocation
    UPDATE crowdfunding.benefit_allocations
    SET
        quantity_used = quantity_used + p_quantity,
        fulfillment_status = CASE
            WHEN quantity_remaining - p_quantity <= 0 THEN 'fulfilled'
            ELSE 'in_progress'
        END,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_allocation_id;

    -- Log usage
    INSERT INTO crowdfunding.benefit_usage_log (
        allocation_id,
        quantity_used,
        used_for,
        staff_id,
        staff_verified,
        notes
    )
    VALUES (
        p_allocation_id,
        p_quantity,
        p_used_for,
        p_staff_id,
        p_staff_id IS NOT NULL, -- Auto-verify if staff processed
        p_notes
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- ROW LEVEL SECURITY
-- ============================================================================

ALTER TABLE crowdfunding.benefit_allocations ENABLE ROW LEVEL SECURITY;
ALTER TABLE crowdfunding.benefit_usage_log ENABLE ROW LEVEL SECURITY;

-- Service role has full access
CREATE POLICY "Service role has full access to allocations"
    ON crowdfunding.benefit_allocations FOR ALL
    USING (current_setting('request.jwt.claims', true)::json->>'role' = 'service_role');

CREATE POLICY "Service role has full access to usage log"
    ON crowdfunding.benefit_usage_log FOR ALL
    USING (current_setting('request.jwt.claims', true)::json->>'role' = 'service_role');

-- Authenticated users can view their own benefits (for future user accounts)
CREATE POLICY "Users can view their own benefits"
    ON crowdfunding.benefit_allocations FOR SELECT
    USING (
        backer_id IN (
            SELECT id FROM crowdfunding.backers
            WHERE user_id = auth.uid()
        )
    );

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

GRANT SELECT ON crowdfunding.v_backer_summary TO authenticated, service_role;
GRANT SELECT ON crowdfunding.v_backer_benefits_detailed TO authenticated, service_role;
GRANT SELECT ON crowdfunding.v_pending_fulfillment TO authenticated, service_role;
GRANT SELECT ON crowdfunding.v_fulfillment_summary TO authenticated, service_role;
GRANT SELECT ON crowdfunding.v_active_backer_benefits TO authenticated, service_role;

GRANT EXECUTE ON FUNCTION crowdfunding.allocate_benefits_from_tier(UUID, UUID, UUID) TO service_role;
GRANT EXECUTE ON FUNCTION crowdfunding.redeem_benefit(UUID, DECIMAL, TEXT, UUID, TEXT) TO service_role, authenticated;

COMMENT ON TABLE crowdfunding.benefit_allocations IS 'Individual benefit items allocated to backers with redemption tracking';
COMMENT ON TABLE crowdfunding.benefit_usage_log IS 'Log of benefit redemptions and usage';
COMMENT ON VIEW crowdfunding.v_backer_summary IS 'All backers with contribution and benefit summary';
COMMENT ON VIEW crowdfunding.v_backer_benefits_detailed IS 'Detailed view of backer benefits with claim status';
COMMENT ON FUNCTION crowdfunding.allocate_benefits_from_tier IS 'Create benefit allocations from tier benefits JSON';
COMMENT ON FUNCTION crowdfunding.redeem_benefit IS 'Record benefit usage and update quantities';
