# Tournament Management System - Database Schema

## Schema Overview

The tournament management system extends the existing Dink House database with a comprehensive set of tables designed to handle all aspects of tournament operations. The schema follows PostgreSQL best practices with proper indexing, constraints, and relationships.

## Database Design Principles

1. **Normalization**: 3NF to minimize redundancy
2. **Audit Trail**: All tables include created_at, updated_at, and soft delete
3. **UUID Keys**: Use UUIDs for all primary keys
4. **Timezone Handling**: All timestamps in UTC with timezone
5. **JSON Flexibility**: JSONB for extensible metadata
6. **Row-Level Security**: Supabase RLS policies for access control

## Core Tournament Tables

### tournaments

```sql
CREATE TABLE tournaments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Basic Information
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(255) UNIQUE NOT NULL,
    description TEXT,
    rules_document_url VARCHAR(500),

    -- Tournament Type
    tournament_type VARCHAR(50) NOT NULL, -- 'single_elimination', 'double_elimination', 'round_robin', 'pool_play'
    sport VARCHAR(50) DEFAULT 'pickleball',
    format VARCHAR(50) NOT NULL, -- 'singles', 'doubles', 'mixed_doubles'

    -- Dates and Schedule
    registration_opens_at TIMESTAMPTZ NOT NULL,
    registration_closes_at TIMESTAMPTZ NOT NULL,
    early_bird_ends_at TIMESTAMPTZ,
    check_in_starts_at TIMESTAMPTZ NOT NULL,
    event_starts_at TIMESTAMPTZ NOT NULL,
    event_ends_at TIMESTAMPTZ NOT NULL,
    rain_dates JSONB DEFAULT '[]'::jsonb, -- Array of alternate dates

    -- Venue Information
    venue_id UUID REFERENCES venues(id),
    venue_name VARCHAR(255) NOT NULL,
    venue_address TEXT NOT NULL,
    venue_map_url VARCHAR(500),
    parking_info TEXT,

    -- Capacity and Limits
    max_teams_total INTEGER,
    min_teams_total INTEGER DEFAULT 8,
    max_waitlist_size INTEGER DEFAULT 20,

    -- Pricing
    base_price_member DECIMAL(10, 2) NOT NULL,
    base_price_guest DECIMAL(10, 2) NOT NULL,
    early_bird_discount_percent INTEGER DEFAULT 0,
    late_fee_amount DECIMAL(10, 2) DEFAULT 0,

    -- Status and Visibility
    status VARCHAR(50) DEFAULT 'draft', -- 'draft', 'published', 'registration_open', 'in_progress', 'completed', 'cancelled'
    is_featured BOOLEAN DEFAULT FALSE,
    is_members_only BOOLEAN DEFAULT FALSE,
    requires_approval BOOLEAN DEFAULT FALSE,

    -- Settings
    allow_substitutes BOOLEAN DEFAULT TRUE,
    allow_refunds BOOLEAN DEFAULT TRUE,
    refund_deadline_hours INTEGER DEFAULT 48,
    send_reminders BOOLEAN DEFAULT TRUE,
    reminder_schedule JSONB DEFAULT '[]'::jsonb, -- Array of hours before event

    -- Contact Information
    director_name VARCHAR(255) NOT NULL,
    director_email VARCHAR(255) NOT NULL,
    director_phone VARCHAR(50),
    support_email VARCHAR(255),

    -- Metadata
    tags JSONB DEFAULT '[]'::jsonb,
    sponsor_info JSONB DEFAULT '{}'::jsonb,
    custom_fields JSONB DEFAULT '{}'::jsonb,

    -- Audit
    created_by UUID REFERENCES auth.users(id),
    updated_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMPTZ
);

CREATE INDEX idx_tournaments_status ON tournaments(status);
CREATE INDEX idx_tournaments_dates ON tournaments(event_starts_at, event_ends_at);
CREATE INDEX idx_tournaments_slug ON tournaments(slug);
```

