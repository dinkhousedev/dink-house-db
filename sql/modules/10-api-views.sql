-- ============================================================================
-- API VIEWS MODULE
-- Create views for REST API endpoints in api schema
-- ============================================================================

-- Switch to api schema
SET search_path TO api, auth, content, contact, launch, system, public;

-- ============================================================================
-- USER VIEWS
-- ============================================================================

-- Public user profile view
CREATE OR REPLACE VIEW api.users_public AS
SELECT
    u.id,
    u.username,
    u.first_name,
    u.last_name,
    u.role,
    u.is_active,
    u.is_verified,
    u.created_at
FROM app_auth.users u
WHERE u.is_active = true
  AND u.is_verified = true;

COMMENT ON VIEW api.users_public IS 'Public user profiles for API access';

-- User profile with stats
CREATE OR REPLACE VIEW api.user_profiles AS
SELECT
    u.id,
    u.username,
    u.email,
    u.first_name,
    u.last_name,
    u.role,
    u.is_active,
    u.is_verified,
    u.last_login,
    u.created_at,
    u.updated_at,
    COUNT(DISTINCT p.id) AS total_pages,
    COUNT(DISTINCT ci.id) AS assigned_inquiries
FROM app_auth.users u
LEFT JOIN content.pages p ON p.author_id = u.id
LEFT JOIN contact.contact_inquiries ci ON ci.assigned_to = u.id
GROUP BY u.id;

COMMENT ON VIEW api.user_profiles IS 'User profiles with statistics';

-- ============================================================================
-- CONTENT VIEWS
-- ============================================================================

-- Published content view
CREATE OR REPLACE VIEW api.content_published AS
SELECT
    p.id,
    p.slug,
    p.title,
    p.content,
    p.excerpt,
    p.featured_image,
    p.status,
    p.published_at,
    p.views_count,
    p.meta_title,
    p.meta_description,
    p.meta_keywords,
    c.id AS category_id,
    c.name AS category_name,
    c.slug AS category_slug,
    u.id AS author_id,
    u.username AS author_username,
    u.first_name AS author_first_name,
    u.last_name AS author_last_name,
    p.created_at,
    p.updated_at
FROM content.pages p
LEFT JOIN content.categories c ON p.category_id = c.id
LEFT JOIN app_auth.users u ON p.author_id = u.id
WHERE p.status = 'published'
  AND p.published_at <= CURRENT_TIMESTAMP;

COMMENT ON VIEW api.content_published IS 'Published content for public API access';

-- Content categories with counts
CREATE OR REPLACE VIEW api.categories_with_counts AS
SELECT
    c.id,
    c.name,
    c.slug,
    c.description,
    c.parent_id,
    c.is_active,
    COUNT(DISTINCT p.id) AS page_count,
    c.created_at,
    c.updated_at
FROM content.categories c
LEFT JOIN content.pages p ON p.category_id = c.id AND p.status = 'published'
WHERE c.is_active = true
GROUP BY c.id;

COMMENT ON VIEW api.categories_with_counts IS 'Categories with page counts';

-- Media files view
CREATE OR REPLACE VIEW api.media_files AS
SELECT
    m.id,
    m.filename,
    m.original_name,
    m.mime_type,
    m.file_size,
    m.file_path,
    m.url,
    m.thumbnail_url,
    m.alt_text,
    m.caption,
    m.is_public,
    u.username AS uploaded_by_username,
    m.created_at
FROM content.media_files m
LEFT JOIN app_auth.users u ON m.uploaded_by = u.id
WHERE m.is_public = true;

COMMENT ON VIEW api.media_files IS 'Public media files';

-- ============================================================================
-- CONTACT VIEWS
-- ============================================================================

-- Public contact forms
CREATE OR REPLACE VIEW api.contact_forms_public AS
SELECT
    cf.id,
    cf.name,
    cf.slug,
    cf.description,
    cf.fields,
    cf.submit_button_text,
    cf.success_message,
    cf.is_active
FROM contact.contact_forms cf
WHERE cf.is_active = true;

COMMENT ON VIEW api.contact_forms_public IS 'Public contact forms for submissions';

-- Contact inquiries summary (admin view)
CREATE OR REPLACE VIEW api.contact_inquiries_summary AS
SELECT
    ci.id,
    ci.form_id,
    cf.name AS form_name,
    ci.name,
    ci.email,
    ci.subject,
    ci.status,
    ci.priority,
    ci.assigned_to,
    u.username AS assigned_to_username,
    ci.created_at,
    ci.updated_at
FROM contact.contact_inquiries ci
LEFT JOIN contact.contact_forms cf ON ci.form_id = cf.id
LEFT JOIN app_auth.users u ON ci.assigned_to = u.id;

COMMENT ON VIEW api.contact_inquiries_summary IS 'Contact inquiries summary for admin API';

-- ============================================================================
-- LAUNCH CAMPAIGN VIEWS
-- ============================================================================

