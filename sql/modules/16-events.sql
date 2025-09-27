-- ============================================================================
-- EVENTS MODULE
-- Calendar event management for pickleball sessions
-- ============================================================================

-- Drop schema if exists for clean rebuilds
DROP SCHEMA IF EXISTS events CASCADE;

-- Create events schema
CREATE SCHEMA events AUTHORIZATION postgres;
COMMENT ON SCHEMA events IS 'Calendar event management and court scheduling';

-- Grant usage on schema
GRANT USAGE ON SCHEMA events TO postgres;
GRANT CREATE ON SCHEMA events TO postgres;
GRANT USAGE ON SCHEMA events TO service_role;
GRANT USAGE ON SCHEMA events TO authenticated;
GRANT USAGE ON SCHEMA events TO anon;

-- ============================================================================
-- ENUMS AND TYPES
-- ============================================================================

CREATE TYPE events.event_type AS ENUM (
    'event_scramble',
    'dupr_open_play',
    'dupr_tournament',
    'non_dupr_tournament',
    'league',
    'clinic',
    'private_lesson'
);

CREATE TYPE events.court_surface AS ENUM (
    'hard',
    'clay',
    'grass',
    'indoor'
);

CREATE TYPE events.court_environment AS ENUM (
    'indoor',
    'outdoor'
);

CREATE TYPE events.court_status AS ENUM (
    'available',
    'maintenance',
    'reserved',
    'closed'
);

CREATE TYPE events.skill_level AS ENUM (
    '2.0', '2.5', '3.0', '3.5', '4.0', '4.5', '5.0', '5.0+'
);

CREATE TYPE events.recurrence_frequency AS ENUM (
    'daily',
    'weekly',
    'biweekly',
    'monthly',
    'custom'
);

CREATE TYPE events.registration_status AS ENUM (
    'registered',
    'waitlisted',
    'cancelled',
    'no_show'
);

-- ============================================================================
-- COURTS TABLE
-- ============================================================================

CREATE TABLE events.courts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    court_number INTEGER NOT NULL UNIQUE,
    name VARCHAR(100) NOT NULL,
    surface_type events.court_surface DEFAULT 'hard',
    environment events.court_environment NOT NULL DEFAULT 'indoor',
    status events.court_status DEFAULT 'available',
    location VARCHAR(100),
    features JSONB DEFAULT '[]'::jsonb, -- lights, covered, etc.
    max_capacity INTEGER DEFAULT 4,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE events.courts IS 'Physical courts available for booking';

-- Create indexes
CREATE INDEX idx_courts_status ON events.courts(status);
CREATE INDEX idx_courts_number ON events.courts(court_number);
CREATE INDEX idx_courts_environment ON events.courts(environment);

-- ============================================================================
-- DUPR BRACKETS TABLE
-- ============================================================================

CREATE TABLE events.dupr_brackets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    label VARCHAR(100) NOT NULL UNIQUE,
    min_rating NUMERIC(3, 2),
    min_inclusive BOOLEAN DEFAULT true,
    max_rating NUMERIC(3, 2),
    max_inclusive BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT dupr_bracket_presence CHECK (
        min_rating IS NOT NULL OR max_rating IS NOT NULL
    ),
    CONSTRAINT dupr_bracket_bounds CHECK (
        max_rating IS NULL OR min_rating IS NULL OR max_rating >= min_rating
    )
);

COMMENT ON TABLE events.dupr_brackets IS 'Standard DUPR rating brackets available for event configuration';

-- Create indexes
CREATE INDEX idx_dupr_brackets_min_rating ON events.dupr_brackets(min_rating);
CREATE INDEX idx_dupr_brackets_max_rating ON events.dupr_brackets(max_rating);

GRANT SELECT ON events.dupr_brackets TO service_role;
GRANT SELECT ON events.dupr_brackets TO authenticated;

-- ============================================================================
-- EVENT TEMPLATES TABLE
-- ============================================================================

