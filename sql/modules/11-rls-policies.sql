-- ============================================================================
-- ROW LEVEL SECURITY POLICIES MODULE
-- Implement RLS policies for all tables
-- ============================================================================

-- Enable RLS on all tables
ALTER TABLE app_auth.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_auth.sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_auth.refresh_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_auth.api_keys ENABLE ROW LEVEL SECURITY;

ALTER TABLE content.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE content.pages ENABLE ROW LEVEL SECURITY;
ALTER TABLE content.page_revisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE content.media_files ENABLE ROW LEVEL SECURITY;

ALTER TABLE contact.contact_forms ENABLE ROW LEVEL SECURITY;
ALTER TABLE contact.contact_inquiries ENABLE ROW LEVEL SECURITY;
ALTER TABLE contact.contact_responses ENABLE ROW LEVEL SECURITY;

ALTER TABLE launch.launch_campaigns ENABLE ROW LEVEL SECURITY;
ALTER TABLE launch.launch_subscribers ENABLE ROW LEVEL SECURITY;
ALTER TABLE launch.launch_waitlist ENABLE ROW LEVEL SECURITY;
ALTER TABLE launch.launch_referrals ENABLE ROW LEVEL SECURITY;
ALTER TABLE launch.notification_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE launch.notification_queue ENABLE ROW LEVEL SECURITY;

ALTER TABLE system.system_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE system.activity_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE system.system_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE system.feature_flags ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- AUTHENTICATION POLICIES
-- ============================================================================

-- Users table policies
CREATE POLICY "users_public_read" ON app_auth.users
    FOR SELECT
    TO anon, authenticated
    USING (is_active = true AND is_verified = true);

CREATE POLICY "users_self_read" ON app_auth.users
    FOR SELECT
    TO authenticated
    USING (id = auth.uid());

CREATE POLICY "users_self_update" ON app_auth.users
    FOR UPDATE
    TO authenticated
    USING (id = auth.uid())
    WITH CHECK (id = auth.uid() AND role = role); -- Prevent role escalation

CREATE POLICY "users_admin_all" ON app_auth.users
    FOR ALL
    TO authenticated
    USING (auth.jwt() ->> 'role' IN ('admin', 'super_admin'));

-- Sessions table policies
CREATE POLICY "sessions_own_read" ON app_auth.sessions
    FOR SELECT
    TO authenticated
    USING (user_id = auth.uid());

CREATE POLICY "sessions_own_delete" ON app_auth.sessions
    FOR DELETE
    TO authenticated
    USING (user_id = auth.uid());

CREATE POLICY "sessions_service_all" ON app_auth.sessions
    FOR ALL
    TO service_role
    USING (true);

-- Refresh tokens policies
CREATE POLICY "refresh_tokens_own" ON app_auth.refresh_tokens
    FOR ALL
    TO authenticated
    USING (user_id = auth.uid());

CREATE POLICY "refresh_tokens_service" ON app_auth.refresh_tokens
    FOR ALL
    TO service_role
    USING (true);

-- API keys policies
CREATE POLICY "api_keys_own_read" ON app_auth.api_keys
    FOR SELECT
    TO authenticated
    USING (user_id = auth.uid());

CREATE POLICY "api_keys_admin_all" ON app_auth.api_keys
    FOR ALL
    TO authenticated
    USING (auth.jwt() ->> 'role' IN ('admin', 'super_admin'));

-- ============================================================================
-- CONTENT POLICIES
-- ============================================================================

-- Categories policies
CREATE POLICY "categories_public_read" ON content.categories
    FOR SELECT
    TO anon, authenticated
    USING (is_active = true);

CREATE POLICY "categories_editor_insert" ON content.categories
    FOR INSERT
    TO authenticated
    WITH CHECK (auth.jwt() ->> 'role' IN ('editor', 'admin', 'super_admin'));

CREATE POLICY "categories_editor_update" ON content.categories
    FOR UPDATE
    TO authenticated
    USING (auth.jwt() ->> 'role' IN ('editor', 'admin', 'super_admin'))
    WITH CHECK (auth.jwt() ->> 'role' IN ('editor', 'admin', 'super_admin'));

CREATE POLICY "categories_admin_delete" ON content.categories
    FOR DELETE
    TO authenticated
    USING (auth.jwt() ->> 'role' IN ('admin', 'super_admin'));

-- Pages policies
CREATE POLICY "pages_published_read" ON content.pages
    FOR SELECT
    TO anon, authenticated
    USING (status = 'published' AND published_at <= CURRENT_TIMESTAMP);

CREATE POLICY "pages_own_drafts_read" ON content.pages
    FOR SELECT
    TO authenticated
    USING (author_id = auth.uid() AND status = 'draft');

CREATE POLICY "pages_editor_read" ON content.pages
    FOR SELECT
    TO authenticated
    USING (auth.jwt() ->> 'role' IN ('editor', 'admin', 'super_admin'));

