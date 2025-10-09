-- ============================================================================
-- OPEN PLAY SCHEDULE MODULE
-- Recurring weekly open play schedule with court allocations by skill level
-- ============================================================================

-- ============================================================================
-- ENUMS AND TYPES
-- ============================================================================

CREATE TYPE events.open_play_session_type AS ENUM (
    'divided_by_skill',  -- Courts split among skill levels (peak hours)
    'mixed_levels',      -- All skill levels can play together
    'dedicated_skill',   -- All courts for one skill level
    'special_event'      -- Named events (Ladies Night, Clinics, etc.)
);

COMMENT ON TYPE events.open_play_session_type IS 'Types of open play sessions';

-- ============================================================================
-- OPEN PLAY SCHEDULE BLOCKS TABLE
-- Defines recurring weekly schedule blocks
-- ============================================================================

CREATE TABLE events.open_play_schedule_blocks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(200) NOT NULL,
    description TEXT,

    -- Timing
    day_of_week INTEGER NOT NULL CHECK (day_of_week >= 0 AND day_of_week <= 6), -- 0=Sunday, 6=Saturday (single day per block)
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,

    -- Session configuration
    session_type events.open_play_session_type NOT NULL,
    special_event_name VARCHAR(200), -- For special events (Ladies Night, Sunset Social, etc.)

    -- For dedicated_skill sessions, specify which skill level gets all courts
    dedicated_skill_min NUMERIC(3, 2),
    dedicated_skill_max NUMERIC(3, 2),
    dedicated_skill_label VARCHAR(100), -- Beginner, Intermediate, Advanced

    -- Pricing
    price_member DECIMAL(10, 2) DEFAULT 15.00,
    price_guest DECIMAL(10, 2) DEFAULT 20.00,

    -- Session details
    max_capacity INTEGER DEFAULT 20, -- Total players across all courts (deprecated - use calculated capacity)
    max_players_per_court INTEGER DEFAULT 8, -- Max players per court (4 playing + 4 waiting)
    check_in_instructions TEXT,
    special_instructions TEXT,

    -- Status
    is_active BOOLEAN DEFAULT true,
    effective_from DATE DEFAULT CURRENT_DATE,
    effective_until DATE,

    -- Metadata
    created_by UUID REFERENCES app_auth.admin_users(id),
    updated_by UUID REFERENCES app_auth.admin_users(id),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
    CONSTRAINT valid_time_range CHECK (end_time > start_time),
    CONSTRAINT dedicated_skill_required CHECK (
        (session_type = 'dedicated_skill' AND dedicated_skill_min IS NOT NULL AND dedicated_skill_label IS NOT NULL)
        OR session_type != 'dedicated_skill'
    ),
    CONSTRAINT special_event_name_required CHECK (
        (session_type = 'special_event' AND special_event_name IS NOT NULL)
        OR session_type != 'special_event'
    ),
    CONSTRAINT valid_effective_dates CHECK (
        effective_until IS NULL OR effective_until >= effective_from
    )
);

COMMENT ON TABLE events.open_play_schedule_blocks IS 'Recurring weekly open play schedule blocks';

-- Create indexes
CREATE INDEX idx_schedule_blocks_day ON events.open_play_schedule_blocks(day_of_week);
CREATE INDEX idx_schedule_blocks_time ON events.open_play_schedule_blocks(start_time, end_time);
CREATE INDEX idx_schedule_blocks_active ON events.open_play_schedule_blocks(is_active);
CREATE INDEX idx_schedule_blocks_session_type ON events.open_play_schedule_blocks(session_type);
CREATE INDEX idx_schedule_blocks_effective ON events.open_play_schedule_blocks(effective_from, effective_until);

-- ============================================================================
-- OPEN PLAY COURT ALLOCATIONS TABLE
-- Defines which courts are assigned to which skill levels during each block
-- ============================================================================

