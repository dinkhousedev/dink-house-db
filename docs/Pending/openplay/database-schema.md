# Database Schema for Open Play System

## Overview
This document details the complete database schema required for the Pickleball Open Play system with DUPR integration. The schema builds upon the existing PostgreSQL/Supabase infrastructure.

## Schema Architecture

### Existing Schemas
- `app_auth`: Authentication and user management
- `events`: Core event management
- `system`: System configuration and logs
- `content`: CMS and static content
- `contact`: Contact forms and inquiries

### New Schemas Required
- `analytics`: Event and player analytics
- `payments`: Payment processing and transactions
- `notifications`: Communication logs and templates

## Core Tables Enhancement

### 1. Player Profiles Enhancement

```sql
-- Enhance existing app_auth.players table
ALTER TABLE app_auth.players
ADD COLUMN IF NOT EXISTS dupr_data JSONB DEFAULT '{}'::jsonb,
ADD COLUMN IF NOT EXISTS play_preferences JSONB DEFAULT '{}'::jsonb,
ADD COLUMN IF NOT EXISTS notification_preferences JSONB DEFAULT '{}'::jsonb,
ADD COLUMN IF NOT EXISTS stats JSONB DEFAULT '{}'::jsonb;

-- DUPR data structure
COMMENT ON COLUMN app_auth.players.dupr_data IS '
{
  "dupr_id": "string",
  "doubles_rating": 3.45,
  "singles_rating": 3.25,
  "reliability": 0.95,
  "total_matches": 127,
  "last_sync": "2024-03-14T10:00:00Z",
  "access_token": "encrypted_token",
  "refresh_token": "encrypted_refresh_token",
  "connection_status": "active|expired|disconnected"
}';

-- Play preferences structure
COMMENT ON COLUMN app_auth.players.play_preferences IS '
{
  "play_style": "competitive|recreational|both",
  "preferred_times": ["morning", "evening", "weekend"],
  "preferred_formats": ["doubles", "singles", "mixed"],
  "preferred_courts": [1, 2, 3],
  "partner_preferences": {
    "skill_range": [3.0, 4.0],
    "play_style": "aggressive|defensive|balanced"
  }
}';

-- Create indexes for better query performance
CREATE INDEX idx_players_dupr_rating ON app_auth.players ((dupr_data->>'doubles_rating'));
CREATE INDEX idx_players_skill_level ON app_auth.players (skill_level);
CREATE INDEX idx_players_member_status ON app_auth.players (membership_level);
```

### 2. Enhanced Event Tables

```sql
-- Add columns to existing events.events table
ALTER TABLE events.events
ADD COLUMN IF NOT EXISTS dupr_submission_status VARCHAR(50),
ADD COLUMN IF NOT EXISTS dupr_submission_time TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS dupr_submission_results JSONB,
ADD COLUMN IF NOT EXISTS session_config JSONB DEFAULT '{}'::jsonb,
ADD COLUMN IF NOT EXISTS check_in_config JSONB DEFAULT '{}'::jsonb;

-- Session configuration structure
COMMENT ON COLUMN events.events.session_config IS '
{
  "format": "round_robin|ladder|swiss|elimination",
  "rounds": 8,
  "time_per_round": 15,
  "break_after_round": 4,
  "scoring": {
    "game_to": 11,
    "win_by": 2,
    "rally_scoring": true
  },
  "rotation": {
    "type": "automatic|manual",
    "algorithm": "balanced|random|snake"
  }
}';

-- Check-in configuration
COMMENT ON COLUMN events.events.check_in_config IS '
{
  "opens_minutes_before": 30,
  "closes_minutes_after": 15,
  "allow_walk_ins": true,
  "walk_in_fee_adjustment": 5.00,
  "require_waiver": true,
  "qr_code_enabled": true
}';
```

### 3. Registration System Enhancement

