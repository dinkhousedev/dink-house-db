-- ============================================================================
-- Event Registration Management Functions
-- ============================================================================
-- Functions to get player event registrations and handle cancellations/refunds
-- Guest players get refund if cancelled more than 24 hours before event
-- ============================================================================

-- ============================================================================
-- Get Player's Event Registrations
-- ============================================================================

CREATE OR REPLACE FUNCTION api.get_player_event_registrations(
    p_player_id UUID,
    p_include_past BOOLEAN DEFAULT false
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
DECLARE
    v_result JSON;
BEGIN
    SELECT json_agg(
        json_build_object(
            'registration_id', er.id,
            'event', json_build_object(
                'id', e.id,
                'title', e.title,
                'description', e.description,
                'event_type', e.event_type,
                'start_time', e.start_time,
                'end_time', e.end_time,
                'check_in_time', e.check_in_time,
                'is_cancelled', e.is_cancelled
            ),
            'status', er.status,
            'registration_time', er.registration_time,
            'check_in_time', er.check_in_time,
            'amount_paid', er.amount_paid,
            'payment_status', er.payment_status,
            'payment_method', er.payment_method,
            'payment_reference', er.payment_reference,
            'stripe_payment_intent_id', er.stripe_payment_intent_id,
            'stripe_session_id', er.stripe_session_id,
            'special_requests', er.special_requests,
            'notes', er.notes,
            'courts', COALESCE(
                (SELECT json_agg(json_build_object(
                    'court_id', c.id,
                    'court_number', c.court_number,
                    'name', c.name,
                    'environment', c.environment
                ))
                FROM events.event_courts ec
                JOIN events.courts c ON c.id = ec.court_id
                WHERE ec.event_id = e.id),
                '[]'::json
            )
        )
        ORDER BY e.start_time ASC
    ) INTO v_result
    FROM events.event_registrations er
    JOIN events.events e ON e.id = er.event_id
    WHERE er.user_id = p_player_id
    AND er.status != 'cancelled'
    AND (p_include_past OR e.start_time > CURRENT_TIMESTAMP);

    RETURN COALESCE(v_result, '[]'::json);
END;
$$;

COMMENT ON FUNCTION api.get_player_event_registrations
    IS 'Get all event registrations for a player (upcoming by default)';

-- ============================================================================
-- Cancel Event Registration with Refund Logic
-- ============================================================================

CREATE OR REPLACE FUNCTION api.cancel_event_registration(
    p_registration_id UUID,
    p_player_id UUID,
    p_reason TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_registration RECORD;
    v_event RECORD;
    v_player RECORD;
    v_hours_until_event NUMERIC;
    v_refund_eligible BOOLEAN;
    v_refund_amount DECIMAL(10, 2);
    v_refund_message TEXT;
BEGIN
    -- Get registration details
    SELECT
        er.id,
        er.event_id,
        er.user_id,
        er.status,
        er.amount_paid,
        er.payment_status,
        er.stripe_payment_intent_id,
        er.payment_method
    INTO v_registration
    FROM events.event_registrations er
    WHERE er.id = p_registration_id
    AND er.user_id = p_player_id;

    -- Check registration exists and belongs to player
    IF v_registration.id IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Registration not found or does not belong to you'
        );
    END IF;

    -- Check if already cancelled
    IF v_registration.status = 'cancelled' THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Registration is already cancelled'
        );
    END IF;

    -- Get event details
    SELECT
        e.id,
        e.title,
        e.start_time,
        e.is_cancelled
    INTO v_event
    FROM events.events e
    WHERE e.id = v_registration.event_id;

    -- Check if event has already started or passed
    IF v_event.start_time < CURRENT_TIMESTAMP THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Cannot cancel registration for an event that has already started'
        );
    END IF;

    -- Get player info
    SELECT
        p.id,
        p.membership_level,
        p.first_name,
        p.last_name
    INTO v_player
    FROM app_auth.players p
    WHERE p.id = p_player_id;

    -- Calculate hours until event
    v_hours_until_event := EXTRACT(EPOCH FROM (v_event.start_time - CURRENT_TIMESTAMP)) / 3600;

    -- Determine refund eligibility
    -- Guest players: full refund if > 24 hours, no refund if <= 24 hours
    -- Members: always free (no refund needed)
    v_refund_amount := 0;
    v_refund_eligible := false;

    IF v_player.membership_level = 'guest' AND v_registration.amount_paid > 0 AND v_registration.payment_status = 'completed' THEN
        IF v_hours_until_event > 24 THEN
            v_refund_eligible := true;
            v_refund_amount := v_registration.amount_paid;
            v_refund_message := 'Full refund will be processed (cancelled more than 24 hours in advance)';
        ELSE
            v_refund_eligible := false;
            v_refund_message := 'No refund available (cancellation within 24 hours of event)';
        END IF;
    ELSE
        v_refund_message := 'No payment to refund';
    END IF;

    -- Update registration to cancelled
    UPDATE events.event_registrations
    SET
        status = 'cancelled'::events.registration_status,
        notes = COALESCE(notes, '') || E'\nCancelled: ' || COALESCE(p_reason, 'Player requested cancellation') ||
                E'\nCancellation time: ' || CURRENT_TIMESTAMP::TEXT ||
                E'\nHours before event: ' || ROUND(v_hours_until_event, 1)::TEXT ||
                CASE WHEN v_refund_eligible THEN E'\nRefund amount: $' || v_refund_amount::TEXT ELSE '' END,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_registration_id;

    -- Return result
    RETURN json_build_object(
        'success', true,
        'registration_id', p_registration_id,
        'event_title', v_event.title,
        'cancelled_at', CURRENT_TIMESTAMP,
        'hours_until_event', ROUND(v_hours_until_event, 1),
        'refund_eligible', v_refund_eligible,
        'refund_amount', v_refund_amount,
        'refund_message', v_refund_message,
        'stripe_payment_intent_id', v_registration.stripe_payment_intent_id,
        'requires_stripe_refund', v_refund_eligible AND v_registration.stripe_payment_intent_id IS NOT NULL
    );
END;
$$;

COMMENT ON FUNCTION api.cancel_event_registration
    IS 'Cancel event registration with 24-hour refund policy for guests';

-- ============================================================================
-- Grant Permissions
-- ============================================================================

GRANT EXECUTE ON FUNCTION api.get_player_event_registrations TO authenticated;
GRANT EXECUTE ON FUNCTION api.get_player_event_registrations TO service_role;

GRANT EXECUTE ON FUNCTION api.cancel_event_registration TO authenticated;
GRANT EXECUTE ON FUNCTION api.cancel_event_registration TO service_role;
