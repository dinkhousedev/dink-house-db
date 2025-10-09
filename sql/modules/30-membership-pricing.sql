-- ============================================================================
-- MEMBERSHIP PRICING MODULE
-- Membership tier configuration and pricing management
-- ============================================================================

SET search_path TO system, app_auth, public;

-- ============================================================================
-- MEMBERSHIP TIERS TABLE
-- Configuration for all membership levels
-- ============================================================================

CREATE TABLE IF NOT EXISTS system.membership_tiers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tier_code app_auth.membership_level NOT NULL UNIQUE,
    tier_name VARCHAR(50) NOT NULL,
    monthly_price DECIMAL(10, 2) NOT NULL DEFAULT 0,
    description TEXT,

    -- Open Play Pricing
    open_play_access TEXT, -- 'unlimited', 'off-peak', 'none'
    open_play_peak_price DECIMAL(10, 2) DEFAULT 0,
    open_play_offpeak_price DECIMAL(10, 2) DEFAULT 0,

    -- Court Rental Pricing
    court_rental_discount_percent INTEGER DEFAULT 0, -- Percentage off
    court_rental_peak_price DECIMAL(10, 2),
    court_rental_offpeak_price DECIMAL(10, 2),
    free_court_rental_hours TEXT, -- e.g., 'weekdays 7am-5pm outdoor'

    -- Equipment & Other
    equipment_rental_price DECIMAL(10, 2) DEFAULT 0,

    -- Access & Policies
    booking_window_days INTEGER DEFAULT 3, -- Days in advance
    cancellation_hours INTEGER DEFAULT 24, -- Hours notice required
    guest_passes_per_month INTEGER DEFAULT 0,

    -- Benefits (JSON for flexibility)
    benefits JSONB DEFAULT '[]'::jsonb,
    features JSONB DEFAULT '[]'::jsonb,

    -- Metadata
    is_active BOOLEAN DEFAULT true,
    sort_order INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE system.membership_tiers IS 'Configuration for all membership tier pricing and benefits';

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_membership_tiers_code ON system.membership_tiers(tier_code);
CREATE INDEX IF NOT EXISTS idx_membership_tiers_active ON system.membership_tiers(is_active);

-- ============================================================================
-- PLAYER REGISTRATION FEES TABLE
-- Track one-time $5 registration fee for guests
-- ============================================================================

CREATE TABLE IF NOT EXISTS app_auth.player_fees (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id UUID NOT NULL REFERENCES app_auth.players(id) ON DELETE CASCADE,
    fee_type VARCHAR(50) NOT NULL DEFAULT 'registration', -- 'registration', 'late_cancellation', etc.
    amount DECIMAL(10, 2) NOT NULL,

    -- Payment tracking
    stripe_payment_intent_id TEXT,
    stripe_charge_id TEXT,
    payment_status VARCHAR(50) DEFAULT 'pending', -- 'pending', 'paid', 'failed', 'refunded'
    paid_at TIMESTAMPTZ,

    -- Metadata
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_player_registration_fee UNIQUE (player_id, fee_type)
);

COMMENT ON TABLE app_auth.player_fees IS 'Track one-time fees like $5 registration fee';

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_player_fees_player ON app_auth.player_fees(player_id);
CREATE INDEX IF NOT EXISTS idx_player_fees_status ON app_auth.player_fees(payment_status);
CREATE INDEX IF NOT EXISTS idx_player_fees_type ON app_auth.player_fees(fee_type);

-- ============================================================================
-- MEMBERSHIP TRANSACTIONS TABLE
-- Track all membership payments, upgrades, renewals
-- ============================================================================

CREATE TABLE IF NOT EXISTS app_auth.membership_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id UUID NOT NULL REFERENCES app_auth.players(id) ON DELETE CASCADE,

    -- Membership details
    from_tier app_auth.membership_level,
    to_tier app_auth.membership_level NOT NULL,
    transaction_type VARCHAR(50) NOT NULL, -- 'upgrade', 'downgrade', 'renewal', 'new'

    -- Payment
    amount DECIMAL(10, 2) NOT NULL,
    stripe_payment_intent_id TEXT,
    stripe_subscription_id TEXT,
    payment_status VARCHAR(50) DEFAULT 'pending', -- 'pending', 'completed', 'failed', 'refunded'

    -- Period
    effective_date DATE NOT NULL,
    expires_date DATE,

    -- Metadata
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE app_auth.membership_transactions IS 'All membership payment and upgrade transactions';

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_membership_transactions_player ON app_auth.membership_transactions(player_id);
CREATE INDEX IF NOT EXISTS idx_membership_transactions_status ON app_auth.membership_transactions(payment_status);
CREATE INDEX IF NOT EXISTS idx_membership_transactions_type ON app_auth.membership_transactions(transaction_type);
CREATE INDEX IF NOT EXISTS idx_membership_transactions_effective ON app_auth.membership_transactions(effective_date);

