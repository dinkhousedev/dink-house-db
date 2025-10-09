-- ============================================================================
-- OPEN PLAY REGISTRATIONS MODULE
-- Player check-in and registration system for open play sessions
-- Members play FREE, guests pay per session
-- ============================================================================

SET search_path TO events, app_auth, public;

-- ============================================================================
-- OPEN PLAY REGISTRATIONS TABLE
-- Track player check-ins for open play sessions
-- ============================================================================

CREATE TABLE events.open_play_registrations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Session reference
    instance_id UUID NOT NULL REFERENCES events.open_play_instances(id) ON DELETE CASCADE,
    schedule_block_id UUID NOT NULL REFERENCES events.open_play_schedule_blocks(id) ON DELETE CASCADE,

    -- Player reference
    player_id UUID NOT NULL REFERENCES app_auth.players(id) ON DELETE CASCADE,

    -- Court/Skill level allocation
    court_id UUID REFERENCES events.courts(id) ON DELETE SET NULL,
    skill_level_label VARCHAR(100), -- Which skill bracket they're in
    assigned_skill_min NUMERIC(3, 2),
    assigned_skill_max NUMERIC(3, 2),

    -- Check-in details
    check_in_time TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    checked_out_at TIMESTAMPTZ,

    -- Player info snapshot (for historical reference)
    player_name VARCHAR(200) NOT NULL,
    player_email VARCHAR(255),
    player_phone VARCHAR(50),
    membership_level app_auth.membership_level NOT NULL,
    player_skill_level events.skill_level,
    player_dupr_rating NUMERIC(3, 2),

    -- Payment (guests only)
    fee_amount DECIMAL(10, 2) DEFAULT 0.00,
    fee_type VARCHAR(50) DEFAULT 'open_play_session', -- 'open_play_session', 'waived_member'
    payment_status VARCHAR(50) DEFAULT 'completed', -- 'pending', 'completed', 'waived', 'refunded'
    fee_id UUID REFERENCES app_auth.player_fees(id) ON DELETE SET NULL,
    waived_reason TEXT, -- For comped sessions

    -- Session details
    is_cancelled BOOLEAN DEFAULT false,
    cancelled_at TIMESTAMPTZ,
    cancellation_reason TEXT,
    refund_issued BOOLEAN DEFAULT false,
    refund_amount DECIMAL(10, 2),

    -- Notes
    notes TEXT,
    special_requests TEXT,

    -- Metadata
    registered_by UUID REFERENCES app_auth.admin_users(id), -- NULL if self-registration
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
    CONSTRAINT unique_instance_player UNIQUE(instance_id, player_id),
    CONSTRAINT valid_checkout CHECK (checked_out_at IS NULL OR checked_out_at >= check_in_time),
    CONSTRAINT valid_cancellation CHECK (
        (is_cancelled = false AND cancelled_at IS NULL) OR
        (is_cancelled = true AND cancelled_at IS NOT NULL)
    ),
    CONSTRAINT valid_refund CHECK (
        (refund_issued = false AND refund_amount IS NULL) OR
        (refund_issued = true AND refund_amount IS NOT NULL AND refund_amount >= 0)
    )
);

COMMENT ON TABLE events.open_play_registrations IS 'Player check-ins for open play sessions - members free, guests pay';

-- Create indexes
CREATE INDEX idx_open_play_reg_instance ON events.open_play_registrations(instance_id);
CREATE INDEX idx_open_play_reg_player ON events.open_play_registrations(player_id);
CREATE INDEX idx_open_play_reg_schedule_block ON events.open_play_registrations(schedule_block_id);
CREATE INDEX idx_open_play_reg_court ON events.open_play_registrations(court_id);
CREATE INDEX idx_open_play_reg_skill ON events.open_play_registrations(skill_level_label);
CREATE INDEX idx_open_play_reg_checkin ON events.open_play_registrations(check_in_time);
CREATE INDEX idx_open_play_reg_cancelled ON events.open_play_registrations(is_cancelled);
CREATE INDEX idx_open_play_reg_payment ON events.open_play_registrations(payment_status);