```sql
-- Enhance events.registrations table
ALTER TABLE events.registrations
ADD COLUMN IF NOT EXISTS check_in_time TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS check_in_method VARCHAR(50),
ADD COLUMN IF NOT EXISTS check_in_code VARCHAR(100) UNIQUE,
ADD COLUMN IF NOT EXISTS qr_code_data TEXT,
ADD COLUMN IF NOT EXISTS court_assignment INTEGER,
ADD COLUMN IF NOT EXISTS payment_id UUID,
ADD COLUMN IF NOT EXISTS refund_status VARCHAR(50),
ADD COLUMN IF NOT EXISTS refund_amount DECIMAL(10, 2);

-- Add check-in index
CREATE INDEX idx_registrations_check_in_code ON events.registrations (check_in_code);
CREATE INDEX idx_registrations_check_in_time ON events.registrations (check_in_time);

-- Check-in status view
CREATE VIEW events.check_in_status AS
SELECT
  r.id,
  r.event_id,
  r.player_id,
  p.first_name || ' ' || p.last_name as player_name,
  r.status as registration_status,
  r.check_in_time,
  r.check_in_method,
  r.court_assignment,
  CASE
    WHEN r.check_in_time IS NOT NULL THEN 'checked_in'
    WHEN e.start_time - INTERVAL '30 minutes' > NOW() THEN 'pending'
    WHEN e.start_time < NOW() THEN 'no_show'
    ELSE 'ready'
  END as check_in_status
FROM events.registrations r
JOIN app_auth.players p ON r.player_id = p.id
JOIN events.events e ON r.event_id = e.id;
```

## New Tables for Open Play Features

### 4. Match Results Management

```sql
-- Create match results table
CREATE TABLE events.match_results (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID NOT NULL REFERENCES events.events(id) ON DELETE CASCADE,
  session_id UUID,
  round_number INTEGER NOT NULL,
  court_id UUID REFERENCES events.courts(id),
  court_number INTEGER,

  -- Teams (for doubles)
  team1_player1_id UUID REFERENCES app_auth.players(id),
  team1_player2_id UUID REFERENCES app_auth.players(id),
  team2_player1_id UUID REFERENCES app_auth.players(id),
  team2_player2_id UUID REFERENCES app_auth.players(id),

  -- Scores
  team1_score INTEGER,
  team2_score INTEGER,

  -- Timing
  scheduled_time TIMESTAMPTZ,
  start_time TIMESTAMPTZ,
  end_time TIMESTAMPTZ,

  -- DUPR submission
  dupr_submitted BOOLEAN DEFAULT false,
  dupr_submission_id VARCHAR(100),
  dupr_submission_time TIMESTAMPTZ,
  dupr_submission_response JSONB,

  -- Metadata
  status VARCHAR(50) DEFAULT 'scheduled',
  notes TEXT,
  disputed BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT valid_scores CHECK (
    (team1_score IS NULL AND team2_score IS NULL) OR
    (team1_score >= 0 AND team2_score >= 0)
  )
);

-- Indexes for match results
CREATE INDEX idx_match_results_event_id ON events.match_results(event_id);
CREATE INDEX idx_match_results_session_id ON events.match_results(session_id);
CREATE INDEX idx_match_results_dupr_submitted ON events.match_results(dupr_submitted);
CREATE INDEX idx_match_results_players ON events.match_results(team1_player1_id, team1_player2_id, team2_player1_id, team2_player2_id);

-- Match results view for easier querying
CREATE VIEW events.match_results_view AS
SELECT
  mr.*,
  e.title as event_title,
  e.event_type,
  c.name as court_name,
  p1.first_name || ' ' || p1.last_name as team1_player1_name,
  p2.first_name || ' ' || p2.last_name as team1_player2_name,
  p3.first_name || ' ' || p3.last_name as team2_player1_name,
  p4.first_name || ' ' || p4.last_name as team2_player2_name
FROM events.match_results mr
LEFT JOIN events.events e ON mr.event_id = e.id
LEFT JOIN events.courts c ON mr.court_id = c.id
LEFT JOIN app_auth.players p1 ON mr.team1_player1_id = p1.id
LEFT JOIN app_auth.players p2 ON mr.team1_player2_id = p2.id
LEFT JOIN app_auth.players p3 ON mr.team2_player1_id = p3.id
LEFT JOIN app_auth.players p4 ON mr.team2_player2_id = p4.id;
```

### 5. Session Management

