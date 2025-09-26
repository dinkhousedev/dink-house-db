-- ============================================================================
-- SYSTEM MODULE
-- System settings, logs, and administrative functions
-- ============================================================================

-- Set search path for system schema
SET search_path TO system, public;

-- System settings
CREATE TABLE IF NOT EXISTS system.system_settings (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    setting_key VARCHAR(255) UNIQUE NOT NULL,
    setting_value TEXT,
    setting_type VARCHAR(50) DEFAULT 'string'
        CHECK (setting_type IN ('string', 'number', 'boolean', 'json', 'array')),
    category VARCHAR(100) DEFAULT 'general',
    description TEXT,
    is_public BOOLEAN DEFAULT false,
    is_encrypted BOOLEAN DEFAULT false,
    validation_rules JSONB,
    updated_by UUID REFERENCES app_auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Activity logs
CREATE TABLE IF NOT EXISTS system.activity_logs (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    user_id UUID REFERENCES app_auth.users(id) ON DELETE SET NULL,
    action VARCHAR(100) NOT NULL,
    entity_type VARCHAR(100) NOT NULL,
    entity_id UUID,
    old_values JSONB,
    new_values JSONB,
    details JSONB,
    ip_address INET,
    user_agent TEXT,
    session_id UUID REFERENCES app_auth.sessions(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- System jobs/tasks queue
CREATE TABLE IF NOT EXISTS system.system_jobs (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    job_type VARCHAR(100) NOT NULL,
    job_name VARCHAR(255) NOT NULL,
    payload JSONB DEFAULT '{}',
    status VARCHAR(50) DEFAULT 'pending'
        CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'cancelled')),
    priority INT DEFAULT 5 CHECK (priority BETWEEN 1 AND 10),
    max_retries INT DEFAULT 3,
    retry_count INT DEFAULT 0,
    scheduled_at TIMESTAMP WITH TIME ZONE,
    started_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,
    failed_at TIMESTAMP WITH TIME ZONE,
    error_message TEXT,
    result JSONB,
    created_by UUID REFERENCES app_auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Email queue for async sending
CREATE TABLE IF NOT EXISTS system.email_queue (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    to_email TEXT[] NOT NULL,
    cc_email TEXT[],
    bcc_email TEXT[],
    from_email VARCHAR(255),
    reply_to VARCHAR(255),
    subject VARCHAR(255) NOT NULL,
    html_body TEXT,
    text_body TEXT,
    attachments JSONB DEFAULT '[]',
    headers JSONB DEFAULT '{}',
    priority INT DEFAULT 5 CHECK (priority BETWEEN 1 AND 10),
    template_id UUID REFERENCES launch.notification_templates(id) ON DELETE SET NULL,
    template_data JSONB,
    status VARCHAR(50) DEFAULT 'queued'
        CHECK (status IN ('queued', 'sending', 'sent', 'failed', 'bounced')),
    attempts INT DEFAULT 0,
    sent_at TIMESTAMP WITH TIME ZONE,
    failed_at TIMESTAMP WITH TIME ZONE,
    error_message TEXT,
    provider_message_id VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Audit trail for compliance
CREATE TABLE IF NOT EXISTS system.audit_trail (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    table_name VARCHAR(100) NOT NULL,
    record_id UUID NOT NULL,
    operation VARCHAR(20) NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
    user_id UUID REFERENCES app_auth.users(id) ON DELETE SET NULL,
    old_data JSONB,
    new_data JSONB,
    changed_fields TEXT[],
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Feature flags for gradual rollouts
CREATE TABLE IF NOT EXISTS system.feature_flags (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    flag_key VARCHAR(255) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    is_enabled BOOLEAN DEFAULT false,
    rollout_percentage INT DEFAULT 0 CHECK (rollout_percentage BETWEEN 0 AND 100),
    conditions JSONB DEFAULT '{}',
    allowed_users UUID[],
    blocked_users UUID[],
    metadata JSONB DEFAULT '{}',
    created_by UUID REFERENCES app_auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for system tables
CREATE INDEX settings_key ON system.system_settings(setting_key);
CREATE INDEX settings_category ON system.system_settings(category);
CREATE INDEX activity_logs_user_id ON system.activity_logs(user_id);
CREATE INDEX activity_logs_entity_type ON system.activity_logs(entity_type);
CREATE INDEX activity_logs_entity_id ON system.activity_logs(entity_id);
CREATE INDEX activity_logs_created_at ON system.activity_logs(created_at);
CREATE INDEX jobs_status ON system.system_jobs(status);
CREATE INDEX jobs_job_type ON system.system_jobs(job_type);
CREATE INDEX jobs_scheduled_at ON system.system_jobs(scheduled_at);
CREATE INDEX email_queue_status ON system.email_queue(status);
CREATE INDEX email_queue_created_at ON system.email_queue(created_at);
CREATE INDEX audit_trail_table_name ON system.audit_trail(table_name);
CREATE INDEX audit_trail_record_id ON system.audit_trail(record_id);
CREATE INDEX audit_trail_user_id ON system.audit_trail(user_id);
CREATE INDEX audit_trail_created_at ON system.audit_trail(created_at);
CREATE INDEX feature_flags_flag_key ON system.feature_flags(flag_key);