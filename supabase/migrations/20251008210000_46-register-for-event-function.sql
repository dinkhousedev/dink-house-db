-- ============================================================================
-- Deploy api.register_for_event Function
-- ============================================================================
-- This migration creates the register_for_event function in the api schema
-- for player event registration in the web app
-- ============================================================================

-- Create or replace the function
CREATE OR REPLACE FUNCTION api.register_for_event(
    p_event_id UUID,
    p_player_name VARCHAR DEFAULT NULL,
    p_player_email VARCHAR DEFAULT NULL,
    p_player_phone VARCHAR DEFAULT NULL,
    p_skill_level events.skill_level DEFAULT NULL,
    p_dupr_rating NUMERIC DEFAULT NULL,
    p_notes TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_registration_id UUID;
    v_status events.registration_status;
    v_current_registrations INTEGER;
    v_max_capacity INTEGER;
    v_waitlist_capacity INTEGER;
    v_result JSON;
    v_player_id UUID;
    v_player_first_name TEXT;
    v_player_last_name TEXT;
    v_player_email TEXT;
    v_player_membership TEXT;
    v_event_type events.event_type;
    v_price_member DECIMAL(10, 2);
    v_price_guest DECIMAL(10, 2);
    v_amount_to_pay DECIMAL(10, 2);
    v_dupr_min_rating NUMERIC(3, 2);
    v_dupr_max_rating NUMERIC(3, 2);
    v_dupr_open_ended BOOLEAN;
    v_dupr_min_inclusive BOOLEAN;
    v_dupr_max_inclusive BOOLEAN;
    v_required_dupr BOOLEAN := false;
    v_player_dupr_rating NUMERIC(3, 2);
    v_effective_dupr_rating NUMERIC(3, 2);
BEGIN
    -- Get event details
    SELECT
        current_registrations,
        max_capacity,
        waitlist_capacity,
        event_type,
        price_member,
        price_guest,
        dupr_min_rating,
        dupr_max_rating,
        dupr_open_ended,
        dupr_min_inclusive,
        dupr_max_inclusive
    INTO
        v_current_registrations,
        v_max_capacity,
        v_waitlist_capacity,
        v_event_type,
        v_price_member,
        v_price_guest,
        v_dupr_min_rating,
        v_dupr_max_rating,
        v_dupr_open_ended,
        v_dupr_min_inclusive,
        v_dupr_max_inclusive
    FROM events.events
    WHERE id = p_event_id
    AND is_published = true
    AND is_cancelled = false
    AND start_time > NOW();

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Event not found or registration closed';
    END IF;

    v_required_dupr := v_event_type IN ('dupr_open_play', 'dupr_tournament');

    -- Resolve player profile: try by email first (for service role calls), then by auth
    IF p_player_email IS NOT NULL THEN
        SELECT p.id, p.first_name, p.last_name, ua.email, p.dupr_rating, p.membership_level
        INTO v_player_id, v_player_first_name, v_player_last_name, v_player_email, v_player_dupr_rating, v_player_membership
        FROM app_auth.players p
        JOIN app_auth.user_accounts ua ON ua.id = p.account_id
        WHERE ua.email = p_player_email;
    ELSIF auth.uid() IS NOT NULL THEN
        SELECT p.id, p.first_name, p.last_name, ua.email, p.dupr_rating, p.membership_level
        INTO v_player_id, v_player_first_name, v_player_last_name, v_player_email, v_player_dupr_rating, v_player_membership
        FROM app_auth.players p
        JOIN app_auth.user_accounts ua ON ua.id = p.account_id
        WHERE p.account_id = auth.uid();
    END IF;

    -- Calculate amount to pay based on membership level (default to guest price if unknown)
    v_amount_to_pay := CASE
        WHEN v_player_membership IS NULL THEN v_price_guest
        WHEN v_player_membership = 'guest' THEN v_price_guest
        ELSE v_price_member
    END;

    -- Check if already registered with completed payment
    IF EXISTS (
        SELECT 1 FROM events.event_registrations
        WHERE event_id = p_event_id
        AND (
            (v_player_id IS NOT NULL AND user_id = v_player_id)
            OR (p_player_email IS NOT NULL AND player_email = p_player_email)
        )
        AND status IN ('registered', 'waitlisted')
        AND payment_method IS NOT NULL
        AND payment_method NOT IN ('stripe_failed')
    ) THEN
        RAISE EXCEPTION 'Already registered for this event';
    END IF;

    -- Clean up any incomplete registrations (no payment completed)
    DELETE FROM events.event_registrations
    WHERE event_id = p_event_id
    AND (
        (v_player_id IS NOT NULL AND user_id = v_player_id)
        OR (p_player_email IS NOT NULL AND player_email = p_player_email)
    )
    AND (payment_method IS NULL OR payment_method = 'stripe_failed');

    -- Validate DUPR requirements when applicable
    IF v_required_dupr THEN
        v_effective_dupr_rating := COALESCE(v_player_dupr_rating, p_dupr_rating);

        IF v_effective_dupr_rating IS NULL THEN
            RAISE EXCEPTION 'DUPR rating is required to register for this event';
        END IF;

        IF v_dupr_min_rating IS NOT NULL THEN
            IF v_dupr_min_inclusive THEN
                IF v_effective_dupr_rating < v_dupr_min_rating THEN
                    RAISE EXCEPTION 'Player DUPR rating % is below the minimum % for this event', v_effective_dupr_rating, v_dupr_min_rating;
                END IF;
            ELSE
                IF v_effective_dupr_rating <= v_dupr_min_rating THEN
                    RAISE EXCEPTION 'Player DUPR rating % must be greater than % for this event', v_effective_dupr_rating, v_dupr_min_rating;
                END IF;
            END IF;
        END IF;

        IF NOT v_dupr_open_ended AND v_dupr_max_rating IS NOT NULL THEN
            IF v_dupr_max_inclusive THEN
                IF v_effective_dupr_rating > v_dupr_max_rating THEN
                    RAISE EXCEPTION 'Player DUPR rating % exceeds the maximum % for this event', v_effective_dupr_rating, v_dupr_max_rating;
                END IF;
            ELSE
                IF v_effective_dupr_rating >= v_dupr_max_rating THEN
                    RAISE EXCEPTION 'Player DUPR rating % must be less than % for this event', v_effective_dupr_rating, v_dupr_max_rating;
                END IF;
            END IF;
        END IF;
    ELSE
        v_effective_dupr_rating := COALESCE(v_player_dupr_rating, p_dupr_rating);
    END IF;

    -- Determine registration status
    IF v_current_registrations < v_max_capacity THEN
        v_status := 'registered';
    ELSIF v_current_registrations < v_max_capacity + v_waitlist_capacity THEN
        v_status := 'waitlisted';
    ELSE
        RAISE EXCEPTION 'Event is full';
    END IF;

    -- Create registration
    INSERT INTO events.event_registrations (
        event_id,
        user_id,
        player_name,
        player_email,
        player_phone,
        skill_level,
        dupr_rating,
        status,
        amount_paid,
        notes
    ) VALUES (
        p_event_id,
        v_player_id,
        COALESCE(
            p_player_name,
            NULLIF(CONCAT_WS(' ', v_player_first_name, v_player_last_name), '')
        ),
        COALESCE(p_player_email, v_player_email),
        p_player_phone,
        p_skill_level,
        v_effective_dupr_rating,
        v_status,
        v_amount_to_pay,
        p_notes
    ) RETURNING id INTO v_registration_id;

    -- Return result
    SELECT json_build_object(
        'registration_id', v_registration_id,
        'event_id', p_event_id,
        'status', v_status,
        'dupr_rating', v_effective_dupr_rating,
        'position', CASE
            WHEN v_status = 'registered' THEN v_current_registrations + 1
            ELSE v_current_registrations - v_max_capacity + 1
        END
    ) INTO v_result;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION api.register_for_event IS 'Registers a user for an event';

-- Grant permissions
GRANT EXECUTE ON FUNCTION api.register_for_event TO authenticated;
GRANT EXECUTE ON FUNCTION api.register_for_event TO anon;
GRANT EXECUTE ON FUNCTION api.register_for_event TO service_role;
