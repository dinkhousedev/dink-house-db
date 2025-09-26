-- ============================================================================
-- CONTACT NOTIFICATION TABLE
-- Simple table for waitlist and notification signups
-- ============================================================================

-- Set search path for contact schema
SET search_path TO contact, public;

-- Create contact_notification table
CREATE TABLE IF NOT EXISTS contact.contact_notification (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email public.CITEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create index on email for faster lookups
CREATE INDEX IF NOT EXISTS idx_contact_notification_email ON contact.contact_notification(email);

-- Create index on created_at for sorting
CREATE INDEX IF NOT EXISTS idx_contact_notification_created_at ON contact.contact_notification(created_at DESC);

-- Add comment to table
COMMENT ON TABLE contact.contact_notification IS 'Stores waitlist and notification signup information';
COMMENT ON COLUMN contact.contact_notification.id IS 'Unique identifier for the notification signup';
COMMENT ON COLUMN contact.contact_notification.first_name IS 'First name of the person signing up';
COMMENT ON COLUMN contact.contact_notification.last_name IS 'Last name of the person signing up';
COMMENT ON COLUMN contact.contact_notification.email IS 'Email address for notifications';
COMMENT ON COLUMN contact.contact_notification.created_at IS 'Timestamp when the signup occurred';