-- ============================================================================
-- ROW LEVEL SECURITY POLICIES MODULE
-- Implement RLS policies for all tables using new multi-persona auth model
-- ============================================================================

-- Enable RLS on key tables (idempotent guards)
ALTER TABLE IF EXISTS app_auth.user_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS app_auth.admin_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS app_auth.players ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS app_auth.guest_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS app_auth.sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS app_auth.refresh_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS app_auth.api_keys ENABLE ROW LEVEL SECURITY;

ALTER TABLE IF EXISTS content.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS content.pages ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS content.revisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS content.media_files ENABLE ROW LEVEL SECURITY;

ALTER TABLE IF EXISTS contact.contact_forms ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS contact.contact_inquiries ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS contact.contact_responses ENABLE ROW LEVEL SECURITY;

ALTER TABLE IF EXISTS launch.launch_campaigns ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS launch.launch_subscribers ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS launch.launch_waitlist ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS launch.launch_referrals ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS launch.notification_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS launch.notification_queue ENABLE ROW LEVEL SECURITY;

ALTER TABLE IF EXISTS system.system_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS system.activity_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS system.system_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS system.feature_flags ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- AUTH SCHEMA POLICIES
-- ============================================================================

-- user_accounts: user can read/update their own account; admins and service role have full access
DROP POLICY IF EXISTS user_accounts_self_read ON app_auth.user_accounts;
CREATE POLICY user_accounts_self_read ON app_auth.user_accounts
    FOR SELECT
    TO authenticated
    USING (id = auth.uid());

DROP POLICY IF EXISTS user_accounts_self_update ON app_auth.user_accounts;
CREATE POLICY user_accounts_self_update ON app_auth.user_accounts
    FOR UPDATE
    TO authenticated
    USING (id = auth.uid())
    WITH CHECK (id = auth.uid() AND user_type <> 'guest');

DROP POLICY IF EXISTS user_accounts_admin_manage ON app_auth.user_accounts;
CREATE POLICY user_accounts_admin_manage ON app_auth.user_accounts
    FOR ALL
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('admin', 'super_admin')
    )
    WITH CHECK (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('admin', 'super_admin')
    );

DROP POLICY IF EXISTS user_accounts_service_full ON app_auth.user_accounts;
CREATE POLICY user_accounts_service_full ON app_auth.user_accounts
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- admin_users: admins can see/manage their own profile, super admins/admins can manage everyone
DROP POLICY IF EXISTS admin_users_self_read ON app_auth.admin_users;
CREATE POLICY admin_users_self_read ON app_auth.admin_users
    FOR SELECT
    TO authenticated
    USING (account_id = auth.uid());

DROP POLICY IF EXISTS admin_users_self_update ON app_auth.admin_users;
CREATE POLICY admin_users_self_update ON app_auth.admin_users
    FOR UPDATE
    TO authenticated
    USING (account_id = auth.uid())
    WITH CHECK (account_id = auth.uid());

DROP POLICY IF EXISTS admin_users_admin_manage ON app_auth.admin_users;
CREATE POLICY admin_users_admin_manage ON app_auth.admin_users
    FOR ALL
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('admin', 'super_admin')
    )
    WITH CHECK (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('admin', 'super_admin')
    );

DROP POLICY IF EXISTS admin_users_service_full ON app_auth.admin_users;
CREATE POLICY admin_users_service_full ON app_auth.admin_users
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- players: players can see/update their own record; service role full access
DROP POLICY IF EXISTS players_self_read ON app_auth.players;
CREATE POLICY players_self_read ON app_auth.players
    FOR SELECT
    TO authenticated
    USING (account_id = auth.uid());

DROP POLICY IF EXISTS players_self_update ON app_auth.players;
CREATE POLICY players_self_update ON app_auth.players
    FOR UPDATE
    TO authenticated
    USING (account_id = auth.uid())
    WITH CHECK (account_id = auth.uid());

DROP POLICY IF EXISTS players_admin_manage ON app_auth.players;
CREATE POLICY players_admin_manage ON app_auth.players
    FOR ALL
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('admin', 'super_admin', 'manager', 'coach')
    )
    WITH CHECK (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('admin', 'super_admin', 'manager', 'coach')
    );

DROP POLICY IF EXISTS players_service_full ON app_auth.players;
CREATE POLICY players_service_full ON app_auth.players
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- guest_users: guests can read their own record, but cannot modify; admins/service manage
DROP POLICY IF EXISTS guest_users_self_read ON app_auth.guest_users;
CREATE POLICY guest_users_self_read ON app_auth.guest_users
    FOR SELECT
    TO authenticated
    USING (account_id = auth.uid());