### tournament_divisions

```sql
CREATE TABLE tournament_divisions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tournament_id UUID NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,

    -- Division Information
    name VARCHAR(255) NOT NULL,
    code VARCHAR(50) NOT NULL, -- 'MD35', 'WD40', etc.
    description TEXT,
    sort_order INTEGER DEFAULT 0,

    -- Skill Requirements
    skill_level_min VARCHAR(10), -- '2.5', '3.0', etc.
    skill_level_max VARCHAR(10),
    age_min INTEGER,
    age_max INTEGER,
    gender_restriction VARCHAR(20), -- 'male', 'female', 'mixed', null

    -- DUPR Integration
    uses_dupr BOOLEAN DEFAULT FALSE,
    dupr_min_combined DECIMAL(5, 2),
    dupr_max_combined DECIMAL(5, 2),
    dupr_max_spread DECIMAL(5, 2), -- Max difference between partners
    dupr_bracket_id VARCHAR(100),

    -- Capacity
    max_teams INTEGER NOT NULL,
    min_teams INTEGER DEFAULT 4,
    current_teams_count INTEGER DEFAULT 0,
    waitlist_count INTEGER DEFAULT 0,

    -- Schedule
    estimated_start_time TIMESTAMPTZ,
    estimated_duration_hours DECIMAL(3, 1),
    court_assignments JSONB DEFAULT '[]'::jsonb, -- Array of court IDs

    -- Pricing (if different from tournament base)
    price_member DECIMAL(10, 2),
    price_guest DECIMAL(10, 2),

    -- Format
    bracket_type VARCHAR(50), -- Inherits from tournament if null
    games_per_match INTEGER DEFAULT 1,
    points_per_game INTEGER DEFAULT 11,
    win_by INTEGER DEFAULT 2,

    -- Status
    status VARCHAR(50) DEFAULT 'open', -- 'open', 'closed', 'in_progress', 'completed'
    registration_closed BOOLEAN DEFAULT FALSE,

    -- Metadata
    rules_variations TEXT,
    custom_fields JSONB DEFAULT '{}'::jsonb,

    -- Audit
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    UNIQUE(tournament_id, code)
);

CREATE INDEX idx_divisions_tournament ON tournament_divisions(tournament_id);
CREATE INDEX idx_divisions_status ON tournament_divisions(status);
```

### tournament_teams

