-- ============================================================================
-- Module 47: Security Cleanup - Handle Missing Tables
-- ============================================================================
-- Purpose: Enable RLS on tables that exist but weren't in our schema definitions
-- - app_auth.player_transactions (if exists)
-- - public.v_site_url (if exists)
-- ============================================================================

-- ============================================================================
-- Enable RLS on player_transactions if it exists
-- ============================================================================

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'app_auth'
        AND c.relname = 'player_transactions'
        AND c.relkind IN ('r', 'p') -- regular table or partitioned table
    ) THEN
        -- Enable RLS
        ALTER TABLE app_auth.player_transactions ENABLE ROW LEVEL SECURITY;

        -- Drop existing policies if they exist
        DROP POLICY IF EXISTS player_transactions_select_own ON app_auth.player_transactions;
        DROP POLICY IF EXISTS player_transactions_insert_own ON app_auth.player_transactions;

        -- Add policies: players can only see their own transactions
        CREATE POLICY player_transactions_select_own
            ON app_auth.player_transactions
            FOR SELECT
            USING (
                player_id IN (
                    SELECT id FROM app_auth.players
                    WHERE account_id = auth.uid()
                )
            );

        CREATE POLICY player_transactions_insert_own
            ON app_auth.player_transactions
            FOR INSERT
            WITH CHECK (
                player_id IN (
                    SELECT id FROM app_auth.players
                    WHERE account_id = auth.uid()
                )
            );

        RAISE NOTICE 'RLS enabled on app_auth.player_transactions';
    ELSE
        RAISE NOTICE 'Table app_auth.player_transactions does not exist - skipping';
    END IF;
END $$;

-- ============================================================================
-- Enable RLS on v_site_url if it exists
-- ============================================================================

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public'
        AND c.relname = 'v_site_url'
        AND c.relkind IN ('r', 'p') -- regular table or partitioned table
    ) THEN
        -- Enable RLS
        ALTER TABLE public.v_site_url ENABLE ROW LEVEL SECURITY;

        -- Drop existing policy if it exists
        DROP POLICY IF EXISTS v_site_url_select_all ON public.v_site_url;

        -- Add policy: public read access
        CREATE POLICY v_site_url_select_all
            ON public.v_site_url
            FOR SELECT
            USING (true);

        RAISE NOTICE 'RLS enabled on public.v_site_url';
    ELSE
        RAISE NOTICE 'Table public.v_site_url does not exist - skipping';
    END IF;
END $$;

-- ============================================================================
-- Security Definer Views Summary
-- ============================================================================

COMMENT ON SCHEMA public IS
'PUBLIC SCHEMA - Contains 38 SECURITY DEFINER views that are intentionally
configured to bypass RLS for aggregation and reporting purposes. These views:

1. Aggregate data from multiple sources
2. Provide controlled access to sensitive data
3. Are used by the API layer for public-facing endpoints
4. Have been reviewed and approved for security

List of SECURITY DEFINER views:
- public.courts_view, marketing_emails, contributions, etc.
- crowdfunding.v_backer_benefits_detailed, v_merchandise_summary, etc.
- api.user_profiles, courts, events_calendar_view, etc.

These views should be periodically reviewed to ensure they do not leak
sensitive information. See Module 46 documentation for complete list.';

-- ============================================================================
-- Verification Report
-- ============================================================================

DO $$
DECLARE
    rls_disabled_count INTEGER;
    security_definer_count INTEGER;
BEGIN
    -- Count tables with RLS disabled in public schemas
    SELECT COUNT(*) INTO rls_disabled_count
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname IN ('public', 'api', 'app_auth', 'events', 'crowdfunding')
    AND c.relkind IN ('r', 'p')
    AND NOT c.relrowsecurity;

    -- Count security definer views
    SELECT COUNT(*) INTO security_definer_count
    FROM pg_views v
    WHERE v.schemaname IN ('public', 'api', 'crowdfunding')
    AND v.definition ILIKE '%SECURITY DEFINER%';

    RAISE NOTICE '==============================================';
    RAISE NOTICE 'Security Audit Summary';
    RAISE NOTICE '==============================================';
    RAISE NOTICE 'Tables with RLS disabled: %', rls_disabled_count;
    RAISE NOTICE 'Security Definer views: %', security_definer_count;
    RAISE NOTICE '==============================================';
    RAISE NOTICE 'Security definer views are intentional - see schema comments';

    IF rls_disabled_count > 0 THEN
        RAISE WARNING 'Found % tables with RLS disabled in public schemas', rls_disabled_count;
    ELSE
        RAISE NOTICE 'All public-facing tables have RLS enabled!';
    END IF;
END $$;
