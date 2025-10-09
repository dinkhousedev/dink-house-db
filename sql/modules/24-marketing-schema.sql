-- ============================================================================
-- MARKETING SCHEMA MODULE
-- Email marketing campaigns with AI-generated content and analytics
-- ============================================================================

-- Create marketing schema
CREATE SCHEMA IF NOT EXISTS marketing;

-- Set search path
SET search_path TO marketing, public;

COMMENT ON SCHEMA marketing IS 'Marketing email campaigns and analytics';

-- ============================================================================
-- TABLES
-- ============================================================================

-- Main emails table - stores generated marketing emails
CREATE TABLE IF NOT EXISTS marketing.emails (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subject VARCHAR(500) NOT NULL,
    html_content TEXT NOT NULL,
    text_content TEXT,

    -- AI Generation metadata
    source_prompt TEXT,
    grok_model VARCHAR(100) DEFAULT 'grok-code-fast-1',
    content_sources JSONB DEFAULT '[]', -- Array of sources/references cited
    images_email TEXT[] DEFAULT '{}', -- Array of image URLs used in email

    -- Branding
    theme_color VARCHAR(50) DEFAULT '#B3FF00',
    logo_url TEXT DEFAULT 'https://wchxzbuuwssrnaxshseu.supabase.co/storage/v1/object/public/dink-files/dinklogo.jpg',

    -- Status tracking
    status VARCHAR(50) DEFAULT 'draft',
        CHECK (status IN ('draft', 'reviewed', 'scheduled', 'sending', 'sent', 'failed')),

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    reviewed_at TIMESTAMP WITH TIME ZONE,
    scheduled_for TIMESTAMP WITH TIME ZONE,
    sent_at TIMESTAMP WITH TIME ZONE,

    -- Audit
    created_by UUID, -- References auth.users(id) but nullable for system-generated

    -- Metadata
    metadata JSONB DEFAULT '{}'
);

