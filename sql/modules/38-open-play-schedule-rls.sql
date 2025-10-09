-- ============================================================================
-- OPEN PLAY SCHEDULE RLS POLICIES
-- Row Level Security policies for open play schedule system
-- ============================================================================

-- Enable RLS on all open play schedule tables
ALTER TABLE events.open_play_schedule_blocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE events.open_play_court_allocations ENABLE ROW LEVEL SECURITY;
ALTER TABLE events.open_play_schedule_overrides ENABLE ROW LEVEL SECURITY;
ALTER TABLE events.open_play_instances ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- SCHEDULE BLOCKS POLICIES
-- ============================================================================

-- Schedule Blocks: Everyone can view active blocks
CREATE POLICY "schedule_blocks_select_all" ON events.open_play_schedule_blocks
    FOR SELECT
    USING (
        is_active = true
        OR events.is_staff()
    );

-- Schedule Blocks: Staff can create
CREATE POLICY "schedule_blocks_insert_staff" ON events.open_play_schedule_blocks
    FOR INSERT
    WITH CHECK (
        events.is_staff()
        AND created_by = auth.uid()
    );

-- Schedule Blocks: Staff can update
CREATE POLICY "schedule_blocks_update_staff" ON events.open_play_schedule_blocks
    FOR UPDATE
    USING (events.is_staff())
    WITH CHECK (events.is_staff());

-- Schedule Blocks: Only admins can delete
CREATE POLICY "schedule_blocks_delete_admin" ON events.open_play_schedule_blocks
    FOR DELETE
    USING (events.is_admin_or_manager());

-- ============================================================================
-- COURT ALLOCATIONS POLICIES
-- ============================================================================

-- Court Allocations: Everyone can view
CREATE POLICY "court_allocations_select_all" ON events.open_play_court_allocations
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM events.open_play_schedule_blocks opsb
            WHERE opsb.id = open_play_court_allocations.schedule_block_id
            AND (opsb.is_active = true OR events.is_staff())
        )
    );

-- Court Allocations: Staff can create
CREATE POLICY "court_allocations_insert_staff" ON events.open_play_court_allocations
    FOR INSERT
    WITH CHECK (events.is_staff());

-- Court Allocations: Staff can update
CREATE POLICY "court_allocations_update_staff" ON events.open_play_court_allocations
    FOR UPDATE
    USING (events.is_staff())
    WITH CHECK (events.is_staff());

-- Court Allocations: Staff can delete
CREATE POLICY "court_allocations_delete_staff" ON events.open_play_court_allocations
    FOR DELETE
    USING (events.is_staff());

-- ============================================================================
-- SCHEDULE OVERRIDES POLICIES
-- ============================================================================

-- Overrides: Everyone can view (to see schedule changes)
CREATE POLICY "overrides_select_all" ON events.open_play_schedule_overrides
    FOR SELECT
    USING (true);

-- Overrides: Staff can create
CREATE POLICY "overrides_insert_staff" ON events.open_play_schedule_overrides
    FOR INSERT
    WITH CHECK (
        events.is_staff()
        AND created_by = auth.uid()
    );

-- Overrides: Staff can update
CREATE POLICY "overrides_update_staff" ON events.open_play_schedule_overrides
    FOR UPDATE
    USING (events.is_staff())
    WITH CHECK (events.is_staff());

-- Overrides: Admins can delete
CREATE POLICY "overrides_delete_admin" ON events.open_play_schedule_overrides
    FOR DELETE
    USING (events.is_admin_or_manager());

-- ============================================================================
-- OPEN PLAY INSTANCES POLICIES
-- ============================================================================

-- Instances: Everyone can view active instances
CREATE POLICY "instances_select_all" ON events.open_play_instances
    FOR SELECT
    USING (true);

-- Instances: Only system functions can insert/update (via SECURITY DEFINER functions)
-- No direct INSERT/UPDATE/DELETE policies - only through API functions

-- ============================================================================
-- GRANT ADDITIONAL PERMISSIONS
-- ============================================================================

-- Grant permissions on tables for direct querying (RLS will control actual access)
GRANT SELECT ON events.open_play_schedule_blocks TO authenticated, anon;
GRANT SELECT ON events.open_play_court_allocations TO authenticated, anon;
GRANT SELECT ON events.open_play_schedule_overrides TO authenticated, anon;
GRANT SELECT ON events.open_play_instances TO authenticated, anon;

-- Grant INSERT, UPDATE, DELETE to authenticated users (RLS policies will control who can actually perform these)
GRANT INSERT, UPDATE, DELETE ON events.open_play_schedule_blocks TO authenticated;
GRANT INSERT, UPDATE, DELETE ON events.open_play_court_allocations TO authenticated;
GRANT INSERT, UPDATE, DELETE ON events.open_play_schedule_overrides TO authenticated;

-- Staff need full access through functions (granted via SECURITY DEFINER)
GRANT ALL ON events.open_play_schedule_blocks TO service_role;
GRANT ALL ON events.open_play_court_allocations TO service_role;
GRANT ALL ON events.open_play_schedule_overrides TO service_role;
GRANT ALL ON events.open_play_instances TO service_role;

-- Grant sequence permissions for inserts
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA events TO authenticated;