```sql
-- Create event sessions table
CREATE TABLE events.event_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID NOT NULL REFERENCES events.events(id) ON DELETE CASCADE,

  -- Session details
  status VARCHAR(50) DEFAULT 'pending',
  actual_start_time TIMESTAMPTZ,
  actual_end_time TIMESTAMPTZ,

  -- Player counts
  total_players INTEGER,
  checked_in_players INTEGER,
  no_show_players INTEGER,
  walk_in_players INTEGER,

  -- Courts
  courts_used INTEGER[],

  -- Round tracking
  current_round INTEGER DEFAULT 0,
  total_rounds INTEGER,
  round_start_times TIMESTAMPTZ[],

  -- Session data
  rotation_data JSONB,
  leaderboard JSONB,

  -- Metadata
  created_by UUID REFERENCES app_auth.admin_users(id),
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_event_sessions_event_id ON events.event_sessions(event_id);
CREATE INDEX idx_event_sessions_status ON events.event_sessions(status);

-- Round rotations table
CREATE TABLE events.round_rotations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES events.event_sessions(id) ON DELETE CASCADE,
  round_number INTEGER NOT NULL,

  -- Rotation data
  court_assignments JSONB NOT NULL,
  -- Format: [{"court": 1, "team1": ["player1_id", "player2_id"], "team2": ["player3_id", "player4_id"]}]

  -- Timing
  scheduled_start TIMESTAMPTZ,
  actual_start TIMESTAMPTZ,
  actual_end TIMESTAMPTZ,

  -- Status
  status VARCHAR(50) DEFAULT 'pending',

  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

  UNIQUE(session_id, round_number)
);

CREATE INDEX idx_round_rotations_session_id ON events.round_rotations(session_id);
```

### 6. Payment Processing

```sql
-- Create payments schema
CREATE SCHEMA IF NOT EXISTS payments;

-- Payment transactions table
CREATE TABLE payments.transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Related entities
  player_id UUID REFERENCES app_auth.players(id),
  event_id UUID REFERENCES events.events(id),
  registration_id UUID REFERENCES events.registrations(id),

  -- Transaction details
  amount DECIMAL(10, 2) NOT NULL,
  currency VARCHAR(3) DEFAULT 'USD',
  payment_method VARCHAR(50) NOT NULL,
  processor VARCHAR(50), -- stripe, square, paypal
  processor_transaction_id VARCHAR(255),

  -- Status
  status VARCHAR(50) NOT NULL,
  failure_reason TEXT,

  -- Refund tracking
  refunded BOOLEAN DEFAULT false,
  refund_amount DECIMAL(10, 2),
  refund_transaction_id VARCHAR(255),
  refund_date TIMESTAMPTZ,
  refund_reason TEXT,

  -- Metadata
  metadata JSONB,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_transactions_player_id ON payments.transactions(player_id);
CREATE INDEX idx_transactions_event_id ON payments.transactions(event_id);
CREATE INDEX idx_transactions_status ON payments.transactions(status);
CREATE INDEX idx_transactions_created_at ON payments.transactions(created_at);

-- Payment methods table (stored cards, etc.)
CREATE TABLE payments.payment_methods (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  player_id UUID NOT NULL REFERENCES app_auth.players(id),

  -- Method details
  type VARCHAR(50) NOT NULL, -- card, bank_account, paypal
  processor VARCHAR(50) NOT NULL,
  processor_customer_id VARCHAR(255),
  processor_payment_method_id VARCHAR(255),

  -- Display info (for cards)
  last_four VARCHAR(4),
  brand VARCHAR(50),
  exp_month INTEGER,
  exp_year INTEGER,

  -- Status
  is_default BOOLEAN DEFAULT false,
  is_active BOOLEAN DEFAULT true,

  -- Metadata
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_payment_methods_player_id ON payments.payment_methods(player_id);
CREATE INDEX idx_payment_methods_is_default ON payments.payment_methods(is_default);
```

### 7. Notifications System

