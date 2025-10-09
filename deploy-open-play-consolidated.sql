-- ============================================================================
-- CONSOLIDATED OPEN PLAY SYSTEM DEPLOYMENT
-- Deploy via Supabase Dashboard: https://supabase.com/dashboard/project/wchxzbuuwssrnaxshseu/sql
-- ============================================================================

BEGIN;

-- ============================================================================
-- MODULE 35: FIX COURTS PERMISSIONS
-- ============================================================================

GRANT SELECT ON events.events TO authenticated;
GRANT SELECT ON events.event_courts TO authenticated;
GRANT SELECT ON events.courts TO authenticated;
GRANT SELECT ON events.event_registrations TO authenticated;
GRANT SELECT ON events.event_templates TO authenticated;
GRANT SELECT ON app_auth.admin_users TO authenticated;

GRANT SELECT ON events.events TO anon;
GRANT SELECT ON events.courts TO anon;

GRANT INSERT ON events.events TO authenticated;
GRANT INSERT ON events.event_courts TO authenticated;
GRANT INSERT ON events.event_registrations TO authenticated;

DROP POLICY IF EXISTS "events_select_published" ON events.events;
DROP POLICY IF EXISTS "events_select_all_authenticated" ON events.events;
DROP POLICY IF EXISTS "events_select_anon" ON events.events;

CREATE POLICY "events_select_all_authenticated" ON events.events
    FOR SELECT TO authenticated
    USING (is_published = true OR created_by = auth.uid());

CREATE POLICY "events_select_anon" ON events.events
    FOR SELECT TO anon
    USING (is_published = true);

DROP POLICY IF EXISTS "event_courts_select" ON events.event_courts;
DROP POLICY IF EXISTS "event_courts_select_all_authenticated" ON events.event_courts;
DROP POLICY IF EXISTS "event_courts_select_anon" ON events.event_courts;

CREATE POLICY "event_courts_select_all_authenticated" ON events.event_courts
    FOR SELECT TO authenticated USING (true);

CREATE POLICY "event_courts_select_anon" ON events.event_courts
    FOR SELECT TO anon USING (true);

DROP POLICY IF EXISTS "courts_select_all" ON events.courts;

CREATE POLICY "courts_select_all" ON events.courts
    FOR SELECT USING (true);

DO $$
BEGIN
    ALTER TABLE app_auth.admin_users ENABLE ROW LEVEL SECURITY;
EXCEPTION
    WHEN OTHERS THEN NULL;
END $$;

DROP POLICY IF EXISTS "admin_users_select_for_fk" ON app_auth.admin_users;

CREATE POLICY "admin_users_select_for_fk" ON app_auth.admin_users
    FOR SELECT TO authenticated USING (true);

-- ============================================================================
-- MODULE 36: OPEN PLAY SCHEDULE TABLES
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'open_play_session_type') THEN
        CREATE TYPE events.open_play_session_type AS ENUM (
            'divided_by_skill',
            'mixed_levels',
            'dedicated_skill',
            'special_event'
        );
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS events.open_play_schedule_blocks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(200) NOT NULL,
    description TEXT,
    day_of_week INTEGER NOT NULL CHECK (day_of_week >= 0 AND day_of_week <= 6),
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    session_type events.open_play_session_type NOT NULL,
    special_event_name VARCHAR(200),
    dedicated_skill_min NUMERIC(3, 2),
    dedicated_skill_max NUMERIC(3, 2),
    dedicated_skill_label VARCHAR(100),
    price_member DECIMAL(10, 2) DEFAULT 15.00,
    price_guest DECIMAL(10, 2) DEFAULT 20.00,
    max_capacity INTEGER DEFAULT 20,
    max_players_per_court INTEGER DEFAULT 8,
    check_in_instructions TEXT,
    special_instructions TEXT,
    is_active BOOLEAN DEFAULT true,
    effective_from DATE DEFAULT CURRENT_DATE,
    effective_until DATE,
    created_by UUID REFERENCES app_auth.admin_users(id),
    updated_by UUID REFERENCES app_auth.admin_users(id),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
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

CREATE INDEX IF NOT EXISTS idx_schedule_blocks_day ON events.open_play_schedule_blocks(day_of_week);
CREATE INDEX IF NOT EXISTS idx_schedule_blocks_time ON events.open_play_schedule_blocks(start_time, end_time);
CREATE INDEX IF NOT EXISTS idx_schedule_blocks_active ON events.open_play_schedule_blocks(is_active);