-- Composite index for attendance queries
CREATE INDEX idx_open_play_reg_instance_active ON events.open_play_registrations(instance_id, is_cancelled)
    WHERE is_cancelled = false;

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Calculate fee for a player based on membership and time
CREATE OR REPLACE FUNCTION events.calculate_open_play_fee(
    p_player_id UUID,
    p_schedule_block_id UUID
)
RETURNS TABLE (
    fee_amount DECIMAL,
    fee_type VARCHAR,
    payment_required BOOLEAN
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_membership_level app_auth.membership_level;
    v_price_member DECIMAL(10, 2);
    v_price_guest DECIMAL(10, 2);
BEGIN
    -- Get player's membership level
    SELECT membership_level INTO v_membership_level
    FROM app_auth.players
    WHERE id = p_player_id;

    IF v_membership_level IS NULL THEN
        RAISE EXCEPTION 'Player not found';
    END IF;

    -- Get pricing from schedule block
    SELECT price_member, price_guest INTO v_price_member, v_price_guest
    FROM events.open_play_schedule_blocks
    WHERE id = p_schedule_block_id;

    -- Members play for FREE (basic, premium, vip)
    IF v_membership_level IN ('basic', 'premium', 'vip') THEN
        RETURN QUERY SELECT
            0.00::DECIMAL(10, 2) as fee_amount,
            'waived_member'::VARCHAR as fee_type,
            false as payment_required;
    -- Guests pay per session
    ELSIF v_membership_level = 'guest' THEN
        RETURN QUERY SELECT
            COALESCE(v_price_guest, 15.00)::DECIMAL(10, 2) as fee_amount,
            'open_play_session'::VARCHAR as fee_type,
            true as payment_required;
    ELSE
        RAISE EXCEPTION 'Unknown membership level: %', v_membership_level;
    END IF;
END;
$$;

COMMENT ON FUNCTION events.calculate_open_play_fee IS 'Calculate fee for open play session based on membership level';

-- Get current capacity for a skill level in an instance
CREATE OR REPLACE FUNCTION events.get_skill_level_capacity(
    p_instance_id UUID,
    p_skill_level_label VARCHAR
)
RETURNS TABLE (
    skill_label VARCHAR,
    total_capacity INTEGER,
    current_registrations INTEGER,
    available_spots INTEGER,
    courts_allocated INTEGER
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_schedule_block_id UUID;
    v_max_per_court INTEGER;
    v_court_count INTEGER;
    v_total_capacity INTEGER;
    v_current_count INTEGER;
BEGIN
    -- Get schedule block and max players per court
    SELECT schedule_block_id INTO v_schedule_block_id
    FROM events.open_play_instances
    WHERE id = p_instance_id;

    SELECT max_players_per_court INTO v_max_per_court
    FROM events.open_play_schedule_blocks
    WHERE id = v_schedule_block_id;

    v_max_per_court := COALESCE(v_max_per_court, 8);

    -- Count courts allocated to this skill level
    SELECT COUNT(*) INTO v_court_count
    FROM events.open_play_court_allocations
    WHERE schedule_block_id = v_schedule_block_id
    AND skill_level_label = p_skill_level_label;

    -- Calculate total capacity
    v_total_capacity := v_court_count * v_max_per_court;

    -- Count current registrations
    SELECT COUNT(*) INTO v_current_count
    FROM events.open_play_registrations
    WHERE instance_id = p_instance_id
    AND skill_level_label = p_skill_level_label
    AND is_cancelled = false;

    RETURN QUERY SELECT
        p_skill_level_label,
        v_total_capacity,
        v_current_count::INTEGER,
        (v_total_capacity - v_current_count)::INTEGER as available_spots,
        v_court_count::INTEGER;
END;
$$;

COMMENT ON FUNCTION events.get_skill_level_capacity IS 'Get current capacity and availability for a skill level';

-- ============================================================================
-- API FUNCTIONS
-- ============================================================================

-- Register/Check-in player for open play session
CREATE OR REPLACE FUNCTION api.register_for_open_play(
    p_instance_id UUID,
    p_player_id UUID,
    p_skill_level_label VARCHAR,
    p_notes TEXT DEFAULT NULL,
    p_payment_intent_id TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_schedule_block_id UUID;
    v_instance_date DATE;
    v_is_cancelled BOOLEAN;
    v_player RECORD;
    v_fee RECORD;
    v_capacity RECORD;
    v_registration_id UUID;
    v_fee_id UUID;
    v_court_id UUID;
    v_skill_min NUMERIC(3, 2);
    v_skill_max NUMERIC(3, 2);
BEGIN
    -- Verify instance exists and is not cancelled
    SELECT schedule_block_id, instance_date, is_cancelled
    INTO v_schedule_block_id, v_instance_date, v_is_cancelled
    FROM events.open_play_instances
    WHERE id = p_instance_id;

    IF v_schedule_block_id IS NULL THEN
        RAISE EXCEPTION 'Open play instance not found';
    END IF;

    IF v_is_cancelled THEN
        RAISE EXCEPTION 'This open play session has been cancelled';
    END IF;

    -- Get player information
    SELECT
        p.id,
        p.first_name || ' ' || p.last_name as full_name,
        p.email,
        p.phone,
        p.membership_level,
        p.skill_level,
        p.dupr_rating
    INTO v_player
    FROM app_auth.players p
    WHERE p.id = p_player_id;

    IF v_player.id IS NULL THEN
        RAISE EXCEPTION 'Player not found';
    END IF;

    -- Check if already registered
    IF EXISTS (
        SELECT 1 FROM events.open_play_registrations
        WHERE instance_id = p_instance_id
        AND player_id = p_player_id
        AND is_cancelled = false
    ) THEN
        RAISE EXCEPTION 'Player is already registered for this session';
    END IF;

    -- Calculate fee
    SELECT * INTO v_fee
    FROM events.calculate_open_play_fee(p_player_id, v_schedule_block_id);

    -- Check capacity for this skill level
    SELECT * INTO v_capacity
    FROM events.get_skill_level_capacity(p_instance_id, p_skill_level_label);

    IF v_capacity.available_spots <= 0 THEN
        RAISE EXCEPTION 'No available spots for skill level: %', p_skill_level_label;
    END IF;

    -- Get court allocation details
    SELECT court_id, skill_level_min, skill_level_max
    INTO v_court_id, v_skill_min, v_skill_max
    FROM events.open_play_court_allocations
    WHERE schedule_block_id = v_schedule_block_id
    AND skill_level_label = p_skill_level_label
    LIMIT 1;

    -- Create fee record for guests if payment required
    IF v_fee.payment_required THEN
        IF p_payment_intent_id IS NULL THEN
            RAISE EXCEPTION 'Payment required for guest players';
        END IF;

        INSERT INTO app_auth.player_fees (
            player_id,
            fee_type,
            amount,
            stripe_payment_intent_id,
            payment_status,
            paid_at,
            notes
        ) VALUES (
            p_player_id,
            'open_play_session',
            v_fee.fee_amount,
            p_payment_intent_id,
            'paid',
            CURRENT_TIMESTAMP,
            'Open play session: ' || v_instance_date || ' - ' || p_skill_level_label
        )
        RETURNING id INTO v_fee_id;
    END IF;

    -- Create registration
    INSERT INTO events.open_play_registrations (
        instance_id,
        schedule_block_id,
        player_id,
        court_id,
        skill_level_label,
        assigned_skill_min,
        assigned_skill_max,
        player_name,
        player_email,
        player_phone,
        membership_level,
        player_skill_level,
        player_dupr_rating,
        fee_amount,
        fee_type,
        payment_status,
        fee_id,
        waived_reason,
        notes
    ) VALUES (
        p_instance_id,
        v_schedule_block_id,
        p_player_id,
        v_court_id,
        p_skill_level_label,
        v_skill_min,
        v_skill_max,
        v_player.full_name,
        v_player.email,
        v_player.phone,
        v_player.membership_level,
        v_player.skill_level,
        v_player.dupr_rating,
        v_fee.fee_amount,
        v_fee.fee_type,
        CASE WHEN v_fee.payment_required THEN 'completed' ELSE 'waived' END,
        v_fee_id,
        CASE WHEN NOT v_fee.payment_required THEN 'Member - free access' ELSE NULL END,
        p_notes
    )
    RETURNING id INTO v_registration_id;

    -- Return success response
    RETURN json_build_object(
        'success', true,
        'registration_id', v_registration_id,
        'player_name', v_player.full_name,
        'skill_level', p_skill_level_label,
        'fee_amount', v_fee.fee_amount,
        'payment_required', v_fee.payment_required,
        'check_in_time', CURRENT_TIMESTAMP,
        'capacity', json_build_object(
            'total', v_capacity.total_capacity,
            'current', v_capacity.current_registrations + 1,
            'available', v_capacity.available_spots - 1
        )
    );
END;
$$;

COMMENT ON FUNCTION api.register_for_open_play IS 'Register player for open play session - members free, guests pay';

-- Cancel open play registration
CREATE OR REPLACE FUNCTION api.cancel_open_play_registration(
    p_registration_id UUID,
    p_reason TEXT DEFAULT NULL,
    p_issue_refund BOOLEAN DEFAULT false
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_registration RECORD;
    v_refund_amount DECIMAL(10, 2);
BEGIN
    -- Get registration details
    SELECT
        opr.id,
        opr.player_id,
        opr.instance_id,
        opr.fee_amount,
        opr.fee_id,
        opr.payment_status,
        opr.is_cancelled,
        opi.start_time
    INTO v_registration
    FROM events.open_play_registrations opr
    JOIN events.open_play_instances opi ON opi.id = opr.instance_id
    WHERE opr.id = p_registration_id;

    IF v_registration.id IS NULL THEN
        RAISE EXCEPTION 'Registration not found';
    END IF;

    IF v_registration.is_cancelled THEN
        RAISE EXCEPTION 'Registration is already cancelled';
    END IF;

    -- Check if session has already started
    IF v_registration.start_time < CURRENT_TIMESTAMP THEN
        RAISE EXCEPTION 'Cannot cancel registration for a session that has already started';
    END IF;

    -- Calculate refund if applicable
    v_refund_amount := 0.00;
    IF p_issue_refund AND v_registration.fee_amount > 0 THEN
        -- Full refund if cancelled more than 24 hours before
        IF v_registration.start_time > CURRENT_TIMESTAMP + INTERVAL '24 hours' THEN
            v_refund_amount := v_registration.fee_amount;
        -- 50% refund if cancelled within 24 hours
        ELSIF v_registration.start_time > CURRENT_TIMESTAMP THEN
            v_refund_amount := v_registration.fee_amount * 0.5;
        END IF;
    END IF;

    -- Update registration
    UPDATE events.open_play_registrations
    SET
        is_cancelled = true,
        cancelled_at = CURRENT_TIMESTAMP,
        cancellation_reason = p_reason,
        refund_issued = (v_refund_amount > 0),
        refund_amount = CASE WHEN v_refund_amount > 0 THEN v_refund_amount ELSE NULL END,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_registration_id;

    -- Update fee record if refund issued
    IF v_refund_amount > 0 AND v_registration.fee_id IS NOT NULL THEN
        UPDATE app_auth.player_fees
        SET
            payment_status = 'refunded',
            notes = COALESCE(notes, '') || E'\nRefund issued: $' || v_refund_amount::TEXT,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = v_registration.fee_id;
    END IF;

    RETURN json_build_object(
        'success', true,
        'registration_id', p_registration_id,
        'cancelled_at', CURRENT_TIMESTAMP,
        'refund_issued', (v_refund_amount > 0),
        'refund_amount', v_refund_amount
    );
END;
$$;

COMMENT ON FUNCTION api.cancel_open_play_registration IS 'Cancel open play registration with optional refund';

-- Get registrations for an open play instance
CREATE OR REPLACE FUNCTION api.get_open_play_registrations(
    p_instance_id UUID,
    p_include_cancelled BOOLEAN DEFAULT false
)
RETURNS JSON
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_result JSON;
BEGIN
    WITH registration_data AS (
        SELECT
            opr.id,
            opr.player_id,
            opr.player_name,
            opr.membership_level::TEXT,
            opr.skill_level_label,
            opr.player_skill_level::TEXT,
            opr.player_dupr_rating,
            opr.check_in_time,
            opr.checked_out_at,
            opr.fee_amount,
            opr.payment_status,
            opr.is_cancelled,
            opr.cancelled_at,
            c.court_number,
            c.name as court_name
        FROM events.open_play_registrations opr
        LEFT JOIN events.courts c ON c.id = opr.court_id
        WHERE opr.instance_id = p_instance_id
        AND (p_include_cancelled OR opr.is_cancelled = false)
        ORDER BY opr.skill_level_label, opr.check_in_time
    ),
    capacity_data AS (
        SELECT
            opca.skill_level_label,
            COUNT(*) as court_count,
            opsb.max_players_per_court
        FROM events.open_play_instances opi
        JOIN events.open_play_court_allocations opca ON opca.schedule_block_id = opi.schedule_block_id
        JOIN events.open_play_schedule_blocks opsb ON opsb.id = opi.schedule_block_id
        WHERE opi.id = p_instance_id
        GROUP BY opca.skill_level_label, opsb.max_players_per_court
    )
    SELECT json_build_object(
        'instance_id', p_instance_id,
        'total_registrations', (SELECT COUNT(*) FROM registration_data WHERE NOT is_cancelled),
        'registrations', (
            SELECT json_agg(
                json_build_object(
                    'id', id,
                    'player_id', player_id,
                    'player_name', player_name,
                    'membership_level', membership_level,
                    'skill_level_label', skill_level_label,
                    'player_skill_level', player_skill_level,
                    'player_dupr_rating', player_dupr_rating,
                    'check_in_time', check_in_time,
                    'checked_out_at', checked_out_at,
                    'fee_amount', fee_amount,
                    'payment_status', payment_status,
                    'is_cancelled', is_cancelled,
                    'cancelled_at', cancelled_at,
                    'court_number', court_number,
                    'court_name', court_name
                )
            )
            FROM registration_data
        ),
        'capacity_by_skill', (
            SELECT json_agg(
                json_build_object(
                    'skill_level', cd.skill_level_label,
                    'total_capacity', cd.court_count * cd.max_players_per_court,
                    'current_count', (
                        SELECT COUNT(*) FROM registration_data rd
                        WHERE rd.skill_level_label = cd.skill_level_label
                        AND NOT rd.is_cancelled
                    ),
                    'available_spots', (cd.court_count * cd.max_players_per_court) - (
                        SELECT COUNT(*) FROM registration_data rd
                        WHERE rd.skill_level_label = cd.skill_level_label
                        AND NOT rd.is_cancelled
                    ),
                    'courts_allocated', cd.court_count
                )
            )
            FROM capacity_data cd
        )
    ) INTO v_result;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION api.get_open_play_registrations IS 'Get all registrations for an open play instance';

-- Get player's open play history
CREATE OR REPLACE FUNCTION api.get_player_open_play_history(
    p_player_id UUID,
    p_limit INTEGER DEFAULT 20,
    p_offset INTEGER DEFAULT 0
)
RETURNS JSON
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_result JSON;
BEGIN
    SELECT json_build_object(
        'player_id', p_player_id,
        'total_sessions', (
            SELECT COUNT(*)
            FROM events.open_play_registrations
            WHERE player_id = p_player_id
            AND is_cancelled = false
        ),
        'sessions', (
            SELECT json_agg(
                json_build_object(
                    'registration_id', opr.id,
                    'session_date', opi.instance_date,
                    'start_time', opi.start_time,
                    'end_time', opi.end_time,
                    'session_name', opsb.name,
                    'skill_level', opr.skill_level_label,
                    'check_in_time', opr.check_in_time,
                    'checked_out_at', opr.checked_out_at,
                    'fee_amount', opr.fee_amount,
                    'payment_status', opr.payment_status,
                    'court_number', c.court_number,
                    'is_cancelled', opr.is_cancelled
                ) ORDER BY opi.instance_date DESC, opi.start_time DESC
            )
            FROM events.open_play_registrations opr
            JOIN events.open_play_instances opi ON opi.id = opr.instance_id
            JOIN events.open_play_schedule_blocks opsb ON opsb.id = opr.schedule_block_id
            LEFT JOIN events.courts c ON c.id = opr.court_id
            WHERE opr.player_id = p_player_id
            LIMIT p_limit
            OFFSET p_offset
        )
    ) INTO v_result;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION api.get_player_open_play_history IS 'Get player open play session history';

-- Get upcoming open play schedule with availability
CREATE OR REPLACE FUNCTION api.get_upcoming_open_play_schedule(
    p_start_date DATE DEFAULT CURRENT_DATE,
    p_end_date DATE DEFAULT NULL,
    p_days_ahead INTEGER DEFAULT 7
)
RETURNS JSON
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_end_date DATE;
    v_result JSON;
BEGIN
    v_end_date := COALESCE(p_end_date, p_start_date + p_days_ahead);

    WITH instance_data AS (
        SELECT
            opi.id as instance_id,
            opi.instance_date,
            opi.start_time,
            opi.end_time,
            opi.is_cancelled,
            opsb.id as block_id,
            opsb.name,
            opsb.description,
            opsb.session_type::TEXT,
            opsb.special_event_name,
            opsb.price_member,
            opsb.price_guest,
            opsb.max_players_per_court,
            opsb.special_instructions
        FROM events.open_play_instances opi
        JOIN events.open_play_schedule_blocks opsb ON opsb.id = opi.schedule_block_id
        WHERE opi.instance_date >= p_start_date
        AND opi.instance_date <= v_end_date
        AND opsb.is_active = true
        ORDER BY opi.instance_date, opi.start_time
    )
    SELECT json_build_object(
        'start_date', p_start_date,
        'end_date', v_end_date,
        'sessions', (
            SELECT json_agg(
                json_build_object(
                    'instance_id', id.instance_id,
                    'date', id.instance_date,
                    'start_time', id.start_time,
                    'end_time', id.end_time,
                    'name', id.name,
                    'description', id.description,
                    'session_type', id.session_type,
                    'special_event_name', id.special_event_name,
                    'price_member', id.price_member,
                    'price_guest', id.price_guest,
                    'is_cancelled', id.is_cancelled,
                    'special_instructions', id.special_instructions,
                    'capacity_by_skill', (
                        SELECT json_agg(
                            json_build_object(
                                'skill_level', opca.skill_level_label,
                                'skill_min', opca.skill_level_min,
                                'skill_max', opca.skill_level_max,
                                'court_count', COUNT(*),
                                'total_capacity', COUNT(*) * id.max_players_per_court,
                                'current_registrations', (
                                    SELECT COUNT(*)
                                    FROM events.open_play_registrations opr
                                    WHERE opr.instance_id = id.instance_id
                                    AND opr.skill_level_label = opca.skill_level_label
                                    AND opr.is_cancelled = false
                                ),
                                'available_spots', (COUNT(*) * id.max_players_per_court) - (
                                    SELECT COUNT(*)
                                    FROM events.open_play_registrations opr
                                    WHERE opr.instance_id = id.instance_id
                                    AND opr.skill_level_label = opca.skill_level_label
                                    AND opr.is_cancelled = false
                                )
                            )
                        )
                        FROM events.open_play_court_allocations opca
                        WHERE opca.schedule_block_id = id.block_id
                        GROUP BY opca.skill_level_label, opca.skill_level_min, opca.skill_level_max
                    )
                ) ORDER BY id.instance_date, id.start_time
            )
            FROM instance_data id
        )
    ) INTO v_result;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION api.get_upcoming_open_play_schedule IS 'Get upcoming open play schedule with availability';

-- ============================================================================
-- ROW LEVEL SECURITY POLICIES
-- ============================================================================

-- Enable RLS on registrations table
ALTER TABLE events.open_play_registrations ENABLE ROW LEVEL SECURITY;

-- Policy: Staff can view all registrations
CREATE POLICY open_play_reg_staff_all ON events.open_play_registrations
    FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM app_auth.admin_users au
            WHERE au.id = auth.uid()
        )
    );

-- Policy: Players can view their own registrations
CREATE POLICY open_play_reg_player_own ON events.open_play_registrations
    FOR SELECT
    USING (
        player_id IN (
            SELECT id FROM app_auth.players
            WHERE account_id = auth.uid()
        )
    );

-- Policy: Authenticated users can insert their own registrations
CREATE POLICY open_play_reg_player_insert ON events.open_play_registrations
    FOR INSERT
    WITH CHECK (
        player_id IN (
            SELECT id FROM app_auth.players
            WHERE account_id = auth.uid()
        )
    );

-- Policy: Players can update (cancel) their own registrations
CREATE POLICY open_play_reg_player_update ON events.open_play_registrations
    FOR UPDATE
    USING (
        player_id IN (
            SELECT id FROM app_auth.players
            WHERE account_id = auth.uid()
        )
    );

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Update timestamp trigger
CREATE TRIGGER update_open_play_registrations_updated_at
    BEFORE UPDATE ON events.open_play_registrations
    FOR EACH ROW EXECUTE FUNCTION events.update_updated_at();

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

-- Grant SELECT to authenticated users
GRANT SELECT ON events.open_play_registrations TO authenticated;
GRANT INSERT, UPDATE ON events.open_play_registrations TO authenticated;

-- Grant all to service_role
GRANT ALL ON events.open_play_registrations TO service_role;

-- Grant execute on functions
GRANT EXECUTE ON FUNCTION events.calculate_open_play_fee TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION events.get_skill_level_capacity TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION api.register_for_open_play TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION api.cancel_open_play_registration TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION api.get_open_play_registrations TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION api.get_player_open_play_history TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION api.get_upcoming_open_play_schedule TO authenticated, anon, service_role;
