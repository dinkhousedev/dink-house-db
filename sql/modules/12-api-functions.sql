-- ============================================================================
-- API FUNCTIONS MODULE
-- Create database functions for API operations
-- ============================================================================

SET search_path TO api, auth, content, contact, launch, system, public;

-- ============================================================================
-- AUTHENTICATION FUNCTIONS
-- ============================================================================

-- Register new user
CREATE OR REPLACE FUNCTION api.register_user(
    p_email TEXT,
    p_username TEXT,
    p_password TEXT,
    p_first_name TEXT,
    p_last_name TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID;
    v_verification_token VARCHAR(255);
    v_password_hash VARCHAR(255);
BEGIN
    -- Check if email already exists
    IF EXISTS (SELECT 1 FROM app_auth.users WHERE email = lower(p_email)) THEN
        RAISE EXCEPTION 'Email already registered';
    END IF;

    -- Check if username already exists
    IF EXISTS (SELECT 1 FROM app_auth.users WHERE username = lower(p_username)) THEN
        RAISE EXCEPTION 'Username already taken';
    END IF;

    -- Generate password hash
    v_password_hash := public.crypt(p_password, public.gen_salt('bf', 10));

    -- Generate verification token
    v_verification_token := encode(public.gen_random_bytes(32), 'hex');

    -- Insert new user
    INSERT INTO app_auth.users (
        email,
        username,
        password_hash,
        first_name,
        last_name,
        verification_token,
        role
    ) VALUES (
        lower(p_email),
        lower(p_username),
        v_password_hash,
        p_first_name,
        p_last_name,
        v_verification_token,
        'viewer'
    ) RETURNING id INTO v_user_id;

    -- Log activity
    INSERT INTO system.activity_logs (
        user_id,
        action,
        entity_type,
        entity_id,
        details
    ) VALUES (
        v_user_id,
        'user_registered',
        'user',
        v_user_id,
        jsonb_build_object('email', p_email, 'username', p_username)
    );

    RETURN json_build_object(
        'success', true,
        'user_id', v_user_id,
        'verification_token', v_verification_token,
        'message', 'Registration successful. Please verify your email.'
    );
END;
$$;

-- Login user
CREATE OR REPLACE FUNCTION api.login(
    p_email TEXT,
    p_password TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user RECORD;
    v_session_id UUID;
    v_token VARCHAR(255);
    v_refresh_token VARCHAR(255);
BEGIN
    -- Find user
    SELECT * INTO v_user
    FROM app_auth.users
    WHERE email = lower(p_email) OR username = lower(p_email);

    IF v_user IS NULL THEN
        RAISE EXCEPTION 'Invalid credentials';
    END IF;

    -- Check if account is locked
    IF v_user.locked_until IS NOT NULL AND v_user.locked_until > CURRENT_TIMESTAMP THEN
        RAISE EXCEPTION 'Account is locked. Please try again later.';
    END IF;

    -- Verify password
    IF NOT (v_user.password_hash = public.crypt(p_password, v_user.password_hash)) THEN
        -- Increment failed login attempts
        UPDATE app_auth.users
        SET failed_login_attempts = failed_login_attempts + 1,
            locked_until = CASE
                WHEN failed_login_attempts >= 4 THEN CURRENT_TIMESTAMP + INTERVAL '15 minutes'
                ELSE NULL
            END
        WHERE id = v_user.id;

        RAISE EXCEPTION 'Invalid credentials';
    END IF;

    -- Check if user is active
    IF NOT v_user.is_active THEN
        RAISE EXCEPTION 'Account is inactive';
    END IF;

    -- Check if user is verified
    IF NOT v_user.is_verified THEN
        RAISE EXCEPTION 'Please verify your email address';
    END IF;

    -- Generate tokens
    v_token := encode(public.gen_random_bytes(32), 'hex');
    v_refresh_token := encode(public.gen_random_bytes(32), 'hex');

    -- Create session
    INSERT INTO app_auth.sessions (
        user_id,
        token_hash,
        expires_at
    ) VALUES (
        v_user.id,
        encode(public.digest(v_token, 'sha256'), 'hex'),
        CURRENT_TIMESTAMP + INTERVAL '24 hours'
    ) RETURNING id INTO v_session_id;

    -- Create refresh token
    INSERT INTO app_auth.refresh_tokens (
        user_id,
        token_hash,
        expires_at
    ) VALUES (
        v_user.id,
        encode(public.digest(v_refresh_token, 'sha256'), 'hex'),
        CURRENT_TIMESTAMP + INTERVAL '7 days'
    );

    -- Update user last login
    UPDATE app_auth.users
    SET last_login = CURRENT_TIMESTAMP,
        failed_login_attempts = 0,
        locked_until = NULL
    WHERE id = v_user.id;

    -- Log activity
    INSERT INTO system.activity_logs (
        user_id,
        action,
        entity_type,
        entity_id,
        details
    ) VALUES (
        v_user.id,
        'user_login',
        'session',
        v_session_id,
        jsonb_build_object('method', 'password')
    );

    RETURN json_build_object(
        'success', true,
        'user', json_build_object(
            'id', v_user.id,
            'email', v_user.email,
            'username', v_user.username,
            'first_name', v_user.first_name,
            'last_name', v_user.last_name,
            'role', v_user.role
        ),
        'session_token', v_token,
        'refresh_token', v_refresh_token,
        'expires_at', (CURRENT_TIMESTAMP + INTERVAL '24 hours')
    );
END;
$$;

-- Logout user
CREATE OR REPLACE FUNCTION api.logout(
    p_session_token TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_session_id UUID;
    v_user_id UUID;
BEGIN
    -- Find and delete session
    DELETE FROM app_auth.sessions
    WHERE token_hash = encode(public.digest(p_session_token, 'sha256'), 'hex')
    RETURNING id, user_id INTO v_session_id, v_user_id;

    IF v_session_id IS NULL THEN
        RAISE EXCEPTION 'Invalid session';
    END IF;

    -- Log activity
    INSERT INTO system.activity_logs (
        user_id,
        action,
        entity_type,
        entity_id
    ) VALUES (
        v_user_id,
        'user_logout',
        'session',
        v_session_id
    );

    RETURN json_build_object(
        'success', true,
        'message', 'Logged out successfully'
    );
END;
$$;

-- Refresh access token
CREATE OR REPLACE FUNCTION api.refresh_token(
    p_refresh_token TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID;
    v_new_token VARCHAR(255);
    v_new_refresh_token VARCHAR(255);
BEGIN
    -- Verify refresh token
    SELECT user_id INTO v_user_id
    FROM app_auth.refresh_tokens
    WHERE token_hash = encode(public.digest(p_refresh_token, 'sha256'), 'hex')
        AND expires_at > CURRENT_TIMESTAMP
        AND revoked_at IS NULL;

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Invalid refresh token';
    END IF;

    -- Revoke old refresh token
    UPDATE app_auth.refresh_tokens
    SET revoked_at = CURRENT_TIMESTAMP
    WHERE token_hash = encode(public.digest(p_refresh_token, 'sha256'), 'hex');

    -- Generate new tokens
    v_new_token := encode(public.gen_random_bytes(32), 'hex');
    v_new_refresh_token := encode(public.gen_random_bytes(32), 'hex');

    -- Create new session
    INSERT INTO app_auth.sessions (
        user_id,
        token_hash,
        expires_at
    ) VALUES (
        v_user_id,
        encode(public.digest(v_new_token, 'sha256'), 'hex'),
        CURRENT_TIMESTAMP + INTERVAL '24 hours'
    );

    -- Create new refresh token
    INSERT INTO app_auth.refresh_tokens (
        user_id,
        token_hash,
        expires_at
    ) VALUES (
        v_user_id,
        encode(public.digest(v_new_refresh_token, 'sha256'), 'hex'),
        CURRENT_TIMESTAMP + INTERVAL '7 days'
    );

    RETURN json_build_object(
        'success', true,
        'session_token', v_new_token,
        'refresh_token', v_new_refresh_token,
        'expires_at', (CURRENT_TIMESTAMP + INTERVAL '24 hours')
    );
END;
$$;

-- ============================================================================
-- CONTENT FUNCTIONS
-- ============================================================================

-- Get published content with filters
CREATE OR REPLACE FUNCTION api.get_published_content(
    p_category_id UUID DEFAULT NULL,
    p_search TEXT DEFAULT NULL,
    p_limit INT DEFAULT 20,
    p_offset INT DEFAULT 0
)
RETURNS JSON
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_result JSON;
    v_total INT;
BEGIN
    -- Get total count
    SELECT COUNT(*)
    INTO v_total
    FROM content.pages p
    WHERE p.status = 'published'
        AND p.published_at <= CURRENT_TIMESTAMP
        AND (p_category_id IS NULL OR p.category_id = p_category_id)
        AND (p_search IS NULL OR (
            p.title ILIKE '%' || p_search || '%'
            OR p.content ILIKE '%' || p_search || '%'
            OR p.excerpt ILIKE '%' || p_search || '%'
        ));

    -- Get paginated results
    SELECT json_build_object(
        'total', v_total,
        'limit', p_limit,
        'offset', p_offset,
        'data', COALESCE(json_agg(
            json_build_object(
                'id', p.id,
                'slug', p.slug,
                'title', p.title,
                'excerpt', p.excerpt,
                'featured_image', p.featured_image,
                'published_at', p.published_at,
                'view_count', p.view_count,
                'category', CASE
                    WHEN c.id IS NOT NULL THEN json_build_object(
                        'id', c.id,
                        'name', c.name,
                        'slug', c.slug
                    )
                    ELSE NULL
                END,
                'author', json_build_object(
                    'id', u.id,
                    'username', u.username,
                    'first_name', u.first_name,
                    'last_name', u.last_name
                )
            ) ORDER BY p.published_at DESC
        ), '[]'::json)
    )
    INTO v_result
    FROM content.pages p
    LEFT JOIN content.categories c ON p.category_id = c.id
    LEFT JOIN app_auth.users u ON p.author_id = u.id
    WHERE p.status = 'published'
        AND p.published_at <= CURRENT_TIMESTAMP
        AND (p_category_id IS NULL OR p.category_id = p_category_id)
        AND (p_search IS NULL OR (
            p.title ILIKE '%' || p_search || '%'
            OR p.content ILIKE '%' || p_search || '%'
            OR p.excerpt ILIKE '%' || p_search || '%'
        ))
    LIMIT p_limit
    OFFSET p_offset;

    RETURN v_result;
END;
$$;

-- Create or update content
CREATE OR REPLACE FUNCTION api.upsert_content(
    p_id UUID DEFAULT NULL,
    p_title TEXT DEFAULT NULL,
    p_slug TEXT DEFAULT NULL,
    p_content TEXT DEFAULT NULL,
    p_excerpt TEXT DEFAULT NULL,
    p_category_id UUID DEFAULT NULL,
    p_featured_image TEXT DEFAULT NULL,
    p_status TEXT DEFAULT 'draft',
    p_published_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    p_seo_title TEXT DEFAULT NULL,
    p_seo_description TEXT DEFAULT NULL,
    p_seo_keywords TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_page_id UUID;
    v_author_id UUID;
    v_is_new BOOLEAN;
BEGIN
    -- Get current user
    v_author_id := auth.uid();

    IF v_author_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    -- Check if this is an update
    v_is_new := (p_id IS NULL);

    IF v_is_new THEN
        -- Create new page
        INSERT INTO content.pages (
            title,
            slug,
            content,
            excerpt,
            category_id,
            author_id,
            featured_image,
            status,
            published_at,
            seo_title,
            seo_description,
            seo_keywords
        ) VALUES (
            p_title,
            COALESCE(p_slug, regexp_replace(lower(p_title), '[^a-z0-9]+', '-', 'g')),
            p_content,
            p_excerpt,
            p_category_id,
            v_author_id,
            p_featured_image,
            p_status,
            CASE WHEN p_status = 'published' THEN COALESCE(p_published_at, CURRENT_TIMESTAMP) ELSE NULL END,
            p_seo_title,
            p_seo_description,
            p_seo_keywords
        ) RETURNING id INTO v_page_id;

        -- Log activity
        INSERT INTO system.activity_logs (
            user_id,
            action,
            entity_type,
            entity_id,
            details
        ) VALUES (
            v_author_id,
            'content_created',
            'page',
            v_page_id,
            jsonb_build_object('title', p_title, 'status', p_status)
        );
    ELSE
        -- Update existing page
        UPDATE content.pages
        SET title = COALESCE(p_title, title),
            slug = COALESCE(p_slug, slug),
            content = COALESCE(p_content, content),
            excerpt = COALESCE(p_excerpt, excerpt),
            category_id = COALESCE(p_category_id, category_id),
            featured_image = COALESCE(p_featured_image, featured_image),
            status = COALESCE(p_status, status),
            published_at = CASE
                WHEN p_status = 'published' AND status != 'published' THEN COALESCE(p_published_at, CURRENT_TIMESTAMP)
                WHEN p_status = 'published' THEN COALESCE(p_published_at, published_at)
                ELSE published_at
            END,
            seo_title = COALESCE(p_seo_title, seo_title),
            seo_description = COALESCE(p_seo_description, seo_description),
            seo_keywords = COALESCE(p_seo_keywords, seo_keywords),
            updated_at = CURRENT_TIMESTAMP
        WHERE id = p_id
        RETURNING id INTO v_page_id;

        -- Create revision
        INSERT INTO content.page_revisions (
            page_id,
            title,
            content,
            excerpt,
            revision_by
        )
        SELECT id, title, content, excerpt, v_author_id
        FROM content.pages
        WHERE id = v_page_id;

        -- Log activity
        INSERT INTO system.activity_logs (
            user_id,
            action,
            entity_type,
            entity_id,
            details
        ) VALUES (
            v_author_id,
            'content_updated',
            'page',
            v_page_id,
            jsonb_build_object('status', p_status)
        );
    END IF;

    RETURN json_build_object(
        'success', true,
        'page_id', v_page_id,
        'is_new', v_is_new,
        'message', CASE WHEN v_is_new THEN 'Content created successfully' ELSE 'Content updated successfully' END
    );
END;
$$;

-- ============================================================================
-- CONTACT FUNCTIONS
-- ============================================================================

-- Submit contact form
CREATE OR REPLACE FUNCTION api.submit_contact_form(
    p_form_id UUID,
    p_name TEXT,
    p_email TEXT,
    p_subject TEXT DEFAULT NULL,
    p_message TEXT,
    p_data JSONB DEFAULT '{}'::jsonb
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_inquiry_id UUID;
    v_form RECORD;
BEGIN
    -- Get form details
    SELECT * INTO v_form
    FROM contact.contact_forms
    WHERE id = p_form_id AND is_active = true;

    IF v_form IS NULL THEN
        RAISE EXCEPTION 'Form not found or inactive';
    END IF;

    -- Create inquiry
    INSERT INTO contact.contact_inquiries (
        form_id,
        name,
        email,
        subject,
        message,
        data,
        status,
        priority
    ) VALUES (
        p_form_id,
        p_name,
        lower(p_email),
        COALESCE(p_subject, 'Contact Form Submission'),
        p_message,
        p_data,
        'new',
        'normal'
    ) RETURNING id INTO v_inquiry_id;

    -- Log activity
    INSERT INTO system.activity_logs (
        action,
        entity_type,
        entity_id,
        details
    ) VALUES (
        'contact_form_submitted',
        'inquiry',
        v_inquiry_id,
        jsonb_build_object(
            'form_name', v_form.name,
            'email', p_email
        )
    );

    -- Add to notification queue if configured
    IF v_form.notification_email IS NOT NULL THEN
        INSERT INTO launch.notification_queue (
            template_id,
            recipient_email,
            subject,
            variables,
            priority
        ) VALUES (
            (SELECT id FROM launch.notification_templates WHERE code = 'contact_form_notification' LIMIT 1),
            v_form.notification_email,
            'New Contact Form Submission: ' || COALESCE(p_subject, v_form.name),
            jsonb_build_object(
                'inquiry_id', v_inquiry_id,
                'form_name', v_form.name,
                'name', p_name,
                'email', p_email,
                'subject', p_subject,
                'message', p_message
            ),
            'high'
        );
    END IF;

    RETURN json_build_object(
        'success', true,
        'inquiry_id', v_inquiry_id,
        'message', COALESCE(v_form.success_message, 'Thank you for your submission. We will get back to you soon.')
    );
END;
$$;

-- ============================================================================
-- LAUNCH FUNCTIONS
-- ============================================================================

-- Subscribe to campaign
CREATE OR REPLACE FUNCTION api.subscribe_to_campaign(
    p_campaign_id UUID,
    p_email TEXT,
    p_first_name TEXT DEFAULT NULL,
    p_last_name TEXT DEFAULT NULL,
    p_referral_code TEXT DEFAULT NULL,
    p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_subscriber_id UUID;
    v_campaign RECORD;
    v_verification_token VARCHAR(255);
    v_referrer_id UUID;
BEGIN
    -- Get campaign details
    SELECT * INTO v_campaign
    FROM launch.launch_campaigns
    WHERE id = p_campaign_id
        AND is_active = true
        AND status = 'active'
        AND (start_date IS NULL OR start_date <= CURRENT_TIMESTAMP)
        AND (end_date IS NULL OR end_date >= CURRENT_TIMESTAMP);

    IF v_campaign IS NULL THEN
        RAISE EXCEPTION 'Campaign not found or inactive';
    END IF;

    -- Check if already subscribed
    IF EXISTS (
        SELECT 1 FROM launch.launch_subscribers
        WHERE campaign_id = p_campaign_id AND email = lower(p_email)
    ) THEN
        RAISE EXCEPTION 'Already subscribed to this campaign';
    END IF;

    -- Find referrer if code provided
    IF p_referral_code IS NOT NULL THEN
        SELECT id INTO v_referrer_id
        FROM launch.launch_subscribers
        WHERE referral_code = p_referral_code
            AND campaign_id = p_campaign_id;
    END IF;

    -- Generate verification token
    v_verification_token := encode(public.gen_random_bytes(32), 'hex');

    -- Create subscriber
    INSERT INTO launch.launch_subscribers (
        campaign_id,
        email,
        first_name,
        last_name,
        verification_token,
        referral_code,
        metadata,
        referral_source
    ) VALUES (
        p_campaign_id,
        lower(p_email),
        p_first_name,
        p_last_name,
        v_verification_token,
        encode(public.gen_random_bytes(16), 'hex'),
        p_metadata,
        p_referral_code
    ) RETURNING id INTO v_subscriber_id;

    -- Create referral record if applicable
    IF v_referrer_id IS NOT NULL THEN
        INSERT INTO launch.launch_referrals (
            referrer_id,
            referee_id,
            campaign_id,
            status
        ) VALUES (
            v_referrer_id,
            v_subscriber_id,
            p_campaign_id,
            'pending'
        );

        -- Update referrer's referral count
        UPDATE launch.launch_subscribers
        SET referral_count = referral_count + 1
        WHERE id = v_referrer_id;
    END IF;

    -- Update campaign subscriber count
    UPDATE launch.launch_campaigns
    SET current_subscribers = current_subscribers + 1
    WHERE id = p_campaign_id;

    -- Log activity
    INSERT INTO system.activity_logs (
        action,
        entity_type,
        entity_id,
        details
    ) VALUES (
        'campaign_subscription',
        'subscriber',
        v_subscriber_id,
        jsonb_build_object(
            'campaign_name', v_campaign.name,
            'email', p_email,
            'referred_by', p_referral_code
        )
    );

    -- Add to notification queue
    INSERT INTO launch.notification_queue (
        template_id,
        recipient_email,
        subject,
        variables
    ) VALUES (
        (SELECT id FROM launch.notification_templates WHERE code = 'subscription_confirmation' LIMIT 1),
        p_email,
        'Please confirm your subscription',
        jsonb_build_object(
            'campaign_name', v_campaign.name,
            'verification_token', v_verification_token,
            'first_name', p_first_name
        )
    );

    RETURN json_build_object(
        'success', true,
        'subscriber_id', v_subscriber_id,
        'verification_token', v_verification_token,
        'referral_code', (SELECT referral_code FROM launch.launch_subscribers WHERE id = v_subscriber_id),
        'message', 'Successfully subscribed! Please check your email to verify your subscription.'
    );
END;
$$;

-- Unsubscribe from campaign
CREATE OR REPLACE FUNCTION api.unsubscribe(
    p_token TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_subscriber RECORD;
BEGIN
    -- Find subscriber by unsubscribe token
    SELECT * INTO v_subscriber
    FROM launch.launch_subscribers
    WHERE unsubscribe_token = p_token;

    IF v_subscriber IS NULL THEN
        RAISE EXCEPTION 'Invalid unsubscribe token';
    END IF;

    -- Update subscriber status
    UPDATE launch.launch_subscribers
    SET is_subscribed = false,
        unsubscribed_at = CURRENT_TIMESTAMP
    WHERE id = v_subscriber.id;

    -- Update campaign subscriber count
    UPDATE launch.launch_campaigns
    SET current_subscribers = GREATEST(0, current_subscribers - 1)
    WHERE id = v_subscriber.campaign_id;

    -- Log activity
    INSERT INTO system.activity_logs (
        action,
        entity_type,
        entity_id,
        details
    ) VALUES (
        'campaign_unsubscribe',
        'subscriber',
        v_subscriber.id,
        jsonb_build_object('email', v_subscriber.email)
    );

    RETURN json_build_object(
        'success', true,
        'message', 'Successfully unsubscribed'
    );
END;
$$;

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

-- Search across multiple entities
CREATE OR REPLACE FUNCTION api.global_search(
    p_query TEXT,
    p_limit INT DEFAULT 10
)
RETURNS JSON
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_results JSON;
BEGIN
    SELECT json_build_object(
        'pages', (
            SELECT COALESCE(json_agg(
                json_build_object(
                    'type', 'page',
                    'id', id,
                    'title', title,
                    'slug', slug,
                    'excerpt', excerpt
                )
            ), '[]'::json)
            FROM content.pages
            WHERE status = 'published'
                AND (
                    title ILIKE '%' || p_query || '%'
                    OR content ILIKE '%' || p_query || '%'
                    OR excerpt ILIKE '%' || p_query || '%'
                )
            LIMIT p_limit
        ),
        'categories', (
            SELECT COALESCE(json_agg(
                json_build_object(
                    'type', 'category',
                    'id', id,
                    'name', name,
                    'slug', slug,
                    'description', description
                )
            ), '[]'::json)
            FROM content.categories
            WHERE is_active = true
                AND (
                    name ILIKE '%' || p_query || '%'
                    OR description ILIKE '%' || p_query || '%'
                )
            LIMIT p_limit
        ),
        'users', (
            SELECT COALESCE(json_agg(
                json_build_object(
                    'type', 'user',
                    'id', id,
                    'username', username,
                    'first_name', first_name,
                    'last_name', last_name
                )
            ), '[]'::json)
            FROM app_auth.users
            WHERE is_active = true AND is_verified = true
                AND (
                    username ILIKE '%' || p_query || '%'
                    OR first_name ILIKE '%' || p_query || '%'
                    OR last_name ILIKE '%' || p_query || '%'
                    OR email ILIKE '%' || p_query || '%'
                )
            LIMIT p_limit
        )
    )
    INTO v_results;

    RETURN v_results;
END;
$$;

-- Get system statistics
CREATE OR REPLACE FUNCTION api.get_system_stats()
RETURNS JSON
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
    v_stats JSON;
BEGIN
    SELECT json_build_object(
        'users', json_build_object(
            'total', (SELECT COUNT(*) FROM app_auth.users),
            'active', (SELECT COUNT(*) FROM app_auth.users WHERE is_active = true),
            'verified', (SELECT COUNT(*) FROM app_auth.users WHERE is_verified = true),
            'new_today', (SELECT COUNT(*) FROM app_auth.users WHERE created_at >= CURRENT_DATE)
        ),
        'content', json_build_object(
            'total_pages', (SELECT COUNT(*) FROM content.pages),
            'published', (SELECT COUNT(*) FROM content.pages WHERE status = 'published'),
            'drafts', (SELECT COUNT(*) FROM content.pages WHERE status = 'draft'),
            'categories', (SELECT COUNT(*) FROM content.categories WHERE is_active = true),
            'media_files', (SELECT COUNT(*) FROM content.media_files)
        ),
        'contact', json_build_object(
            'total_inquiries', (SELECT COUNT(*) FROM contact.contact_inquiries),
            'new', (SELECT COUNT(*) FROM contact.contact_inquiries WHERE status = 'new'),
            'in_progress', (SELECT COUNT(*) FROM contact.contact_inquiries WHERE status = 'in_progress'),
            'resolved', (SELECT COUNT(*) FROM contact.contact_inquiries WHERE status = 'resolved')
        ),
        'campaigns', json_build_object(
            'active', (SELECT COUNT(*) FROM launch.launch_campaigns WHERE is_active = true),
            'total_subscribers', (SELECT COUNT(*) FROM launch.launch_subscribers),
            'verified_subscribers', (SELECT COUNT(*) FROM launch.launch_subscribers WHERE is_verified = true),
            'total_referrals', (SELECT COUNT(*) FROM launch.launch_referrals)
        ),
        'system', json_build_object(
            'activities_today', (SELECT COUNT(*) FROM system.activity_logs WHERE created_at >= CURRENT_DATE),
            'pending_jobs', (SELECT COUNT(*) FROM system.system_jobs WHERE status = 'pending'),
            'enabled_features', (SELECT COUNT(*) FROM system.feature_flags WHERE is_enabled = true)
        ),
        'generated_at', CURRENT_TIMESTAMP
    )
    INTO v_stats;

    RETURN v_stats;
END;
$$;

-- ============================================================================
-- GRANT EXECUTE PERMISSIONS
-- ============================================================================

-- Public functions (accessible by anonymous users)
GRANT EXECUTE ON FUNCTION api.register_user TO anon;
GRANT EXECUTE ON FUNCTION api.login TO anon;
GRANT EXECUTE ON FUNCTION api.get_published_content TO anon;
GRANT EXECUTE ON FUNCTION api.submit_contact_form TO anon;
GRANT EXECUTE ON FUNCTION api.subscribe_to_campaign TO anon;
GRANT EXECUTE ON FUNCTION api.unsubscribe TO anon;
GRANT EXECUTE ON FUNCTION api.global_search TO anon;

-- Authenticated functions
GRANT EXECUTE ON FUNCTION api.logout TO authenticated;
GRANT EXECUTE ON FUNCTION api.refresh_token TO authenticated;
GRANT EXECUTE ON FUNCTION api.upsert_content TO authenticated;

-- Admin functions
GRANT EXECUTE ON FUNCTION api.get_system_stats TO authenticated;