CREATE TABLE events.event_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(200) NOT NULL,
    description TEXT,
    event_type events.event_type NOT NULL,
    duration_minutes INTEGER NOT NULL DEFAULT 120,
    max_capacity INTEGER DEFAULT 16,
    min_capacity INTEGER DEFAULT 4,
    skill_levels events.skill_level[] DEFAULT ARRAY['2.0', '2.5', '3.0', '3.5', '4.0', '4.5', '5.0']::events.skill_level[],
    price_member DECIMAL(10, 2) DEFAULT 0,
    price_guest DECIMAL(10, 2) DEFAULT 0,
    court_preferences JSONB DEFAULT '{"count": 2}'::jsonb,
    dupr_bracket_id UUID REFERENCES events.dupr_brackets(id),
    dupr_range_label VARCHAR(100),
    dupr_min_rating NUMERIC(3, 2),
    dupr_max_rating NUMERIC(3, 2),
    dupr_open_ended BOOLEAN DEFAULT false,
    dupr_min_inclusive BOOLEAN DEFAULT true,
    dupr_max_inclusive BOOLEAN DEFAULT true,
    equipment_provided BOOLEAN DEFAULT false,
    settings JSONB DEFAULT '{}'::jsonb,
    is_active BOOLEAN DEFAULT true,
    created_by UUID REFERENCES app_auth.admin_users(id),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT template_dupr_fields CHECK (
        CASE WHEN event_type IN ('dupr_open_play', 'dupr_tournament') THEN
            (
                (dupr_bracket_id IS NOT NULL)
                OR (dupr_range_label IS NOT NULL AND dupr_min_rating IS NOT NULL)
            )
            AND (dupr_open_ended = true OR dupr_max_rating IS NOT NULL)
        ELSE
            dupr_bracket_id IS NULL
            AND dupr_range_label IS NULL
            AND dupr_min_rating IS NULL
            AND dupr_max_rating IS NULL
            AND dupr_open_ended = false
            AND dupr_min_inclusive = true
            AND dupr_max_inclusive = true
        END
    ),
    CONSTRAINT template_dupr_bounds CHECK (
        dupr_max_rating IS NULL OR dupr_min_rating IS NULL OR dupr_max_rating >= dupr_min_rating
    ),
    CONSTRAINT template_dupr_open_ended CHECK (
        dupr_open_ended = false OR dupr_max_rating IS NULL
    )
);

COMMENT ON TABLE events.event_templates IS 'Reusable event configurations';

-- Create indexes
CREATE INDEX idx_event_templates_active ON events.event_templates(is_active);
CREATE INDEX idx_event_templates_type ON events.event_templates(event_type);
CREATE INDEX idx_event_templates_dupr_bracket ON events.event_templates(dupr_bracket_id);

-- ============================================================================
-- EVENTS TABLE
-- ============================================================================

CREATE TABLE events.events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title VARCHAR(200) NOT NULL,
    description TEXT,
    event_type events.event_type NOT NULL,
    template_id UUID REFERENCES events.event_templates(id) ON DELETE SET NULL,

    -- Scheduling
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    check_in_time TIMESTAMPTZ,

    -- Capacity
    max_capacity INTEGER DEFAULT 16,
    min_capacity INTEGER DEFAULT 4,
    current_registrations INTEGER DEFAULT 0,
    waitlist_capacity INTEGER DEFAULT 5,

    -- Requirements
    skill_levels events.skill_level[] DEFAULT ARRAY['2.0', '2.5', '3.0', '3.5', '4.0', '4.5', '5.0']::events.skill_level[],
    dupr_bracket_id UUID REFERENCES events.dupr_brackets(id),
    dupr_range_label VARCHAR(100),
    dupr_min_rating NUMERIC(3, 2),
    dupr_max_rating NUMERIC(3, 2),
    dupr_open_ended BOOLEAN DEFAULT false,
    dupr_min_inclusive BOOLEAN DEFAULT true,
    dupr_max_inclusive BOOLEAN DEFAULT true,
    member_only BOOLEAN DEFAULT false,

    -- Pricing
    price_member DECIMAL(10, 2) DEFAULT 0,
    price_guest DECIMAL(10, 2) DEFAULT 0,

    -- Status
    is_published BOOLEAN DEFAULT true,
    is_cancelled BOOLEAN DEFAULT false,
    cancellation_reason TEXT,

    -- Metadata
    equipment_provided BOOLEAN DEFAULT false,
    special_instructions TEXT,
    settings JSONB DEFAULT '{}'::jsonb,

    -- Tracking
    created_by UUID REFERENCES app_auth.admin_users(id),
    updated_by UUID REFERENCES app_auth.admin_users(id),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
    CONSTRAINT valid_time_range CHECK (end_time > start_time),
    CONSTRAINT valid_capacity CHECK (max_capacity >= min_capacity),
    CONSTRAINT valid_registrations CHECK (current_registrations >= 0),
    CONSTRAINT dupr_fields_required CHECK (
        CASE WHEN event_type IN ('dupr_open_play', 'dupr_tournament') THEN
            (
                (dupr_bracket_id IS NOT NULL)
                OR (dupr_range_label IS NOT NULL AND dupr_min_rating IS NOT NULL)
            )
            AND (dupr_open_ended = true OR dupr_max_rating IS NOT NULL)
        ELSE
            dupr_bracket_id IS NULL
            AND dupr_range_label IS NULL
            AND dupr_min_rating IS NULL
            AND dupr_max_rating IS NULL
            AND dupr_open_ended = false
            AND dupr_min_inclusive = true
            AND dupr_max_inclusive = true
        END
    ),
    CONSTRAINT dupr_bounds CHECK (
        dupr_max_rating IS NULL OR dupr_min_rating IS NULL OR dupr_max_rating >= dupr_min_rating
    ),
    CONSTRAINT dupr_open_ended CHECK (
        dupr_open_ended = false OR dupr_max_rating IS NULL
    )
);