-- Email recipients tracking - one record per recipient per email
CREATE TABLE IF NOT EXISTS marketing.email_recipients (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email_id UUID NOT NULL REFERENCES marketing.emails(id) ON DELETE CASCADE,
    subscriber_id UUID REFERENCES launch.launch_subscribers(id) ON DELETE SET NULL,
    email_address TEXT NOT NULL,

    -- SendGrid tracking
    sendgrid_message_id TEXT,

    -- Status
    status VARCHAR(50) DEFAULT 'pending',
        CHECK (status IN ('pending', 'sent', 'failed', 'bounced', 'dropped', 'deferred')),

    -- Engagement timestamps
    sent_at TIMESTAMP WITH TIME ZONE,
    delivered_at TIMESTAMP WITH TIME ZONE,
    opened_at TIMESTAMP WITH TIME ZONE, -- First open
    last_opened_at TIMESTAMP WITH TIME ZONE, -- Most recent open
    clicked_at TIMESTAMP WITH TIME ZONE, -- First click
    last_clicked_at TIMESTAMP WITH TIME ZONE, -- Most recent click
    bounced_at TIMESTAMP WITH TIME ZONE,

    -- Open and click counts
    open_count INTEGER DEFAULT 0,
    click_count INTEGER DEFAULT 0,

    -- Error tracking
    error_message TEXT,
    bounce_type VARCHAR(50), -- hard, soft, blocked

    -- Additional data
    metadata JSONB DEFAULT '{}',

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- INDEXES
-- ============================================================================

CREATE INDEX idx_emails_status ON marketing.emails(status);
CREATE INDEX idx_emails_created_at ON marketing.emails(created_at DESC);
CREATE INDEX idx_emails_sent_at ON marketing.emails(sent_at DESC) WHERE sent_at IS NOT NULL;

CREATE INDEX idx_recipients_email_id ON marketing.email_recipients(email_id);
CREATE INDEX idx_recipients_subscriber_id ON marketing.email_recipients(subscriber_id) WHERE subscriber_id IS NOT NULL;
CREATE INDEX idx_recipients_status ON marketing.email_recipients(status);
CREATE INDEX idx_recipients_sendgrid_id ON marketing.email_recipients(sendgrid_message_id) WHERE sendgrid_message_id IS NOT NULL;
CREATE INDEX idx_recipients_opened ON marketing.email_recipients(opened_at) WHERE opened_at IS NOT NULL;
CREATE INDEX idx_recipients_clicked ON marketing.email_recipients(clicked_at) WHERE clicked_at IS NOT NULL;

-- ============================================================================
-- VIEWS
-- ============================================================================

-- Email analytics view - comprehensive stats per email
CREATE OR REPLACE VIEW marketing.email_analytics AS
SELECT
    e.id,
    e.subject,
    e.status,
    e.created_at,
    e.sent_at,
    e.grok_model,

    -- Recipient counts
    COUNT(er.id) as total_recipients,
    COUNT(CASE WHEN er.status = 'sent' THEN 1 END) as sent_count,
    COUNT(CASE WHEN er.status = 'failed' THEN 1 END) as failed_count,
    COUNT(CASE WHEN er.status = 'bounced' THEN 1 END) as bounced_count,

    -- Engagement counts
    COUNT(er.delivered_at) as delivered_count,
    COUNT(er.opened_at) as unique_opens,
    COUNT(er.clicked_at) as unique_clicks,
    SUM(er.open_count) as total_opens,
    SUM(er.click_count) as total_clicks,

    -- Rates (as percentages)
    ROUND(
        (COUNT(er.delivered_at)::numeric / NULLIF(COUNT(CASE WHEN er.status = 'sent' THEN 1 END), 0)) * 100,
        2
    ) as delivery_rate,
    ROUND(
        (COUNT(er.opened_at)::numeric / NULLIF(COUNT(er.delivered_at), 0)) * 100,
        2
    ) as open_rate,
    ROUND(
        (COUNT(er.clicked_at)::numeric / NULLIF(COUNT(er.delivered_at), 0)) * 100,
        2
    ) as click_rate,
    ROUND(
        (COUNT(er.clicked_at)::numeric / NULLIF(COUNT(er.opened_at), 0)) * 100,
        2
    ) as click_to_open_rate,
    ROUND(
        (COUNT(CASE WHEN er.status = 'bounced' THEN 1 END)::numeric / NULLIF(COUNT(er.id), 0)) * 100,
        2
    ) as bounce_rate,

    -- Timing
    EXTRACT(EPOCH FROM (MIN(er.opened_at) - e.sent_at)) / 60 as minutes_to_first_open,
    EXTRACT(EPOCH FROM (MIN(er.clicked_at) - e.sent_at)) / 60 as minutes_to_first_click

FROM marketing.emails e
LEFT JOIN marketing.email_recipients er ON e.id = er.email_id
GROUP BY e.id, e.subject, e.status, e.created_at, e.sent_at, e.grok_model;

-- Campaign overview - aggregate stats
CREATE OR REPLACE VIEW marketing.campaign_overview AS
SELECT
    DATE_TRUNC('day', e.sent_at) as sent_date,
    COUNT(DISTINCT e.id) as emails_sent,
    COUNT(er.id) as total_recipients,
    COUNT(er.opened_at) as total_opens,
    COUNT(er.clicked_at) as total_clicks,
    ROUND(
        (COUNT(er.opened_at)::numeric / NULLIF(COUNT(er.id), 0)) * 100,
        2
    ) as avg_open_rate,
    ROUND(
        (COUNT(er.clicked_at)::numeric / NULLIF(COUNT(er.id), 0)) * 100,
        2
    ) as avg_click_rate
FROM marketing.emails e
LEFT JOIN marketing.email_recipients er ON e.id = er.email_id
WHERE e.sent_at IS NOT NULL
GROUP BY DATE_TRUNC('day', e.sent_at)
ORDER BY sent_date DESC;

-- Top performers - emails with best engagement
CREATE OR REPLACE VIEW marketing.top_performing_emails AS
SELECT
    e.id,
    e.subject,
    e.sent_at,
    COUNT(er.opened_at) as opens,
    COUNT(er.clicked_at) as clicks,
    ROUND(
        (COUNT(er.opened_at)::numeric / NULLIF(COUNT(er.id), 0)) * 100,
        2
    ) as open_rate,
    ROUND(
        (COUNT(er.clicked_at)::numeric / NULLIF(COUNT(er.id), 0)) * 100,
        2
    ) as click_rate
FROM marketing.emails e
LEFT JOIN marketing.email_recipients er ON e.id = er.email_id
WHERE e.status = 'sent'
GROUP BY e.id, e.subject, e.sent_at
HAVING COUNT(er.id) > 0
ORDER BY open_rate DESC, click_rate DESC
LIMIT 20;

-- ============================================================================
-- FUNCTIONS
-- ============================================================================

-- Update timestamp function
CREATE OR REPLACE FUNCTION marketing.update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger for email_recipients updated_at
CREATE TRIGGER update_email_recipients_updated_at
    BEFORE UPDATE ON marketing.email_recipients
    FOR EACH ROW
    EXECUTE FUNCTION marketing.update_updated_at();

-- Function to mark email as opened
CREATE OR REPLACE FUNCTION marketing.mark_email_opened(
    p_sendgrid_message_id TEXT,
    p_opened_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
)
RETURNS BOOLEAN AS $$
DECLARE
    v_recipient_id UUID;
BEGIN
    -- Find recipient by SendGrid message ID
    SELECT id INTO v_recipient_id
    FROM marketing.email_recipients
    WHERE sendgrid_message_id = p_sendgrid_message_id;

    IF v_recipient_id IS NULL THEN
        RETURN FALSE;
    END IF;

    -- Update open tracking
    UPDATE marketing.email_recipients
    SET
        opened_at = COALESCE(opened_at, p_opened_at),
        last_opened_at = p_opened_at,
        open_count = open_count + 1,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = v_recipient_id;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- Function to mark email as clicked
CREATE OR REPLACE FUNCTION marketing.mark_email_clicked(
    p_sendgrid_message_id TEXT,
    p_clicked_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
)
RETURNS BOOLEAN AS $$
DECLARE
    v_recipient_id UUID;
BEGIN
    -- Find recipient by SendGrid message ID
    SELECT id INTO v_recipient_id
    FROM marketing.email_recipients
    WHERE sendgrid_message_id = p_sendgrid_message_id;

    IF v_recipient_id IS NULL THEN
        RETURN FALSE;
    END IF;

    -- Update click tracking
    UPDATE marketing.email_recipients
    SET
        clicked_at = COALESCE(clicked_at, p_clicked_at),
        last_clicked_at = p_clicked_at,
        click_count = click_count + 1,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = v_recipient_id;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- PERMISSIONS
-- ============================================================================

-- Grant usage on schema
GRANT USAGE ON SCHEMA marketing TO authenticated, service_role;

-- Service role (Edge Functions) needs full access
GRANT ALL ON ALL TABLES IN SCHEMA marketing TO service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA marketing TO service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA marketing TO service_role;

-- Authenticated users (admins) need read access for analytics
GRANT SELECT ON ALL TABLES IN SCHEMA marketing TO authenticated;
GRANT SELECT ON marketing.email_analytics TO authenticated;
GRANT SELECT ON marketing.campaign_overview TO authenticated;
GRANT SELECT ON marketing.top_performing_emails TO authenticated;

-- Anonymous users have no access to marketing data
-- (tracking webhooks use service_role)

COMMENT ON TABLE marketing.emails IS 'AI-generated marketing emails with engagement tracking';
COMMENT ON TABLE marketing.email_recipients IS 'Individual recipient tracking for each email campaign';
COMMENT ON VIEW marketing.email_analytics IS 'Comprehensive analytics per email campaign';
COMMENT ON VIEW marketing.campaign_overview IS 'Aggregate campaign performance over time';
COMMENT ON VIEW marketing.top_performing_emails IS 'Best performing emails by engagement rate';
