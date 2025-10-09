-- ============================================================================
-- Module 48: Fix Function Search Path Security
-- ============================================================================
-- Purpose: Add explicit SET search_path to all functions to prevent
-- search path hijacking attacks. This addresses Supabase linter warnings.
-- ============================================================================

-- ============================================================================
-- APPROACH
-- ============================================================================
-- For each function, we add: SET search_path = schema1, schema2, public
-- This ensures functions only look in specified schemas for objects
-- ============================================================================

-- Note: This migration will be applied by running ALTER FUNCTION statements
-- to set the search_path configuration parameter on existing functions.

-- ============================================================================
-- API SCHEMA FUNCTIONS
-- ============================================================================

-- Set search_path for api schema functions
ALTER FUNCTION api.cancel_open_play_registration SET search_path = api, events, app_auth, public;
ALTER FUNCTION api.get_pending_dupr_verifications SET search_path = api, app_auth, public;
ALTER FUNCTION api.verify_player_dupr SET search_path = api, app_auth, public;
ALTER FUNCTION api.delete_player_with_cascade SET search_path = api, app_auth, events, crowdfunding, public;
ALTER FUNCTION api.get_player_open_play_history SET search_path = api, events, app_auth, public;
ALTER FUNCTION api.update_booking_payment SET search_path = api, events, app_auth, public;
ALTER FUNCTION api.get_weekly_schedule SET search_path = api, events, public;
ALTER FUNCTION api.get_player_event_registrations SET search_path = api, events, app_auth, public;
ALTER FUNCTION api.register_for_event SET search_path = api, events, app_auth, system, public;
ALTER FUNCTION api.resubscribe_newsletter SET search_path = api, launch, public;
ALTER FUNCTION api.create_court_booking SET search_path = api, events, app_auth, system, public;
ALTER FUNCTION api.register_for_open_play SET search_path = api, events, app_auth, public;
ALTER FUNCTION api.get_event_checkin_status SET search_path = api, events, app_auth, public;
ALTER FUNCTION api.get_booking_details SET search_path = api, events, app_auth, public;
ALTER FUNCTION api.check_refund_eligibility SET search_path = api, events, app_auth, public;
ALTER FUNCTION api.submit_dupr_for_verification SET search_path = api, app_auth, public;
ALTER FUNCTION api.get_player_court_bookings SET search_path = api, events, app_auth, public;
ALTER FUNCTION api.get_all_bookings SET search_path = api, events, app_auth, public;
ALTER FUNCTION api.get_upcoming_open_play_schedule SET search_path = api, events, public;
ALTER FUNCTION api.generate_open_play_instances SET search_path = api, events, public;
ALTER FUNCTION api.get_available_booking_times SET search_path = api, events, public;
ALTER FUNCTION api.delete_schedule_block SET search_path = api, events, public;
ALTER FUNCTION api.create_schedule_blocks_multi_day SET search_path = api, events, public;
ALTER FUNCTION api.auto_link_player_to_backer SET search_path = api, app_auth, crowdfunding, public;
ALTER FUNCTION api.cancel_event_registration SET search_path = api, events, app_auth, system, public;
ALTER FUNCTION api.get_user_profile SET search_path = api, app_auth, public;
ALTER FUNCTION api.update_player_account SET search_path = api, app_auth, public;
ALTER FUNCTION api.get_schedule_for_date SET search_path = api, events, public;
ALTER FUNCTION api.admin_delete_player SET search_path = api, app_auth, events, crowdfunding, public;
ALTER FUNCTION api.get_player_profile SET search_path = api, app_auth, crowdfunding, public;
ALTER FUNCTION api.create_schedule_override SET search_path = api, events, public;
ALTER FUNCTION api.get_booking_by_session SET search_path = api, events, app_auth, public;
ALTER FUNCTION api.check_court_availability SET search_path = api, events, public;
ALTER FUNCTION api.bulk_delete_schedule_blocks SET search_path = api, events, public;
ALTER FUNCTION api.check_in_player SET search_path = api, events, app_auth, public;
ALTER FUNCTION api.update_schedule_block SET search_path = api, events, public;
ALTER FUNCTION api.cancel_booking SET search_path = api, events, app_auth, system, public;
ALTER FUNCTION api.create_schedule_block SET search_path = api, events, public;
ALTER FUNCTION api.update_booking_payment_info SET search_path = api, events, app_auth, public;
ALTER FUNCTION api.get_open_play_registrations SET search_path = api, events, app_auth, public;

