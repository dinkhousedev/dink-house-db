-- ============================================================================
-- SEED DATA: Users and Authentication
-- Default users for development environment
-- ============================================================================

-- Set search path
SET search_path TO auth, public;

-- Insert default admin users
-- Password for all users: 'DevPassword123!'
INSERT INTO auth.users (username, email, password_hash, first_name, last_name, role, is_active, is_verified)
VALUES
    ('admin', 'admin@dinkhouse.com', public.crypt('DevPassword123!', public.gen_salt('bf', 8)), 'Admin', 'User', 'super_admin', true, true),
    ('editor', 'editor@dinkhouse.com', public.crypt('DevPassword123!', public.gen_salt('bf', 8)), 'Editor', 'User', 'editor', true, true),
    ('viewer', 'viewer@dinkhouse.com', public.crypt('DevPassword123!', public.gen_salt('bf', 8)), 'Viewer', 'User', 'viewer', true, true),
    ('john.doe', 'john.doe@example.com', public.crypt('DevPassword123!', public.gen_salt('bf', 8)), 'John', 'Doe', 'admin', true, true),
    ('jane.smith', 'jane.smith@example.com', public.crypt('DevPassword123!', public.gen_salt('bf', 8)), 'Jane', 'Smith', 'editor', true, true);

-- Insert API keys for development
INSERT INTO auth.api_keys (user_id, name, key_hash, permissions, is_active)
SELECT
    id,
    'Development API Key',
    public.crypt('dev_api_key_' || username, public.gen_salt('bf', 8)),
    '["read", "write"]'::jsonb,
    true
FROM auth.users
WHERE username = 'admin';