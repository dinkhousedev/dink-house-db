-- ============================================================================
-- CONTRIBUTION EMAIL FUNCTIONS
-- Functions to send thank you emails with receipts and benefits
-- ============================================================================

SET search_path TO crowdfunding, system, public;

-- ============================================================================
-- EMAIL GENERATION FUNCTIONS
-- ============================================================================

-- Function to format a single benefit for HTML display
CREATE OR REPLACE FUNCTION crowdfunding.format_benefit_html(
    p_benefit_name TEXT,
    p_benefit_description TEXT,
    p_quantity DECIMAL(10, 2),
    p_valid_until TIMESTAMP WITH TIME ZONE
)
RETURNS TEXT AS $$
DECLARE
    v_html TEXT;
    v_details TEXT := '';
BEGIN
    -- Build details string
    IF p_quantity IS NOT NULL THEN
        v_details := '<span class="benefit-quantity">' || p_quantity::TEXT || 'x</span>';
    END IF;

    IF p_valid_until IS NOT NULL THEN
        IF v_details != '' THEN
            v_details := v_details || ' • ';
        END IF;
        v_details := v_details || 'Valid until ' || TO_CHAR(p_valid_until, 'Mon DD, YYYY');
    ELSIF p_quantity IS NULL THEN
        v_details := '<span class="benefit-quantity">Lifetime</span>';
    END IF;

    -- Build HTML
    v_html := '<div class="benefit-item">' ||
              '<div class="checkmark">✓</div>' ||
              '<div class="benefit-content">' ||
              '<div class="benefit-name">' || COALESCE(p_benefit_description, p_benefit_name) || '</div>';

    IF v_details != '' THEN
        v_html := v_html || '<div class="benefit-details">' || v_details || '</div>';
    END IF;

    v_html := v_html || '</div></div>';

    RETURN v_html;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Function to format a single benefit for plain text display
CREATE OR REPLACE FUNCTION crowdfunding.format_benefit_text(
    p_benefit_name TEXT,
    p_benefit_description TEXT,
    p_quantity DECIMAL(10, 2),
    p_valid_until TIMESTAMP WITH TIME ZONE
)
RETURNS TEXT AS $$
DECLARE
    v_text TEXT;
    v_details TEXT := '';
BEGIN
    v_text := '• ' || COALESCE(p_benefit_description, p_benefit_name);

    -- Add quantity if specified
    IF p_quantity IS NOT NULL THEN
        v_details := ' (' || p_quantity::TEXT || 'x';
    END IF;

    -- Add expiration if specified
    IF p_valid_until IS NOT NULL THEN
        IF v_details = '' THEN
            v_details := ' (Valid until ' || TO_CHAR(p_valid_until, 'Mon DD, YYYY') || ')';
        ELSE
            v_details := v_details || ', valid until ' || TO_CHAR(p_valid_until, 'Mon DD, YYYY') || ')';
        END IF;
    ELSIF p_quantity IS NULL THEN
        v_details := ' (Lifetime benefit)';
    ELSIF p_quantity IS NOT NULL AND v_details != '' THEN
        v_details := v_details || ')';
    END IF;

    RETURN v_text || v_details;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ============================================================================
-- MAIN EMAIL SENDING FUNCTION
-- ============================================================================

-- Function to send contribution thank you email with receipt and benefits
CREATE OR REPLACE FUNCTION crowdfunding.send_contribution_thank_you_email(
    p_contribution_id UUID
)
RETURNS JSONB AS $$
DECLARE
    v_contribution RECORD;
    v_backer RECORD;
    v_tier RECORD;
    v_campaign RECORD;
    v_founders_wall RECORD;
    v_benefits RECORD;
    v_benefits_html TEXT := '';
    v_benefits_text TEXT := '';
    v_email_data JSONB;
    v_email_log_id UUID;
    v_benefit_count INTEGER := 0;