```sql
-- Create notifications schema
CREATE SCHEMA IF NOT EXISTS notifications;

-- Notification templates
CREATE TABLE notifications.templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Template identification
  name VARCHAR(100) NOT NULL UNIQUE,
  type VARCHAR(50) NOT NULL, -- email, sms, push
  category VARCHAR(50) NOT NULL, -- registration, reminder, update, marketing

  -- Content
  subject VARCHAR(255),
  body_template TEXT NOT NULL,
  body_html TEXT,

  -- Variables
  required_variables TEXT[], -- ['player_name', 'event_title', 'start_time']

  -- Settings
  is_active BOOLEAN DEFAULT true,

  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- Notification log
CREATE TABLE notifications.send_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Recipient
  player_id UUID REFERENCES app_auth.players(id),
  recipient_email VARCHAR(255),
  recipient_phone VARCHAR(50),

  -- Template and content
  template_id UUID REFERENCES notifications.templates(id),
  type VARCHAR(50) NOT NULL,
  subject VARCHAR(255),
  body TEXT,

  -- Related entities
  event_id UUID REFERENCES events.events(id),
  registration_id UUID REFERENCES events.registrations(id),

  -- Delivery
  status VARCHAR(50) NOT NULL, -- pending, sent, delivered, failed, bounced
  provider VARCHAR(50), -- sendgrid, twilio, firebase
  provider_message_id VARCHAR(255),

  -- Tracking
  sent_at TIMESTAMPTZ,
  delivered_at TIMESTAMPTZ,
  opened_at TIMESTAMPTZ,
  clicked_at TIMESTAMPTZ,

  -- Error handling
  error_message TEXT,
  retry_count INTEGER DEFAULT 0,

  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_send_log_player_id ON notifications.send_log(player_id);
CREATE INDEX idx_send_log_event_id ON notifications.send_log(event_id);
CREATE INDEX idx_send_log_status ON notifications.send_log(status);
CREATE INDEX idx_send_log_created_at ON notifications.send_log(created_at);

-- Notification preferences (player-specific)
CREATE TABLE notifications.player_preferences (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  player_id UUID NOT NULL REFERENCES app_auth.players(id) UNIQUE,

  -- Channel preferences
  email_enabled BOOLEAN DEFAULT true,
  sms_enabled BOOLEAN DEFAULT false,
  push_enabled BOOLEAN DEFAULT false,

  -- Category preferences
  registration_notifications BOOLEAN DEFAULT true,
  reminder_notifications BOOLEAN DEFAULT true,
  update_notifications BOOLEAN DEFAULT true,
  marketing_notifications BOOLEAN DEFAULT false,

  -- Timing preferences
  reminder_hours_before INTEGER DEFAULT 24,
  quiet_hours_start TIME,
  quiet_hours_end TIME,

  -- Frequency
  max_emails_per_day INTEGER DEFAULT 5,
  max_sms_per_day INTEGER DEFAULT 3,

  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);
```

### 8. Analytics Tables

```sql
-- Create analytics schema
CREATE SCHEMA IF NOT EXISTS analytics;

-- Event performance metrics
CREATE TABLE analytics.event_metrics (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID NOT NULL REFERENCES events.events(id),

  -- Registration metrics
  total_registrations INTEGER DEFAULT 0,
  confirmed_registrations INTEGER DEFAULT 0,
  waitlist_registrations INTEGER DEFAULT 0,
  cancellations INTEGER DEFAULT 0,
  no_shows INTEGER DEFAULT 0,
  walk_ins INTEGER DEFAULT 0,

  -- Financial metrics
  total_revenue DECIMAL(10, 2) DEFAULT 0,
  member_revenue DECIMAL(10, 2) DEFAULT 0,
  guest_revenue DECIMAL(10, 2) DEFAULT 0,
  refunds_issued DECIMAL(10, 2) DEFAULT 0,

  -- Engagement metrics
  check_in_rate DECIMAL(5, 2),
  completion_rate DECIMAL(5, 2),
  average_rating DECIMAL(3, 2),
  feedback_count INTEGER DEFAULT 0,

  -- DUPR metrics
  dupr_matches_played INTEGER DEFAULT 0,
  dupr_matches_submitted INTEGER DEFAULT 0,
  average_dupr_rating DECIMAL(3, 2),

  -- Timing metrics
  average_check_in_time INTEGER, -- seconds before start
  average_game_duration INTEGER, -- minutes

  calculated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_event_metrics_event_id ON analytics.event_metrics(event_id);
CREATE INDEX idx_event_metrics_calculated_at ON analytics.event_metrics(calculated_at);

-- Player activity tracking
CREATE TABLE analytics.player_activity (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  player_id UUID NOT NULL REFERENCES app_auth.players(id),

  -- Activity type
  activity_type VARCHAR(50) NOT NULL, -- login, register, check_in, play, cancel

  -- Related entities
  event_id UUID REFERENCES events.events(id),
  registration_id UUID REFERENCES events.registrations(id),

  -- Details
  details JSONB,

  -- Tracking
  ip_address INET,
  user_agent TEXT,

  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_player_activity_player_id ON analytics.player_activity(player_id);
CREATE INDEX idx_player_activity_type ON analytics.player_activity(activity_type);
CREATE INDEX idx_player_activity_created_at ON analytics.player_activity(created_at);

-- Aggregated player stats
CREATE TABLE analytics.player_stats (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  player_id UUID NOT NULL REFERENCES app_auth.players(id) UNIQUE,

  -- Participation stats
  total_events INTEGER DEFAULT 0,
  total_matches INTEGER DEFAULT 0,
  total_wins INTEGER DEFAULT 0,
  total_losses INTEGER DEFAULT 0,
  win_percentage DECIMAL(5, 2),

  -- Financial stats
  total_spent DECIMAL(10, 2) DEFAULT 0,
  average_spend_per_event DECIMAL(10, 2),

  -- Engagement stats
  last_played_date DATE,
  days_since_last_play INTEGER,
  average_events_per_month DECIMAL(5, 2),
  no_show_count INTEGER DEFAULT 0,
  cancellation_count INTEGER DEFAULT 0,

  -- DUPR progression
  starting_dupr_rating DECIMAL(3, 2),
  current_dupr_rating DECIMAL(3, 2),
  highest_dupr_rating DECIMAL(3, 2),
  dupr_rating_change DECIMAL(3, 2),

  -- Preferences learned
  preferred_play_times JSONB,
  frequent_partners UUID[],
  preferred_courts INTEGER[],

  last_calculated TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_player_stats_player_id ON analytics.player_stats(player_id);
CREATE INDEX idx_player_stats_last_played ON analytics.player_stats(last_played_date);
```

