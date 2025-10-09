-- ============================================================================
-- PLAYERS API VIEW
-- Create public view for players table to enable PostgREST access
-- ============================================================================

-- Create players view in public schema for PostgREST API access
CREATE OR REPLACE VIEW public.players AS
SELECT
    p.id,
    p.account_id,
    p.first_name,
    p.last_name,
    ua.email,
    p.phone,
    p.membership_level,
    p.skill_level,
    p.dupr_rating,
    p.stripe_customer_id,
    p.date_of_birth,
    ua.is_verified,
    ua.is_active,
    p.display_name,
    p.street_address,
    p.city,
    p.state,
    p.membership_started_on,
    p.membership_expires_on,
    p.dupr_rating_updated_at,
    p.club_id,
    p.profile,
    p.created_at,
    p.updated_at
FROM app_auth.players p
JOIN app_auth.user_accounts ua ON p.account_id = ua.id;

COMMENT ON VIEW public.players IS 'Players API view for PostgREST access';

-- Grant permissions
GRANT SELECT ON public.players TO authenticated;
GRANT SELECT ON public.players TO anon;

-- Staff can see all fields
GRANT ALL ON public.players TO service_role;
