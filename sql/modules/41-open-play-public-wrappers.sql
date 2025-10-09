-- ============================================================================
-- OPEN PLAY PUBLIC WRAPPER FUNCTIONS
-- Creates public schema wrappers for api schema functions to enable PostgREST access
-- ============================================================================

-- Wrapper for get_weekly_schedule
CREATE OR REPLACE FUNCTION public.get_weekly_schedule(
    p_include_inactive BOOLEAN DEFAULT false
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN api.get_weekly_schedule(p_include_inactive);
END;
$$;

-- Wrapper for get_schedule_for_date
CREATE OR REPLACE FUNCTION public.get_schedule_for_date(
    p_date DATE
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN api.get_schedule_for_date(p_date);
END;
$$;

-- Wrapper for update_schedule_block
CREATE OR REPLACE FUNCTION public.update_schedule_block(
    p_block_id UUID,
    p_updates JSONB
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN api.update_schedule_block(p_block_id, p_updates);
END;
$$;

-- Wrapper for delete_schedule_block
CREATE OR REPLACE FUNCTION public.delete_schedule_block(
    p_block_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN api.delete_schedule_block(p_block_id);
END;
$$;

-- Wrapper for create_schedule_override
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

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION public.get_weekly_schedule TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_schedule_for_date TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.update_schedule_block TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.delete_schedule_block TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.create_schedule_override TO authenticated, service_role;

-- Add comments
COMMENT ON FUNCTION public.get_weekly_schedule IS 'Public wrapper for api.get_weekly_schedule';
COMMENT ON FUNCTION public.get_schedule_for_date IS 'Public wrapper for api.get_schedule_for_date';
COMMENT ON FUNCTION public.update_schedule_block IS 'Public wrapper for api.update_schedule_block';
COMMENT ON FUNCTION public.delete_schedule_block IS 'Public wrapper for api.delete_schedule_block';
COMMENT ON FUNCTION public.create_schedule_override IS 'Public wrapper for api.create_schedule_override';