-- ============================================================================
-- SEED MEMBERSHIP TIER DATA
-- ============================================================================

INSERT INTO system.membership_tiers (
    tier_code,
    tier_name,
    monthly_price,
    description,
    open_play_access,
    open_play_peak_price,
    open_play_offpeak_price,
    court_rental_peak_price,
    court_rental_offpeak_price,
    equipment_rental_price,
    booking_window_days,
    cancellation_hours,
    guest_passes_per_month,
    benefits,
    features,
    sort_order
) VALUES
-- GUEST TIER
(
    'guest',
    'Guest',
    0.00,
    'Pay-per-session access with no monthly commitment',
    'none',
    15.00, -- $15 peak open play
    10.00, -- $10 off-peak open play
    45.00, -- $45/hour peak court rental
    35.00, -- $35/hour off-peak court rental
    8.00,  -- $8 equipment rental
    3,     -- 3 days advance booking
    24,    -- 24 hour cancellation
    0,
    '["One-time $5 registration fee", "Pay per session", "No monthly commitment", "Access to all facilities"]'::jsonb,
    '["Open play access (pay per session)", "Court rentals (pay per hour)", "Equipment rentals available"]'::jsonb,
    1
),
-- BASIC TIER (Dink)
(
    'basic',
    'Dink',
    59.00,
    'Perfect for casual players who want regular access',
    'unlimited-outdoor',
    0.00,  -- Free open play
    0.00,
    40.50, -- 10% off: $45 -> $40.50
    31.50, -- 10% off: $35 -> $31.50
    8.00,
    7,     -- 7 days advance
    24,
    1,     -- 1 guest pass per month
    '["Unlimited outdoor open play", "10% off court bookings", "1 guest pass per month", "7-day advance booking"]'::jsonb,
    '["Unlimited outdoor open play", "10% discount on court bookings", "Book up to 7 days in advance", "1 free guest pass per month"]'::jsonb,
    2
),
-- PREMIUM TIER (Ace)
(
    'premium',
    'Ace',
    109.00,
    'For dedicated players who want indoor + outdoor access',
    'unlimited',
    0.00,  -- Free all open play
    0.00,
    36.00, -- 20% off: $45 -> $36
    28.00, -- 20% off: $35 -> $28
    0.00,  -- Free equipment rental
    10,    -- 10 days advance
    24,
    2,     -- 2 guest passes per month
    '["Unlimited indoor + outdoor open play", "Free weekday court rentals (7am-5pm outdoor)", "20% off all court bookings", "Free equipment rental", "Free clinics access", "2 guest passes per month", "10-day advance booking"]'::jsonb,
    '["Unlimited open play (all times)", "Free court rentals weekdays 7am-5pm (outdoor)", "20% discount on court bookings", "Free equipment rental", "Free clinics access", "Book up to 10 days in advance", "2 free guest passes per month"]'::jsonb,
    3
),
-- VIP TIER (Champion)
(
    'vip',
    'Champion',
    159.00,
    'Elite membership with maximum benefits and priority access',
    'unlimited',
    0.00,  -- Free all open play
    0.00,
    33.75, -- 25% off: $45 -> $33.75
    26.25, -- 25% off: $35 -> $26.25
    0.00,  -- Free equipment rental
    14,    -- 14 days advance
    24,
    4,     -- 4 guest passes per month
    '["Unlimited indoor + outdoor open play (all times)", "Free weekday court rentals (7am-5pm indoor + outdoor)", "25% off prime-time bookings", "Free equipment rental", "Free clinics + 1 private lesson per month", "Priority tournament registration", "4 guest passes per month", "14-day advance booking"]'::jsonb,
    '["Unlimited open play (peak + off-peak)", "Free court rentals weekdays 7am-5pm (indoor + outdoor)", "25% discount on prime-time bookings", "Free equipment rental", "Free clinics + 1 private lesson monthly", "Priority tournament registration", "Book up to 14 days in advance", "4 free guest passes per month"]'::jsonb,
    4
)
ON CONFLICT (tier_code) DO UPDATE SET
    tier_name = EXCLUDED.tier_name,
    monthly_price = EXCLUDED.monthly_price,
    description = EXCLUDED.description,
    open_play_access = EXCLUDED.open_play_access,
    open_play_peak_price = EXCLUDED.open_play_peak_price,
    open_play_offpeak_price = EXCLUDED.open_play_offpeak_price,
    court_rental_peak_price = EXCLUDED.court_rental_peak_price,
    court_rental_offpeak_price = EXCLUDED.court_rental_offpeak_price,
    equipment_rental_price = EXCLUDED.equipment_rental_price,
    booking_window_days = EXCLUDED.booking_window_days,
    cancellation_hours = EXCLUDED.cancellation_hours,
    guest_passes_per_month = EXCLUDED.guest_passes_per_month,
    benefits = EXCLUDED.benefits,
    features = EXCLUDED.features,
    sort_order = EXCLUDED.sort_order,
    updated_at = CURRENT_TIMESTAMP;

