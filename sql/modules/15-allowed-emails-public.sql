-- ============================================================================
-- ALLOWED EMAILS MODULE (PUBLIC SCHEMA)
-- Manage pre-authorized email addresses for sign-up
-- Using public schema since auth schema is managed by Supabase
-- ============================================================================

-- Use public schema
SET search_path TO public;

-- Drop the auth schema table if it exists (cleanup)
DROP TABLE IF EXISTS app_auth.allowed_emails CASCADE;

-- Table for storing allowed email addresses for sign-up
CREATE TABLE IF NOT EXISTS public.allowed_emails (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email CITEXT UNIQUE NOT NULL,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    role VARCHAR(50) DEFAULT 'viewer'
        CHECK (role IN ('super_admin', 'admin', 'editor', 'viewer', 'manager', 'coach')),
    added_by UUID,
    notes TEXT,
    is_active BOOLEAN DEFAULT true,
    used_at TIMESTAMP WITH TIME ZONE,
    used_by UUID,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_allowed_emails_email ON public.allowed_emails(email);
CREATE INDEX IF NOT EXISTS idx_allowed_emails_is_active ON public.allowed_emails(is_active);
CREATE INDEX IF NOT EXISTS idx_allowed_emails_created_at ON public.allowed_emails(created_at DESC);

-- Add comment on table
COMMENT ON TABLE public.allowed_emails IS 'Pre-authorized email addresses that are allowed to sign up';
COMMENT ON COLUMN public.allowed_emails.email IS 'The email address that is allowed to sign up';
COMMENT ON COLUMN public.allowed_emails.role IS 'The default role to assign when this email signs up';
COMMENT ON COLUMN public.allowed_emails.added_by IS 'The user who added this email to the allowed list';
COMMENT ON COLUMN public.allowed_emails.used_at IS 'When this email was used to sign up';
COMMENT ON COLUMN public.allowed_emails.used_by IS 'The user ID created when this email signed up';

-- Function to check if an email is allowed to sign up
CREATE OR REPLACE FUNCTION public.is_email_allowed(check_email TEXT)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1
        FROM public.allowed_emails
        WHERE email = LOWER(check_email)
        AND is_active = true
        AND used_at IS NULL
    );
END;
$$ LANGUAGE plpgsql;

-- Function to mark an allowed email as used
CREATE OR REPLACE FUNCTION public.mark_email_used(
    used_email TEXT,
    user_id UUID
)
RETURNS VOID AS $$
BEGIN
    UPDATE public.allowed_emails
    SET
        used_at = CURRENT_TIMESTAMP,
        used_by = user_id,
        updated_at = CURRENT_TIMESTAMP
    WHERE email = LOWER(used_email);
END;
$$ LANGUAGE plpgsql;

-- Enable RLS (Row Level Security)
ALTER TABLE public.allowed_emails ENABLE ROW LEVEL SECURITY;

-- Create policies for public access (adjust as needed)
CREATE POLICY "Enable read access for all users" ON public.allowed_emails
    FOR SELECT USING (true);

CREATE POLICY "Enable insert for authenticated users" ON public.allowed_emails
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Enable update for authenticated users" ON public.allowed_emails
    FOR UPDATE USING (true);

CREATE POLICY "Enable delete for authenticated users" ON public.allowed_emails
    FOR DELETE USING (true);