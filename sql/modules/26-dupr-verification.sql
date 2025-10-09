-- ============================================================================
-- DUPR VERIFICATION MODULE
-- Staff verification workflow for player DUPR ratings
-- ============================================================================

SET search_path TO app_auth, api, public;

-- ============================================================================
-- ADD VERIFICATION COLUMNS TO PLAYERS TABLE
-- ============================================================================

-- Add verification tracking columns
ALTER TABLE app_auth.players
ADD COLUMN IF NOT EXISTS dupr_verified BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS dupr_verified_by UUID REFERENCES app_auth.admin_users(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS dupr_verified_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS dupr_verification_notes TEXT;

-- Create indexes for verification queries
CREATE INDEX IF NOT EXISTS idx_players_dupr_verified ON app_auth.players(dupr_verified);
CREATE INDEX IF NOT EXISTS idx_players_pending_verification
    ON app_auth.players(dupr_rating_updated_at)
    WHERE dupr_rating IS NOT NULL AND dupr_verified = false;

COMMENT ON COLUMN app_auth.players.dupr_verified IS 'Whether staff has verified the DUPR rating';
COMMENT ON COLUMN app_auth.players.dupr_verified_by IS 'Admin user who verified the DUPR rating';
COMMENT ON COLUMN app_auth.players.dupr_verified_at IS 'Timestamp when DUPR was verified';
COMMENT ON COLUMN app_auth.players.dupr_verification_notes IS 'Staff notes about DUPR verification';

-- ============================================================================
-- API FUNCTION: Submit DUPR for Verification (Player Self-Service)
-- ============================================================================

CREATE OR REPLACE FUNCTION api.submit_dupr_for_verification(
    p_player_id UUID,
    p_dupr_rating NUMERIC(3, 2)
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_player RECORD;
BEGIN
    -- Validate DUPR rating range (2.00 to 8.00 is standard DUPR range)
    IF p_dupr_rating < 2.00 OR p_dupr_rating > 8.00 THEN
        RETURN json_build_object(
            'success', false,
            'error', 'DUPR rating must be between 2.00 and 8.00'
        );
    END IF;

    -- Get player record
    SELECT * INTO v_player
    FROM app_auth.players
    WHERE id = p_player_id;

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Player not found');
    END IF;

    -- Update DUPR rating and reset verification status
    UPDATE app_auth.players
    SET dupr_rating = p_dupr_rating,
        dupr_rating_updated_at = CURRENT_TIMESTAMP,
        dupr_verified = false,
        dupr_verified_by = NULL,
        dupr_verified_at = NULL,
        dupr_verification_notes = NULL,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_player_id;

    -- Log activity
    INSERT INTO system.activity_logs (
        user_id,
        action,
        entity_type,
        entity_id,
        details
    ) VALUES (
        p_player_id,
        'dupr_submitted_for_verification',
        'player',
        p_player_id,
        jsonb_build_object(
            'dupr_rating', p_dupr_rating,
            'status', 'pending_verification'
        )
    );

    RETURN json_build_object(
        'success', true,
        'message', 'DUPR rating submitted for staff verification',
        'dupr_rating', p_dupr_rating,
        'status', 'pending_verification'
    );
END;
$$;

COMMENT ON FUNCTION api.submit_dupr_for_verification IS 'Player submits DUPR rating for staff verification';

-- ============================================================================
-- API FUNCTION: Verify Player DUPR (Staff Only)
-- ============================================================================

CREATE OR REPLACE FUNCTION api.verify_player_dupr(
    p_player_id UUID,
    p_admin_id UUID,
    p_verified BOOLEAN,
    p_notes TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_player RECORD;
    v_admin RECORD;
BEGIN
    -- Get player record
    SELECT p.*, ua.email
    INTO v_player
    FROM app_auth.players p
    JOIN app_auth.user_accounts ua ON ua.id = p.account_id
    WHERE p.id = p_player_id;

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Player not found');
    END IF;

    -- Verify admin exists
    SELECT * INTO v_admin
    FROM app_auth.admin_users
    WHERE id = p_admin_id;

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Admin user not found');
    END IF;

    -- Check if player has submitted a DUPR rating
    IF v_player.dupr_rating IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Player has not submitted a DUPR rating'
        );
    END IF;

    IF p_verified THEN
        -- Approve verification
        UPDATE app_auth.players
        SET dupr_verified = true,
            dupr_verified_by = p_admin_id,
            dupr_verified_at = CURRENT_TIMESTAMP,
            dupr_verification_notes = p_notes,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = p_player_id;

        -- Log approval
        INSERT INTO system.activity_logs (
            user_id,
            action,
            entity_type,
            entity_id,
            details
        ) VALUES (
            p_admin_id,
            'dupr_verified',
            'player',
            p_player_id,
            jsonb_build_object(
                'player_email', v_player.email,
                'player_name', v_player.first_name || ' ' || v_player.last_name,
                'dupr_rating', v_player.dupr_rating,
                'verified_by', v_admin.username,
                'notes', p_notes
            )
        );

        RETURN json_build_object(
            'success', true,
            'message', 'Player DUPR rating verified successfully',
            'player_name', v_player.first_name || ' ' || v_player.last_name,
            'dupr_rating', v_player.dupr_rating
        );
    ELSE
        -- Reject verification - reset DUPR to null
        UPDATE app_auth.players
        SET dupr_rating = NULL,
            dupr_rating_updated_at = NULL,
            dupr_verified = false,
            dupr_verified_by = NULL,
            dupr_verified_at = NULL,
            dupr_verification_notes = p_notes,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = p_player_id;

        -- Log rejection
        INSERT INTO system.activity_logs (
            user_id,
            action,
            entity_type,
            entity_id,
            details
        ) VALUES (
            p_admin_id,
            'dupr_rejected',
            'player',
            p_player_id,
            jsonb_build_object(
                'player_email', v_player.email,
                'player_name', v_player.first_name || ' ' || v_player.last_name,
                'previous_dupr_rating', v_player.dupr_rating,
                'rejected_by', v_admin.username,
                'notes', p_notes
            )
        );

        RETURN json_build_object(
            'success', true,
            'message', 'DUPR rating rejected. Player must resubmit.',
            'player_name', v_player.first_name || ' ' || v_player.last_name
        );
    END IF;
END;
$$;

COMMENT ON FUNCTION api.verify_player_dupr IS 'Staff verifies or rejects a player DUPR rating';

-- ============================================================================
-- API FUNCTION: Get Pending DUPR Verifications
-- ============================================================================

CREATE OR REPLACE FUNCTION api.get_pending_dupr_verifications(
    p_limit INT DEFAULT 50,
    p_offset INT DEFAULT 0
)
RETURNS JSON
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
    v_result JSON;
    v_total INT;
BEGIN
    -- Get total count
    SELECT COUNT(*)
    INTO v_total
    FROM app_auth.players p
    WHERE p.dupr_rating IS NOT NULL
      AND p.dupr_verified = false;

    -- Get paginated results
    SELECT json_build_object(
        'success', true,
        'total', v_total,
        'limit', p_limit,
        'offset', p_offset,
        'data', COALESCE(json_agg(
            json_build_object(
                'id', p.id,
                'account_id', ua.id,
                'first_name', p.first_name,
                'last_name', p.last_name,
                'full_name', p.first_name || ' ' || p.last_name,
                'email', ua.email,
                'phone', p.phone,
                'dupr_rating', p.dupr_rating,
                'submitted_at', p.dupr_rating_updated_at,
                'membership_level', p.membership_level,
                'created_at', p.created_at
            ) ORDER BY p.dupr_rating_updated_at ASC
        ), '[]'::json)
    )
    INTO v_result
    FROM app_auth.players p
    JOIN app_auth.user_accounts ua ON ua.id = p.account_id
    WHERE p.dupr_rating IS NOT NULL
      AND p.dupr_verified = false
    LIMIT p_limit
    OFFSET p_offset;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION api.get_pending_dupr_verifications IS 'Get list of players awaiting DUPR verification';

-- ============================================================================
-- API FUNCTION: Get Player Profile with Verification Status
-- ============================================================================

CREATE OR REPLACE FUNCTION api.get_player_profile(
    p_account_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
    v_result JSON;
BEGIN
    SELECT json_build_object(
        'success', true,
        'data', json_build_object(
            'id', p.id,
            'account_id', ua.id,
            'email', ua.email,
            'first_name', p.first_name,
            'last_name', p.last_name,
            'full_name', p.first_name || ' ' || p.last_name,
            'display_name', p.display_name,
            'phone', p.phone,
            'address', p.address,
            'date_of_birth', p.date_of_birth,
            'membership_level', p.membership_level,
            'membership_started_on', p.membership_started_on,
            'membership_expires_on', p.membership_expires_on,
            'skill_level', p.skill_level,
            'dupr_rating', p.dupr_rating,
            'dupr_rating_updated_at', p.dupr_rating_updated_at,
            'dupr_verified', p.dupr_verified,
            'dupr_verified_at', p.dupr_verified_at,
            'dupr_verification_notes', p.dupr_verification_notes,
            'verified_by_name', CASE
                WHEN p.dupr_verified_by IS NOT NULL
                THEN (SELECT au.first_name || ' ' || au.last_name FROM app_auth.admin_users au WHERE au.id = p.dupr_verified_by)
                ELSE NULL
            END,
            'stripe_customer_id', p.stripe_customer_id,
            'is_active', ua.is_active,
            'is_verified', ua.is_verified,
            'last_login', ua.last_login,
            'created_at', p.created_at,
            'updated_at', p.updated_at,
            'profile_status', CASE
                WHEN p.dupr_rating IS NULL THEN 'incomplete'
                WHEN p.dupr_rating IS NOT NULL AND p.dupr_verified = false THEN 'pending_verification'
                WHEN p.dupr_verified = true THEN 'verified'
                ELSE 'unknown'
            END
        )
    )
    INTO v_result
    FROM app_auth.user_accounts ua
    JOIN app_auth.players p ON p.account_id = ua.id
    WHERE ua.id = p_account_id OR p.id = p_account_id;

    IF v_result IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'Player profile not found');
    END IF;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION api.get_player_profile IS 'Get player profile including DUPR verification status';

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

-- Grant execute permissions to authenticated users
GRANT EXECUTE ON FUNCTION api.submit_dupr_for_verification TO authenticated;
GRANT EXECUTE ON FUNCTION api.get_player_profile TO authenticated;

-- Grant execute permissions to service role
GRANT EXECUTE ON FUNCTION api.submit_dupr_for_verification TO service_role;
GRANT EXECUTE ON FUNCTION api.verify_player_dupr TO service_role;
GRANT EXECUTE ON FUNCTION api.get_pending_dupr_verifications TO service_role;
GRANT EXECUTE ON FUNCTION api.get_player_profile TO service_role;

-- Grant to admin authenticated users (additional layer - can be enforced in app)
GRANT EXECUTE ON FUNCTION api.verify_player_dupr TO authenticated;
GRANT EXECUTE ON FUNCTION api.get_pending_dupr_verifications TO authenticated;