```sql
CREATE TABLE tournament_teams (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tournament_id UUID NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
    division_id UUID NOT NULL REFERENCES tournament_divisions(id) ON DELETE CASCADE,

    -- Team Information
    team_name VARCHAR(255),
    team_code VARCHAR(50) UNIQUE NOT NULL, -- Auto-generated: 'DH2024-001'

    -- Players
    player1_id UUID REFERENCES auth.users(id),
    player1_name VARCHAR(255) NOT NULL,
    player1_email VARCHAR(255) NOT NULL,
    player1_phone VARCHAR(50),
    player1_dupr_id VARCHAR(100),
    player1_dupr_rating DECIMAL(4, 2),
    player1_skill_level VARCHAR(10),

    player2_id UUID REFERENCES auth.users(id),
    player2_name VARCHAR(255) NOT NULL,
    player2_email VARCHAR(255) NOT NULL,
    player2_phone VARCHAR(50),
    player2_dupr_id VARCHAR(100),
    player2_dupr_rating DECIMAL(4, 2),
    player2_skill_level VARCHAR(10),

    -- DUPR Validation
    combined_dupr_rating DECIMAL(5, 2),
    dupr_verified BOOLEAN DEFAULT FALSE,
    dupr_verified_at TIMESTAMPTZ,

    -- Registration Details
    registration_type VARCHAR(50) DEFAULT 'standard', -- 'early_bird', 'standard', 'late'
    registered_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    registered_by UUID REFERENCES auth.users(id),

    -- Status
    status VARCHAR(50) DEFAULT 'pending', -- 'pending', 'confirmed', 'waitlisted', 'withdrawn', 'no_show'
    seed_number INTEGER,
    checked_in BOOLEAN DEFAULT FALSE,
    checked_in_at TIMESTAMPTZ,
    checked_in_by UUID REFERENCES auth.users(id),

    -- Payment
    payment_status VARCHAR(50) DEFAULT 'pending', -- 'pending', 'partial', 'completed', 'refunded'
    payment_amount DECIMAL(10, 2),
    payment_split BOOLEAN DEFAULT FALSE,
    player1_paid DECIMAL(10, 2) DEFAULT 0,
    player2_paid DECIMAL(10, 2) DEFAULT 0,

    -- Waivers and Documents
    waiver_signed BOOLEAN DEFAULT FALSE,
    waiver_signed_at TIMESTAMPTZ,
    medical_info JSONB DEFAULT '{}'::jsonb,
    emergency_contact JSONB DEFAULT '{}'::jsonb,

    -- Substitutions
    has_substitute BOOLEAN DEFAULT FALSE,
    substitute_for_player INTEGER, -- 1 or 2
    original_player_data JSONB, -- Store original player info
    substitute_approved BOOLEAN,
    substitute_approved_by UUID REFERENCES auth.users(id),

    -- Communication Preferences
    accepts_emails BOOLEAN DEFAULT TRUE,
    accepts_sms BOOLEAN DEFAULT TRUE,
    preferred_contact VARCHAR(20) DEFAULT 'email',

    -- Notes
    internal_notes TEXT, -- Staff only
    player_notes TEXT, -- From registration

    -- Metadata
    custom_fields JSONB DEFAULT '{}'::jsonb,

    -- Audit
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    withdrawn_at TIMESTAMPTZ,
    withdrawn_reason TEXT
);

CREATE INDEX idx_teams_tournament ON tournament_teams(tournament_id);
CREATE INDEX idx_teams_division ON tournament_teams(division_id);
CREATE INDEX idx_teams_status ON tournament_teams(status);
CREATE INDEX idx_teams_players ON tournament_teams(player1_id, player2_id);
```

### tournament_matches

```sql
CREATE TABLE tournament_matches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tournament_id UUID NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
    division_id UUID NOT NULL REFERENCES tournament_divisions(id) ON DELETE CASCADE,

    -- Match Identification
    match_number INTEGER NOT NULL,
    round_number INTEGER NOT NULL,
    round_name VARCHAR(50), -- 'Round of 16', 'Quarterfinals', etc.
    bracket_position VARCHAR(50), -- 'W1', 'L3', etc. for double elimination

    -- Teams
    team1_id UUID REFERENCES tournament_teams(id),
    team2_id UUID REFERENCES tournament_teams(id),

    -- Scheduling
    scheduled_time TIMESTAMPTZ,
    estimated_duration_minutes INTEGER DEFAULT 45,
    court_id UUID REFERENCES events.courts(id),
    court_number INTEGER,

    -- Status
    status VARCHAR(50) DEFAULT 'pending', -- 'pending', 'ready', 'in_progress', 'completed', 'forfeit', 'bye'
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,

    -- Scoring
    games_data JSONB DEFAULT '[]'::jsonb, -- Array of game scores
    /* Example:
    [
        {
            "game_number": 1,
            "team1_score": 11,
            "team2_score": 9,
            "duration_minutes": 18
        }
    ]
    */
    team1_games_won INTEGER DEFAULT 0,
    team2_games_won INTEGER DEFAULT 0,
    winner_id UUID REFERENCES tournament_teams(id),

    -- Match Details
    is_consolation BOOLEAN DEFAULT FALSE,
    is_third_place BOOLEAN DEFAULT FALSE,
    is_final BOOLEAN DEFAULT FALSE,
    referee_id UUID REFERENCES auth.users(id),

    -- Score Entry
    score_entered_by UUID REFERENCES auth.users(id),
    score_confirmed_by UUID REFERENCES auth.users(id),
    score_disputed BOOLEAN DEFAULT FALSE,
    dispute_notes TEXT,

    -- Next Match Progression
    winner_to_match_id UUID REFERENCES tournament_matches(id),
    winner_to_position VARCHAR(10), -- 'team1' or 'team2'
    loser_to_match_id UUID REFERENCES tournament_matches(id),
    loser_to_position VARCHAR(10),

    -- Live Updates
    live_stream_url VARCHAR(500),
    court_monitor_id UUID REFERENCES auth.users(id),
    last_update_at TIMESTAMPTZ,

    -- Metadata
    notes TEXT,
    stats JSONB DEFAULT '{}'::jsonb, -- Additional statistics

    -- Audit
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_matches_tournament ON tournament_matches(tournament_id);
CREATE INDEX idx_matches_division ON tournament_matches(division_id);
CREATE INDEX idx_matches_status ON tournament_matches(status);
CREATE INDEX idx_matches_schedule ON tournament_matches(scheduled_time);
CREATE INDEX idx_matches_court ON tournament_matches(court_id);
```

