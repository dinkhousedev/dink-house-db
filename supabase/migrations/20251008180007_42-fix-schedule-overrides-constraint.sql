-- ============================================================================
-- FIX SCHEDULE OVERRIDES FOREIGN KEY CONSTRAINT
-- Makes created_by nullable and adds better handling
-- ============================================================================

-- Drop the existing foreign key constraint
ALTER TABLE events.open_play_schedule_overrides
    DROP CONSTRAINT IF EXISTS open_play_schedule_overrides_created_by_fkey;

-- Make created_by nullable
ALTER TABLE events.open_play_schedule_overrides
    ALTER COLUMN created_by DROP NOT NULL;

-- Add a new foreign key constraint that allows NULL
ALTER TABLE events.open_play_schedule_overrides
    ADD CONSTRAINT open_play_schedule_overrides_created_by_fkey
    FOREIGN KEY (created_by) REFERENCES app_auth.admin_users(id)
    ON DELETE SET NULL;

-- Update the create_schedule_override function to handle missing admin users
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
BEGIN
    -- Check if user is staff
    IF NOT events.is_staff() THEN
        RAISE EXCEPTION 'Unauthorized: Only staff can create schedule overrides';
    END IF;

    -- Try to get admin user ID (may be NULL if not in admin_users table)
    SELECT id INTO v_admin_user_id
    FROM app_auth.admin_users
    WHERE id = auth.uid();

    -- Create the override
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
        v_admin_user_id  -- Use the admin user ID or NULL
    ) RETURNING id INTO v_override_id;

    -- Mark any existing instance as cancelled or update it
    UPDATE events.open_play_instances
    SET
        is_cancelled = p_is_cancelled,
        override_id = v_override_id
    WHERE schedule_block_id = p_block_id
      AND instance_date = p_override_date;

    -- Return success
    SELECT json_build_object(
        'success', true,
        'override_id', v_override_id,
        'message', 'Schedule override created successfully'
    ) INTO v_result;

    RETURN v_result;
END;
$$;

-- Update the public wrapper function
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
COMMENT ON TABLE events.open_play_schedule_overrides IS
    'Stores overrides for scheduled open play sessions. created_by may be NULL if user is not in admin_users table.';
