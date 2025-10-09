-- ============================================================================
-- Create api.events_with_dupr_matching View
-- ============================================================================
-- This migration creates the events_with_dupr_matching view in the api schema
-- for DUPR-based event filtering in the player app
-- ============================================================================

-- Ensure api schema exists
CREATE SCHEMA IF NOT EXISTS api;
GRANT USAGE ON SCHEMA api TO authenticated;
GRANT USAGE ON SCHEMA api TO anon;
GRANT USAGE ON SCHEMA api TO service_role;

-- Drop existing view if it exists
DROP VIEW IF EXISTS api.events_with_dupr_matching;

-- Create view in api schema
CREATE VIEW api.events_with_dupr_matching AS
SELECT
    e.*,
    db.label as dupr_bracket_label
FROM public.events_view e
LEFT JOIN events.dupr_brackets db ON db.id = e.dupr_bracket_id
WHERE e.is_published = true
  AND e.is_cancelled = false;

COMMENT ON VIEW api.events_with_dupr_matching IS 'Events with DUPR bracket information for player matching';

-- Grant permissions
GRANT SELECT ON api.events_with_dupr_matching TO service_role;
GRANT SELECT ON api.events_with_dupr_matching TO authenticated;
GRANT SELECT ON api.events_with_dupr_matching TO anon;