### tournament_brackets

```sql
CREATE TABLE tournament_brackets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    division_id UUID NOT NULL REFERENCES tournament_divisions(id) ON DELETE CASCADE,

    -- Bracket Configuration
    bracket_type VARCHAR(50) NOT NULL, -- 'single_elimination', 'double_elimination', 'round_robin'
    total_rounds INTEGER NOT NULL,
    consolation_rounds INTEGER DEFAULT 0,

    -- Seeding
    seeding_method VARCHAR(50) DEFAULT 'random', -- 'random', 'dupr', 'manual', 'snake'
    seeds JSONB NOT NULL, -- Array mapping seed numbers to team IDs

    -- Bracket Structure
    structure JSONB NOT NULL, -- Complete bracket structure
    /* Example:
    {
        "rounds": [
            {
                "round_number": 1,
                "matches": [
                    {
                        "match_number": 1,
                        "team1_seed": 1,
                        "team2_seed": 16
                    }
                ]
            }
        ]
    }
    */

    -- Status
    generated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    generated_by UUID REFERENCES auth.users(id),
    is_finalized BOOLEAN DEFAULT FALSE,
    finalized_at TIMESTAMPTZ,

    -- Pool Play Specific
    pools_config JSONB, -- For round robin/pool play

    -- Metadata
    generation_notes TEXT,
    custom_config JSONB DEFAULT '{}'::jsonb,

    -- Audit
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_brackets_division ON tournament_brackets(division_id);
```

## Supporting Tables

### tournament_staff

```sql
CREATE TABLE tournament_staff (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tournament_id UUID NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id),

    -- Role and Permissions
    role VARCHAR(50) NOT NULL, -- 'director', 'admin', 'court_monitor', 'referee', 'medical', 'volunteer'
    permissions JSONB DEFAULT '{}'::jsonb,

    -- Assignment
    assigned_courts JSONB DEFAULT '[]'::jsonb, -- Array of court IDs
    shift_start TIMESTAMPTZ,
    shift_end TIMESTAMPTZ,

    -- Status
    status VARCHAR(50) DEFAULT 'assigned', -- 'assigned', 'checked_in', 'on_break', 'checked_out'
    checked_in_at TIMESTAMPTZ,
    checked_out_at TIMESTAMPTZ,

    -- Contact
    phone VARCHAR(50),
    emergency_contact JSONB,

    -- Training
    training_completed BOOLEAN DEFAULT FALSE,
    training_completed_at TIMESTAMPTZ,
    certifications JSONB DEFAULT '[]'::jsonb,

    -- Notes
    notes TEXT,

    -- Audit
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    UNIQUE(tournament_id, user_id)
);

CREATE INDEX idx_staff_tournament ON tournament_staff(tournament_id);
CREATE INDEX idx_staff_user ON tournament_staff(user_id);
CREATE INDEX idx_staff_role ON tournament_staff(role);
```