COMMENT ON TABLE events.events IS 'Calendar events and sessions';

-- Create indexes
CREATE INDEX idx_events_start_time ON events.events(start_time);
CREATE INDEX idx_events_end_time ON events.events(end_time);
CREATE INDEX idx_events_type ON events.events(event_type);
CREATE INDEX idx_events_published ON events.events(is_published);
CREATE INDEX idx_events_cancelled ON events.events(is_cancelled);
CREATE INDEX idx_events_date_range ON events.events(start_time, end_time);
CREATE INDEX idx_events_dupr_bracket ON events.events(dupr_bracket_id);

-- ============================================================================
-- EVENT COURTS TABLE (Many-to-Many)
-- ============================================================================

CREATE TABLE events.event_courts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL REFERENCES events.events(id) ON DELETE CASCADE,
    court_id UUID NOT NULL REFERENCES events.courts(id) ON DELETE CASCADE,
    is_primary BOOLEAN DEFAULT false,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT unique_event_court UNIQUE(event_id, court_id)
);

COMMENT ON TABLE events.event_courts IS 'Courts assigned to events';

-- Create indexes
CREATE INDEX idx_event_courts_event ON events.event_courts(event_id);
CREATE INDEX idx_event_courts_court ON events.event_courts(court_id);

-- ============================================================================
-- RECURRENCE PATTERNS TABLE
-- ============================================================================

CREATE TABLE events.recurrence_patterns (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL REFERENCES events.events(id) ON DELETE CASCADE,
    frequency events.recurrence_frequency NOT NULL,
    interval_count INTEGER DEFAULT 1, -- every N days/weeks/months

    -- Weekly options
    days_of_week INTEGER[], -- 0=Sunday, 6=Saturday

    -- Monthly options
    day_of_month INTEGER, -- 1-31
    week_of_month INTEGER, -- 1-5 (5=last)

    -- Series info
    series_start_date DATE NOT NULL,
    series_end_date DATE,
    occurrences_count INTEGER,

    -- Metadata
    timezone VARCHAR(100) DEFAULT 'America/New_York',
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE events.recurrence_patterns IS 'Recurring event patterns';

-- Create indexes
CREATE INDEX idx_recurrence_event ON events.recurrence_patterns(event_id);
CREATE INDEX idx_recurrence_dates ON events.recurrence_patterns(series_start_date, series_end_date);

-- ============================================================================
-- EVENT SERIES TABLE
-- ============================================================================

CREATE TABLE events.event_series (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    series_name VARCHAR(200) NOT NULL,
    parent_event_id UUID REFERENCES events.events(id) ON DELETE SET NULL,
    recurrence_pattern_id UUID REFERENCES events.recurrence_patterns(id) ON DELETE CASCADE,
    created_by UUID REFERENCES app_auth.admin_users(id),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE events.event_series IS 'Groups of recurring events';

-- ============================================================================
-- EVENT SERIES INSTANCES TABLE
-- ============================================================================

CREATE TABLE events.event_series_instances (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    series_id UUID NOT NULL REFERENCES events.event_series(id) ON DELETE CASCADE,
    event_id UUID NOT NULL REFERENCES events.events(id) ON DELETE CASCADE,
    original_start_time TIMESTAMPTZ NOT NULL,
    is_exception BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT unique_series_event UNIQUE(series_id, event_id)
);

COMMENT ON TABLE events.event_series_instances IS 'Individual instances of recurring events';

-- Create indexes
CREATE INDEX idx_series_instances_series ON events.event_series_instances(series_id);
CREATE INDEX idx_series_instances_event ON events.event_series_instances(event_id);

-- ============================================================================
-- EVENT EXCEPTIONS TABLE
-- ============================================================================

CREATE TABLE events.event_exceptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recurrence_pattern_id UUID NOT NULL REFERENCES events.recurrence_patterns(id) ON DELETE CASCADE,
    exception_date DATE NOT NULL,
    reason TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT unique_pattern_exception UNIQUE(recurrence_pattern_id, exception_date)
);

COMMENT ON TABLE events.event_exceptions IS 'Dates to skip in recurring patterns';

-- Create indexes
CREATE INDEX idx_exceptions_pattern ON events.event_exceptions(recurrence_pattern_id);
CREATE INDEX idx_exceptions_date ON events.event_exceptions(exception_date);

-- ============================================================================
-- EVENT REGISTRATIONS TABLE
-- ============================================================================

CREATE TABLE events.event_registrations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL REFERENCES events.events(id) ON DELETE CASCADE,
    user_id UUID REFERENCES app_auth.players(id) ON DELETE SET NULL,

    -- Player info (for guests)
    player_name VARCHAR(200),
    player_email VARCHAR(255),
    player_phone VARCHAR(50),
    skill_level events.skill_level,
    dupr_rating NUMERIC(3, 2),

    -- Registration details
    status events.registration_status DEFAULT 'registered',
    registration_time TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    check_in_time TIMESTAMPTZ,

    -- Payment
    amount_paid DECIMAL(10, 2) DEFAULT 0,
    payment_method VARCHAR(50),
    payment_reference VARCHAR(200),

    -- Notes
    notes TEXT,
    special_requests TEXT,

    -- Metadata
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT unique_event_user UNIQUE(event_id, user_id),
    CONSTRAINT player_info_required CHECK (
        user_id IS NOT NULL OR
        (player_name IS NOT NULL AND player_email IS NOT NULL)
    )
);

