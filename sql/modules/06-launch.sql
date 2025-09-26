-- ============================================================================
-- LAUNCH & NOTIFICATION MODULE
-- Campaign management and subscriber notifications
-- ============================================================================

-- Set search path for launch schema
SET search_path TO launch, public;

-- Launch campaigns
CREATE TABLE IF NOT EXISTS launch.launch_campaigns (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(255) UNIQUE NOT NULL,
    description TEXT,
    campaign_type VARCHAR(50) DEFAULT 'product_launch'
        CHECK (campaign_type IN ('product_launch', 'feature_release', 'announcement', 'newsletter', 'event')),
    launch_date TIMESTAMP WITH TIME ZONE,
    end_date TIMESTAMP WITH TIME ZONE,
    status VARCHAR(50) DEFAULT 'draft'
        CHECK (status IN ('draft', 'scheduled', 'active', 'paused', 'completed', 'cancelled')),
    target_audience JSONB DEFAULT '{}',
    goals JSONB DEFAULT '{}',
    metadata JSONB DEFAULT '{}',
    created_by UUID NOT NULL REFERENCES app_auth.users(id) ON DELETE RESTRICT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Launch subscribers
CREATE TABLE IF NOT EXISTS launch.launch_subscribers (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    email public.CITEXT UNIQUE NOT NULL,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    phone VARCHAR(30),
    company VARCHAR(255),
    job_title VARCHAR(255),
    interests TEXT[],
    preferences JSONB DEFAULT '{}',
    source VARCHAR(100) DEFAULT 'website',
    source_campaign VARCHAR(255),
    referrer_url TEXT,
    subscription_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    double_opt_in BOOLEAN DEFAULT false,
    verification_token VARCHAR(255),
    verified_at TIMESTAMP WITH TIME ZONE,
    is_active BOOLEAN DEFAULT true,
    unsubscribed_at TIMESTAMP WITH TIME ZONE,
    unsubscribe_reason TEXT,
    bounce_count INT DEFAULT 0,
    complaint_count INT DEFAULT 0,
    engagement_score DECIMAL(5,2) DEFAULT 0,
    tags TEXT[],
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Campaign subscribers (many-to-many relationship)
CREATE TABLE IF NOT EXISTS launch.launch_campaign_subscribers (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    campaign_id UUID NOT NULL REFERENCES launch.launch_campaigns(id) ON DELETE CASCADE,
    subscriber_id UUID NOT NULL REFERENCES launch.launch_subscribers(id) ON DELETE CASCADE,
    added_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(campaign_id, subscriber_id)
);

-- Notification templates (created first as it's referenced by launch_notifications)
CREATE TABLE IF NOT EXISTS launch.notification_templates (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(255) UNIQUE NOT NULL,
    template_type VARCHAR(50) NOT NULL
        CHECK (template_type IN ('email', 'sms', 'push', 'in_app')),
    category VARCHAR(100) NOT NULL
        CHECK (category IN ('launch_notification', 'welcome', 'confirmation', 'reminder', 'follow_up', 'newsletter', 'transactional')),
    subject VARCHAR(255),
    html_content TEXT,
    text_content TEXT,
    variables JSONB DEFAULT '{}',
    is_active BOOLEAN DEFAULT true,
    created_by UUID NOT NULL REFERENCES app_auth.users(id) ON DELETE RESTRICT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Launch notifications
CREATE TABLE IF NOT EXISTS launch.launch_notifications (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    campaign_id UUID NOT NULL REFERENCES launch.launch_campaigns(id) ON DELETE CASCADE,
    subscriber_id UUID NOT NULL REFERENCES launch.launch_subscribers(id) ON DELETE CASCADE,
    notification_type VARCHAR(50) NOT NULL
        CHECK (notification_type IN ('email', 'sms', 'push', 'in_app')),
    template_id UUID REFERENCES launch.notification_templates(id) ON DELETE SET NULL,
    subject VARCHAR(255),
    content TEXT,
    status VARCHAR(50) DEFAULT 'pending'
        CHECK (status IN ('pending', 'queued', 'sending', 'sent', 'delivered', 'opened', 'clicked', 'failed', 'bounced', 'complained')),
    scheduled_for TIMESTAMP WITH TIME ZONE,
    sent_at TIMESTAMP WITH TIME ZONE,
    delivered_at TIMESTAMP WITH TIME ZONE,
    opened_at TIMESTAMP WITH TIME ZONE,
    clicked_at TIMESTAMP WITH TIME ZONE,
    failed_at TIMESTAMP WITH TIME ZONE,
    error_message TEXT,
    retry_count INT DEFAULT 0,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Subscriber segments for targeted campaigns
CREATE TABLE IF NOT EXISTS launch.launch_segments (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    criteria JSONB NOT NULL,
    is_dynamic BOOLEAN DEFAULT true,
    subscriber_count INT DEFAULT 0,
    created_by UUID NOT NULL REFERENCES app_auth.users(id) ON DELETE RESTRICT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Segment subscribers (for static segments)
CREATE TABLE IF NOT EXISTS launch.launch_segment_subscribers (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    segment_id UUID NOT NULL REFERENCES launch.launch_segments(id) ON DELETE CASCADE,
    subscriber_id UUID NOT NULL REFERENCES launch.launch_subscribers(id) ON DELETE CASCADE,
    added_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(segment_id, subscriber_id)
);

-- Create indexes for launch tables
CREATE INDEX campaigns_status ON launch.launch_campaigns(status);
CREATE INDEX campaigns_launch_date ON launch.launch_campaigns(launch_date);
CREATE INDEX subscribers_email ON launch.launch_subscribers(email);
CREATE INDEX subscribers_is_active ON launch.launch_subscribers(is_active);
CREATE INDEX campaign_subscribers_campaign_id ON launch.launch_campaign_subscribers(campaign_id);
CREATE INDEX campaign_subscribers_subscriber_id ON launch.launch_campaign_subscribers(subscriber_id);
CREATE INDEX notifications_campaign_id ON launch.launch_notifications(campaign_id);
CREATE INDEX notifications_subscriber_id ON launch.launch_notifications(subscriber_id);
CREATE INDEX notifications_status ON launch.launch_notifications(status);
CREATE INDEX notifications_scheduled_for ON launch.launch_notifications(scheduled_for);
CREATE INDEX templates_slug ON launch.notification_templates(slug);
CREATE INDEX templates_category ON launch.notification_templates(category);