CREATE TABLE events.open_play_court_allocations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    schedule_block_id UUID NOT NULL REFERENCES events.open_play_schedule_blocks(id) ON DELETE CASCADE,
    court_id UUID NOT NULL REFERENCES events.courts(id) ON DELETE CASCADE,

    -- Skill level for this court during this block
    skill_level_min NUMERIC(3, 2) NOT NULL,
    skill_level_max NUMERIC(3, 2),
    skill_level_label VARCHAR(100) NOT NULL, -- Beginner, Intermediate, Advanced, Mixed

    -- For mixed sessions, this might be NULL or open to all
    is_mixed_level BOOLEAN DEFAULT false, -- True if this court allows all skill levels

    -- Display order
    sort_order INTEGER DEFAULT 0,

    -- Notes
    notes TEXT,

    -- Metadata
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
    CONSTRAINT valid_skill_range CHECK (
        skill_level_max IS NULL
        OR skill_level_max >= skill_level_min
    ),
    CONSTRAINT unique_block_court UNIQUE(schedule_block_id, court_id)
);

COMMENT ON TABLE events.open_play_court_allocations IS 'Court assignments for each schedule block';

-- Create indexes
CREATE INDEX idx_allocations_block ON events.open_play_court_allocations(schedule_block_id);
CREATE INDEX idx_allocations_court ON events.open_play_court_allocations(court_id);
CREATE INDEX idx_allocations_skill_range ON events.open_play_court_allocations(skill_level_min, skill_level_max);

-- ============================================================================
-- OPEN PLAY SCHEDULE OVERRIDES TABLE
-- One-off changes to the regular schedule (holidays, special events, etc.)
-- ============================================================================

CREATE TABLE events.open_play_schedule_overrides (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    schedule_block_id UUID REFERENCES events.open_play_schedule_blocks(id) ON DELETE CASCADE,

    -- Override details
    override_date DATE NOT NULL,
    is_cancelled BOOLEAN DEFAULT false,

    -- If not cancelled, provide replacement details
    replacement_name VARCHAR(200),
    replacement_start_time TIME,
    replacement_end_time TIME,
    replacement_session_type events.open_play_session_type,

    -- Reason and notes
    reason TEXT NOT NULL,
    special_instructions TEXT,

    -- Metadata
    created_by UUID REFERENCES app_auth.admin_users(id),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
    CONSTRAINT valid_replacement_time CHECK (
        is_cancelled = true
        OR (replacement_start_time IS NOT NULL AND replacement_end_time IS NOT NULL)
    ),
    CONSTRAINT unique_block_override_date UNIQUE(schedule_block_id, override_date)
);

COMMENT ON TABLE events.open_play_schedule_overrides IS 'One-off changes to regular schedule';

-- Create indexes
CREATE INDEX idx_overrides_block ON events.open_play_schedule_overrides(schedule_block_id);
CREATE INDEX idx_overrides_date ON events.open_play_schedule_overrides(override_date);
CREATE INDEX idx_overrides_cancelled ON events.open_play_schedule_overrides(is_cancelled);

-- ============================================================================
-- OPEN PLAY GENERATED INSTANCES TABLE
-- Generated instances for conflict detection with player bookings
-- This table will be populated by a function that generates instances
-- ============================================================================

CREATE TABLE events.open_play_instances (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    schedule_block_id UUID NOT NULL REFERENCES events.open_play_schedule_blocks(id) ON DELETE CASCADE,

    -- Instance details
    instance_date DATE NOT NULL,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,

    -- Override tracking
    override_id UUID REFERENCES events.open_play_schedule_overrides(id) ON DELETE CASCADE,
    is_cancelled BOOLEAN DEFAULT false,

    -- Metadata
    generated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
    CONSTRAINT valid_instance_time CHECK (end_time > start_time),
    CONSTRAINT unique_block_instance_date UNIQUE(schedule_block_id, instance_date)
);

COMMENT ON TABLE events.open_play_instances IS 'Generated open play instances for booking conflict detection';

-- Create indexes for performance
CREATE INDEX idx_instances_block ON events.open_play_instances(schedule_block_id);
CREATE INDEX idx_instances_date ON events.open_play_instances(instance_date);
CREATE INDEX idx_instances_time_range ON events.open_play_instances(start_time, end_time);
CREATE INDEX idx_instances_cancelled ON events.open_play_instances(is_cancelled);

