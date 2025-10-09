-- ============================================================================
-- SCHEDULE OVERRIDE UPSERT FIX
-- Updates create_schedule_override to handle existing overrides
-- ============================================================================

CREATE OR REPLACE FUNCTION api.create_schedule_override(
    p_block_id UUID,
    p_override_date DATE,
    p_is_cancelled BOOLEAN,
    p_reason TEXT,
    p_replacement_details JSONB DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_override_id UUID;
    v_result JSON;
    v_admin_user_id UUID;
    v_is_new BOOLEAN;
BEGIN
    -- Check if user is staff
    IF NOT events.is_staff() THEN
        RAISE EXCEPTION 'Unauthorized: Only staff can create schedule overrides';
    END IF;

    -- Try to get admin user ID (may be NULL if not in admin_users table)
    SELECT id INTO v_admin_user_id
    FROM app_auth.admin_users
    WHERE id = auth.uid();

    -- Upsert the override (insert or update if already exists)
    INSERT INTO events.open_play_schedule_overrides (
        schedule_block_id,
        override_date,
        is_cancelled,
        replacement_name,
        replacement_start_time,
        replacement_end_time,
        replacement_session_type,
        reason,
        special_instructions,
        created_by
    ) VALUES (
        p_block_id,
        p_override_date,
        p_is_cancelled,
        p_replacement_details->>'name',
        (p_replacement_details->>'start_time')::TIME,
        (p_replacement_details->>'end_time')::TIME,
        (p_replacement_details->>'session_type')::events.open_play_session_type,
        p_reason,
        p_replacement_details->>'special_instructions',
        v_admin_user_id
    )
    ON CONFLICT (schedule_block_id, override_date)
    DO UPDATE SET
        is_cancelled = EXCLUDED.is_cancelled,
        replacement_name = EXCLUDED.replacement_name,
        replacement_start_time = EXCLUDED.replacement_start_time,
        replacement_end_time = EXCLUDED.replacement_end_time,
        replacement_session_type = EXCLUDED.replacement_session_type,
        reason = EXCLUDED.reason,
        special_instructions = EXCLUDED.special_instructions,
        updated_at = CURRENT_TIMESTAMP
    RETURNING id, (xmax = 0) INTO v_override_id, v_is_new;

    -- Mark any existing instance as cancelled or update it
    UPDATE events.open_play_instances
    SET
        is_cancelled = p_is_cancelled,
        override_id = v_override_id,
        updated_at = CURRENT_TIMESTAMP
    WHERE schedule_block_id = p_block_id
      AND instance_date = p_override_date;

    -- Return success
    SELECT json_build_object(
        'success', true,
        'override_id', v_override_id,
        'is_new', v_is_new,
        'message', CASE
            WHEN v_is_new THEN 'Schedule override created successfully'
            ELSE 'Schedule override updated successfully'
        END
    ) INTO v_result;

    RETURN v_result;
END;
$$;

-- Update public wrapper (no changes needed, just ensuring it's correct)
CREATE OR REPLACE FUNCTION public.create_schedule_override(
    p_block_id UUID,
    p_override_date DATE,
    p_is_cancelled BOOLEAN,
    p_reason TEXT DEFAULT NULL,
    p_replacement_details JSONB DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN api.create_schedule_override(
        p_block_id,
        p_override_date,
        p_is_cancelled,
        p_reason,
        p_replacement_details
    );
END;
$$;

-- Add comment
COMMENT ON FUNCTION api.create_schedule_override IS
    'Creates or updates a schedule override for a specific date. Uses UPSERT to handle existing overrides.';
