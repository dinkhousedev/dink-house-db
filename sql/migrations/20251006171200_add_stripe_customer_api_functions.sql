-- ============================================================================
-- STRIPE CUSTOMER API FUNCTIONS
-- Functions for Stripe Edge Function to manage customer IDs
-- ============================================================================

SET search_path TO api, app_auth, public;

-- ============================================================================
-- FUNCTION: Get player stripe customer info (for Edge Functions)
-- ============================================================================

CREATE OR REPLACE FUNCTION api.get_player_stripe_info(
    p_player_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSON;
BEGIN
    SELECT json_build_object(
        'success', true,
        'data', json_build_object(
            'id', p.id,
            'account_id', p.account_id,
            'stripe_customer_id', p.stripe_customer_id
        )
    )
    INTO v_result
    FROM app_auth.players p
    WHERE p.id = p_player_id;

    IF v_result IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Player not found'
        );
    END IF;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION api.get_player_stripe_info IS 'Get player Stripe customer info for Edge Functions (service role only)';

-- ============================================================================
-- FUNCTION: Update player stripe customer ID (for Edge Functions)
-- ============================================================================

CREATE OR REPLACE FUNCTION api.update_player_stripe_customer(
    p_player_id UUID,
    p_stripe_customer_id TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Update the player record
    UPDATE app_auth.players
    SET stripe_customer_id = p_stripe_customer_id,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_player_id;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Player not found'
        );
    END IF;

    RETURN json_build_object(
        'success', true,
        'message', 'Stripe customer ID updated successfully'
    );
END;
$$;

COMMENT ON FUNCTION api.update_player_stripe_customer IS 'Update player Stripe customer ID from Edge Functions (service role only)';

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

-- Grant execute to service role (used by Edge Functions)
GRANT EXECUTE ON FUNCTION api.get_player_stripe_info TO service_role;
GRANT EXECUTE ON FUNCTION api.update_player_stripe_customer TO service_role;

-- Revoke from authenticated users (Edge Function only)
REVOKE EXECUTE ON FUNCTION api.get_player_stripe_info FROM authenticated;
REVOKE EXECUTE ON FUNCTION api.update_player_stripe_customer FROM authenticated;