CREATE POLICY "pages_author_insert" ON content.pages
    FOR INSERT
    TO authenticated
    WITH CHECK (
        author_id = auth.uid() AND
        (status = 'draft' OR auth.jwt() ->> 'role' IN ('editor', 'admin', 'super_admin'))
    );

CREATE POLICY "pages_author_update" ON content.pages
    FOR UPDATE
    TO authenticated
    USING (author_id = auth.uid() OR auth.jwt() ->> 'role' IN ('editor', 'admin', 'super_admin'))
    WITH CHECK (author_id = auth.uid() OR auth.jwt() ->> 'role' IN ('editor', 'admin', 'super_admin'));

CREATE POLICY "pages_editor_delete" ON content.pages
    FOR DELETE
    TO authenticated
    USING (auth.jwt() ->> 'role' IN ('editor', 'admin', 'super_admin'));

-- Page revisions policies
CREATE POLICY "revisions_page_author_read" ON content.page_revisions
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM content.pages p
            WHERE p.id = page_id
            AND (p.author_id = auth.uid() OR auth.jwt() ->> 'role' IN ('editor', 'admin', 'super_admin'))
        )
    );

CREATE POLICY "revisions_insert" ON content.page_revisions
    FOR INSERT
    TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM content.pages p
            WHERE p.id = page_id
            AND (p.author_id = auth.uid() OR auth.jwt() ->> 'role' IN ('editor', 'admin', 'super_admin'))
        )
    );

-- Media files policies
CREATE POLICY "media_public_read" ON content.media_files
    FOR SELECT
    TO anon, authenticated
    USING (is_public = true);

CREATE POLICY "media_own_read" ON content.media_files
    FOR SELECT
    TO authenticated
    USING (uploaded_by = auth.uid());

CREATE POLICY "media_own_insert" ON content.media_files
    FOR INSERT
    TO authenticated
    WITH CHECK (uploaded_by = auth.uid());

CREATE POLICY "media_own_update" ON content.media_files
    FOR UPDATE
    TO authenticated
    USING (uploaded_by = auth.uid())
    WITH CHECK (uploaded_by = auth.uid());

CREATE POLICY "media_own_delete" ON content.media_files
    FOR DELETE
    TO authenticated
    USING (uploaded_by = auth.uid() OR auth.jwt() ->> 'role' IN ('admin', 'super_admin'));

-- ============================================================================
-- CONTACT POLICIES
-- ============================================================================

-- Contact forms policies
CREATE POLICY "contact_forms_public_read" ON contact.contact_forms
    FOR SELECT
    TO anon, authenticated
    USING (is_active = true);

CREATE POLICY "contact_forms_admin_all" ON contact.contact_forms
    FOR ALL
    TO authenticated
    USING (auth.jwt() ->> 'role' IN ('admin', 'super_admin'));

-- Contact inquiries policies
CREATE POLICY "inquiries_public_insert" ON contact.contact_inquiries
    FOR INSERT
    TO anon, authenticated
    WITH CHECK (true); -- Anyone can submit

CREATE POLICY "inquiries_own_read" ON contact.contact_inquiries
    FOR SELECT
    TO authenticated
    USING (
        submitted_by = auth.uid() OR
        assigned_to = auth.uid() OR
        auth.jwt() ->> 'role' IN ('editor', 'admin', 'super_admin')
    );

CREATE POLICY "inquiries_assigned_update" ON contact.contact_inquiries
    FOR UPDATE
    TO authenticated
    USING (assigned_to = auth.uid() OR auth.jwt() ->> 'role' IN ('admin', 'super_admin'))
    WITH CHECK (assigned_to = auth.uid() OR auth.jwt() ->> 'role' IN ('admin', 'super_admin'));

CREATE POLICY "inquiries_admin_delete" ON contact.contact_inquiries
    FOR DELETE
    TO authenticated
    USING (auth.jwt() ->> 'role' IN ('admin', 'super_admin'));

-- Contact responses policies
CREATE POLICY "responses_related_read" ON contact.contact_responses
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM contact.contact_inquiries ci
            WHERE ci.id = inquiry_id
            AND (ci.submitted_by = auth.uid() OR ci.assigned_to = auth.uid() OR auth.jwt() ->> 'role' IN ('admin', 'super_admin'))
        )
    );

CREATE POLICY "responses_staff_insert" ON contact.contact_responses
    FOR INSERT
    TO authenticated
    WITH CHECK (
        responded_by = auth.uid() AND
        EXISTS (
            SELECT 1 FROM contact.contact_inquiries ci
            WHERE ci.id = inquiry_id
            AND (ci.assigned_to = auth.uid() OR auth.jwt() ->> 'role' IN ('admin', 'super_admin'))
        )
    );

-- ============================================================================
-- LAUNCH CAMPAIGN POLICIES
-- ============================================================================