### 9. System Tables

```sql
-- DUPR sync tracking
CREATE TABLE system.dupr_sync_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Sync details
  sync_type VARCHAR(50) NOT NULL, -- rating_update, match_submission, player_verify

  -- Related entities
  player_id UUID REFERENCES app_auth.players(id),
  event_id UUID REFERENCES events.events(id),

  -- Request/Response
  request_data JSONB,
  response_data JSONB,

  -- Status
  status VARCHAR(50) NOT NULL,
  error_message TEXT,

  -- Timing
  started_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  completed_at TIMESTAMPTZ,
  duration_ms INTEGER
);

CREATE INDEX idx_dupr_sync_log_player_id ON system.dupr_sync_log(player_id);
CREATE INDEX idx_dupr_sync_log_status ON system.dupr_sync_log(status);
CREATE INDEX idx_dupr_sync_log_started_at ON system.dupr_sync_log(started_at);

-- API rate limiting
CREATE TABLE system.api_rate_limits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Identifier
  identifier VARCHAR(255) NOT NULL, -- player_id, ip_address, api_key
  identifier_type VARCHAR(50) NOT NULL,

  -- Limits
  endpoint VARCHAR(255),
  requests_count INTEGER DEFAULT 0,
  window_start TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

  -- Rate limit settings
  max_requests INTEGER,
  window_seconds INTEGER,

  UNIQUE(identifier, identifier_type, endpoint, window_start)
);

CREATE INDEX idx_api_rate_limits_identifier ON system.api_rate_limits(identifier);
CREATE INDEX idx_api_rate_limits_window_start ON system.api_rate_limits(window_start);

-- Feature flags
CREATE TABLE system.feature_flags (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Flag details
  name VARCHAR(100) NOT NULL UNIQUE,
  description TEXT,

  -- Settings
  enabled BOOLEAN DEFAULT false,
  rollout_percentage INTEGER DEFAULT 0,

  -- Targeting
  enabled_for_players UUID[],
  enabled_for_groups VARCHAR[],

  -- Metadata
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);
```

## Views and Materialized Views

### 10. Useful Views

