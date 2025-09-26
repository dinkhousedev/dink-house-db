-- ============================================================================
-- ALLOWED EMAILS MODULE
-- Manage pre-authorized email addresses for sign-up
-- ============================================================================

-- Switch to app_auth schema
SET search_path TO app_auth, public;

-- Table for storing allowed email addresses for sign-up
CREATE TABLE IF NOT EXISTS app_auth.allowed_emails (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    email public.CITEXT UNIQUE NOT NULL,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    role VARCHAR(50) DEFAULT 'viewer'
        CHECK (role IN ('super_admin', 'admin', 'editor', 'viewer', 'manager', 'coach')),
    added_by UUID REFERENCES app_auth.users(id),
    notes TEXT,
    is_active BOOLEAN DEFAULT true,
    used_at TIMESTAMP WITH TIME ZONE,
    used_by UUID REFERENCES app_auth.users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for performance
CREATE INDEX idx_allowed_emails_email ON app_auth.allowed_emails(email);
CREATE INDEX idx_allowed_emails_is_active ON app_auth.allowed_emails(is_active);
CREATE INDEX idx_allowed_emails_created_at ON app_auth.allowed_emails(created_at DESC);

-- Add comment on table
COMMENT ON TABLE app_auth.allowed_emails IS 'Pre-authorized email addresses that are allowed to sign up';
COMMENT ON COLUMN app_auth.allowed_emails.email IS 'The email address that is allowed to sign up';
COMMENT ON COLUMN app_auth.allowed_emails.role IS 'The default role to assign when this email signs up';
COMMENT ON COLUMN app_auth.allowed_emails.added_by IS 'The user who added this email to the allowed list';
COMMENT ON COLUMN app_auth.allowed_emails.used_at IS 'When this email was used to sign up';
COMMENT ON COLUMN app_auth.allowed_emails.used_by IS 'The user ID created when this email signed up';

-- Function to check if an email is allowed to sign up
CREATE OR REPLACE FUNCTION app_auth.is_email_allowed(check_email TEXT)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1
        FROM app_auth.allowed_emails
        WHERE email = LOWER(check_email)
        AND is_active = true
        AND used_at IS NULL
    );
END;
$$ LANGUAGE plpgsql;

-- Function to mark an allowed email as used
CREATE OR REPLACE FUNCTION app_auth.mark_email_used(
    used_email TEXT,
    user_id UUID
)
RETURNS VOID AS $$
BEGIN
    UPDATE app_auth.allowed_emails
    SET
        used_at = CURRENT_TIMESTAMP,
        used_by = user_id,
        updated_at = CURRENT_TIMESTAMP
    WHERE email = LOWER(used_email);
END;
$$ LANGUAGE plpgsql;

-- Grant necessary permissions
GRANT SELECT ON app_auth.allowed_emails TO anon;
GRANT SELECT, INSERT, UPDATE ON app_auth.allowed_emails TO authenticated;
GRANT ALL ON app_auth.allowed_emails TO service_role;