-- ============================================================================
-- CROWDFUNDING SCHEMA FUNCTIONS
-- ============================================================================

ALTER FUNCTION crowdfunding.refund_contribution SET search_path = crowdfunding, public;
ALTER FUNCTION crowdfunding.get_backer_contributions SET search_path = crowdfunding, public;
ALTER FUNCTION crowdfunding.complete_contribution SET search_path = crowdfunding, public;
ALTER FUNCTION crowdfunding.upsert_founders_wall SET search_path = crowdfunding, public;
ALTER FUNCTION crowdfunding.get_available_tiers SET search_path = crowdfunding, public;
ALTER FUNCTION crowdfunding.create_checkout_contribution SET search_path = crowdfunding, public;
ALTER FUNCTION crowdfunding.log_benefit_usage SET search_path = crowdfunding, public;
ALTER FUNCTION crowdfunding.get_campaign_progress SET search_path = crowdfunding, public;
ALTER FUNCTION crowdfunding.update_merchandise_timestamp SET search_path = crowdfunding, public;
ALTER FUNCTION crowdfunding.update_contribution_session SET search_path = crowdfunding, public;
ALTER FUNCTION crowdfunding.calculate_badge_tier SET search_path = crowdfunding, public;
ALTER FUNCTION crowdfunding.auto_allocate_backer_benefits SET search_path = crowdfunding, public;
ALTER FUNCTION crowdfunding.redeem_benefit SET search_path = crowdfunding, public;
ALTER FUNCTION crowdfunding.trigger_contribution_thank_you_email SET search_path = crowdfunding, system, public;
ALTER FUNCTION crowdfunding.get_backers_by_badge SET search_path = crowdfunding, public;
ALTER FUNCTION crowdfunding.get_badge_stats SET search_path = crowdfunding, public;
ALTER FUNCTION crowdfunding.update_event_timestamp SET search_path = crowdfunding, public;
ALTER FUNCTION crowdfunding.get_backer_badge_info SET search_path = crowdfunding, public;
ALTER FUNCTION crowdfunding.update_campaign_total SET search_path = crowdfunding, public;
ALTER FUNCTION crowdfunding.update_backer_badge SET search_path = crowdfunding, public;
ALTER FUNCTION crowdfunding.update_fulfillment_status SET search_path = crowdfunding, public;
ALTER FUNCTION crowdfunding.get_backer_by_email SET search_path = crowdfunding, public;
ALTER FUNCTION crowdfunding.format_benefit_text SET search_path = crowdfunding, public;
ALTER FUNCTION crowdfunding.format_benefit_html SET search_path = crowdfunding, public;
ALTER FUNCTION crowdfunding.allocate_benefits_from_tier SET search_path = crowdfunding, public;
ALTER FUNCTION crowdfunding.update_benefit_remaining SET search_path = crowdfunding, public;
ALTER FUNCTION crowdfunding.auto_create_recognition_item SET search_path = crowdfunding, public;
ALTER FUNCTION crowdfunding.send_contribution_thank_you_email SET search_path = crowdfunding, system, public;
ALTER FUNCTION crowdfunding.get_badge_tier_info SET search_path = crowdfunding, public;

-- ============================================================================
-- PUBLIC SCHEMA FUNCTIONS
-- ============================================================================

