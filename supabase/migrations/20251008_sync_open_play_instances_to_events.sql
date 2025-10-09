-- ============================================================================
-- Sync Open Play Instances to Events Table
-- ============================================================================
-- This migration creates a trigger that automatically syncs open_play_instances
-- to the events.events table so they appear in the player app calendar
-- ============================================================================

-- ============================================================================
-- FUNCTION: Sync Instance to Events Table
-- ============================================================================

CREATE OR REPLACE FUNCTION events.sync_open_play_instance_to_event()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_block RECORD;
    v_event_title TEXT;
    v_event_description TEXT;
    v_dupr_min NUMERIC(3, 2);
    v_dupr_max NUMERIC(3, 2);
    v_dupr_label TEXT;
BEGIN
    -- Get the schedule block details
    SELECT * INTO v_block
    FROM events.open_play_schedule_blocks
    WHERE id = NEW.schedule_block_id;

    -- Build event title
    IF v_block.session_type = 'special_event' THEN
        v_event_title := v_block.special_event_name;
    ELSIF v_block.session_type = 'dedicated_skill' THEN
        v_event_title := v_block.name || ' - ' || v_block.dedicated_skill_label;
    ELSE
        v_event_title := v_block.name;
    END IF;

    -- Build description
    v_event_description := COALESCE(v_block.description, '');
    IF v_block.special_instructions IS NOT NULL THEN
        v_event_description := v_event_description || E'\n\n' || v_block.special_instructions;
    END IF;

    -- Determine DUPR range
    IF v_block.session_type = 'dedicated_skill' THEN
        v_dupr_min := v_block.dedicated_skill_min;
        v_dupr_max := v_block.dedicated_skill_max;
        v_dupr_label := v_block.dedicated_skill_label;
    ELSE
        -- For mixed/divided sessions, it's open to all levels
        v_dupr_min := NULL;
        v_dupr_max := NULL;
        v_dupr_label := 'All Levels';
    END IF;

    IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
        -- Check if event already exists
        IF EXISTS (
            SELECT 1 FROM events.events
            WHERE event_type = 'dupr_open_play'
              AND start_time = NEW.start_time
              AND end_time = NEW.end_time
        ) THEN
            -- Update existing event
            UPDATE events.events
            SET
                title = v_event_title,
                description = v_event_description,
                max_capacity = v_block.max_capacity,
                price_member = v_block.price_member,
                price_guest = v_block.price_guest,
                dupr_range_label = v_dupr_label,
                dupr_min_rating = v_dupr_min,
                dupr_max_rating = v_dupr_max,
                is_published = NOT NEW.is_cancelled,
                is_cancelled = NEW.is_cancelled,
                special_instructions = v_block.check_in_instructions,
                updated_at = NOW()
            WHERE event_type = 'dupr_open_play'
              AND start_time = NEW.start_time
              AND end_time = NEW.end_time;
        ELSE
            -- Insert new event
            INSERT INTO events.events (
                title,
                description,
                event_type,
                start_time,
                end_time,
                check_in_time,
                max_capacity,
                min_capacity,
                price_member,
                price_guest,
                skill_levels,
                member_only,
                dupr_range_label,
                dupr_min_rating,
                dupr_max_rating,
                is_published,
                is_cancelled,
                equipment_provided,
                special_instructions,
                created_at,
                updated_at
            ) VALUES (
                v_event_title,
                v_event_description,
                'dupr_open_play',
                NEW.start_time,
                NEW.end_time,
                NEW.start_time - INTERVAL '15 minutes',
                v_block.max_capacity,
                4,
                v_block.price_member,
                v_block.price_guest,
                ARRAY[]::events.skill_level[],
                false,
                v_dupr_label,
                v_dupr_min,
                v_dupr_max,
                NOT NEW.is_cancelled,
                NEW.is_cancelled,
                true,
                v_block.check_in_instructions,
                NOW(),
                NOW()
            );
        END IF;

        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        -- Mark the event as cancelled instead of deleting
        UPDATE events.events
        SET is_cancelled = true,
            is_published = false,
            updated_at = NOW()
        WHERE event_type = 'dupr_open_play'
          AND start_time = OLD.start_time
          AND end_time = OLD.end_time;

        RETURN OLD;
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION events.sync_open_play_instance_to_event IS 'Syncs open_play_instances to events.events table for calendar display';

-- ============================================================================
-- TRIGGER: Sync on Insert/Update/Delete
-- ============================================================================

DROP TRIGGER IF EXISTS trg_sync_instance_to_event ON events.open_play_instances;

CREATE TRIGGER trg_sync_instance_to_event
    AFTER INSERT OR UPDATE OR DELETE
    ON events.open_play_instances
    FOR EACH ROW
    EXECUTE FUNCTION events.sync_open_play_instance_to_event();

COMMENT ON TRIGGER trg_sync_instance_to_event ON events.open_play_instances IS
'Automatically syncs open play instances to the events table';

-- ============================================================================
-- ONE-TIME SYNC: Sync Existing Instances
-- ============================================================================

-- Sync all existing instances to events table
DO $$
DECLARE
    v_instance RECORD;
BEGIN
    FOR v_instance IN
        SELECT * FROM events.open_play_instances
        WHERE NOT is_cancelled
    LOOP
        -- The trigger will handle the sync for each instance
        -- We just need to update the instance to trigger it
        UPDATE events.open_play_instances
        SET generated_at = generated_at
        WHERE id = v_instance.id;
    END LOOP;
END $$;