### tournament_payments

```sql
CREATE TABLE tournament_payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tournament_id UUID NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
    team_id UUID NOT NULL REFERENCES tournament_teams(id) ON DELETE CASCADE,

    -- Payment Details
    amount DECIMAL(10, 2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',
    payment_method VARCHAR(50) NOT NULL, -- 'credit_card', 'paypal', 'cash', 'check'

    -- Transaction
    transaction_id VARCHAR(255) UNIQUE,
    processor VARCHAR(50), -- 'stripe', 'paypal', 'manual'
    processor_fee DECIMAL(10, 2) DEFAULT 0,
    net_amount DECIMAL(10, 2),

    -- Status
    status VARCHAR(50) NOT NULL, -- 'pending', 'processing', 'completed', 'failed', 'refunded'
    paid_at TIMESTAMPTZ,

    -- Payer Information
    payer_id UUID REFERENCES auth.users(id),
    payer_email VARCHAR(255) NOT NULL,
    payer_name VARCHAR(255) NOT NULL,
    billing_address JSONB,

    -- Split Payment
    is_split_payment BOOLEAN DEFAULT FALSE,
    split_for_player INTEGER, -- 1 or 2, or null for full payment

    -- Refund
    refunded_amount DECIMAL(10, 2) DEFAULT 0,
    refund_reason TEXT,
    refunded_at TIMESTAMPTZ,
    refund_transaction_id VARCHAR(255),

    -- Metadata
    invoice_number VARCHAR(100),
    receipt_url VARCHAR(500),
    notes TEXT,
    metadata JSONB DEFAULT '{}'::jsonb,

    -- Audit
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_payments_tournament ON tournament_payments(tournament_id);
CREATE INDEX idx_payments_team ON tournament_payments(team_id);
CREATE INDEX idx_payments_status ON tournament_payments(status);
CREATE INDEX idx_payments_transaction ON tournament_payments(transaction_id);
```

### tournament_communications

```sql
CREATE TABLE tournament_communications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tournament_id UUID NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,

    -- Message Details
    subject VARCHAR(500) NOT NULL,
    content TEXT NOT NULL,
    content_html TEXT,

    -- Type and Channel
    message_type VARCHAR(50) NOT NULL, -- 'registration_confirm', 'reminder', 'update', 'result', 'custom'
    channel VARCHAR(20) NOT NULL, -- 'email', 'sms', 'push', 'in_app'

    -- Recipients
    recipient_type VARCHAR(50) NOT NULL, -- 'all', 'division', 'team', 'individual', 'staff'
    recipient_filters JSONB DEFAULT '{}'::jsonb,
    recipient_count INTEGER DEFAULT 0,
    recipients JSONB DEFAULT '[]'::jsonb, -- Array of recipient details

    -- Scheduling
    scheduled_for TIMESTAMPTZ,
    sent_at TIMESTAMPTZ,

    -- Status
    status VARCHAR(50) DEFAULT 'draft', -- 'draft', 'scheduled', 'sending', 'sent', 'failed'

    -- Delivery Stats
    delivered_count INTEGER DEFAULT 0,
    failed_count INTEGER DEFAULT 0,
    opened_count INTEGER DEFAULT 0,
    clicked_count INTEGER DEFAULT 0,

    -- Template
    template_id UUID REFERENCES communication_templates(id),
    template_variables JSONB DEFAULT '{}'::jsonb,

    -- Metadata
    tags JSONB DEFAULT '[]'::jsonb,
    attachments JSONB DEFAULT '[]'::jsonb,

    -- Audit
    created_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_communications_tournament ON tournament_communications(tournament_id);
CREATE INDEX idx_communications_status ON tournament_communications(status);
CREATE INDEX idx_communications_scheduled ON tournament_communications(scheduled_for);
```

### tournament_check_ins

