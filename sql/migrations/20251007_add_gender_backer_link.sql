-- ============================================================================
-- ADD GENDER, PROFILE PICTURES & BACKER AUTO-LINKING
-- Links players to crowdfunding backers by matching email addresses
-- ============================================================================

SET search_path TO app_auth, crowdfunding, api, public;

-- ============================================================================
-- CREATE GENDER ENUM TYPE
-- ============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_type t
    JOIN pg_namespace n ON t.typnamespace = n.oid
    WHERE t.typname = 'gender' AND n.nspname = 'app_auth'
  ) THEN
    CREATE TYPE app_auth.gender AS ENUM ('male', 'female');
  END IF;
END $$;

-- ============================================================================
-- ADD COLUMNS TO PLAYERS TABLE
-- ============================================================================

ALTER TABLE app_auth.players
  ADD COLUMN IF NOT EXISTS gender app_auth.gender DEFAULT 'male',
  ADD COLUMN IF NOT EXISTS profile_picture_url TEXT,
  ADD COLUMN IF NOT EXISTS use_default_picture BOOLEAN DEFAULT true,
  ADD COLUMN IF NOT EXISTS backer_id UUID;

-- Add foreign key constraint
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'fk_players_backer_id'
  ) THEN
    ALTER TABLE app_auth.players
    ADD CONSTRAINT fk_players_backer_id
    FOREIGN KEY (backer_id) REFERENCES crowdfunding.backers(id) ON DELETE SET NULL;
  END IF;
END $$;

-- ============================================================================
-- CREATE INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_players_backer_id ON app_auth.players(backer_id);
CREATE INDEX IF NOT EXISTS idx_players_gender ON app_auth.players(gender);
CREATE INDEX IF NOT EXISTS idx_backers_email_lower ON crowdfunding.backers(LOWER(email));

-- ============================================================================
-- AUTO-LINK FUNCTION (Matches player email with backer email)
-- ============================================================================

CREATE OR REPLACE FUNCTION api.auto_link_player_to_backer(p_player_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_email TEXT;
  v_backer_id UUID;
  v_badge_tier crowdfunding.badge_tier;
  v_total_contributed DECIMAL(10,2);
BEGIN
  -- Get player email from user_accounts via account_id
  SELECT ua.email INTO v_player_email
  FROM app_auth.players p
  JOIN app_auth.user_accounts ua ON ua.id = p.account_id
  WHERE p.id = p_player_id;

  IF v_player_email IS NULL THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Player not found'
    );
  END IF;

  -- Find matching backer by email (case-insensitive)
  SELECT id, badge_level, total_contributed
  INTO v_backer_id, v_badge_tier, v_total_contributed
  FROM crowdfunding.backers
  WHERE LOWER(email) = LOWER(v_player_email)
  LIMIT 1;

  IF v_backer_id IS NOT NULL THEN
    -- Link player to backer
    UPDATE app_auth.players
    SET backer_id = v_backer_id
    WHERE id = p_player_id;

    RETURN json_build_object(
      'success', true,
      'backer_linked', true,
      'backer_id', v_backer_id,
      'badge_tier', v_badge_tier,
      'total_contributed', v_total_contributed,
      'message', 'Player successfully linked to backer account'
    );
  ELSE
    RETURN json_build_object(
      'success', true,
      'backer_linked', false,
      'message', 'No matching backer found for this email'
    );
  END IF;
END;
$$;

-- ============================================================================
-- UPDATE GET_PLAYER_PROFILE TO INCLUDE BACKER INFO
-- ============================================================================

CREATE OR REPLACE FUNCTION api.get_player_profile(p_account_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result JSON;
BEGIN
  SELECT json_build_object(
    'success', true,
    'data', json_build_object(
      'id', p.id,
      'account_id', p.account_id,
      'email', ua.email,
      'first_name', p.first_name,
      'last_name', p.last_name,
      'display_name', p.display_name,
      'gender', p.gender,
      'profile_picture_url',
        CASE
          WHEN p.use_default_picture OR p.profile_picture_url IS NULL THEN
            CASE p.gender
              WHEN 'female' THEN 'https://wchxzbuuwssrnaxshseu.supabase.co/storage/v1/object/public/dink-files/profile_picture/default_female.png'
              ELSE 'https://wchxzbuuwssrnaxshseu.supabase.co/storage/v1/object/public/dink-files/profile_picture/default_male.png'
            END
          ELSE p.profile_picture_url
        END,
      'use_default_picture', COALESCE(p.use_default_picture, true),
      'phone', p.phone,
      'street_address', p.street_address,
      'city', p.city,
      'state', p.state,
      'date_of_birth', p.date_of_birth,
      'dupr_rating', p.dupr_rating,
      'dupr_verified', p.dupr_verified,
      'membership_level', p.membership_level,
      'profile_status', p.profile_status,
      'is_active', p.is_active,
      'is_verified', p.is_verified,
      -- Backer info
      'is_backer', (p.backer_id IS NOT NULL),
      'backer_info', (
        SELECT json_build_object(
          'backer_id', b.id,
          'total_contributed', b.total_contributed,
          'contribution_count', b.contribution_count,
          'badge', json_build_object(
            'tier', b.badge_level,
            'name', bti.badge_name,
            'image_url', bti.badge_image_url,
            'color', bti.badge_color,
            'icon', bti.badge_icon
          ),
          'benefits', (
            SELECT COALESCE(json_agg(
              json_build_object(
                'id', bb.id,
                'benefit_type', bb.benefit_type,
                'benefit_details', bb.benefit_details,
                'is_active', bb.is_active,
                'expires_at', bb.expires_at,
                'redeemed_count', bb.redeemed_count,
                'activated_at', bb.activated_at
              ) ORDER BY bb.created_at
            ), '[]'::json)
            FROM crowdfunding.backer_benefits bb
            WHERE bb.backer_id = b.id AND bb.is_active = true
          )
        )
        FROM crowdfunding.backers b
        LEFT JOIN crowdfunding.get_badge_tier_info() bti ON b.badge_level = bti.badge
        WHERE b.id = p.backer_id
      ),
      'created_at', p.created_at,
      'updated_at', p.updated_at
    )
  )
  INTO v_result
  FROM app_auth.players p
  JOIN app_auth.user_accounts ua ON ua.id = p.account_id
  WHERE p.account_id = p_account_id;

  IF v_result IS NULL THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Player not found'
    );
  END IF;

  RETURN v_result;
END;
$$;

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

GRANT EXECUTE ON FUNCTION api.auto_link_player_to_backer(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION api.get_player_profile(UUID) TO authenticated, anon, service_role;

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON COLUMN app_auth.players.gender IS 'Player gender (male or female) for default profile picture selection';
COMMENT ON COLUMN app_auth.players.profile_picture_url IS 'Custom profile picture URL uploaded by player';
COMMENT ON COLUMN app_auth.players.use_default_picture IS 'Whether to use default picture based on gender (true) or custom uploaded picture (false)';
COMMENT ON COLUMN app_auth.players.backer_id IS 'Link to crowdfunding.backers for players who contributed to crowdfunding campaign';
COMMENT ON FUNCTION api.auto_link_player_to_backer(UUID) IS 'Automatically links player to backer account by matching email addresses';
COMMENT ON FUNCTION api.get_player_profile(UUID) IS 'Enhanced player profile function that includes crowdfunding backer info and benefits';
