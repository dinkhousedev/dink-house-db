-- ============================================================================
-- MAKE CREATED_BY NULLABLE IN OPEN PLAY TABLES
-- Allows schedule creation without requiring admin_users record
-- ============================================================================

-- Drop foreign key constraints on created_by/updated_by
ALTER TABLE events.open_play_schedule_blocks
    DROP CONSTRAINT IF EXISTS open_play_schedule_blocks_created_by_fkey,
    DROP CONSTRAINT IF EXISTS open_play_schedule_blocks_updated_by_fkey;

ALTER TABLE events.open_play_schedule_overrides
    DROP CONSTRAINT IF EXISTS open_play_schedule_overrides_created_by_fkey;

-- Make created_by and updated_by nullable in schedule blocks
ALTER TABLE events.open_play_schedule_blocks
    ALTER COLUMN created_by DROP NOT NULL,
    ALTER COLUMN updated_by DROP NOT NULL;

-- Make created_by nullable in schedule overrides
ALTER TABLE events.open_play_schedule_overrides
    ALTER COLUMN created_by DROP NOT NULL;

COMMENT ON COLUMN events.open_play_schedule_blocks.created_by IS 'Admin user who created this block (nullable, no FK constraint for Supabase Auth compatibility)';
COMMENT ON COLUMN events.open_play_schedule_blocks.updated_by IS 'Admin user who last updated this block (nullable, no FK constraint for Supabase Auth compatibility)';
COMMENT ON COLUMN events.open_play_schedule_overrides.created_by IS 'Admin user who created this override (nullable, no FK constraint for Supabase Auth compatibility)';
