-- ============================================================================
-- PERMISSIONS AND ROLES MODULE
-- Database roles and schema permissions for security
-- ============================================================================

-- Create database roles
DO $$
BEGIN
    -- Application roles
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_anon') THEN
        CREATE ROLE app_anon NOLOGIN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_user') THEN
        CREATE ROLE app_user NOLOGIN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_admin') THEN
        CREATE ROLE app_admin NOLOGIN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_service') THEN
        CREATE ROLE app_service NOLOGIN;
    END IF;
END
$$;

-- Grant schema usage permissions
-- Anonymous users (public access)
GRANT USAGE ON SCHEMA public TO app_anon;
GRANT USAGE ON SCHEMA api TO app_anon;
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA api TO anon;

-- Authenticated users
GRANT USAGE ON SCHEMA public TO app_user;
GRANT USAGE ON SCHEMA auth TO app_user;
GRANT USAGE ON SCHEMA content TO app_user;
GRANT USAGE ON SCHEMA contact TO app_user;
GRANT USAGE ON SCHEMA launch TO app_user;
GRANT USAGE ON SCHEMA api TO app_user;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA auth TO authenticated;
GRANT USAGE ON SCHEMA content TO authenticated;
GRANT USAGE ON SCHEMA contact TO authenticated;
GRANT USAGE ON SCHEMA launch TO authenticated;
GRANT USAGE ON SCHEMA api TO authenticated;

-- Admin users
GRANT USAGE ON SCHEMA public TO app_admin;
GRANT USAGE ON SCHEMA auth TO app_admin;
GRANT USAGE ON SCHEMA content TO app_admin;
GRANT USAGE ON SCHEMA contact TO app_admin;
GRANT USAGE ON SCHEMA launch TO app_admin;
GRANT USAGE ON SCHEMA system TO app_admin;
GRANT USAGE ON SCHEMA api TO app_admin;
GRANT USAGE ON SCHEMA public TO service_role;
GRANT USAGE ON SCHEMA auth TO service_role;
GRANT USAGE ON SCHEMA content TO service_role;
GRANT USAGE ON SCHEMA contact TO service_role;
GRANT USAGE ON SCHEMA launch TO service_role;
GRANT USAGE ON SCHEMA system TO service_role;
GRANT USAGE ON SCHEMA api TO service_role;

-- Service accounts (full access)
GRANT ALL ON SCHEMA public TO app_service;
GRANT ALL ON SCHEMA auth TO app_service;
GRANT ALL ON SCHEMA content TO app_service;
GRANT ALL ON SCHEMA contact TO app_service;
GRANT ALL ON SCHEMA launch TO app_service;
GRANT ALL ON SCHEMA system TO app_service;
GRANT ALL ON SCHEMA api TO app_service;

-- ============================================================================
-- TABLE PERMISSIONS
-- ============================================================================

-- Auth schema permissions
GRANT SELECT ON ALL TABLES IN SCHEMA auth TO app_anon;  -- Limited read for verification
GRANT ALL ON ALL TABLES IN SCHEMA auth TO app_user;     -- Users can manage their own data
GRANT ALL ON ALL TABLES IN SCHEMA auth TO app_admin;    -- Admins have full access
GRANT ALL ON ALL TABLES IN SCHEMA auth TO app_service;  -- Services have full access

-- Content schema permissions
GRANT SELECT ON ALL TABLES IN SCHEMA content TO app_anon;  -- Anonymous can read public content
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA content TO app_user;  -- Users can create content
GRANT ALL ON ALL TABLES IN SCHEMA content TO app_admin;     -- Admins have full access
GRANT ALL ON ALL TABLES IN SCHEMA content TO app_service;   -- Services have full access

-- Contact schema permissions
GRANT INSERT ON contact.contact_inquiries TO app_anon;      -- Anonymous can submit forms
GRANT SELECT ON contact.contact_forms TO app_anon;          -- Anonymous can view forms
GRANT ALL ON ALL TABLES IN SCHEMA contact TO app_user;      -- Users have full access
GRANT ALL ON ALL TABLES IN SCHEMA contact TO app_admin;     -- Admins have full access
GRANT ALL ON ALL TABLES IN SCHEMA contact TO app_service;   -- Services have full access

-- Launch schema permissions
GRANT SELECT ON launch.launch_campaigns TO app_anon;        -- Anonymous can view campaigns
GRANT INSERT ON launch.launch_subscribers TO app_anon;      -- Anonymous can subscribe
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA launch TO app_user;  -- Users can manage subscriptions
GRANT ALL ON ALL TABLES IN SCHEMA launch TO app_admin;      -- Admins have full access
GRANT ALL ON ALL TABLES IN SCHEMA launch TO app_service;    -- Services have full access