```sql
-- Current event availability
CREATE VIEW events.event_availability AS
SELECT
  e.id,
  e.title,
  e.start_time,
  e.max_capacity,
  COUNT(r.id) FILTER (WHERE r.status = 'registered') as registered_count,
  e.max_capacity - COUNT(r.id) FILTER (WHERE r.status = 'registered') as available_spots,
  COUNT(r.id) FILTER (WHERE r.status = 'waitlisted') as waitlist_count,
  CASE
    WHEN e.max_capacity - COUNT(r.id) FILTER (WHERE r.status = 'registered') > 0 THEN 'available'
    WHEN COUNT(r.id) FILTER (WHERE r.status = 'waitlisted') > 0 THEN 'waitlist'
    ELSE 'full'
  END as status
FROM events.events e
LEFT JOIN events.registrations r ON e.id = r.event_id
WHERE e.status = 'published' AND e.start_time > NOW()
GROUP BY e.id;

-- Player engagement summary
CREATE MATERIALIZED VIEW analytics.player_engagement_summary AS
SELECT
  p.id as player_id,
  p.first_name || ' ' || p.last_name as player_name,
  p.membership_level,
  (p.dupr_data->>'doubles_rating')::NUMERIC as dupr_rating,
  COUNT(DISTINCT r.event_id) as total_events,
  COUNT(DISTINCT r.event_id) FILTER (WHERE r.check_in_time IS NOT NULL) as attended_events,
  COUNT(DISTINCT r.event_id) FILTER (WHERE r.status = 'no_show') as no_shows,
  MAX(r.created_at) as last_registration,
  MAX(r.check_in_time) as last_attendance,
  SUM(pt.amount) FILTER (WHERE pt.status = 'completed') as total_spent
FROM app_auth.players p
LEFT JOIN events.registrations r ON p.id = r.player_id
LEFT JOIN payments.transactions pt ON r.id = pt.registration_id
GROUP BY p.id;

-- Refresh materialized view periodically
CREATE INDEX idx_player_engagement_player_id ON analytics.player_engagement_summary(player_id);

-- Event performance dashboard
CREATE VIEW analytics.event_performance_dashboard AS
SELECT
  e.id,
  e.title,
  e.event_type,
  e.start_time,
  em.total_registrations,
  em.check_in_rate,
  em.total_revenue,
  em.average_rating,
  em.dupr_matches_submitted,
  CASE
    WHEN em.check_in_rate >= 0.9 AND em.average_rating >= 4.5 THEN 'excellent'
    WHEN em.check_in_rate >= 0.8 AND em.average_rating >= 4.0 THEN 'good'
    WHEN em.check_in_rate >= 0.7 AND em.average_rating >= 3.5 THEN 'fair'
    ELSE 'needs_improvement'
  END as performance_rating
FROM events.events e
LEFT JOIN analytics.event_metrics em ON e.id = em.event_id
WHERE e.end_time < NOW()
ORDER BY e.start_time DESC;
```

## Functions and Triggers

### 11. Core Functions

```sql
-- Function to check event eligibility based on DUPR rating
CREATE OR REPLACE FUNCTION events.check_dupr_eligibility(
  p_player_id UUID,
  p_event_id UUID
)
RETURNS BOOLEAN AS $$
DECLARE
  v_player_rating NUMERIC;
  v_event_min NUMERIC;
  v_event_max NUMERIC;
  v_buffer NUMERIC;
BEGIN
  -- Get player's DUPR rating
  SELECT (dupr_data->>'doubles_rating')::NUMERIC
  INTO v_player_rating
  FROM app_auth.players
  WHERE id = p_player_id;

  -- Get event DUPR requirements
  SELECT
    dupr_min_rating,
    dupr_max_rating,
    COALESCE((dupr_buffer)::NUMERIC, 0.25)
  INTO v_event_min, v_event_max, v_buffer
  FROM events.events
  WHERE id = p_event_id;

  -- If event doesn't require DUPR, allow registration
  IF v_event_min IS NULL AND v_event_max IS NULL THEN
    RETURN TRUE;
  END IF;

  -- If player has no DUPR rating, deny
  IF v_player_rating IS NULL THEN
    RETURN FALSE;
  END IF;

  -- Check if player is within range (including buffer)
  RETURN v_player_rating >= (v_event_min - v_buffer)
     AND v_player_rating <= (v_event_max + v_buffer);
END;
$$ LANGUAGE plpgsql;

-- Function to generate check-in code
CREATE OR REPLACE FUNCTION events.generate_check_in_code()
RETURNS TRIGGER AS $$
BEGIN
  NEW.check_in_code := 'CHK-' ||
    TO_CHAR(NOW(), 'YYYY-MMDD-') ||
    LPAD(FLOOR(RANDOM() * 10000)::TEXT, 4, '0');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to generate check-in code on registration
CREATE TRIGGER generate_check_in_code_trigger
BEFORE INSERT ON events.registrations
FOR EACH ROW
EXECUTE FUNCTION events.generate_check_in_code();

-- Function to calculate player statistics
CREATE OR REPLACE FUNCTION analytics.calculate_player_stats(p_player_id UUID)
RETURNS VOID AS $$
BEGIN
  INSERT INTO analytics.player_stats (
    player_id,
    total_events,
    total_matches,
    total_wins,
    total_losses,
    win_percentage,
    total_spent,
    last_played_date,
    current_dupr_rating
  )
  SELECT
    p_player_id,
    COUNT(DISTINCT r.event_id),
    COUNT(DISTINCT mr.id),
    COUNT(DISTINCT mr.id) FILTER (
      WHERE (mr.team1_player1_id = p_player_id OR mr.team1_player2_id = p_player_id)
      AND mr.team1_score > mr.team2_score
    ),
    COUNT(DISTINCT mr.id) FILTER (
      WHERE (mr.team2_player1_id = p_player_id OR mr.team2_player2_id = p_player_id)
      AND mr.team2_score > mr.team1_score
    ),
    CASE
      WHEN COUNT(DISTINCT mr.id) > 0 THEN
        (COUNT(DISTINCT mr.id) FILTER (
          WHERE (mr.team1_player1_id = p_player_id OR mr.team1_player2_id = p_player_id)
          AND mr.team1_score > mr.team2_score
        )::NUMERIC / COUNT(DISTINCT mr.id)) * 100
      ELSE 0
    END,
    COALESCE(SUM(pt.amount), 0),
    MAX(DATE(r.check_in_time)),
    (SELECT (dupr_data->>'doubles_rating')::NUMERIC FROM app_auth.players WHERE id = p_player_id)
  FROM events.registrations r
  LEFT JOIN events.match_results mr ON r.event_id = mr.event_id
  LEFT JOIN payments.transactions pt ON r.id = pt.registration_id
  WHERE r.player_id = p_player_id
  ON CONFLICT (player_id) DO UPDATE SET
    total_events = EXCLUDED.total_events,
    total_matches = EXCLUDED.total_matches,
    total_wins = EXCLUDED.total_wins,
    total_losses = EXCLUDED.total_losses,
    win_percentage = EXCLUDED.win_percentage,
    total_spent = EXCLUDED.total_spent,
    last_played_date = EXCLUDED.last_played_date,
    current_dupr_rating = EXCLUDED.current_dupr_rating,
    last_calculated = NOW();
END;
$$ LANGUAGE plpgsql;
```

