-- ============================================================================
-- Add Stripe Payment Fields to Event Registrations
-- ============================================================================
-- Adds Stripe-specific payment tracking fields to event_registrations table
-- and creates the update_booking_payment function for webhook integration
-- ============================================================================

-- Add Stripe payment tracking columns to event_registrations
ALTER TABLE events.event_registrations
ADD COLUMN IF NOT EXISTS stripe_payment_intent_id TEXT,
ADD COLUMN IF NOT EXISTS stripe_session_id TEXT,
ADD COLUMN IF NOT EXISTS payment_status VARCHAR(50) DEFAULT 'pending';

-- Add indexes for Stripe fields
CREATE INDEX IF NOT EXISTS idx_event_reg_stripe_payment_intent
    ON events.event_registrations(stripe_payment_intent_id);
CREATE INDEX IF NOT EXISTS idx_event_reg_stripe_session
    ON events.event_registrations(stripe_session_id);
CREATE INDEX IF NOT EXISTS idx_event_reg_payment_status
    ON events.event_registrations(payment_status);

-- Add comments
COMMENT ON COLUMN events.event_registrations.stripe_payment_intent_id
    IS 'Stripe PaymentIntent ID for tracking payments';
COMMENT ON COLUMN events.event_registrations.stripe_session_id
    IS 'Stripe Checkout Session ID for tracking sessions';
COMMENT ON COLUMN events.event_registrations.payment_status
    IS 'Payment status: pending, completed, failed, refunded';

-- ============================================================================
-- Create update_booking_payment RPC Function
-- ============================================================================

-- Drop existing function if it exists (with any signature)
DROP FUNCTION IF EXISTS api.update_booking_payment;

CREATE OR REPLACE FUNCTION api.update_booking_payment(
    p_booking_id UUID,
    p_payment_status VARCHAR DEFAULT NULL,
    p_stripe_payment_intent_id TEXT DEFAULT NULL,
    p_stripe_session_id TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_updated_count INTEGER;
BEGIN
    -- Update the event registration with payment details
    UPDATE events.event_registrations
    SET
        payment_status = COALESCE(p_payment_status, payment_status),
        stripe_payment_intent_id = COALESCE(p_stripe_payment_intent_id, stripe_payment_intent_id),
        stripe_session_id = COALESCE(p_stripe_session_id, stripe_session_id),
        payment_reference = COALESCE(p_stripe_payment_intent_id, payment_reference),
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_booking_id;

    GET DIAGNOSTICS v_updated_count = ROW_COUNT;

    IF v_updated_count = 0 THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Booking not found',
            'booking_id', p_booking_id
        );
    END IF;

    RETURN json_build_object(
        'success', true,
        'booking_id', p_booking_id,
        'payment_status', p_payment_status,
        'updated', true
    );
END;
$$;

COMMENT ON FUNCTION api.update_booking_payment
    IS 'Update event registration payment status and Stripe IDs - used by Stripe webhooks';

-- Grant permissions
GRANT EXECUTE ON FUNCTION api.update_booking_payment TO authenticated;
GRANT EXECUTE ON FUNCTION api.update_booking_payment TO anon;
GRANT EXECUTE ON FUNCTION api.update_booking_payment TO service_role;

-- ============================================================================
-- Update existing registrations to set default payment_status
-- ============================================================================

-- Set payment_status based on existing payment_reference
UPDATE events.event_registrations
SET payment_status = CASE
    WHEN payment_reference IS NOT NULL AND payment_reference != '' THEN 'completed'
    ELSE 'pending'
END
WHERE payment_status IS NULL;