ALTER FUNCTION public.get_all_members SET search_path = public, app_auth, auth;
ALTER FUNCTION public.update_player_account SET search_path = public, app_auth, auth;
ALTER FUNCTION public.unsubscribe_newsletter SET search_path = public, launch;
ALTER FUNCTION public.get_pending_contributions SET search_path = public, crowdfunding;
ALTER FUNCTION public.mark_email_opened SET search_path = public, marketing;
ALTER FUNCTION public.delete_player_with_cascade SET search_path = public, app_auth, events, crowdfunding, auth;
ALTER FUNCTION public.submit_newsletter_signup SET search_path = public, launch;
ALTER FUNCTION public.send_contribution_thank_you_email SET search_path = public, crowdfunding, system;
ALTER FUNCTION public.resubscribe_newsletter SET search_path = public, launch;
ALTER FUNCTION public.delete_schedule_block SET search_path = public, events;
ALTER FUNCTION public.update_schedule_block SET search_path = public, events;
ALTER FUNCTION public.admin_delete_player SET search_path = public, app_auth, events, crowdfunding, auth;
ALTER FUNCTION public.submit_newsletter_signup_with_email SET search_path = public, launch, system;
ALTER FUNCTION public.redeem_benefit SET search_path = public, crowdfunding;
ALTER FUNCTION public.create_schedule_override SET search_path = public, events;
ALTER FUNCTION public.bulk_delete_schedule_blocks SET search_path = public, events;
ALTER FUNCTION public.get_schedule_for_date SET search_path = public, events;
ALTER FUNCTION public.create_event_booking SET search_path = public, events, app_auth;
ALTER FUNCTION public.check_court_availability SET search_path = public, events;
ALTER FUNCTION public.complete_contribution SET search_path = public, crowdfunding;
ALTER FUNCTION public.create_stripe_customer_async SET search_path = public, crowdfunding, app_auth;
ALTER FUNCTION public.refund_contribution SET search_path = public, crowdfunding;
ALTER FUNCTION public.get_backer_by_email SET search_path = public, crowdfunding;
ALTER FUNCTION public.complete_contribution_by_session SET search_path = public, crowdfunding;
ALTER FUNCTION public.get_player_court_bookings SET search_path = public, events, app_auth;
ALTER FUNCTION public.marketing_email_recipients_insert SET search_path = public, marketing, launch;
ALTER FUNCTION public.marketing_email_recipients_update SET search_path = public, marketing;
ALTER FUNCTION public.marketing_emails_insert SET search_path = public, marketing;
ALTER FUNCTION public.marketing_emails_update SET search_path = public, marketing;
ALTER FUNCTION public.get_subscriber_preferences SET search_path = public, launch;
ALTER FUNCTION public.mark_email_clicked SET search_path = public, marketing;
ALTER FUNCTION public.get_email_template SET search_path = public, system;
ALTER FUNCTION public.cancel_booking SET search_path = public, events, app_auth, system;
ALTER FUNCTION public.verify_dupr SET search_path = public, app_auth;
ALTER FUNCTION public.update_updated_at SET search_path = public;
ALTER FUNCTION public.update_updated_at_column SET search_path = public;
ALTER FUNCTION public.handle_updated_at SET search_path = public;
ALTER FUNCTION public.create_checkout_contribution SET search_path = public, crowdfunding;
ALTER FUNCTION public.create_court_booking SET search_path = public, events, app_auth, system;
ALTER FUNCTION public.get_player_pricing_info SET search_path = public, app_auth, system;
ALTER FUNCTION public.get_weekly_schedule SET search_path = public, events;
ALTER FUNCTION public.get_all_membership_tiers SET search_path = public, app_auth;
ALTER FUNCTION public.get_player_profile SET search_path = public, app_auth, crowdfunding;
ALTER FUNCTION public.record_registration_fee SET search_path = public, app_auth, system;
ALTER FUNCTION public.has_paid_registration_fee SET search_path = public, app_auth;
ALTER FUNCTION public.update_contribution_session SET search_path = public, crowdfunding;
ALTER FUNCTION public.update_booking_payment SET search_path = public, events, app_auth;
ALTER FUNCTION public.get_backer_contributions SET search_path = public, crowdfunding;
ALTER FUNCTION public.update_booking_payment_info SET search_path = public, events, app_auth;
ALTER FUNCTION public.confirm_newsletter_subscription SET search_path = public, launch;

-- ============================================================================
-- EVENTS SCHEMA FUNCTIONS
-- ============================================================================