## Indexes and Performance

### 12. Critical Indexes

```sql
-- Registration performance
CREATE INDEX idx_registrations_composite ON events.registrations(event_id, player_id, status);
CREATE INDEX idx_registrations_created_at ON events.registrations(created_at DESC);

-- Match results performance
CREATE INDEX idx_match_results_composite ON events.match_results(event_id, round_number, court_id);

-- Payment lookups
CREATE INDEX idx_transactions_composite ON payments.transactions(player_id, status, created_at DESC);

-- Notification delivery
CREATE INDEX idx_send_log_composite ON notifications.send_log(player_id, type, status, created_at DESC);

-- Analytics queries
CREATE INDEX idx_event_metrics_composite ON analytics.event_metrics(event_id, calculated_at DESC);
CREATE INDEX idx_player_activity_composite ON analytics.player_activity(player_id, activity_type, created_at DESC);
```

## Security and RLS Policies

### 13. Row Level Security

```sql
-- Enable RLS on sensitive tables
ALTER TABLE app_auth.players ENABLE ROW LEVEL SECURITY;
ALTER TABLE events.registrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments.transactions ENABLE ROW LEVEL SECURITY;

-- Players can only see their own data
CREATE POLICY players_self_view ON app_auth.players
  FOR SELECT USING (auth.uid() = id);

CREATE POLICY players_self_update ON app_auth.players
  FOR UPDATE USING (auth.uid() = id);

-- Players can see their own registrations
CREATE POLICY registrations_self_view ON events.registrations
  FOR SELECT USING (auth.uid() = player_id);

-- Players can see their own payments
CREATE POLICY transactions_self_view ON payments.transactions
  FOR SELECT USING (auth.uid() = player_id);

-- Public can view published events
CREATE POLICY events_public_view ON events.events
  FOR SELECT USING (status = 'published');

-- Staff can see all data (role-based)
CREATE POLICY staff_all_access ON app_auth.players
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM app_auth.admin_users
      WHERE id = auth.uid()
      AND role IN ('super_admin', 'admin', 'manager')
    )
  );
```

## Data Migration Scripts

### 14. Migration from Existing Schema

```sql
-- Migrate existing player data to enhanced schema
UPDATE app_auth.players
SET
  dupr_data = jsonb_build_object(
    'doubles_rating', dupr_rating,
    'connection_status', CASE WHEN dupr_id IS NOT NULL THEN 'active' ELSE 'disconnected' END
  ),
  play_preferences = jsonb_build_object(
    'play_style', 'competitive',
    'preferred_times', ARRAY['evening', 'weekend']
  ),
  notification_preferences = jsonb_build_object(
    'email', true,
    'sms', false,
    'push', false
  )
WHERE dupr_data IS NULL;

-- Populate initial analytics
INSERT INTO analytics.player_stats (player_id)
SELECT id FROM app_auth.players
ON CONFLICT DO NOTHING;

-- Create notification templates
INSERT INTO notifications.templates (name, type, category, subject, body_template) VALUES
  ('registration_confirmation', 'email', 'registration',
   'Registration Confirmed: {{event_title}}',
   'Hi {{player_name}}, you are registered for {{event_title}} on {{start_time}}.'),
  ('event_reminder_48h', 'email', 'reminder',
   'Reminder: {{event_title}} in 48 hours',
   'Hi {{player_name}}, this is a reminder about {{event_title}} on {{start_time}}.'),
  ('check_in_open', 'sms', 'reminder',
   null,
   'Check-in is now open for {{event_title}}. Show this code at the desk: {{check_in_code}}');
```