-- Composite index for conflict detection queries
CREATE INDEX idx_instances_conflict_detection ON events.open_play_instances(instance_date, start_time, end_time)
    WHERE is_cancelled = false;

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Update timestamp trigger for schedule blocks
CREATE TRIGGER update_schedule_blocks_updated_at
    BEFORE UPDATE ON events.open_play_schedule_blocks
    FOR EACH ROW EXECUTE FUNCTION events.update_updated_at();

-- Update timestamp trigger for court allocations
CREATE TRIGGER update_court_allocations_updated_at
    BEFORE UPDATE ON events.open_play_court_allocations
    FOR EACH ROW EXECUTE FUNCTION events.update_updated_at();

-- Update timestamp trigger for overrides
CREATE TRIGGER update_overrides_updated_at
    BEFORE UPDATE ON events.open_play_schedule_overrides
    FOR EACH ROW EXECUTE FUNCTION events.update_updated_at();

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Function to check if a time overlaps with open play
CREATE OR REPLACE FUNCTION events.check_open_play_conflict(
    p_start_time TIMESTAMPTZ,
    p_end_time TIMESTAMPTZ,
    p_court_ids UUID[] DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_has_conflict BOOLEAN;
BEGIN
    -- Check if the requested time overlaps with any open play instances
    SELECT EXISTS (
        SELECT 1
        FROM events.open_play_instances opi
        WHERE opi.is_cancelled = false
        AND (opi.start_time, opi.end_time) OVERLAPS (p_start_time, p_end_time)
        AND (
            p_court_ids IS NULL
            OR EXISTS (
                SELECT 1
                FROM events.open_play_court_allocations opca
                WHERE opca.schedule_block_id = opi.schedule_block_id
                AND opca.court_id = ANY(p_court_ids)
            )
        )
    ) INTO v_has_conflict;

    RETURN v_has_conflict;
END;
$$;

COMMENT ON FUNCTION events.check_open_play_conflict IS 'Check if a booking time conflicts with open play schedule';

-- Function to get schedule block for a specific day/time
CREATE OR REPLACE FUNCTION events.get_schedule_block_at_time(
    p_day_of_week INTEGER,
    p_time TIME
)
RETURNS SETOF events.open_play_schedule_blocks
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN QUERY
    SELECT *
    FROM events.open_play_schedule_blocks
    WHERE day_of_week = p_day_of_week
    AND start_time <= p_time
    AND end_time > p_time
    AND is_active = true
    AND (effective_from IS NULL OR effective_from <= CURRENT_DATE)
    AND (effective_until IS NULL OR effective_until >= CURRENT_DATE);
END;
$$;

COMMENT ON FUNCTION events.get_schedule_block_at_time IS 'Get active schedule block for a specific day and time';

-- Function to calculate max capacity for a skill level in a schedule block
CREATE OR REPLACE FUNCTION events.calculate_skill_level_capacity(
    p_schedule_block_id UUID,
    p_skill_level_label VARCHAR
)
RETURNS INTEGER
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_court_count INTEGER;
    v_max_players_per_court INTEGER;
    v_calculated_capacity INTEGER;
BEGIN
    -- Get max players per court from schedule block
    SELECT max_players_per_court INTO v_max_players_per_court
    FROM events.open_play_schedule_blocks
    WHERE id = p_schedule_block_id;

    -- Count courts allocated to this skill level
    SELECT COUNT(*) INTO v_court_count
    FROM events.open_play_court_allocations
    WHERE schedule_block_id = p_schedule_block_id
    AND skill_level_label = p_skill_level_label;

    -- Calculate capacity: courts × max_players_per_court
    v_calculated_capacity := v_court_count * COALESCE(v_max_players_per_court, 8);

    RETURN v_calculated_capacity;
END;
$$;

COMMENT ON FUNCTION events.calculate_skill_level_capacity IS 'Calculate max capacity for a skill level based on court allocations';

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

-- Grant SELECT to authenticated users (to view schedule)
GRANT SELECT ON events.open_play_schedule_blocks TO authenticated;
GRANT SELECT ON events.open_play_court_allocations TO authenticated;
GRANT SELECT ON events.open_play_instances TO authenticated;

-- Grant SELECT to anonymous users (for public schedule view)
GRANT SELECT ON events.open_play_schedule_blocks TO anon;
GRANT SELECT ON events.open_play_court_allocations TO anon;
GRANT SELECT ON events.open_play_instances TO anon;
