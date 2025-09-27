-- ============================================================================
-- REALTIME CONFIGURATION MODULE
-- Enable real-time subscriptions for tables
-- ============================================================================

-- Create publication for real-time
DROP PUBLICATION IF EXISTS supabase_realtime CASCADE;
CREATE PUBLICATION supabase_realtime;

-- ============================================================================
-- ENABLE REALTIME FOR TABLES
-- ============================================================================

-- Authentication tables
ALTER PUBLICATION supabase_realtime ADD TABLE app_auth.user_accounts;
ALTER PUBLICATION supabase_realtime ADD TABLE app_auth.admin_users;
ALTER PUBLICATION supabase_realtime ADD TABLE app_auth.players;
ALTER PUBLICATION supabase_realtime ADD TABLE app_auth.guest_users;
ALTER PUBLICATION supabase_realtime ADD TABLE app_auth.sessions;

-- Content tables
ALTER PUBLICATION supabase_realtime ADD TABLE content.pages;
ALTER PUBLICATION supabase_realtime ADD TABLE content.categories;
ALTER PUBLICATION supabase_realtime ADD TABLE content.media_files;

-- Contact tables
ALTER PUBLICATION supabase_realtime ADD TABLE contact.contact_inquiries;
ALTER PUBLICATION supabase_realtime ADD TABLE contact.contact_responses;

-- Launch campaign tables
ALTER PUBLICATION supabase_realtime ADD TABLE launch.launch_campaigns;
ALTER PUBLICATION supabase_realtime ADD TABLE launch.launch_subscribers;
-- notification_queue table doesn't exist, using launch_notifications instead
ALTER PUBLICATION supabase_realtime ADD TABLE launch.launch_notifications;

-- System tables
ALTER PUBLICATION supabase_realtime ADD TABLE system.activity_logs;
ALTER PUBLICATION supabase_realtime ADD TABLE system.system_jobs;
ALTER PUBLICATION supabase_realtime ADD TABLE system.feature_flags;

-- ============================================================================
-- REALTIME TRIGGERS
-- ============================================================================

-- Function to notify channel on data changes
CREATE OR REPLACE FUNCTION notify_channel()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    channel_name TEXT;
    payload JSONB;
BEGIN
    -- Determine channel name based on table
    channel_name := TG_TABLE_SCHEMA || '_' || TG_TABLE_NAME || '_changes';

    -- Build payload
    payload := jsonb_build_object(
        'table', TG_TABLE_NAME,
        'schema', TG_TABLE_SCHEMA,
        'action', TG_OP,
        'new', to_jsonb(NEW),
        'old', to_jsonb(OLD),
        'timestamp', CURRENT_TIMESTAMP
    );

    -- Send notification
    PERFORM pg_notify(channel_name, payload::text);

    RETURN NEW;
END;
$$;

-- Create triggers for important tables

-- Content updates trigger
CREATE TRIGGER content_pages_notify
AFTER INSERT OR UPDATE OR DELETE ON content.pages
FOR EACH ROW
EXECUTE FUNCTION notify_channel();

-- Contact form submissions trigger
CREATE TRIGGER contact_inquiries_notify
AFTER INSERT ON contact.contact_inquiries
FOR EACH ROW
EXECUTE FUNCTION notify_channel();

-- Campaign subscription trigger
CREATE TRIGGER launch_subscribers_notify
AFTER INSERT OR UPDATE ON launch.launch_subscribers
FOR EACH ROW
EXECUTE FUNCTION notify_channel();

-- System activity trigger
CREATE TRIGGER activity_logs_notify
AFTER INSERT ON system.activity_logs
FOR EACH ROW
EXECUTE FUNCTION notify_channel();

-- ============================================================================
-- REALTIME FILTERS
-- ============================================================================

