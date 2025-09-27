-- ============================================================================
-- SEED DATA: User Accounts and Authentication Profiles
-- Default identities for development environment
-- ============================================================================

SET search_path TO app_auth, public;

-- --------------------------------------------------------------------------
-- Helper CTE to insert baseline accounts
-- --------------------------------------------------------------------------
WITH base_accounts AS (
    INSERT INTO app_auth.user_accounts (
        email,
        password_hash,
        user_type,
        is_active,
        is_verified,
        last_login
    ) VALUES
        ('admin@dinkhouse.com', public.crypt('DevPassword123!', public.gen_salt('bf', 8)), 'admin'::app_auth.user_type, true, true, CURRENT_TIMESTAMP),
        ('editor@dinkhouse.com', public.crypt('DevPassword123!', public.gen_salt('bf', 8)), 'admin'::app_auth.user_type, true, true, CURRENT_TIMESTAMP),
        ('viewer@dinkhouse.com', public.crypt('DevPassword123!', public.gen_salt('bf', 8)), 'admin'::app_auth.user_type, true, true, CURRENT_TIMESTAMP),
        ('john.doe@example.com', public.crypt('DevPassword123!', public.gen_salt('bf', 8)), 'admin'::app_auth.user_type, true, true, CURRENT_TIMESTAMP),
        ('jane.smith@example.com', public.crypt('DevPassword123!', public.gen_salt('bf', 8)), 'admin'::app_auth.user_type, true, true, CURRENT_TIMESTAMP),
        ('player.one@example.com', public.crypt('DevPassword123!', public.gen_salt('bf', 8)), 'player'::app_auth.user_type, true, true, CURRENT_TIMESTAMP),
        ('guest.one@example.com', public.crypt('DevPassword123!', public.gen_salt('bf', 8)), 'guest'::app_auth.user_type, true, false, NULL)
    RETURNING id, email, user_type
)
INSERT INTO app_auth.admin_users (id, account_id, username, first_name, last_name, role)
SELECT
    CASE email
        WHEN 'admin@dinkhouse.com' THEN id
        WHEN 'editor@dinkhouse.com' THEN id
        WHEN 'viewer@dinkhouse.com' THEN id
        WHEN 'john.doe@example.com' THEN id
        WHEN 'jane.smith@example.com' THEN id
    END AS id,
    id AS account_id,
    CASE email
        WHEN 'admin@dinkhouse.com' THEN 'admin'
        WHEN 'editor@dinkhouse.com' THEN 'editor'
        WHEN 'viewer@dinkhouse.com' THEN 'viewer'
        WHEN 'john.doe@example.com' THEN 'john.doe'
        WHEN 'jane.smith@example.com' THEN 'jane.smith'
    END AS username,
    CASE email
        WHEN 'admin@dinkhouse.com' THEN 'Admin'
        WHEN 'editor@dinkhouse.com' THEN 'Editor'
        WHEN 'viewer@dinkhouse.com' THEN 'Viewer'
        WHEN 'john.doe@example.com' THEN 'John'
        WHEN 'jane.smith@example.com' THEN 'Jane'
    END AS first_name,
    CASE email
        WHEN 'admin@dinkhouse.com' THEN 'User'
        WHEN 'editor@dinkhouse.com' THEN 'User'
        WHEN 'viewer@dinkhouse.com' THEN 'User'
        WHEN 'john.doe@example.com' THEN 'Doe'
        WHEN 'jane.smith@example.com' THEN 'Smith'
    END AS last_name,
    CASE email
        WHEN 'admin@dinkhouse.com' THEN 'super_admin'::app_auth.admin_role
        WHEN 'editor@dinkhouse.com' THEN 'editor'::app_auth.admin_role
        WHEN 'viewer@dinkhouse.com' THEN 'viewer'::app_auth.admin_role
        WHEN 'john.doe@example.com' THEN 'admin'::app_auth.admin_role
        WHEN 'jane.smith@example.com' THEN 'editor'::app_auth.admin_role
    END AS role
FROM base_accounts
WHERE user_type = 'admin';

-- --------------------------------------------------------------------------
-- Player demo profile
-- --------------------------------------------------------------------------
INSERT INTO app_auth.players (id, account_id, first_name, last_name, display_name, membership_level, skill_level)
SELECT
    id,
    id,
    'Player',
    'One',
    'Player One',
    'basic',
    'intermediate'
FROM app_auth.user_accounts
WHERE email = 'player.one@example.com'
ON CONFLICT DO NOTHING;

-- --------------------------------------------------------------------------
-- Guest example (expires soon for QA flows)
-- --------------------------------------------------------------------------
INSERT INTO app_auth.guest_users (id, account_id, display_name, email, expires_at)
SELECT
    id,
    id,
    'Guest One',
    'guest.one@example.com',
    CURRENT_TIMESTAMP + INTERVAL '12 hours'
FROM app_auth.user_accounts
WHERE email = 'guest.one@example.com'
ON CONFLICT DO NOTHING;

-- --------------------------------------------------------------------------
-- Issue API key tied to super admin account for local testing
-- --------------------------------------------------------------------------
INSERT INTO app_auth.api_keys (account_id, name, key_hash, permissions, is_active)
SELECT
    ua.id,
    'Development API Key',
    public.crypt('dev_api_key_admin', public.gen_salt('bf', 8)),
    '["read", "write"]'::jsonb,
    true
FROM app_auth.user_accounts ua
JOIN app_auth.admin_users au ON au.account_id = ua.id
WHERE au.username = 'admin'
ON CONFLICT DO NOTHING;