## Maintenance Procedures

### 15. Regular Maintenance

```sql
-- Daily maintenance procedure
CREATE OR REPLACE PROCEDURE maintenance.daily_cleanup()
LANGUAGE plpgsql AS $$
BEGIN
  -- Clean up old rate limit records
  DELETE FROM system.api_rate_limits
  WHERE window_start < NOW() - INTERVAL '1 day';

  -- Archive old notifications
  INSERT INTO notifications.send_log_archive
  SELECT * FROM notifications.send_log
  WHERE created_at < NOW() - INTERVAL '30 days';

  DELETE FROM notifications.send_log
  WHERE created_at < NOW() - INTERVAL '30 days';

  -- Update player statistics
  PERFORM analytics.calculate_player_stats(id)
  FROM app_auth.players
  WHERE updated_at > NOW() - INTERVAL '1 day';

  -- Refresh materialized views
  REFRESH MATERIALIZED VIEW CONCURRENTLY analytics.player_engagement_summary;
END;
$$;

-- Schedule with pg_cron
SELECT cron.schedule('daily-maintenance', '0 2 * * *', 'CALL maintenance.daily_cleanup()');
```

## Backup and Recovery

### 16. Backup Strategy

```sql
-- Critical tables for point-in-time recovery
COMMENT ON TABLE app_auth.players IS 'BACKUP_PRIORITY: CRITICAL';
COMMENT ON TABLE events.events IS 'BACKUP_PRIORITY: CRITICAL';
COMMENT ON TABLE events.registrations IS 'BACKUP_PRIORITY: CRITICAL';
COMMENT ON TABLE events.match_results IS 'BACKUP_PRIORITY: CRITICAL';
COMMENT ON TABLE payments.transactions IS 'BACKUP_PRIORITY: CRITICAL';

-- Create backup schema
CREATE SCHEMA IF NOT EXISTS backup;

-- Automated backup function
CREATE OR REPLACE FUNCTION backup.create_snapshot(p_table_name TEXT)
RETURNS VOID AS $$
DECLARE
  v_backup_table TEXT;
BEGIN
  v_backup_table := 'backup.' || p_table_name || '_' || TO_CHAR(NOW(), 'YYYYMMDD_HH24MI');

  EXECUTE format('CREATE TABLE %s AS SELECT * FROM %s', v_backup_table, p_table_name);

  RAISE NOTICE 'Backup created: %', v_backup_table;
END;
$$ LANGUAGE plpgsql;
```

## Monitoring Queries

### 17. Health Check Queries

```sql
-- System health dashboard
SELECT
  'Active Events' as metric,
  COUNT(*) as value
FROM events.events
WHERE start_time BETWEEN NOW() AND NOW() + INTERVAL '7 days'
  AND status = 'published'
UNION ALL
SELECT
  'Pending Check-ins' as metric,
  COUNT(*) as value
FROM events.registrations r
JOIN events.events e ON r.event_id = e.id
WHERE e.start_time BETWEEN NOW() AND NOW() + INTERVAL '1 hour'
  AND r.check_in_time IS NULL
UNION ALL
SELECT
  'Failed Payments Today' as metric,
  COUNT(*) as value
FROM payments.transactions
WHERE created_at > CURRENT_DATE
  AND status = 'failed'
UNION ALL
SELECT
  'Pending DUPR Submissions' as metric,
  COUNT(*) as value
FROM events.match_results
WHERE dupr_submitted = false
  AND created_at > NOW() - INTERVAL '24 hours';
```

## Conclusion

This comprehensive database schema provides the foundation for a robust pickleball open play management system with full DUPR integration. The schema is designed for:

- **Scalability**: Proper indexing and partitioning strategies
- **Performance**: Materialized views and optimized queries
- **Security**: Row-level security and encryption
- **Maintainability**: Clear structure and documentation
- **Extensibility**: Room for future features and integrations

Regular monitoring, maintenance, and backups ensure system reliability and data integrity.