-- Launch campaigns policies
CREATE POLICY "campaigns_active_read" ON launch.launch_campaigns
    FOR SELECT
    TO anon, authenticated
    USING (is_active = true AND status = 'active');

CREATE POLICY "campaigns_admin_all" ON launch.launch_campaigns
    FOR ALL
    TO authenticated
    USING (auth.jwt() ->> 'role' IN ('admin', 'super_admin'));

-- Launch subscribers policies
CREATE POLICY "subscribers_public_insert" ON launch.launch_subscribers
    FOR INSERT
    TO anon, authenticated
    WITH CHECK (true); -- Anyone can subscribe

CREATE POLICY "subscribers_own_read" ON launch.launch_subscribers
    FOR SELECT
    TO authenticated
    USING (
        (user_id IS NOT NULL AND user_id = auth.uid()) OR
        auth.jwt() ->> 'role' IN ('admin', 'super_admin')
    );

CREATE POLICY "subscribers_own_update" ON launch.launch_subscribers
    FOR UPDATE
    TO authenticated
    USING (user_id IS NOT NULL AND user_id = auth.uid())
    WITH CHECK (user_id IS NOT NULL AND user_id = auth.uid());

CREATE POLICY "subscribers_admin_all" ON launch.launch_subscribers
    FOR ALL
    TO authenticated
    USING (auth.jwt() ->> 'role' IN ('admin', 'super_admin'));

-- Launch waitlist policies
CREATE POLICY "waitlist_public_insert" ON launch.launch_waitlist
    FOR INSERT
    TO anon, authenticated
    WITH CHECK (true);

CREATE POLICY "waitlist_admin_all" ON launch.launch_waitlist
    FOR ALL
    TO authenticated
    USING (auth.jwt() ->> 'role' IN ('admin', 'super_admin'));

-- Launch referrals policies
CREATE POLICY "referrals_own_read" ON launch.launch_referrals
    FOR SELECT
    TO authenticated
    USING (
        referrer_id IN (
            SELECT id FROM launch.launch_subscribers
            WHERE user_id = auth.uid()
        )
    );

CREATE POLICY "referrals_insert" ON launch.launch_referrals
    FOR INSERT
    TO anon, authenticated
    WITH CHECK (true);

CREATE POLICY "referrals_admin_all" ON launch.launch_referrals
    FOR ALL
    TO authenticated
    USING (auth.jwt() ->> 'role' IN ('admin', 'super_admin'));

-- Notification templates policies
CREATE POLICY "templates_admin_all" ON launch.notification_templates
    FOR ALL
    TO authenticated
    USING (auth.jwt() ->> 'role' IN ('admin', 'super_admin'));

-- Notification queue policies
CREATE POLICY "queue_admin_all" ON launch.notification_queue
    FOR ALL
    TO authenticated
    USING (auth.jwt() ->> 'role' IN ('admin', 'super_admin'));

-- ============================================================================
-- SYSTEM POLICIES
-- ============================================================================

-- System settings policies
CREATE POLICY "settings_public_read" ON system.system_settings
    FOR SELECT
    TO anon, authenticated
    USING (is_public = true);

CREATE POLICY "settings_authenticated_read" ON system.system_settings
    FOR SELECT
    TO authenticated
    USING (true);

CREATE POLICY "settings_admin_all" ON system.system_settings
    FOR ALL
    TO authenticated
    USING (auth.jwt() ->> 'role' IN ('super_admin'));

-- Activity logs policies
CREATE POLICY "logs_own_read" ON system.activity_logs
    FOR SELECT
    TO authenticated
    USING (user_id = auth.uid());

CREATE POLICY "logs_admin_read" ON system.activity_logs
    FOR SELECT
    TO authenticated
    USING (auth.jwt() ->> 'role' IN ('admin', 'super_admin'));

CREATE POLICY "logs_system_insert" ON system.activity_logs
    FOR INSERT
    TO authenticated, service_role
    WITH CHECK (true);

-- System jobs policies
CREATE POLICY "jobs_admin_all" ON system.system_jobs
    FOR ALL
    TO authenticated
    USING (auth.jwt() ->> 'role' IN ('super_admin'));

CREATE POLICY "jobs_service_all" ON system.system_jobs
    FOR ALL
    TO service_role
    USING (true);

-- Feature flags policies
CREATE POLICY "flags_public_read" ON system.feature_flags
    FOR SELECT
    TO anon, authenticated
    USING (is_enabled = true);

CREATE POLICY "flags_admin_all" ON system.feature_flags
    FOR ALL
    TO authenticated
    USING (auth.jwt() ->> 'role' IN ('super_admin'));

-- ============================================================================
-- GRANT SCHEMA USAGE
-- ============================================================================

-- Grant usage on schemas to roles
GRANT USAGE ON SCHEMA auth TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA content TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA contact TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA launch TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA system TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA api TO anon, authenticated, service_role;