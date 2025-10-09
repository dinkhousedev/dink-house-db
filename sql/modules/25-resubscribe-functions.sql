-- ============================================================================
-- RESUBSCRIBE FUNCTIONS MODULE
-- Functions to handle newsletter resubscription
-- ============================================================================

SET search_path TO api, launch, system, public;

-- ============================================================================
-- RESUBSCRIBE NEWSLETTER FUNCTION
-- ============================================================================

-- Resubscribe to newsletter
CREATE OR REPLACE FUNCTION api.resubscribe_newsletter(
    p_email TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_subscriber RECORD;
BEGIN
    -- Find subscriber by email (case-insensitive)
    SELECT * INTO v_subscriber
    FROM launch.launch_subscribers
    WHERE email = lower(p_email);

    -- Check if email exists in database
    IF v_subscriber IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'message', 'Email not found. Please sign up first to join our newsletter.'
        );
    END IF;

    -- Check if already active/subscribed
    IF v_subscriber.is_active = true AND v_subscriber.unsubscribed_at IS NULL THEN
        RETURN json_build_object(
            'success', true,
            'already_subscribed', true,
            'message', 'You are already subscribed to our newsletter!'
        );
    END IF;

    -- Reactivate subscription
    UPDATE launch.launch_subscribers
    SET is_active = true,
        unsubscribed_at = NULL,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = v_subscriber.id;

    -- Log the resubscribe action
    INSERT INTO system.activity_logs (
        action,
        entity_type,
        entity_id,
        details
    ) VALUES (
        'newsletter_resubscribe',
        'subscriber',
        v_subscriber.id,
        jsonb_build_object(
            'email', v_subscriber.email,
            'resubscribed_at', CURRENT_TIMESTAMP
        )
    );

    RETURN json_build_object(
        'success', true,
        'message', 'Thank you for resubscribing! You will now receive our newsletter updates.',
        'subscriber_id', v_subscriber.id
    );
END;
$$;

-- ============================================================================
-- PERMISSIONS
-- ============================================================================

-- Grant execute permission to anonymous users (public access)
GRANT EXECUTE ON FUNCTION api.resubscribe_newsletter TO anon;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION api.resubscribe_newsletter TO authenticated;