```sql
CREATE TABLE tournament_check_ins (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tournament_id UUID NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
    team_id UUID NOT NULL REFERENCES tournament_teams(id) ON DELETE CASCADE,

    -- Check-in Details
    player_number INTEGER NOT NULL, -- 1 or 2
    checked_in_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    checked_in_by UUID REFERENCES auth.users(id),

    -- Verification
    id_verified BOOLEAN DEFAULT FALSE,
    waiver_signed BOOLEAN DEFAULT FALSE,
    payment_verified BOOLEAN DEFAULT FALSE,

    -- QR Code
    qr_code VARCHAR(100) UNIQUE,
    qr_scanned_at TIMESTAMPTZ,

    -- Location
    check_in_location VARCHAR(100),
    device_id VARCHAR(100),
    ip_address INET,

    -- Items Received
    wristband_number VARCHAR(50),
    packet_received BOOLEAN DEFAULT FALSE,
    merchandise_received JSONB DEFAULT '{}'::jsonb,

    -- Notes
    notes TEXT,
    issues TEXT,

    -- Audit
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_checkins_tournament ON tournament_check_ins(tournament_id);
CREATE INDEX idx_checkins_team ON tournament_check_ins(team_id);
CREATE INDEX idx_checkins_qr ON tournament_check_ins(qr_code);
```

## Lookup/Reference Tables

### communication_templates

```sql
CREATE TABLE communication_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Template Information
    name VARCHAR(255) NOT NULL,
    code VARCHAR(100) UNIQUE NOT NULL,
    description TEXT,

    -- Content
    subject VARCHAR(500),
    content_plain TEXT NOT NULL,
    content_html TEXT,
    content_sms VARCHAR(500),

    -- Type
    message_type VARCHAR(50) NOT NULL,
    channel VARCHAR(20) NOT NULL,

    -- Variables
    available_variables JSONB DEFAULT '[]'::jsonb,
    default_values JSONB DEFAULT '{}'::jsonb,

    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    is_system BOOLEAN DEFAULT FALSE, -- System templates can't be deleted

    -- Metadata
    tags JSONB DEFAULT '[]'::jsonb,
    usage_count INTEGER DEFAULT 0,

    -- Audit
    created_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_templates_code ON communication_templates(code);
CREATE INDEX idx_templates_type ON communication_templates(message_type);
```

### venues

```sql
CREATE TABLE venues (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Venue Information
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(255) UNIQUE NOT NULL,
    description TEXT,

    -- Location
    address_line1 VARCHAR(255) NOT NULL,
    address_line2 VARCHAR(255),
    city VARCHAR(100) NOT NULL,
    state VARCHAR(50) NOT NULL,
    postal_code VARCHAR(20) NOT NULL,
    country VARCHAR(100) DEFAULT 'USA',

    -- Coordinates
    latitude DECIMAL(10, 8),
    longitude DECIMAL(11, 8),

    -- Facilities
    total_courts INTEGER NOT NULL,
    indoor_courts INTEGER DEFAULT 0,
    outdoor_courts INTEGER DEFAULT 0,

    -- Amenities
    amenities JSONB DEFAULT '[]'::jsonb, -- ['parking', 'restrooms', 'pro_shop', 'food', etc.]

    -- Contact
    contact_name VARCHAR(255),
    contact_email VARCHAR(255),
    contact_phone VARCHAR(50),
    website VARCHAR(500),

    -- Hours
    operating_hours JSONB DEFAULT '{}'::jsonb,

    -- Images
    logo_url VARCHAR(500),
    images JSONB DEFAULT '[]'::jsonb,
    venue_map_url VARCHAR(500),

    -- Status
    is_active BOOLEAN DEFAULT TRUE,

    -- Metadata
    custom_fields JSONB DEFAULT '{}'::jsonb,

    -- Audit
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_venues_slug ON venues(slug);
CREATE INDEX idx_venues_location ON venues(city, state);
```

## Functions and Triggers

### Auto-update timestamps

