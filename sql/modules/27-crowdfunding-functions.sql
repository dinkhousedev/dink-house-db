-- ============================================================================
-- CROWDFUNDING RPC FUNCTIONS
-- Functions for checkout flow, payment processing, and backer management
-- ============================================================================

SET search_path TO crowdfunding, public;

-- ============================================================================
-- BACKER MANAGEMENT FUNCTIONS
-- ============================================================================

-- Get backer by email (used during checkout to check if backer exists)
CREATE OR REPLACE FUNCTION crowdfunding.get_backer_by_email(p_email public.CITEXT)
RETURNS TABLE(
    id UUID,
    email public.CITEXT,
    first_name VARCHAR(100),
    last_initial VARCHAR(1),
    phone VARCHAR(30),
    city VARCHAR(100),
    state VARCHAR(2),
    stripe_customer_id TEXT,
    total_contributed DECIMAL(10, 2),
    contribution_count INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        b.id,
        b.email,
        b.first_name,
        b.last_initial,
        b.phone,
        b.city,
        b.state,
        b.stripe_customer_id,
        b.total_contributed,
        b.contribution_count
    FROM crowdfunding.backers b
    WHERE b.email = p_email;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- CHECKOUT & CONTRIBUTION FUNCTIONS
-- ============================================================================

-- Create or update backer and create pending contribution
CREATE OR REPLACE FUNCTION crowdfunding.create_checkout_contribution(
    p_email public.CITEXT,
    p_first_name VARCHAR(100),
    p_last_initial VARCHAR(1),
    p_campaign_type_id UUID,
    p_tier_id UUID,
    p_amount DECIMAL(10, 2),
    p_phone VARCHAR(30) DEFAULT NULL,
    p_city VARCHAR(100) DEFAULT NULL,
    p_state VARCHAR(2) DEFAULT NULL,
    p_stripe_customer_id TEXT DEFAULT NULL,
    p_is_public BOOLEAN DEFAULT TRUE,
    p_show_amount BOOLEAN DEFAULT TRUE
)
RETURNS TABLE(
    backer_id UUID,
    contribution_id UUID
) AS $$
DECLARE
    v_backer_id UUID;
    v_contribution_id UUID;
BEGIN
    -- Create or update backer
    INSERT INTO crowdfunding.backers (
        email,
        first_name,
        last_initial,
        phone,
        city,
        state,
        stripe_customer_id
    )
    VALUES (
        p_email,
        p_first_name,
        p_last_initial,
        p_phone,
        p_city,
        p_state,
        p_stripe_customer_id
    )
    ON CONFLICT (email)
    DO UPDATE SET
        first_name = EXCLUDED.first_name,
        last_initial = EXCLUDED.last_initial,
        phone = COALESCE(EXCLUDED.phone, crowdfunding.backers.phone),
        city = COALESCE(EXCLUDED.city, crowdfunding.backers.city),
        state = COALESCE(EXCLUDED.state, crowdfunding.backers.state),
        stripe_customer_id = COALESCE(EXCLUDED.stripe_customer_id, crowdfunding.backers.stripe_customer_id),
        updated_at = CURRENT_TIMESTAMP
    RETURNING id INTO v_backer_id;

    -- Create pending contribution
    INSERT INTO crowdfunding.contributions (
        backer_id,
        campaign_type_id,
        tier_id,
        amount,
        status,
        is_public,
        show_amount
    )
    VALUES (
        v_backer_id,
        p_campaign_type_id,
        p_tier_id,
        p_amount,
        'pending',
        p_is_public,
        p_show_amount
    )
    RETURNING id INTO v_contribution_id;

    -- Return both IDs
    RETURN QUERY SELECT v_backer_id, v_contribution_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Update contribution with Stripe checkout session ID
CREATE OR REPLACE FUNCTION crowdfunding.update_contribution_session(
    p_contribution_id UUID,
    p_session_id TEXT
)
RETURNS VOID AS $$
BEGIN
    UPDATE crowdfunding.contributions
    SET stripe_checkout_session_id = p_session_id
    WHERE id = p_contribution_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Mark contribution as completed (called by webhook)
CREATE OR REPLACE FUNCTION crowdfunding.complete_contribution(
    p_contribution_id UUID,
    p_payment_intent_id TEXT,
    p_checkout_session_id TEXT,
    p_payment_method VARCHAR(50)
)
RETURNS VOID AS $$
BEGIN
    UPDATE crowdfunding.contributions
    SET
        status = 'completed',
        stripe_payment_intent_id = p_payment_intent_id,
        stripe_checkout_session_id = p_checkout_session_id,
        payment_method = p_payment_method,
        completed_at = CURRENT_TIMESTAMP
    WHERE id = p_contribution_id;

    -- Note: Triggers will handle updating campaign totals and creating founders wall entry
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

-- Grant execute to service role (used by API)
GRANT EXECUTE ON FUNCTION crowdfunding.get_backer_by_email(public.CITEXT) TO service_role;
GRANT EXECUTE ON FUNCTION crowdfunding.create_checkout_contribution(
    public.CITEXT, VARCHAR(100), VARCHAR(1), UUID, UUID, DECIMAL(10, 2),
    VARCHAR(30), VARCHAR(100), VARCHAR(2), TEXT, BOOLEAN, BOOLEAN
) TO service_role;
GRANT EXECUTE ON FUNCTION crowdfunding.update_contribution_session(UUID, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION crowdfunding.complete_contribution(UUID, TEXT, TEXT, VARCHAR(50)) TO service_role;

-- Grant execute to anon for public-facing checkout
GRANT EXECUTE ON FUNCTION crowdfunding.get_backer_by_email(public.CITEXT) TO anon;

COMMENT ON FUNCTION crowdfunding.get_backer_by_email IS 'Get backer details by email for checkout flow';
COMMENT ON FUNCTION crowdfunding.create_checkout_contribution IS 'Create or update backer and create pending contribution';
COMMENT ON FUNCTION crowdfunding.update_contribution_session IS 'Update contribution with Stripe session ID';
COMMENT ON FUNCTION crowdfunding.complete_contribution IS 'Mark contribution as completed after successful payment';