BEGIN
    -- Get contribution details
    SELECT
        c.id,
        c.amount,
        c.completed_at,
        c.stripe_payment_intent_id,
        c.stripe_charge_id,
        c.payment_method,
        c.backer_id,
        c.tier_id,
        c.campaign_type_id
    INTO v_contribution
    FROM crowdfunding.contributions c
    WHERE c.id = p_contribution_id;

    IF v_contribution IS NULL THEN
        RAISE EXCEPTION 'Contribution not found: %', p_contribution_id;
    END IF;

    IF v_contribution.completed_at IS NULL THEN
        RAISE EXCEPTION 'Contribution has not been completed yet';
    END IF;

    -- Get backer details
    SELECT * INTO v_backer
    FROM crowdfunding.backers
    WHERE id = v_contribution.backer_id;

    -- Get tier details
    IF v_contribution.tier_id IS NOT NULL THEN
        SELECT * INTO v_tier
        FROM crowdfunding.contribution_tiers
        WHERE id = v_contribution.tier_id;
    END IF;

    -- Get campaign details
    SELECT * INTO v_campaign
    FROM crowdfunding.campaign_types
    WHERE id = v_contribution.campaign_type_id;

    -- Get founders wall entry if exists
    SELECT * INTO v_founders_wall
    FROM crowdfunding.founders_wall
    WHERE backer_id = v_contribution.backer_id;

    -- Get all benefits allocated to this contribution
    FOR v_benefits IN
        SELECT
            benefit_name,
            benefit_description,
            quantity_allocated,
            valid_until
        FROM crowdfunding.benefit_allocations
        WHERE contribution_id = p_contribution_id
        ORDER BY created_at
    LOOP
        v_benefit_count := v_benefit_count + 1;

        -- Build HTML benefits list
        v_benefits_html := v_benefits_html ||
            crowdfunding.format_benefit_html(
                v_benefits.benefit_name,
                v_benefits.benefit_description,
                v_benefits.quantity_allocated,
                v_benefits.valid_until
            );

        -- Build plain text benefits list
        v_benefits_text := v_benefits_text ||
            crowdfunding.format_benefit_text(
                v_benefits.benefit_name,
                v_benefits.benefit_description,
                v_benefits.quantity_allocated,
                v_benefits.valid_until
            ) || E'\n';
    END LOOP;

    -- If no benefits found, check tier benefits directly
    IF v_benefit_count = 0 AND v_tier IS NOT NULL THEN
        DECLARE
            v_tier_benefit JSONB;
        BEGIN
            FOR v_tier_benefit IN SELECT * FROM jsonb_array_elements(v_tier.benefits)
            LOOP
                v_benefits_html := v_benefits_html ||
                    crowdfunding.format_benefit_html(
                        v_tier_benefit->>'type',
                        v_tier_benefit->>'text',
                        NULL,
                        NULL
                    );

                v_benefits_text := v_benefits_text || '• ' || (v_tier_benefit->>'text') || E'\n';
            END LOOP;
        END;
    END IF;

    -- If still no benefits, add a default message
    IF v_benefits_html = '' THEN
        v_benefits_html := '<div class="benefit-item"><div class="checkmark">✓</div><div class="benefit-content"><div class="benefit-name">Your support is making The Dink House possible!</div></div></div>';
        v_benefits_text := '• Your support is making The Dink House possible!';
    END IF;

    -- Build email data
    v_email_data := jsonb_build_object(
        'first_name', v_backer.first_name,
        'amount', TO_CHAR(v_contribution.amount, 'FM999,999.00'),
        'tier_name', COALESCE(v_tier.name, 'Custom Contribution'),
        'contribution_date', TO_CHAR(v_contribution.completed_at, 'Mon DD, YYYY at HH12:MI AM'),
        'contribution_id', v_contribution.id::TEXT,
        'payment_method', COALESCE(INITCAP(v_contribution.payment_method), 'Card'),
        'stripe_charge_id', COALESCE(v_contribution.stripe_charge_id, v_contribution.stripe_payment_intent_id, 'N/A'),
        'benefits_html', v_benefits_html,
        'benefits_text', v_benefits_text,
        'on_founders_wall', (v_founders_wall IS NOT NULL),
        'display_name', COALESCE(v_founders_wall.display_name, v_backer.first_name || ' ' || v_backer.last_initial || '.'),
        'founders_wall_message', CASE
            WHEN v_founders_wall.is_featured THEN
                'You''ll be featured prominently as a major supporter!'
            WHEN v_founders_wall IS NOT NULL THEN
                'Thank you for being a founding member of our community!'
            ELSE
                ''
        END,
        'site_url', 'https://thedinkhouse.com',
        'campaign_name', v_campaign.name
    );

    -- Log the email (ready to be sent by external service)
    v_email_log_id := system.log_email(
        'contribution_thank_you',
        v_backer.email,
        'support@thedinkhouse.com',
        'Thank You for Your Contribution to The Dink House! 🎉',
        'pending',
        jsonb_build_object(
            'contribution_id', v_contribution.id,
            'backer_id', v_backer.id,
            'amount', v_contribution.amount,
            'tier_id', v_contribution.tier_id
        )
    );

    -- Return success with email data and log ID
    RETURN jsonb_build_object(
        'success', true,
        'email_log_id', v_email_log_id,
        'recipient', v_backer.email,
        'email_data', v_email_data,
        'message', 'Email queued for sending'
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', SQLERRM,
            'message', 'Failed to prepare thank you email'
        );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- TRIGGER TO AUTO-SEND EMAILS ON CONTRIBUTION COMPLETION