DROP POLICY IF EXISTS guest_users_admin_manage ON app_auth.guest_users;
CREATE POLICY guest_users_admin_manage ON app_auth.guest_users
    FOR ALL
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('admin', 'super_admin', 'manager')
    )
    WITH CHECK (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('admin', 'super_admin', 'manager')
    );

DROP POLICY IF EXISTS guest_users_service_full ON app_auth.guest_users;
CREATE POLICY guest_users_service_full ON app_auth.guest_users
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- sessions: account owners can view/delete their sessions; service role full access
DROP POLICY IF EXISTS sessions_own_read ON app_auth.sessions;
CREATE POLICY sessions_own_read ON app_auth.sessions
    FOR SELECT
    TO authenticated
    USING (account_id = auth.uid());

DROP POLICY IF EXISTS sessions_own_delete ON app_auth.sessions;
CREATE POLICY sessions_own_delete ON app_auth.sessions
    FOR DELETE
    TO authenticated
    USING (account_id = auth.uid());

DROP POLICY IF EXISTS sessions_service_all ON app_auth.sessions;
CREATE POLICY sessions_service_all ON app_auth.sessions
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- refresh tokens
DROP POLICY IF EXISTS refresh_tokens_own ON app_auth.refresh_tokens;
CREATE POLICY refresh_tokens_own ON app_auth.refresh_tokens
    FOR ALL
    TO authenticated
    USING (account_id = auth.uid());

DROP POLICY IF EXISTS refresh_tokens_service ON app_auth.refresh_tokens;
CREATE POLICY refresh_tokens_service ON app_auth.refresh_tokens
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- API keys restricted to admins
DROP POLICY IF EXISTS api_keys_admin_read ON app_auth.api_keys;
CREATE POLICY api_keys_admin_read ON app_auth.api_keys
    FOR SELECT
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND account_id = auth.uid()
    );

DROP POLICY IF EXISTS api_keys_admin_all ON app_auth.api_keys;
CREATE POLICY api_keys_admin_all ON app_auth.api_keys
    FOR ALL
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('admin', 'super_admin')
    )
    WITH CHECK (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('admin', 'super_admin')
    );

DROP POLICY IF EXISTS api_keys_service_all ON app_auth.api_keys;
CREATE POLICY api_keys_service_all ON app_auth.api_keys
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- ============================================================================
-- CONTENT POLICIES (admin-only management)
-- ============================================================================

-- Helper predicate usage: JWT must carry user_type/admin_role claims
DROP POLICY IF EXISTS categories_public_read ON content.categories;
CREATE POLICY categories_public_read ON content.categories
    FOR SELECT
    TO anon, authenticated
    USING (is_active = true);

DROP POLICY IF EXISTS categories_editor_insert ON content.categories;
CREATE POLICY categories_editor_insert ON content.categories
    FOR INSERT
    TO authenticated
    WITH CHECK (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('editor', 'admin', 'super_admin')
    );

DROP POLICY IF EXISTS categories_editor_update ON content.categories;
CREATE POLICY categories_editor_update ON content.categories
    FOR UPDATE
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('editor', 'admin', 'super_admin')
    )
    WITH CHECK (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('editor', 'admin', 'super_admin')
    );

DROP POLICY IF EXISTS categories_admin_delete ON content.categories;
CREATE POLICY categories_admin_delete ON content.categories
    FOR DELETE
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('admin', 'super_admin')
    );

-- Pages policies
DROP POLICY IF EXISTS pages_published_read ON content.pages;
CREATE POLICY pages_published_read ON content.pages
    FOR SELECT
    TO anon, authenticated
    USING (status = 'published' AND published_at <= CURRENT_TIMESTAMP);

DROP POLICY IF EXISTS pages_own_drafts_read ON content.pages;
CREATE POLICY pages_own_drafts_read ON content.pages
    FOR SELECT
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND author_id = auth.uid()
        AND status = 'draft'
    );

DROP POLICY IF EXISTS pages_editor_read ON content.pages;
CREATE POLICY pages_editor_read ON content.pages
    FOR SELECT
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('editor', 'admin', 'super_admin')
    );

DROP POLICY IF EXISTS pages_author_insert ON content.pages;
CREATE POLICY pages_author_insert ON content.pages
    FOR INSERT
    TO authenticated
    WITH CHECK (
        auth.jwt() ->> 'user_type' = 'admin'
        AND (
            author_id = auth.uid()
            AND (
                status = 'draft'
                OR auth.jwt() ->> 'admin_role' IN ('editor', 'admin', 'super_admin')
            )
        )
    );

