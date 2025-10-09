-- ============================================================================
-- EVENT CHECK-IN FUNCTION MODULE
-- QR code-based player check-in functionality
-- ============================================================================

-- ============================================================================
-- CHECK IN PLAYER TO EVENT
-- Marks a player as checked in for an event
-- ============================================================================

CREATE OR REPLACE FUNCTION api.check_in_player(
    p_event_id UUID,
    p_player_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_registration_id UUID;
    v_check_in_time TIMESTAMPTZ;
    v_player_name TEXT;
    v_dupr_rating NUMERIC(3, 2);
    v_event_title TEXT;
    v_result JSON;
BEGIN
    -- Check if user is staff or the player themselves
    IF NOT events.is_staff() AND auth.uid() != (
        SELECT account_id FROM app_auth.players WHERE id = p_player_id
    ) THEN
        RAISE EXCEPTION 'Unauthorized: Only staff or the player can check in';
    END IF;

    -- Verify event exists and hasn't ended
    SELECT title INTO v_event_title
    FROM events.events
    WHERE id = p_event_id
    AND is_published = true
    AND is_cancelled = false;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Event not found or is not available';
    END IF;

    -- Find the registration
    SELECT id, player_name, dupr_rating
    INTO v_registration_id, v_player_name, v_dupr_rating
    FROM events.event_registrations
    WHERE event_id = p_event_id
    AND user_id = p_player_id
    AND status = 'registered';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Player is not registered for this event';
    END IF;

    -- Check if already checked in
    IF EXISTS (
        SELECT 1 FROM events.event_registrations
        WHERE id = v_registration_id
        AND check_in_time IS NOT NULL
    ) THEN
        SELECT check_in_time INTO v_check_in_time
        FROM events.event_registrations
        WHERE id = v_registration_id;

        RETURN json_build_object(
            'success', true,
            'already_checked_in', true,
            'registration_id', v_registration_id,
            'player_name', v_player_name,
            'check_in_time', v_check_in_time,
            'message', 'Player already checked in at ' || to_char(v_check_in_time AT TIME ZONE 'America/New_York', 'HH12:MI AM')
        );
    END IF;

    -- Update check-in time
    UPDATE events.event_registrations
    SET
        check_in_time = NOW(),
        updated_at = NOW()
    WHERE id = v_registration_id
    RETURNING check_in_time INTO v_check_in_time;

    -- Return success result
    SELECT json_build_object(
        'success', true,
        'already_checked_in', false,
        'registration_id', v_registration_id,
        'event_id', p_event_id,
        'event_title', v_event_title,
        'player_id', p_player_id,
        'player_name', v_player_name,
        'dupr_rating', v_dupr_rating,
        'check_in_time', v_check_in_time,
        'message', 'Successfully checked in'
    ) INTO v_result;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION api.check_in_player IS 'Checks in a player to an event via QR code scan';

-- ============================================================================
-- GET EVENT CHECK-IN STATUS
-- Returns real-time check-in status for an event
-- ============================================================================

CREATE OR REPLACE FUNCTION api.get_event_checkin_status(
    p_event_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_result JSON;
BEGIN
    SELECT json_build_object(
        'event_id', e.id,
        'event_title', e.title,
        'event_type', e.event_type,
        'start_time', e.start_time,
        'end_time', e.end_time,
        'total_registered', COUNT(er.id),
        'total_checked_in', COUNT(er.id) FILTER (WHERE er.check_in_time IS NOT NULL),
        'registrations', json_agg(
            json_build_object(
                'registration_id', er.id,
                'player_id', er.user_id,
                'player_name', COALESCE(
                    er.player_name,
                    p.first_name || ' ' || p.last_name
                ),
                'dupr_rating', COALESCE(er.dupr_rating, p.dupr_rating),
                'skill_level', er.skill_level,
                'registration_time', er.registration_time,
                'check_in_time', er.check_in_time,
                'checked_in', er.check_in_time IS NOT NULL
            ) ORDER BY
                CASE WHEN er.check_in_time IS NOT NULL THEN 0 ELSE 1 END,
                er.check_in_time DESC NULLS LAST,
                er.registration_time ASC
        )
    ) INTO v_result
    FROM events.events e
    LEFT JOIN events.event_registrations er ON e.id = er.event_id AND er.status = 'registered'
    LEFT JOIN app_auth.players p ON er.user_id = p.id
    WHERE e.id = p_event_id
    GROUP BY e.id;

    RETURN COALESCE(v_result, json_build_object('error', 'Event not found'));
END;
$$;

COMMENT ON FUNCTION api.get_event_checkin_status IS 'Returns real-time check-in status for an event';

-- ============================================================================
-- GRANT EXECUTE PERMISSIONS
-- ============================================================================

GRANT EXECUTE ON FUNCTION api.check_in_player TO authenticated;
GRANT EXECUTE ON FUNCTION api.get_event_checkin_status TO authenticated;