```sql
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply to all tables
CREATE TRIGGER update_tournaments_updated_at BEFORE UPDATE ON tournaments
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_divisions_updated_at BEFORE UPDATE ON tournament_divisions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ... (similar triggers for all tables)
```

### Validate DUPR ratings

```sql
CREATE OR REPLACE FUNCTION validate_dupr_rating()
RETURNS TRIGGER AS $$
BEGIN
    -- Check if team meets division requirements
    IF NEW.division_id IS NOT NULL THEN
        DECLARE
            div_record RECORD;
            combined_rating DECIMAL(5, 2);
            rating_spread DECIMAL(5, 2);
        BEGIN
            SELECT * INTO div_record
            FROM tournament_divisions
            WHERE id = NEW.division_id;

            IF div_record.uses_dupr THEN
                combined_rating := COALESCE(NEW.player1_dupr_rating, 0) +
                                  COALESCE(NEW.player2_dupr_rating, 0);
                rating_spread := ABS(COALESCE(NEW.player1_dupr_rating, 0) -
                                    COALESCE(NEW.player2_dupr_rating, 0));

                IF combined_rating < div_record.dupr_min_combined OR
                   combined_rating > div_record.dupr_max_combined OR
                   rating_spread > div_record.dupr_max_spread THEN
                    RAISE EXCEPTION 'Team does not meet DUPR requirements for division';
                END IF;

                NEW.combined_dupr_rating := combined_rating;
            END IF;
        END;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER validate_team_dupr BEFORE INSERT OR UPDATE ON tournament_teams
    FOR EACH ROW EXECUTE FUNCTION validate_dupr_rating();
```

### Update division counts

```sql
CREATE OR REPLACE FUNCTION update_division_counts()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE tournament_divisions
        SET current_teams_count = current_teams_count + 1
        WHERE id = NEW.division_id AND NEW.status = 'confirmed';

        UPDATE tournament_divisions
        SET waitlist_count = waitlist_count + 1
        WHERE id = NEW.division_id AND NEW.status = 'waitlisted';
    ELSIF TG_OP = 'UPDATE' THEN
        -- Handle status changes
        IF OLD.status != NEW.status THEN
            -- Decrement old status count
            IF OLD.status = 'confirmed' THEN
                UPDATE tournament_divisions
                SET current_teams_count = current_teams_count - 1
                WHERE id = OLD.division_id;
            ELSIF OLD.status = 'waitlisted' THEN
                UPDATE tournament_divisions
                SET waitlist_count = waitlist_count - 1
                WHERE id = OLD.division_id;
            END IF;

            -- Increment new status count
            IF NEW.status = 'confirmed' THEN
                UPDATE tournament_divisions
                SET current_teams_count = current_teams_count + 1
                WHERE id = NEW.division_id;
            ELSIF NEW.status = 'waitlisted' THEN
                UPDATE tournament_divisions
                SET waitlist_count = waitlist_count + 1
                WHERE id = NEW.division_id;
            END IF;
        END IF;
    ELSIF TG_OP = 'DELETE' THEN
        IF OLD.status = 'confirmed' THEN
            UPDATE tournament_divisions
            SET current_teams_count = current_teams_count - 1
            WHERE id = OLD.division_id;
        ELSIF OLD.status = 'waitlisted' THEN
            UPDATE tournament_divisions
            SET waitlist_count = waitlist_count - 1
            WHERE id = OLD.division_id;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_division_team_counts
    AFTER INSERT OR UPDATE OR DELETE ON tournament_teams
    FOR EACH ROW EXECUTE FUNCTION update_division_counts();
```

## Indexes for Performance