DROP POLICY IF EXISTS pages_author_update ON content.pages;
CREATE POLICY pages_author_update ON content.pages
    FOR UPDATE
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND (author_id = auth.uid() OR auth.jwt() ->> 'admin_role' IN ('editor', 'admin', 'super_admin'))
    )
    WITH CHECK (
        auth.jwt() ->> 'user_type' = 'admin'
        AND (author_id = auth.uid() OR auth.jwt() ->> 'admin_role' IN ('editor', 'admin', 'super_admin'))
    );

DROP POLICY IF EXISTS pages_editor_delete ON content.pages;
CREATE POLICY pages_editor_delete ON content.pages
    FOR DELETE
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('editor', 'admin', 'super_admin')
    );

-- Page revisions
DROP POLICY IF EXISTS revisions_page_author_read ON content.revisions;
CREATE POLICY revisions_page_author_read ON content.revisions
    FOR SELECT
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND EXISTS (
            SELECT 1 FROM content.pages p
            WHERE p.id = page_id
              AND (p.author_id = auth.uid() OR auth.jwt() ->> 'admin_role' IN ('editor', 'admin', 'super_admin'))
        )
    );

DROP POLICY IF EXISTS revisions_insert ON content.revisions;
CREATE POLICY revisions_insert ON content.revisions
    FOR INSERT
    TO authenticated
    WITH CHECK (
        auth.jwt() ->> 'user_type' = 'admin'
        AND EXISTS (
            SELECT 1 FROM content.pages p
            WHERE p.id = page_id
              AND (p.author_id = auth.uid() OR auth.jwt() ->> 'admin_role' IN ('editor', 'admin', 'super_admin'))
        )
    );

-- Media files
DROP POLICY IF EXISTS media_public_read ON content.media_files;
CREATE POLICY media_public_read ON content.media_files
    FOR SELECT
    TO anon, authenticated
    USING (is_public = true);

DROP POLICY IF EXISTS media_own_read ON content.media_files;
CREATE POLICY media_own_read ON content.media_files
    FOR SELECT
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND uploaded_by = auth.uid()
    );

DROP POLICY IF EXISTS media_own_insert ON content.media_files;
CREATE POLICY media_own_insert ON content.media_files
    FOR INSERT
    TO authenticated
    WITH CHECK (
        auth.jwt() ->> 'user_type' = 'admin'
        AND uploaded_by = auth.uid()
    );

DROP POLICY IF EXISTS media_own_update ON content.media_files;
CREATE POLICY media_own_update ON content.media_files
    FOR UPDATE
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND uploaded_by = auth.uid()
    )
    WITH CHECK (
        auth.jwt() ->> 'user_type' = 'admin'
        AND uploaded_by = auth.uid()
    );

DROP POLICY IF EXISTS media_editor_delete ON content.media_files;
CREATE POLICY media_editor_delete ON content.media_files
    FOR DELETE
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('editor', 'admin', 'super_admin')
    );

-- ============================================================================
-- CONTACT POLICIES
-- ============================================================================

DROP POLICY IF EXISTS inquiries_insert_anon ON contact.contact_inquiries;
CREATE POLICY inquiries_insert_anon ON contact.contact_inquiries
    FOR INSERT
    TO anon, authenticated
    WITH CHECK (true);

DROP POLICY IF EXISTS inquiries_view_admin ON contact.contact_inquiries;
CREATE POLICY inquiries_view_admin ON contact.contact_inquiries
    FOR SELECT
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('manager', 'admin', 'super_admin', 'coach', 'editor')
    );

DROP POLICY IF EXISTS inquiries_self_view ON contact.contact_inquiries;
CREATE POLICY inquiries_self_view ON contact.contact_inquiries
    FOR SELECT
    TO authenticated
    USING (
        (email = auth.jwt() ->> 'email')
        OR (
            auth.jwt() ->> 'user_type' = 'admin'
            AND assigned_to = auth.uid()
        )
    );

DROP POLICY IF EXISTS inquiries_admin_update ON contact.contact_inquiries;
CREATE POLICY inquiries_admin_update ON contact.contact_inquiries
    FOR UPDATE
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('manager', 'admin', 'super_admin', 'coach')
    )
    WITH CHECK (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('manager', 'admin', 'super_admin', 'coach')
    );

