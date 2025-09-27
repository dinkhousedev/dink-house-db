-- ============================================================================
-- SEED DATA: Allowed Emails
-- Initial set of pre-authorized email addresses for sign-up
-- ============================================================================

-- Switch to app_auth schema
SET search_path TO app_auth, public;

-- Clear existing allowed emails (optional, comment out if you want to keep existing)
-- TRUNCATE app_auth.allowed_emails;

-- Insert initial allowed email addresses
INSERT INTO app_auth.allowed_emails (email, first_name, last_name, role, notes, is_active)
VALUES
    ('john.doe@dinkhouse.com', 'John', 'Doe', 'manager', 'Initial manager account', true),
    ('jane.smith@dinkhouse.com', 'Jane', 'Smith', 'admin', 'Initial admin account', true),
    ('mike.wilson@dinkhouse.com', 'Mike', 'Wilson', 'coach', 'Initial coach account', true),
    ('admin@dinkhouse.com', 'Admin', 'User', 'admin', 'Primary admin account', true),
    ('test.manager@dinkhouse.com', 'Test', 'Manager', 'manager', 'Test manager account', true),
    ('test.coach@dinkhouse.com', 'Test', 'Coach', 'coach', 'Test coach account', true)
ON CONFLICT (email) DO UPDATE SET
    first_name = EXCLUDED.first_name,
    last_name = EXCLUDED.last_name,
    role = EXCLUDED.role,
    notes = EXCLUDED.notes,
    is_active = EXCLUDED.is_active,
    updated_at = CURRENT_TIMESTAMP;

-- Additional allowed emails can be added here
-- INSERT INTO auth.allowed_emails (email, first_name, last_name, role, notes)
-- VALUES
--     ('sarah.johnson@dinkhouse.com', 'Sarah', 'Johnson', 'coach', 'Additional coach'),
--     ('robert.brown@dinkhouse.com', 'Robert', 'Brown', 'admin', 'Additional admin')
-- ON CONFLICT (email) DO NOTHING;