-- Active launch campaigns
CREATE OR REPLACE VIEW api.launch_campaigns_active AS
SELECT
    lc.id,
    lc.name,
    lc.slug,
    lc.description,
    lc.start_date,
    lc.end_date,
    lc.target_subscribers,
    lc.current_subscribers,
    lc.conversion_rate,
    lc.is_active,
    lc.campaign_type,
    lc.reward_text,
    lc.terms_conditions,
    lc.privacy_policy_url,
    lc.social_share_text,
    lc.meta_title,
    lc.meta_description,
    lc.og_image
FROM launch.launch_campaigns lc
WHERE lc.is_active = true
  AND lc.status = 'active'
  AND (lc.start_date IS NULL OR lc.start_date <= CURRENT_TIMESTAMP)
  AND (lc.end_date IS NULL OR lc.end_date >= CURRENT_TIMESTAMP);

COMMENT ON VIEW api.launch_campaigns_active IS 'Active launch campaigns for public API';

-- Launch subscriber stats
CREATE OR REPLACE VIEW api.launch_subscriber_stats AS
SELECT
    DATE(created_at) AS signup_date,
    COUNT(*) AS total_signups,
    COUNT(CASE WHEN is_verified = true THEN 1 END) AS verified_signups,
    COUNT(CASE WHEN referral_source IS NOT NULL THEN 1 END) AS referred_signups
FROM launch.launch_subscribers
GROUP BY DATE(created_at)
ORDER BY signup_date DESC;

COMMENT ON VIEW api.launch_subscriber_stats IS 'Launch subscriber statistics by date';

-- ============================================================================
-- SYSTEM VIEWS
-- ============================================================================

-- System settings (public)
CREATE OR REPLACE VIEW api.system_settings_public AS
SELECT
    ss.key,
    ss.value,
    ss.description
FROM system.system_settings ss
WHERE ss.is_public = true;

COMMENT ON VIEW api.system_settings_public IS 'Public system settings';

-- Feature flags
CREATE OR REPLACE VIEW api.feature_flags_active AS
SELECT
    ff.key,
    ff.name,
    ff.description,
    ff.is_enabled
FROM system.feature_flags ff
WHERE ff.is_enabled = true;

COMMENT ON VIEW api.feature_flags_active IS 'Active feature flags';

-- Activity logs summary (admin view)
CREATE OR REPLACE VIEW api.activity_logs_summary AS
SELECT
    DATE(al.created_at) AS activity_date,
    al.action,
    al.entity_type,
    COUNT(*) AS action_count,
    COUNT(DISTINCT al.user_id) AS unique_users
FROM system.activity_logs al
GROUP BY DATE(al.created_at), al.action, al.entity_type
ORDER BY activity_date DESC, action_count DESC;

COMMENT ON VIEW api.activity_logs_summary IS 'Activity logs summary for analytics';

-- ============================================================================
-- DASHBOARD VIEWS
-- ============================================================================

-- Admin dashboard stats
CREATE OR REPLACE VIEW api.dashboard_stats AS
SELECT
    (SELECT COUNT(*) FROM app_auth.users WHERE is_active = true) AS total_users,
    (SELECT COUNT(*) FROM app_auth.users WHERE is_verified = true) AS verified_users,
    (SELECT COUNT(*) FROM content.pages WHERE status = 'published') AS published_pages,
    (SELECT COUNT(*) FROM content.pages WHERE status = 'draft') AS draft_pages,
    (SELECT COUNT(*) FROM contact.contact_inquiries WHERE status = 'new') AS new_inquiries,
    (SELECT COUNT(*) FROM contact.contact_inquiries WHERE status = 'in_progress') AS inquiries_in_progress,
    (SELECT COUNT(*) FROM launch.launch_subscribers WHERE is_verified = true) AS verified_subscribers,
    (SELECT SUM(current_subscribers) FROM launch.launch_campaigns WHERE is_active = true) AS total_campaign_subscribers,
    (SELECT COUNT(*) FROM content.media_files) AS total_media_files,
    (SELECT COUNT(*) FROM system.activity_logs WHERE created_at >= CURRENT_DATE) AS today_activities;

COMMENT ON VIEW api.dashboard_stats IS 'Dashboard statistics for admin panel';

-- Recent activities
CREATE OR REPLACE VIEW api.recent_activities AS
SELECT
    al.id,
    al.user_id,
    u.username,
    u.first_name,
    u.last_name,
    al.action,
    al.entity_type,
    al.entity_id,
    al.details,
    al.ip_address,
    al.created_at
FROM system.activity_logs al
LEFT JOIN app_auth.users u ON al.user_id = u.id
ORDER BY al.created_at DESC
LIMIT 100;

COMMENT ON VIEW api.recent_activities IS 'Recent system activities';

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

-- Grant SELECT on all views to authenticated users
GRANT SELECT ON ALL TABLES IN SCHEMA api TO authenticated;

-- Grant SELECT on public views to anonymous users
GRANT SELECT ON api.users_public TO anon;
GRANT SELECT ON api.content_published TO anon;
GRANT SELECT ON api.categories_with_counts TO anon;
GRANT SELECT ON api.media_files TO anon;
GRANT SELECT ON api.contact_forms_public TO anon;
GRANT SELECT ON api.launch_campaigns_active TO anon;
GRANT SELECT ON api.system_settings_public TO anon;
GRANT SELECT ON api.feature_flags_active TO anon;