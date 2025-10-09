-- ============================================================================
-- SECURITY HARDENING
-- Ensure critical tables enforce RLS and views run as SECURITY INVOKER
-- ============================================================================

SET search_path TO public;

-- ============================================================================
-- ENABLE RLS ON PUBLIC-FACING TABLES
-- ============================================================================

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('crowdfunding', 'benefit_allocations'),
      ('crowdfunding', 'benefit_usage_log'),
      ('events', 'events'),
      ('events', 'event_courts'),
      ('events', 'dupr_brackets'),
      ('app_auth', 'player_transactions'),
      ('app_auth', 'player_fees'),
      ('app_auth', 'membership_transactions'),
      ('public', 'v_site_url')
    ) AS t(schema_name, table_name)
  LOOP
    IF EXISTS (
      SELECT 1
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = r.schema_name
        AND c.relname = r.table_name
        AND c.relkind IN ('r', 'p')
    ) THEN
      EXECUTE format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY;', r.schema_name, r.table_name);
    END IF;
  END LOOP;
END;
$$;

-- ============================================================================
-- ENSURE VIEWS RUN WITH SECURITY INVOKER
-- ============================================================================

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('public', 'marketing_emails'),
      ('crowdfunding', 'v_backer_benefits_detailed'),
      ('crowdfunding', 'v_pending_merchandise_pickups'),
      ('public', 'v_backer_benefits_detailed'),
      ('public', 'contributions'),
      ('public', 'marketing_email_recipients'),
      ('crowdfunding', 'v_merchandise_summary'),
      ('public', 'founders_wall'),
      ('public', 'marketing_top_performing_emails'),
      ('public', 'marketing_email_analytics'),
      ('public', 'v_fulfillment_summary'),
      ('public', 'campaign_types'),
      ('crowdfunding', 'v_backer_benefit_summary'),
      ('crowdfunding', 'v_upcoming_events'),
      ('api', 'user_profiles'),
      ('public', 'launch_subscribers'),
      ('crowdfunding', 'v_pending_recognition_items'),
      ('crowdfunding', 'v_backer_summary'),
      ('public', 'contribution_tiers'),
      ('crowdfunding', 'v_fulfillment_summary'),
      ('public', 'marketing_campaign_overview'),
      ('public', 'v_backer_summary'),
      ('public', 'recognition_items'),
      ('crowdfunding', 'v_pending_fulfillment'),
      ('public', 'v_pending_fulfillment'),
      ('public', 'v_active_backer_benefits'),
      ('crowdfunding', 'v_active_court_sponsorships'),
      ('public', 'v_refundable_contributions'),
      ('crowdfunding', 'v_active_backer_benefits'),
      ('crowdfunding', 'v_refundable_contributions'),
      ('public', 'players'),
      ('crowdfunding', 'v_event_rsvp_summary'),
      ('public', 'backers')
    ) AS t(schema_name, view_name)
  LOOP
    EXECUTE format(
      'ALTER VIEW IF EXISTS %I.%I SET (security_invoker = true);',
      r.schema_name,
      r.view_name
    );
  END LOOP;
END;
$$;