CREATE TABLE IF NOT EXISTS events.open_play_court_allocations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    schedule_block_id UUID NOT NULL REFERENCES events.open_play_schedule_blocks(id) ON DELETE CASCADE,
    court_id UUID NOT NULL REFERENCES events.courts(id) ON DELETE CASCADE,
    skill_level_min NUMERIC(3, 2) NOT NULL,
    skill_level_max NUMERIC(3, 2),
    skill_level_label VARCHAR(100) NOT NULL,
    is_mixed_level BOOLEAN DEFAULT false,
    sort_order INTEGER DEFAULT 0,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT valid_skill_range CHECK (
        skill_level_max IS NULL OR skill_level_max >= skill_level_min
    ),
    CONSTRAINT unique_block_court UNIQUE(schedule_block_id, court_id)
);

CREATE INDEX IF NOT EXISTS idx_allocations_block ON events.open_play_court_allocations(schedule_block_id);
CREATE INDEX IF NOT EXISTS idx_allocations_court ON events.open_play_court_allocations(court_id);

CREATE TABLE IF NOT EXISTS events.open_play_schedule_overrides (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    schedule_block_id UUID REFERENCES events.open_play_schedule_blocks(id) ON DELETE CASCADE,
    override_date DATE NOT NULL,
    is_cancelled BOOLEAN DEFAULT false,
    replacement_name VARCHAR(200),
    replacement_start_time TIME,
    replacement_end_time TIME,
    replacement_session_type events.open_play_session_type,
    reason TEXT NOT NULL,
    special_instructions TEXT,
    created_by UUID REFERENCES app_auth.admin_users(id),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT valid_replacement_time CHECK (
        is_cancelled = true
        OR (replacement_start_time IS NOT NULL AND replacement_end_time IS NOT NULL)
    ),
    CONSTRAINT unique_block_override_date UNIQUE(schedule_block_id, override_date)
);

CREATE INDEX IF NOT EXISTS idx_overrides_block ON events.open_play_schedule_overrides(schedule_block_id);
CREATE INDEX IF NOT EXISTS idx_overrides_date ON events.open_play_schedule_overrides(override_date);

CREATE TABLE IF NOT EXISTS events.open_play_instances (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    schedule_block_id UUID NOT NULL REFERENCES events.open_play_schedule_blocks(id) ON DELETE CASCADE,
    instance_date DATE NOT NULL,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    override_id UUID REFERENCES events.open_play_schedule_overrides(id) ON DELETE CASCADE,
    is_cancelled BOOLEAN DEFAULT false,
    generated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT valid_instance_time CHECK (end_time > start_time),
    CONSTRAINT unique_block_instance_date UNIQUE(schedule_block_id, instance_date)
);

CREATE INDEX IF NOT EXISTS idx_instances_block ON events.open_play_instances(schedule_block_id);
CREATE INDEX IF NOT EXISTS idx_instances_date ON events.open_play_instances(instance_date);
CREATE INDEX IF NOT EXISTS idx_instances_time_range ON events.open_play_instances(start_time, end_time);

-- Triggers
DROP TRIGGER IF EXISTS update_schedule_blocks_updated_at ON events.open_play_schedule_blocks;
CREATE TRIGGER update_schedule_blocks_updated_at
    BEFORE UPDATE ON events.open_play_schedule_blocks
    FOR EACH ROW EXECUTE FUNCTION events.update_updated_at();

DROP TRIGGER IF EXISTS update_court_allocations_updated_at ON events.open_play_court_allocations;
CREATE TRIGGER update_court_allocations_updated_at
    BEFORE UPDATE ON events.open_play_court_allocations
    FOR EACH ROW EXECUTE FUNCTION events.update_updated_at();

DROP TRIGGER IF EXISTS update_overrides_updated_at ON events.open_play_schedule_overrides;
CREATE TRIGGER update_overrides_updated_at
    BEFORE UPDATE ON events.open_play_schedule_overrides
    FOR EACH ROW EXECUTE FUNCTION events.update_updated_at();

GRANT SELECT ON events.open_play_schedule_blocks TO authenticated, anon;
GRANT SELECT ON events.open_play_court_allocations TO authenticated, anon;
GRANT SELECT ON events.open_play_instances TO authenticated, anon;

COMMIT;

-- Module 37 (API functions) will go in a separate file due to size
