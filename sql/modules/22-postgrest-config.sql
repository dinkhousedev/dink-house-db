-- ============================================================================
-- POSTGREST CONFIGURATION MODULE
-- Ensures PostgREST can access the api schema and functions
-- ============================================================================

-- Grant usage on api schema to PostgREST roles
GRANT USAGE ON SCHEMA api TO anon, authenticated, service_role;

-- Grant execute permissions on all existing functions in api schema
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO anon, authenticated, service_role;

-- Set default privileges for future functions in api schema
ALTER DEFAULT PRIVILEGES IN SCHEMA api
    GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role;

-- Ensure specific login functions are accessible
DO $$
BEGIN
    -- Check if functions exist before granting
    IF EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'api' AND p.proname = 'login'
    ) THEN
        GRANT EXECUTE ON FUNCTION api.login(text, text) TO anon, authenticated, service_role;
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'api' AND p.proname = 'login_safe'
    ) THEN
        GRANT EXECUTE ON FUNCTION api.login_safe(text, text) TO anon, authenticated, service_role;
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'api' AND p.proname = 'get_user_by_session'
    ) THEN
        GRANT EXECUTE ON FUNCTION api.get_user_by_session(text) TO anon, authenticated, service_role;
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'api' AND p.proname = 'verify_session'
    ) THEN
        GRANT EXECUTE ON FUNCTION api.verify_session(text) TO anon, authenticated, service_role;
    END IF;

    -- Grant permissions for player management functions
    IF EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'api' AND p.proname = 'create_player_account'
    ) THEN
        GRANT EXECUTE ON FUNCTION api.create_player_account TO authenticated, service_role;
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'api' AND p.proname = 'list_player_accounts'
    ) THEN
        GRANT EXECUTE ON FUNCTION api.list_player_accounts TO authenticated, service_role;
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'api' AND p.proname = 'get_player_account'
    ) THEN
        GRANT EXECUTE ON FUNCTION api.get_player_account TO authenticated, service_role;
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'api' AND p.proname = 'update_player_account'
    ) THEN
        GRANT EXECUTE ON FUNCTION api.update_player_account TO authenticated, service_role;
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'api' AND p.proname = 'delete_player_account'
    ) THEN
        GRANT EXECUTE ON FUNCTION api.delete_player_account TO authenticated, service_role;
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'api' AND p.proname = 'reset_player_password'
    ) THEN
        GRANT EXECUTE ON FUNCTION api.reset_player_password TO authenticated, service_role;
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'api' AND p.proname = 'get_all_account_stats'
    ) THEN
        GRANT EXECUTE ON FUNCTION api.get_all_account_stats TO authenticated, service_role;
    END IF;
END;
$$;

-- Notify PostgREST to reload schema cache
NOTIFY pgrst, 'reload schema';

-- Add comment for documentation
COMMENT ON SCHEMA api IS 'API schema for PostgREST endpoints - contains functions exposed as REST endpoints';