-- ============================================================================
-- RPC FUNCTIONS
-- ============================================================================

-- Get pricing for a specific membership tier
CREATE OR REPLACE FUNCTION get_membership_pricing(p_tier app_auth.membership_level)
RETURNS TABLE (
    tier_code TEXT,
    tier_name TEXT,
    monthly_price DECIMAL,
    description TEXT,
    open_play_access TEXT,
    open_play_peak_price DECIMAL,
    open_play_offpeak_price DECIMAL,
    court_rental_peak_price DECIMAL,
    court_rental_offpeak_price DECIMAL,
    equipment_rental_price DECIMAL,
    booking_window_days INTEGER,
    cancellation_hours INTEGER,
    guest_passes_per_month INTEGER,
    benefits JSONB,
    features JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT
        mt.tier_code::TEXT,
        mt.tier_name,
        mt.monthly_price,
        mt.description,
        mt.open_play_access,
        mt.open_play_peak_price,
        mt.open_play_offpeak_price,
        mt.court_rental_peak_price,
        mt.court_rental_offpeak_price,
        mt.equipment_rental_price,
        mt.booking_window_days,
        mt.cancellation_hours,
        mt.guest_passes_per_month,
        mt.benefits,
        mt.features
    FROM system.membership_tiers mt
    WHERE mt.tier_code = p_tier
    AND mt.is_active = true;
END;
$$;

-- Get all membership tiers for comparison
CREATE OR REPLACE FUNCTION get_all_membership_tiers()
RETURNS TABLE (
    tier_code TEXT,
    tier_name TEXT,
    monthly_price DECIMAL,
    description TEXT,
    open_play_access TEXT,
    open_play_peak_price DECIMAL,
    open_play_offpeak_price DECIMAL,
    court_rental_peak_price DECIMAL,
    court_rental_offpeak_price DECIMAL,
    equipment_rental_price DECIMAL,
    booking_window_days INTEGER,
    cancellation_hours INTEGER,
    guest_passes_per_month INTEGER,
    benefits JSONB,
    features JSONB,
    sort_order INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT
        mt.tier_code::TEXT,
        mt.tier_name,
        mt.monthly_price,
        mt.description,
        mt.open_play_access,
        mt.open_play_peak_price,
        mt.open_play_offpeak_price,
        mt.court_rental_peak_price,
        mt.court_rental_offpeak_price,
        mt.equipment_rental_price,
        mt.booking_window_days,
        mt.cancellation_hours,
        mt.guest_passes_per_month,
        mt.benefits,
        mt.features,
        mt.sort_order
    FROM system.membership_tiers mt
    WHERE mt.is_active = true
    ORDER BY mt.sort_order;
END;
$$;

-- Get player's current pricing information
CREATE OR REPLACE FUNCTION get_player_pricing_info(p_player_id UUID)
RETURNS TABLE (
    player_id UUID,
    membership_level TEXT,
    tier_name TEXT,
    monthly_price DECIMAL,
    registration_fee_paid BOOLEAN,
    registration_fee_amount DECIMAL,
    open_play_peak_price DECIMAL,
    open_play_offpeak_price DECIMAL,
    court_rental_peak_price DECIMAL,
    court_rental_offpeak_price DECIMAL,
    equipment_rental_price DECIMAL,
    booking_window_days INTEGER,
    cancellation_hours INTEGER,
    guest_passes_per_month INTEGER,
    benefits JSONB,
    features JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.id,
        p.membership_level::TEXT,
        mt.tier_name,
        mt.monthly_price,
        COALESCE(pf.payment_status = 'paid', false) as registration_fee_paid,
        COALESCE(pf.amount, 5.00) as registration_fee_amount,
        mt.open_play_peak_price,
        mt.open_play_offpeak_price,
        mt.court_rental_peak_price,
        mt.court_rental_offpeak_price,
        mt.equipment_rental_price,
        mt.booking_window_days,
        mt.cancellation_hours,
        mt.guest_passes_per_month,
        mt.benefits,
        mt.features
    FROM app_auth.players p
    JOIN system.membership_tiers mt ON mt.tier_code = p.membership_level
    LEFT JOIN app_auth.player_fees pf ON pf.player_id = p.id AND pf.fee_type = 'registration'
    WHERE p.id = p_player_id;
END;
$$;

-- Check if player has paid registration fee
CREATE OR REPLACE FUNCTION has_paid_registration_fee(p_player_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_paid BOOLEAN;
BEGIN
    SELECT COALESCE(payment_status = 'paid', false)
    INTO v_paid
    FROM app_auth.player_fees
    WHERE player_id = p_player_id
    AND fee_type = 'registration';

    RETURN COALESCE(v_paid, false);
END;
$$;

-- Record registration fee payment
CREATE OR REPLACE FUNCTION record_registration_fee(
    p_player_id UUID,
    p_stripe_payment_intent_id TEXT,
    p_stripe_charge_id TEXT DEFAULT NULL
)
RETURNS TABLE (
    success BOOLEAN,
    message TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Insert or update registration fee record
    INSERT INTO app_auth.player_fees (
        player_id,
        fee_type,
        amount,
        stripe_payment_intent_id,
        stripe_charge_id,
        payment_status,
        paid_at
    ) VALUES (
        p_player_id,
        'registration',
        5.00,
        p_stripe_payment_intent_id,
        p_stripe_charge_id,
        'paid',
        CURRENT_TIMESTAMP
    )
    ON CONFLICT (player_id, fee_type)
    DO UPDATE SET
        stripe_payment_intent_id = EXCLUDED.stripe_payment_intent_id,
        stripe_charge_id = EXCLUDED.stripe_charge_id,
        payment_status = 'paid',
        paid_at = CURRENT_TIMESTAMP,
        updated_at = CURRENT_TIMESTAMP;

    RETURN QUERY SELECT true, 'Registration fee recorded successfully'::TEXT;
END;
$$;

-- Record membership upgrade/change transaction
CREATE OR REPLACE FUNCTION record_membership_transaction(
    p_player_id UUID,
    p_to_tier app_auth.membership_level,
    p_transaction_type VARCHAR(50),
    p_amount DECIMAL,
    p_stripe_payment_intent_id TEXT DEFAULT NULL,
    p_stripe_subscription_id TEXT DEFAULT NULL,
    p_effective_date DATE DEFAULT CURRENT_DATE,
    p_expires_date DATE DEFAULT NULL
)
RETURNS TABLE (
    success BOOLEAN,
    message TEXT,
    transaction_id UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_from_tier app_auth.membership_level;
    v_transaction_id UUID;
BEGIN
    -- Get current membership level
    SELECT membership_level INTO v_from_tier
    FROM app_auth.players
    WHERE id = p_player_id;

    -- Insert transaction
    INSERT INTO app_auth.membership_transactions (
        player_id,
        from_tier,
        to_tier,
        transaction_type,
        amount,
        stripe_payment_intent_id,
        stripe_subscription_id,
        payment_status,
        effective_date,
        expires_date
    ) VALUES (
        p_player_id,
        v_from_tier,
        p_to_tier,
        p_transaction_type,
        p_amount,
        p_stripe_payment_intent_id,
        p_stripe_subscription_id,
        'completed',
        p_effective_date,
        p_expires_date
    )
    RETURNING id INTO v_transaction_id;

    -- Update player's membership level
    UPDATE app_auth.players
    SET
        membership_level = p_to_tier,
        membership_started_on = p_effective_date,
        membership_expires_on = p_expires_date,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_player_id;

    RETURN QUERY SELECT true, 'Membership transaction recorded successfully'::TEXT, v_transaction_id;
END;
$$;

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

-- Grant access to membership tiers (public read)
GRANT SELECT ON system.membership_tiers TO anon;
GRANT SELECT ON system.membership_tiers TO authenticated;
GRANT SELECT ON system.membership_tiers TO service_role;

-- Grant access to player fees (restricted)
GRANT SELECT ON app_auth.player_fees TO authenticated;
GRANT INSERT, UPDATE ON app_auth.player_fees TO authenticated;
GRANT ALL ON app_auth.player_fees TO service_role;

-- Grant access to membership transactions (restricted)
GRANT SELECT ON app_auth.membership_transactions TO authenticated;
GRANT INSERT ON app_auth.membership_transactions TO authenticated;
GRANT ALL ON app_auth.membership_transactions TO service_role;

-- Grant execute on functions
GRANT EXECUTE ON FUNCTION get_membership_pricing TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION get_all_membership_tiers TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION get_player_pricing_info TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION has_paid_registration_fee TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION record_registration_fee TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION record_membership_transaction TO authenticated, service_role;

COMMENT ON FUNCTION get_membership_pricing IS 'Get pricing details for a specific membership tier';
COMMENT ON FUNCTION get_all_membership_tiers IS 'Get all active membership tiers for comparison';
COMMENT ON FUNCTION get_player_pricing_info IS 'Get player current pricing including registration fee status';
COMMENT ON FUNCTION has_paid_registration_fee IS 'Check if player has paid the one-time registration fee';
COMMENT ON FUNCTION record_registration_fee IS 'Record successful $5 registration fee payment';
COMMENT ON FUNCTION record_membership_transaction IS 'Record membership upgrade/downgrade/renewal transaction';