COMMENT ON TABLE events.event_registrations IS 'Player registrations for events';

-- Create indexes
CREATE INDEX idx_registrations_event ON events.event_registrations(event_id);
CREATE INDEX idx_registrations_user ON events.event_registrations(user_id);
CREATE INDEX idx_registrations_status ON events.event_registrations(status);
CREATE INDEX idx_registrations_time ON events.event_registrations(registration_time);

-- ============================================================================
-- COURT AVAILABILITY TABLE
-- ============================================================================

CREATE TABLE events.court_availability (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    court_id UUID NOT NULL REFERENCES events.courts(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    is_available BOOLEAN DEFAULT true,
    reason VARCHAR(200),
    created_by UUID REFERENCES app_auth.admin_users(id),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT valid_availability_time CHECK (end_time > start_time),
    CONSTRAINT unique_court_availability UNIQUE(court_id, date, start_time, end_time)
);

COMMENT ON TABLE events.court_availability IS 'Court availability schedule';

-- Create indexes
CREATE INDEX idx_availability_court ON events.court_availability(court_id);
CREATE INDEX idx_availability_date ON events.court_availability(date);
CREATE INDEX idx_availability_available ON events.court_availability(is_available);

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Update timestamp trigger
CREATE OR REPLACE FUNCTION events.update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply update trigger to relevant tables
CREATE TRIGGER update_courts_updated_at
    BEFORE UPDATE ON events.courts
    FOR EACH ROW EXECUTE FUNCTION events.update_updated_at();

CREATE TRIGGER update_dupr_brackets_updated_at
    BEFORE UPDATE ON events.dupr_brackets
    FOR EACH ROW EXECUTE FUNCTION events.update_updated_at();

CREATE TRIGGER update_templates_updated_at
    BEFORE UPDATE ON events.event_templates
    FOR EACH ROW EXECUTE FUNCTION events.update_updated_at();

CREATE TRIGGER update_events_updated_at
    BEFORE UPDATE ON events.events
    FOR EACH ROW EXECUTE FUNCTION events.update_updated_at();

CREATE TRIGGER update_registrations_updated_at
    BEFORE UPDATE ON events.event_registrations
    FOR EACH ROW EXECUTE FUNCTION events.update_updated_at();

-- Update registration count trigger
CREATE OR REPLACE FUNCTION events.update_registration_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' AND NEW.status = 'registered' THEN
        UPDATE events.events
        SET current_registrations = current_registrations + 1
        WHERE id = NEW.event_id;
    ELSIF TG_OP = 'DELETE' AND OLD.status = 'registered' THEN
        UPDATE events.events
        SET current_registrations = current_registrations - 1
        WHERE id = OLD.event_id;
    ELSIF TG_OP = 'UPDATE' THEN
        IF OLD.status = 'registered' AND NEW.status != 'registered' THEN
            UPDATE events.events
            SET current_registrations = current_registrations - 1
            WHERE id = NEW.event_id;
        ELSIF OLD.status != 'registered' AND NEW.status = 'registered' THEN
            UPDATE events.events
            SET current_registrations = current_registrations + 1
            WHERE id = NEW.event_id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_event_registration_count
    AFTER INSERT OR UPDATE OR DELETE ON events.event_registrations
    FOR EACH ROW EXECUTE FUNCTION events.update_registration_count();