ALTER FUNCTION events.update_updated_at SET search_path = events, public;
ALTER FUNCTION events.check_open_play_conflict SET search_path = events, public;
ALTER FUNCTION events.update_registration_count SET search_path = events, public;
ALTER FUNCTION events.get_dupr_match_quality SET search_path = events, public;
ALTER FUNCTION events.is_admin_or_manager SET search_path = events, app_auth, auth;
ALTER FUNCTION events.player_matches_event_dupr SET search_path = events, app_auth;
ALTER FUNCTION events.is_staff SET search_path = events, app_auth, auth;
ALTER FUNCTION events.get_current_admin_id SET search_path = events, app_auth, auth;
ALTER FUNCTION events.get_schedule_block_at_time SET search_path = events, public;
ALTER FUNCTION events.sync_open_play_instance_to_event SET search_path = events, public;
ALTER FUNCTION events.calculate_skill_level_capacity SET search_path = events, public;

-- ============================================================================
-- APP_AUTH SCHEMA FUNCTIONS
-- ============================================================================

ALTER FUNCTION app_auth.hash_password SET search_path = app_auth, public;
ALTER FUNCTION app_auth.get_user_role SET search_path = app_auth, auth;
ALTER FUNCTION app_auth.verify_password SET search_path = app_auth, public;

-- ============================================================================
-- LAUNCH SCHEMA FUNCTIONS
-- ============================================================================

ALTER FUNCTION launch.log_newsletter_signup SET search_path = launch, public;
ALTER FUNCTION launch.trigger_newsletter_welcome_email SET search_path = launch, system, public;
ALTER FUNCTION launch.send_newsletter_confirmation_email SET search_path = launch, system, public;
ALTER FUNCTION launch.send_newsletter_welcome_email SET search_path = launch, system, public;

-- ============================================================================
-- ADMIN SCHEMA FUNCTIONS
-- ============================================================================

ALTER FUNCTION admin.get_all_members SET search_path = admin, app_auth, auth;
ALTER FUNCTION admin.update_member_profile SET search_path = admin, app_auth, auth;
ALTER FUNCTION admin.get_member_transactions SET search_path = admin, app_auth, public;
ALTER FUNCTION admin.delete_member SET search_path = admin, app_auth, events, crowdfunding, auth;
ALTER FUNCTION admin.verify_dupr SET search_path = admin, app_auth;

-- ============================================================================
-- MARKETING SCHEMA FUNCTIONS
-- ============================================================================

ALTER FUNCTION marketing.mark_email_clicked SET search_path = marketing, public;
ALTER FUNCTION marketing.update_updated_at SET search_path = marketing, public;
ALTER FUNCTION marketing.mark_email_opened SET search_path = marketing, public;

-- ============================================================================
-- SYSTEM SCHEMA FUNCTIONS
-- ============================================================================

ALTER FUNCTION system.log_email SET search_path = system, public;
ALTER FUNCTION system.get_player_pricing_info SET search_path = system, app_auth, public;
ALTER FUNCTION system.record_registration_fee SET search_path = system, app_auth, public;
ALTER FUNCTION system.submit_contact_form SET search_path = system, contact, public;
ALTER FUNCTION system.record_membership_transaction SET search_path = system, app_auth, public;
ALTER FUNCTION system.get_all_membership_tiers SET search_path = system, app_auth, public;
ALTER FUNCTION system.get_membership_pricing SET search_path = system, app_auth, public;
ALTER FUNCTION system.has_paid_registration_fee SET search_path = system, app_auth, public;

-- ============================================================================
-- VERIFICATION
-- ============================================================================

COMMENT ON SCHEMA public IS
'PUBLIC SCHEMA - All functions now have explicit search_path set to prevent
search path hijacking attacks. This addresses Supabase linter warnings about
function_search_path_mutable.';

-- ============================================================================
-- NOTES
-- ============================================================================
-- This migration sets the search_path configuration parameter on all functions
-- that were flagged by the Supabase linter. The search_path for each function
-- includes only the schemas that function needs to access, following the
-- principle of least privilege.
--
-- Security benefit: Prevents search path hijacking where malicious users could
-- create objects in earlier search path schemas to intercept function calls.
-- ============================================================================
