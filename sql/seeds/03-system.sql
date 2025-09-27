-- ============================================================================
-- SEED DATA: System Settings
-- Default configuration values
-- ============================================================================

-- Set search path for system management
SET search_path TO system, launch, auth, public;

-- Insert default system settings
INSERT INTO system.system_settings (setting_key, setting_value, setting_type, category, description, is_public)
VALUES
    -- General settings
    ('site_name', 'Dink House CMS', 'string', 'general', 'Website name', true),
    ('site_url', 'http://localhost:3000', 'string', 'general', 'Website URL', true),
    ('site_description', 'A powerful content management system', 'string', 'general', 'Site description', true),
    ('timezone', 'America/New_York', 'string', 'general', 'Default timezone', false),
    ('date_format', 'YYYY-MM-DD', 'string', 'general', 'Date format', false),
    ('time_format', 'HH:mm:ss', 'string', 'general', 'Time format', false),

    -- Email settings
    ('smtp_enabled', 'false', 'boolean', 'email', 'Enable SMTP email sending', false),
    ('smtp_host', 'smtp.gmail.com', 'string', 'email', 'SMTP server host', false),
    ('smtp_port', '587', 'number', 'email', 'SMTP server port', false),
    ('smtp_secure', 'true', 'boolean', 'email', 'Use TLS/SSL for SMTP', false),
    ('smtp_username', '', 'string', 'email', 'SMTP username', false),
    ('smtp_password', '', 'string', 'email', 'SMTP password (encrypted)', false),
    ('email_from_address', 'noreply@dinkhouse.com', 'string', 'email', 'Default from email', false),
    ('email_from_name', 'Dink House', 'string', 'email', 'Default from name', false),

    -- Contact settings
    ('contact_email', 'contact@dinkhouse.com', 'string', 'contact', 'Contact email address', true),
    ('contact_phone', '+1 (555) 123-4567', 'string', 'contact', 'Contact phone number', true),
    ('contact_address', '123 Main St, Suite 100', 'string', 'contact', 'Contact address', true),
    ('contact_auto_response', 'true', 'boolean', 'contact', 'Send automatic response to inquiries', false),

    -- Launch notification settings
    ('launch_notifications_enabled', 'true', 'boolean', 'launch', 'Enable launch notifications', false),
    ('launch_double_optin', 'true', 'boolean', 'launch', 'Require double opt-in for subscribers', false),
    ('launch_welcome_email', 'true', 'boolean', 'launch', 'Send welcome email to new subscribers', false),
    ('launch_batch_size', '100', 'number', 'launch', 'Batch size for sending notifications', false),

    -- Security settings
    ('password_min_length', '8', 'number', 'security', 'Minimum password length', false),
    ('password_require_uppercase', 'true', 'boolean', 'security', 'Require uppercase letters', false),
    ('password_require_numbers', 'true', 'boolean', 'security', 'Require numbers', false),
    ('password_require_special', 'true', 'boolean', 'security', 'Require special characters', false),
    ('session_timeout', '3600', 'number', 'security', 'Session timeout in seconds', false),
    ('max_login_attempts', '5', 'number', 'security', 'Maximum login attempts before lockout', false),
    ('lockout_duration', '900', 'number', 'security', 'Lockout duration in seconds', false),

    -- Media settings
    ('media_max_file_size', '10485760', 'number', 'media', 'Maximum file size in bytes (10MB)', false),
    ('media_allowed_types', '["image/jpeg", "image/png", "image/gif", "image/webp", "application/pdf"]', 'json', 'media', 'Allowed MIME types', false),
    ('media_storage_path', '/uploads', 'string', 'media', 'Media storage path', false),
    ('media_optimize_images', 'true', 'boolean', 'media', 'Automatically optimize uploaded images', false),

    -- API settings
    ('api_rate_limit', '100', 'number', 'api', 'API rate limit per minute', false),
    ('api_cors_enabled', 'true', 'boolean', 'api', 'Enable CORS', false),
    ('api_cors_origins', '["http://localhost:3000", "http://localhost:3001"]', 'json', 'api', 'Allowed CORS origins', false),

    -- Feature flags
    ('feature_blog', 'true', 'boolean', 'features', 'Enable blog functionality', false),
    ('feature_comments', 'false', 'boolean', 'features', 'Enable comments', false),
    ('feature_search', 'true', 'boolean', 'features', 'Enable search functionality', false),
    ('feature_analytics', 'false', 'boolean', 'features', 'Enable analytics', false),
    ('maintenance_mode', 'false', 'boolean', 'features', 'Enable maintenance mode', false);

-- Insert notification templates
INSERT INTO launch.notification_templates (name, slug, template_type, category, subject, html_content, text_content, is_active, created_by)
SELECT
    'Welcome Email',
    'welcome-email',
    'email',
    'welcome',
    'Welcome to {{site_name}}!',
    '<html><body><h1>Welcome, {{first_name}}!</h1><p>Thank you for subscribing to our launch notifications. We''ll keep you updated on our latest developments.</p><p>Best regards,<br>The {{site_name}} Team</p></body></html>',
    'Welcome, {{first_name}}! Thank you for subscribing to our launch notifications. We''ll keep you updated on our latest developments. Best regards, The {{site_name}} Team',
    true,
    id
FROM app_auth.admin_users WHERE username = 'admin';

INSERT INTO launch.notification_templates (name, slug, template_type, category, subject, html_content, text_content, is_active, created_by)
SELECT
    'Launch Announcement',
    'launch-announcement',
    'email',
    'launch_notification',
    '🚀 We''ve Launched! - {{campaign_name}}',
    '<html><body><h1>We''re Live!</h1><p>Hi {{first_name}},</p><p>{{campaign_description}}</p><p><a href="{{launch_url}}">Check it out now!</a></p></body></html>',
    'We''re Live! Hi {{first_name}}, {{campaign_description}} Check it out at: {{launch_url}}',
    true,
    id
FROM app_auth.admin_users WHERE username = 'admin';

INSERT INTO launch.notification_templates (name, slug, template_type, category, subject, html_content, text_content, is_active, created_by)
SELECT
    'Contact Confirmation',
    'contact-confirmation',
    'email',
    'confirmation',
    'We received your message',
    '<html><body><h2>Thank you for contacting us</h2><p>Hi {{first_name}},</p><p>We''ve received your inquiry and will respond within 24-48 hours.</p><p>Your reference number is: {{inquiry_id}}</p></body></html>',
    'Thank you for contacting us. Hi {{first_name}}, We''ve received your inquiry and will respond within 24-48 hours. Your reference number is: {{inquiry_id}}',
    true,
    id
FROM app_auth.admin_users WHERE username = 'admin';

-- Insert feature flags
INSERT INTO system.feature_flags (flag_key, name, description, is_enabled, rollout_percentage, created_by)
SELECT
    'new_dashboard',
    'New Dashboard UI',
    'Enable the redesigned dashboard interface',
    false,
    0,
    id
FROM app_auth.admin_users WHERE username = 'admin';

INSERT INTO system.feature_flags (flag_key, name, description, is_enabled, rollout_percentage, created_by)
SELECT
    'advanced_analytics',
    'Advanced Analytics',
    'Enable advanced analytics features',
    false,
    0,
    id
FROM app_auth.admin_users WHERE username = 'admin';