-- Function to filter realtime data based on user role
CREATE OR REPLACE FUNCTION realtime_filter(
    p_table_name TEXT,
    p_user_id UUID,
    p_user_role TEXT,
    p_record JSONB
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Admin and super_admin can see everything
    IF p_user_role IN ('admin', 'super_admin') THEN
        RETURN TRUE;
    END IF;

    -- Table-specific filters
    CASE p_table_name
        WHEN 'pages' THEN
            -- Users can see published pages or their own
            RETURN (p_record->>'status' = 'published') OR
                   (p_record->>'author_id' = p_user_id::text);

        WHEN 'contact_inquiries' THEN
            -- Users can see inquiries they submitted or are assigned to
            RETURN (p_record->>'submitted_by' = p_user_id::text) OR
                   (p_record->>'assigned_to' = p_user_id::text);

        WHEN 'launch_subscribers' THEN
            -- Users can only see their own subscriptions
            RETURN (p_record->>'user_id' = p_user_id::text);

        WHEN 'activity_logs' THEN
            -- Users can see their own activity
            RETURN (p_record->>'user_id' = p_user_id::text);

        ELSE
            -- Default: no access
            RETURN FALSE;
    END CASE;
END;
$$;

-- ============================================================================
-- BROADCAST CHANNELS
-- ============================================================================

-- System broadcast channel for announcements
CREATE OR REPLACE FUNCTION broadcast_system_message(
    p_type TEXT,
    p_title TEXT,
    p_message TEXT,
    p_data JSONB DEFAULT '{}'::jsonb
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_payload JSONB;
BEGIN
    v_payload := jsonb_build_object(
        'type', p_type,
        'title', p_title,
        'message', p_message,
        'data', p_data,
        'timestamp', CURRENT_TIMESTAMP
    );

    PERFORM pg_notify('system_broadcast', v_payload::text);
END;
$$;

-- Content update broadcast
CREATE OR REPLACE FUNCTION broadcast_content_update(
    p_page_id UUID,
    p_action TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_page RECORD;
    v_payload JSONB;
BEGIN
    SELECT p.*, u.username
    INTO v_page
    FROM content.pages p
    LEFT JOIN app_auth.admin_users u ON p.author_id = u.id
    WHERE p.id = p_page_id;

    v_payload := jsonb_build_object(
        'action', p_action,
        'page', jsonb_build_object(
            'id', v_page.id,
            'title', v_page.title,
            'slug', v_page.slug,
            'status', v_page.status,
            'author', v_page.username
        ),
        'timestamp', CURRENT_TIMESTAMP
    );

    PERFORM pg_notify('content_updates', v_payload::text);
END;
$$;

-- ============================================================================
-- PRESENCE TRACKING
-- ============================================================================

-- Table for tracking user presence
CREATE TABLE IF NOT EXISTS realtime.presence (
    user_id UUID REFERENCES app_auth.user_accounts(id) ON DELETE CASCADE,
    channel TEXT NOT NULL,
    status TEXT DEFAULT 'online',
    last_seen TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    metadata JSONB DEFAULT '{}'::jsonb,
    PRIMARY KEY (user_id, channel)
);

-- Function to update user presence
CREATE OR REPLACE FUNCTION update_presence(
    p_user_id UUID,
    p_channel TEXT,
    p_status TEXT DEFAULT 'online',
    p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    INSERT INTO realtime.presence (
        user_id,
        channel,
        status,
        metadata,
        last_seen
    ) VALUES (
        p_user_id,
        p_channel,
        p_status,
        p_metadata,
        CURRENT_TIMESTAMP
    )
    ON CONFLICT (user_id, channel)
    DO UPDATE SET
        status = EXCLUDED.status,
        metadata = EXCLUDED.metadata,
        last_seen = CURRENT_TIMESTAMP;
END;
$$;

-- Function to clean up old presence records
CREATE OR REPLACE FUNCTION cleanup_presence()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Remove presence records older than 5 minutes
    DELETE FROM realtime.presence
    WHERE last_seen < CURRENT_TIMESTAMP - INTERVAL '5 minutes';
END;
$$;

-- ============================================================================
-- METRICS AND MONITORING
-- ============================================================================

-- Table for tracking realtime metrics
CREATE TABLE IF NOT EXISTS realtime.metrics (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    channel TEXT NOT NULL,
    event_type TEXT NOT NULL,
    user_id UUID REFERENCES app_auth.user_accounts(id),
    payload_size INT,
    success BOOLEAN DEFAULT true,
    error_message TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Function to log realtime metrics
CREATE OR REPLACE FUNCTION log_realtime_metric(
    p_channel TEXT,
    p_event_type TEXT,
    p_user_id UUID DEFAULT NULL,
    p_payload_size INT DEFAULT 0,
    p_success BOOLEAN DEFAULT true,
    p_error_message TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    INSERT INTO realtime.metrics (
        channel,
        event_type,
        user_id,
        payload_size,
        success,
        error_message
    ) VALUES (
        p_channel,
        p_event_type,
        p_user_id,
        p_payload_size,
        p_success,
        p_error_message
    );

    -- Clean up old metrics (keep only last 7 days)
    DELETE FROM realtime.metrics
    WHERE created_at < CURRENT_TIMESTAMP - INTERVAL '7 days';
END;
$$;

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

-- Grant permissions for realtime functions
GRANT EXECUTE ON FUNCTION notify_channel() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION realtime_filter TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION broadcast_system_message TO authenticated;
GRANT EXECUTE ON FUNCTION broadcast_content_update TO authenticated;
GRANT EXECUTE ON FUNCTION update_presence TO authenticated;
GRANT EXECUTE ON FUNCTION cleanup_presence TO service_role;
GRANT EXECUTE ON FUNCTION log_realtime_metric TO authenticated, service_role;

-- Grant permissions for presence tracking
GRANT SELECT, INSERT, UPDATE, DELETE ON realtime.presence TO authenticated;
GRANT SELECT ON realtime.metrics TO authenticated;
GRANT INSERT ON realtime.metrics TO service_role;