DROP POLICY IF EXISTS responses_admin_manage ON contact.contact_responses;
CREATE POLICY responses_admin_manage ON contact.contact_responses
    FOR ALL
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('manager', 'admin', 'super_admin', 'coach', 'editor')
    )
    WITH CHECK (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('manager', 'admin', 'super_admin', 'coach', 'editor')
    );

-- ============================================================================
-- LAUNCH / SYSTEM POLICIES
-- ============================================================================

-- For brevity, allow admins (manager+) and service role full access
DROP POLICY IF EXISTS launch_admin_all ON launch.launch_campaigns;
CREATE POLICY launch_admin_all ON launch.launch_campaigns
    FOR ALL
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('manager', 'admin', 'super_admin', 'coach', 'editor')
    )
    WITH CHECK (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('manager', 'admin', 'super_admin', 'coach', 'editor')
    );

DROP POLICY IF EXISTS launch_service_all ON launch.launch_campaigns;
CREATE POLICY launch_service_all ON launch.launch_campaigns
    FOR ALL TO service_role USING (true) WITH CHECK (true);

-- Subscribers can self-manage entries via email match
DROP POLICY IF EXISTS launch_subscribers_self_manage ON launch.launch_subscribers;
CREATE POLICY launch_subscribers_self_manage ON launch.launch_subscribers
    FOR SELECT
    TO authenticated
    USING (email = auth.jwt() ->> 'email');

DROP POLICY IF EXISTS launch_subscribers_insert_public ON launch.launch_subscribers;
CREATE POLICY launch_subscribers_insert_public ON launch.launch_subscribers
    FOR INSERT
    TO anon, authenticated
    WITH CHECK (true);

DROP POLICY IF EXISTS launch_subscribers_admin_manage ON launch.launch_subscribers;
CREATE POLICY launch_subscribers_admin_manage ON launch.launch_subscribers
    FOR ALL
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('manager', 'admin', 'super_admin', 'coach', 'editor')
    )
    WITH CHECK (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('manager', 'admin', 'super_admin', 'coach', 'editor')
    );

-- System schema: only admin (admin role) and service role
DROP POLICY IF EXISTS system_settings_public_read ON system.system_settings;
CREATE POLICY system_settings_public_read ON system.system_settings
    FOR SELECT
    TO anon, authenticated
    USING (is_public = true);

DROP POLICY IF EXISTS system_settings_admin_all ON system.system_settings;
CREATE POLICY system_settings_admin_all ON system.system_settings
    FOR ALL
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('admin', 'super_admin')
    )
    WITH CHECK (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('admin', 'super_admin')
    );

DROP POLICY IF EXISTS system_settings_service_all ON system.system_settings;
CREATE POLICY system_settings_service_all ON system.system_settings
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- Activity logs (read-only for admins; service full)
DROP POLICY IF EXISTS activity_logs_admin_read ON system.activity_logs;
CREATE POLICY activity_logs_admin_read ON system.activity_logs
    FOR SELECT
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('manager', 'admin', 'super_admin')
    );

DROP POLICY IF EXISTS activity_logs_service_all ON system.activity_logs;
CREATE POLICY activity_logs_service_all ON system.activity_logs
    FOR ALL TO service_role USING (true) WITH CHECK (true);

-- Jobs / feature flags reserved for admins & service
DROP POLICY IF EXISTS system_jobs_admin_manage ON system.system_jobs;
CREATE POLICY system_jobs_admin_manage ON system.system_jobs
    FOR ALL
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('admin', 'super_admin')
    )
    WITH CHECK (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('admin', 'super_admin')
    );

DROP POLICY IF EXISTS system_jobs_service_all ON system.system_jobs;
CREATE POLICY system_jobs_service_all ON system.system_jobs
    FOR ALL TO service_role USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS feature_flags_admin_manage ON system.feature_flags;
CREATE POLICY feature_flags_admin_manage ON system.feature_flags
    FOR ALL
    TO authenticated
    USING (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('admin', 'super_admin')
    )
    WITH CHECK (
        auth.jwt() ->> 'user_type' = 'admin'
        AND auth.jwt() ->> 'admin_role' IN ('admin', 'super_admin')
    );

DROP POLICY IF EXISTS feature_flags_service_all ON system.feature_flags;
CREATE POLICY feature_flags_service_all ON system.feature_flags
    FOR ALL TO service_role USING (true) WITH CHECK (true);

-- ============================================================================
-- NOTES
-- ============================================================================
-- Policies assume JWT claims include:
--   user_type  -> 'admin' | 'player' | 'guest'
--   admin_role -> enum value for admin personas when user_type = 'admin'
--   email      -> primary email address for the account
-- Adjust application auth middleware to populate these claims accordingly.