-- System schema permissions (restricted)
-- No access for anonymous users
-- No access for regular users
GRANT ALL ON ALL TABLES IN SCHEMA system TO app_admin;      -- Admins have full access
GRANT ALL ON ALL TABLES IN SCHEMA system TO app_service;    -- Services have full access

-- ============================================================================
-- SEQUENCE PERMISSIONS
-- ============================================================================

GRANT USAGE ON ALL SEQUENCES IN SCHEMA auth TO app_user, app_admin, app_service;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA content TO app_user, app_admin, app_service;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA contact TO app_anon, app_user, app_admin, app_service;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA launch TO app_anon, app_user, app_admin, app_service;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA system TO app_admin, app_service;

-- ============================================================================
-- FUNCTION PERMISSIONS
-- ============================================================================

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO app_anon, app_user, app_admin, app_service;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA auth TO app_user, app_admin, app_service;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO app_anon, app_user, app_admin, app_service;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO anon, authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA auth TO authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO anon, authenticated, service_role;

-- ============================================================================
-- DEFAULT PRIVILEGES
-- Set default permissions for future objects
-- ============================================================================

-- For tables created by postgres user
ALTER DEFAULT PRIVILEGES IN SCHEMA auth
    GRANT ALL ON TABLES TO app_admin, app_service;
ALTER DEFAULT PRIVILEGES IN SCHEMA auth
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_user;

ALTER DEFAULT PRIVILEGES IN SCHEMA content
    GRANT ALL ON TABLES TO app_admin, app_service;
ALTER DEFAULT PRIVILEGES IN SCHEMA content
    GRANT SELECT ON TABLES TO app_anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA content
    GRANT SELECT, INSERT, UPDATE ON TABLES TO app_user;

ALTER DEFAULT PRIVILEGES IN SCHEMA contact
    GRANT ALL ON TABLES TO app_admin, app_service, app_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA contact
    GRANT INSERT ON TABLES TO app_anon;

ALTER DEFAULT PRIVILEGES IN SCHEMA launch
    GRANT ALL ON TABLES TO app_admin, app_service;
ALTER DEFAULT PRIVILEGES IN SCHEMA launch
    GRANT SELECT, INSERT, UPDATE ON TABLES TO app_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA launch
    GRANT SELECT ON TABLES TO app_anon;

ALTER DEFAULT PRIVILEGES IN SCHEMA system
    GRANT ALL ON TABLES TO app_admin, app_service;

-- For sequences
ALTER DEFAULT PRIVILEGES IN SCHEMA auth
    GRANT USAGE ON SEQUENCES TO app_user, app_admin, app_service;

ALTER DEFAULT PRIVILEGES IN SCHEMA content
    GRANT USAGE ON SEQUENCES TO app_user, app_admin, app_service;

ALTER DEFAULT PRIVILEGES IN SCHEMA contact
    GRANT USAGE ON SEQUENCES TO app_anon, app_user, app_admin, app_service;

ALTER DEFAULT PRIVILEGES IN SCHEMA launch
    GRANT USAGE ON SEQUENCES TO app_anon, app_user, app_admin, app_service;

ALTER DEFAULT PRIVILEGES IN SCHEMA system
    GRANT USAGE ON SEQUENCES TO app_admin, app_service;

-- ============================================================================
-- ROW LEVEL SECURITY (RLS)
-- Definitive policies are maintained in sql/modules/11-rls-policies.sql
ALTER TABLE app_auth.user_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_auth.admin_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_auth.players ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_auth.guest_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_auth.sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE content.pages ENABLE ROW LEVEL SECURITY;
ALTER TABLE contact.contact_inquiries ENABLE ROW LEVEL SECURITY;
ALTER TABLE system.system_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY settings_admin_all ON system.system_settings
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM app_auth.admin_users au
            WHERE au.id = current_setting('app.current_user_id', true)::uuid
            AND au.role IN ('admin', 'super_admin')
        )
    );

-- Grant role memberships
GRANT app_anon TO postgres;
GRANT app_user TO postgres;
GRANT app_admin TO postgres;
GRANT app_service TO postgres;

-- ============================================================================
-- NOTES
-- ============================================================================
-- To use these roles in your application:
-- 1. Create database users and assign them to appropriate roles:
--    CREATE USER my_app_user WITH PASSWORD 'password';
--    GRANT app_user TO my_app_user;
--
-- 2. Set session variables for RLS:
--    SET app.current_user_id = 'user-uuid';
--    SET app.current_user_email = 'user@example.com';
--
-- 3. Switch roles in your application based on authentication:
--    SET ROLE app_anon;    -- For unauthenticated requests
--    SET ROLE app_user;    -- For authenticated users
--    SET ROLE app_admin;   -- For admin users
--    SET ROLE app_service; -- For service accounts