```sql
-- Composite indexes for common queries
CREATE INDEX idx_teams_tournament_status ON tournament_teams(tournament_id, status);
CREATE INDEX idx_teams_division_status ON tournament_teams(division_id, status);
CREATE INDEX idx_matches_division_round ON tournament_matches(division_id, round_number);
CREATE INDEX idx_matches_court_time ON tournament_matches(court_id, scheduled_time);
CREATE INDEX idx_payments_team_status ON tournament_payments(team_id, status);

-- Full-text search indexes
CREATE INDEX idx_tournaments_search ON tournaments USING gin(
    to_tsvector('english', name || ' ' || COALESCE(description, ''))
);

CREATE INDEX idx_teams_player_search ON tournament_teams USING gin(
    to_tsvector('english', player1_name || ' ' || player2_name)
);

-- JSONB indexes for metadata queries
CREATE INDEX idx_tournaments_tags ON tournaments USING gin(tags);
CREATE INDEX idx_divisions_custom ON tournament_divisions USING gin(custom_fields);
CREATE INDEX idx_teams_custom ON tournament_teams USING gin(custom_fields);
```

## Row-Level Security Policies

```sql
-- Enable RLS on all tables
ALTER TABLE tournaments ENABLE ROW LEVEL SECURITY;
ALTER TABLE tournament_divisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE tournament_teams ENABLE ROW LEVEL SECURITY;
-- ... (for all tables)

-- Tournament viewing policy
CREATE POLICY "Tournaments viewable by all authenticated users" ON tournaments
    FOR SELECT
    TO authenticated
    USING (
        status != 'draft'
        OR created_by = auth.uid()
        OR EXISTS (
            SELECT 1 FROM tournament_staff
            WHERE tournament_id = tournaments.id
            AND user_id = auth.uid()
        )
    );

-- Tournament editing policy
CREATE POLICY "Tournaments editable by directors and admins" ON tournaments
    FOR ALL
    TO authenticated
    USING (
        created_by = auth.uid()
        OR EXISTS (
            SELECT 1 FROM tournament_staff
            WHERE tournament_id = tournaments.id
            AND user_id = auth.uid()
            AND role IN ('director', 'admin')
        )
    );

-- Team viewing policy
CREATE POLICY "Teams viewable by participants and staff" ON tournament_teams
    FOR SELECT
    TO authenticated
    USING (
        player1_id = auth.uid()
        OR player2_id = auth.uid()
        OR EXISTS (
            SELECT 1 FROM tournament_staff
            WHERE tournament_id = tournament_teams.tournament_id
            AND user_id = auth.uid()
        )
    );

-- Payment viewing policy
CREATE POLICY "Payments viewable by payers and staff" ON tournament_payments
    FOR SELECT
    TO authenticated
    USING (
        payer_id = auth.uid()
        OR EXISTS (
            SELECT 1 FROM tournament_teams
            WHERE id = tournament_payments.team_id
            AND (player1_id = auth.uid() OR player2_id = auth.uid())
        )
        OR EXISTS (
            SELECT 1 FROM tournament_staff
            WHERE tournament_id = tournament_payments.tournament_id
            AND user_id = auth.uid()
            AND role IN ('director', 'admin')
        )
    );
```

## Migration Strategy

1. **Phase 1**: Create base tables (tournaments, divisions, teams)
2. **Phase 2**: Add match and bracket tables
3. **Phase 3**: Implement payment and communication tables
4. **Phase 4**: Add support tables (staff, check-ins, etc.)
5. **Phase 5**: Create functions, triggers, and indexes
6. **Phase 6**: Implement RLS policies
7. **Phase 7**: Seed with test data

## Performance Considerations

1. **Partitioning**: Consider partitioning tournaments table by year
2. **Archiving**: Move completed tournaments to archive tables after 1 year
3. **Caching**: Use materialized views for tournament statistics
4. **Connection Pooling**: Use PgBouncer for high-traffic events
5. **Read Replicas**: Implement read replicas for reporting queries

## Backup and Recovery

1. **Continuous Backups**: Point-in-time recovery enabled
2. **Daily Snapshots**: Automated daily backups retained for 30 days
3. **Pre-Event Backups**: Manual backup before each tournament
4. **Replication**: Multi-region replication for disaster recovery
5. **Audit Logs**: All changes logged to audit tables