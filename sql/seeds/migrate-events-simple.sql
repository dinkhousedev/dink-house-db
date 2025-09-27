-- Simple Events Migration for port 9432
-- Creates events tables without auth dependencies

-- Use events schema
SET search_path TO events, public;

-- Courts table
CREATE TABLE IF NOT EXISTS events.courts (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    court_number INT NOT NULL UNIQUE,
    name VARCHAR(100) NOT NULL,
    surface_type VARCHAR(20) NOT NULL DEFAULT 'hard',
    status VARCHAR(20) NOT NULL DEFAULT 'available',
    location VARCHAR(255),
    features TEXT[],
    max_capacity INT DEFAULT 4,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Events table
CREATE TABLE IF NOT EXISTS events.events (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    event_type VARCHAR(50) NOT NULL,
    template_id UUID,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    check_in_time TIMESTAMPTZ,
    max_capacity INT NOT NULL,
    min_capacity INT DEFAULT 1,
    current_registrations INT DEFAULT 0,
    waitlist_capacity INT DEFAULT 5,
    skill_levels TEXT[],
    member_only BOOLEAN DEFAULT false,
    price_member DECIMAL(10,2) DEFAULT 0,
    price_guest DECIMAL(10,2) DEFAULT 0,
    is_published BOOLEAN DEFAULT true,
    is_cancelled BOOLEAN DEFAULT false,
    cancellation_reason TEXT,
    equipment_provided BOOLEAN DEFAULT false,
    special_instructions TEXT,
    settings JSONB DEFAULT '{}',
    created_by UUID,
    updated_by UUID,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Event courts junction table
CREATE TABLE IF NOT EXISTS events.event_courts (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    event_id UUID NOT NULL REFERENCES events.events(id) ON DELETE CASCADE,
    court_id UUID NOT NULL REFERENCES events.courts(id),
    is_primary BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Event templates table
CREATE TABLE IF NOT EXISTS events.event_templates (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    event_type VARCHAR(50) NOT NULL,
    duration_minutes INT NOT NULL,
    max_capacity INT NOT NULL,
    min_capacity INT DEFAULT 1,
    skill_levels TEXT[],
    price_member DECIMAL(10,2) DEFAULT 0,
    price_guest DECIMAL(10,2) DEFAULT 0,
    court_preferences JSONB DEFAULT '{}',
    equipment_provided BOOLEAN DEFAULT false,
    settings JSONB DEFAULT '{}',
    is_active BOOLEAN DEFAULT true,
    times_used INT DEFAULT 0,
    last_used TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Event registrations table
CREATE TABLE IF NOT EXISTS events.event_registrations (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    event_id UUID NOT NULL REFERENCES events.events(id) ON DELETE CASCADE,
    user_id UUID,
    player_name VARCHAR(255),
    player_email VARCHAR(255),
    player_phone VARCHAR(20),
    skill_level VARCHAR(10),
    status VARCHAR(20) NOT NULL DEFAULT 'registered',
    registration_time TIMESTAMPTZ DEFAULT NOW(),
    check_in_time TIMESTAMPTZ,
    amount_paid DECIMAL(10,2) DEFAULT 0,
    payment_method VARCHAR(50),
    payment_reference VARCHAR(255),
    notes TEXT,
    special_requests TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_events_start_time ON events.events(start_time);
CREATE INDEX IF NOT EXISTS idx_events_event_type ON events.events(event_type);
CREATE INDEX IF NOT EXISTS idx_events_is_cancelled ON events.events(is_cancelled);
CREATE INDEX IF NOT EXISTS idx_event_courts_event_id ON events.event_courts(event_id);
CREATE INDEX IF NOT EXISTS idx_event_courts_court_id ON events.event_courts(court_id);
CREATE INDEX IF NOT EXISTS idx_event_registrations_event_id ON events.event_registrations(event_id);
CREATE INDEX IF NOT EXISTS idx_event_registrations_user_id ON events.event_registrations(user_id);

-- Create views in public schema for Supabase access
CREATE OR REPLACE VIEW public.events AS SELECT * FROM events.events;
CREATE OR REPLACE VIEW public.courts AS SELECT * FROM events.courts;
CREATE OR REPLACE VIEW public.event_courts AS SELECT * FROM events.event_courts;
CREATE OR REPLACE VIEW public.event_templates AS SELECT * FROM events.event_templates;
CREATE OR REPLACE VIEW public.event_registrations AS SELECT * FROM events.event_registrations;

-- Grant permissions (adjust roles as needed)
GRANT ALL ON SCHEMA events TO postgres;
GRANT ALL ON ALL TABLES IN SCHEMA events TO postgres;
GRANT ALL ON ALL SEQUENCES IN SCHEMA events TO postgres;

-- Grant permissions on public views
GRANT ALL ON public.events TO postgres;
GRANT ALL ON public.courts TO postgres;
GRANT ALL ON public.event_courts TO postgres;
GRANT ALL ON public.event_templates TO postgres;
GRANT ALL ON public.event_registrations TO postgres;

-- Update function for updated_at
CREATE OR REPLACE FUNCTION events.update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triggers for updated_at
DROP TRIGGER IF EXISTS update_courts_updated_at ON events.courts;
CREATE TRIGGER update_courts_updated_at BEFORE UPDATE ON events.courts
    FOR EACH ROW EXECUTE FUNCTION events.update_updated_at();

DROP TRIGGER IF EXISTS update_events_updated_at ON events.events;
CREATE TRIGGER update_events_updated_at BEFORE UPDATE ON events.events
    FOR EACH ROW EXECUTE FUNCTION events.update_updated_at();

DROP TRIGGER IF EXISTS update_event_templates_updated_at ON events.event_templates;
CREATE TRIGGER update_event_templates_updated_at BEFORE UPDATE ON events.event_templates
    FOR EACH ROW EXECUTE FUNCTION events.update_updated_at();

DROP TRIGGER IF EXISTS update_event_registrations_updated_at ON events.event_registrations;
CREATE TRIGGER update_event_registrations_updated_at BEFORE UPDATE ON events.event_registrations
    FOR EACH ROW EXECUTE FUNCTION events.update_updated_at();