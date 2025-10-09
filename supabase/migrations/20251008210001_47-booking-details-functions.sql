-- ============================================================================
-- Event Registration Booking Functions
-- ============================================================================
-- Functions to support Stripe payment integration for event registrations
-- ============================================================================

-- Drop existing function if it has wrong signature
DROP FUNCTION IF EXISTS api.get_booking_details(UUID);

-- Function to get booking details for Stripe checkout
CREATE OR REPLACE FUNCTION api.get_booking_details(p_booking_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSON;
BEGIN
    SELECT json_build_object(
        'booking_id', er.id,
        'event_id', er.event_id,
        'user_id', er.user_id,
        'amount_paid', COALESCE(er.amount_paid,
            CASE
                WHEN p.membership_level = 'guest' THEN e.price_guest
                ELSE e.price_member
            END
        ),
        'event', json_build_object(
            'id', e.id,
            'title', e.title,
            'start_time', e.start_time,
            'end_time', e.end_time,
            'event_type', e.event_type
        ),
        'player', json_build_object(
            'id', p.id,
            'first_name', p.first_name,
            'last_name', p.last_name,
            'email', ua.email
        ),
        'courts', COALESCE(
            (SELECT json_agg(json_build_object(
                'court_id', c.id,
                'court_number', c.court_number,
                'name', c.name
            ))
            FROM events.event_courts ec
            JOIN events.courts c ON c.id = ec.court_id
            WHERE ec.event_id = e.id),
            '[]'::json
        )
    ) INTO v_result
    FROM events.event_registrations er
    JOIN events.events e ON e.id = er.event_id
    LEFT JOIN app_auth.players p ON p.id = er.user_id
    LEFT JOIN app_auth.user_accounts ua ON ua.id = p.account_id
    WHERE er.id = p_booking_id;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION api.get_booking_details IS 'Get event registration details for Stripe payment processing';

-- Function to update booking payment info
CREATE OR REPLACE FUNCTION api.update_booking_payment_info(
    p_booking_id UUID,
    p_payment_reference VARCHAR,
    p_payment_method VARCHAR
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE events.event_registrations
    SET
        payment_reference = p_payment_reference,
        payment_method = p_payment_method,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_booking_id;

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Booking not found');
    END IF;

    RETURN json_build_object('success', true);
END;
$$;

COMMENT ON FUNCTION api.update_booking_payment_info IS 'Update event registration payment information';

-- Grant permissions
GRANT EXECUTE ON FUNCTION api.get_booking_details TO authenticated;
GRANT EXECUTE ON FUNCTION api.get_booking_details TO anon;
GRANT EXECUTE ON FUNCTION api.get_booking_details TO service_role;

GRANT EXECUTE ON FUNCTION api.update_booking_payment_info TO authenticated;
GRANT EXECUTE ON FUNCTION api.update_booking_payment_info TO anon;
GRANT EXECUTE ON FUNCTION api.update_booking_payment_info TO service_role;