-- ============================================================================

-- Function to trigger thank you email after contribution is completed
CREATE OR REPLACE FUNCTION crowdfunding.trigger_contribution_thank_you_email()
RETURNS TRIGGER AS $$
DECLARE
    v_result JSONB;
BEGIN
    -- Only send email when contribution status changes to 'completed'
    IF NEW.status = 'completed' AND (OLD IS NULL OR OLD.status != 'completed') THEN
        -- First, allocate benefits if tier exists
        IF NEW.tier_id IS NOT NULL THEN
            PERFORM crowdfunding.allocate_benefits_from_tier(
                NEW.id,
                NEW.tier_id,
                NEW.backer_id
            );
        END IF;

        -- Then send thank you email
        v_result := crowdfunding.send_contribution_thank_you_email(NEW.id);

        -- Log result (for debugging)
        IF NOT (v_result->>'success')::BOOLEAN THEN
            RAISE WARNING 'Failed to send contribution thank you email: %', v_result->>'error';
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger
DROP TRIGGER IF EXISTS trigger_send_contribution_thank_you ON crowdfunding.contributions;
CREATE TRIGGER trigger_send_contribution_thank_you
    AFTER INSERT OR UPDATE ON crowdfunding.contributions
    FOR EACH ROW
    EXECUTE FUNCTION crowdfunding.trigger_contribution_thank_you_email();

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

GRANT EXECUTE ON FUNCTION crowdfunding.format_benefit_html(TEXT, TEXT, DECIMAL, TIMESTAMP WITH TIME ZONE) TO service_role;
GRANT EXECUTE ON FUNCTION crowdfunding.format_benefit_text(TEXT, TEXT, DECIMAL, TIMESTAMP WITH TIME ZONE) TO service_role;
GRANT EXECUTE ON FUNCTION crowdfunding.send_contribution_thank_you_email(UUID) TO service_role, authenticated;

COMMENT ON FUNCTION crowdfunding.send_contribution_thank_you_email IS 'Send contribution thank you email with receipt and benefits';
COMMENT ON FUNCTION crowdfunding.trigger_contribution_thank_you_email IS 'Trigger function to auto-send thank you emails when contributions are completed';
