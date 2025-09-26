-- ============================================================================
-- CONTACT MANAGEMENT MODULE
-- Contact form submissions and inquiry management
-- ============================================================================

-- Set search path for contact schema
SET search_path TO contact, public;

-- Contact form configurations
CREATE TABLE IF NOT EXISTS contact.contact_forms (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(255) UNIQUE NOT NULL,
    description TEXT,
    fields JSONB NOT NULL DEFAULT '[]',
    email_recipients TEXT[],
    success_message TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Contact inquiries
CREATE TABLE IF NOT EXISTS contact.contact_inquiries (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    form_id UUID REFERENCES contact.contact_forms(id) ON DELETE SET NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email public.CITEXT NOT NULL,
    phone VARCHAR(30),
    company VARCHAR(255),
    job_title VARCHAR(255),
    subject VARCHAR(255),
    message TEXT NOT NULL,
    custom_fields JSONB DEFAULT '{}',
    source VARCHAR(100) DEFAULT 'website'
        CHECK (source IN ('website', 'landing_page', 'referral', 'social_media', 'email', 'phone', 'other')),
    source_details JSONB DEFAULT '{}',
    status VARCHAR(50) DEFAULT 'new'
        CHECK (status IN ('new', 'in_progress', 'responded', 'resolved', 'closed', 'spam')),
    priority VARCHAR(20) DEFAULT 'medium'
        CHECK (priority IN ('low', 'medium', 'high', 'urgent')),
    tags TEXT[],
    assigned_to UUID REFERENCES app_auth.users(id) ON DELETE SET NULL,
    responded_at TIMESTAMP WITH TIME ZONE,
    resolved_at TIMESTAMP WITH TIME ZONE,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Contact inquiry responses
CREATE TABLE IF NOT EXISTS contact.contact_responses (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    inquiry_id UUID NOT NULL REFERENCES contact.contact_inquiries(id) ON DELETE CASCADE,
    responder_id UUID NOT NULL REFERENCES app_auth.users(id) ON DELETE RESTRICT,
    response_type VARCHAR(50) DEFAULT 'email'
        CHECK (response_type IN ('email', 'phone', 'internal_note')),
    subject VARCHAR(255),
    message TEXT NOT NULL,
    is_internal BOOLEAN DEFAULT false,
    sent_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Contact blacklist for spam prevention
CREATE TABLE IF NOT EXISTS contact.contact_blacklist (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    email public.CITEXT,
    ip_address INET,
    reason TEXT,
    expires_at TIMESTAMP WITH TIME ZONE,
    created_by UUID REFERENCES app_auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for contact tables
CREATE INDEX inquiries_email ON contact.contact_inquiries(email);
CREATE INDEX inquiries_status ON contact.contact_inquiries(status);
CREATE INDEX inquiries_priority ON contact.contact_inquiries(priority);
CREATE INDEX inquiries_assigned_to ON contact.contact_inquiries(assigned_to);
CREATE INDEX inquiries_created_at ON contact.contact_inquiries(created_at);
CREATE INDEX responses_inquiry_id ON contact.contact_responses(inquiry_id);
CREATE INDEX blacklist_email ON contact.contact_blacklist(email);
CREATE INDEX blacklist_ip_address ON contact.contact_blacklist(ip_address);