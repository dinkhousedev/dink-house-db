# Scramble Realtime & Notification Plan

## Realtime Architecture
- Use Supabase Realtime channels scoped per event: `scramble:event:<eventId>`.
- Distinct topics:
  - `rounds` for lifecycle updates.
  - `matches` for score and status changes.
  - `leaderboard` for standings refresh.
  - `announcements` for staff broadcasts.
- Subscribe admin dashboard and player clients to relevant topics with auth token gating.

## Event Publication Flow
1. Backend updates database (stored procedure or direct insert/update).
2. Postgres replication triggers Supabase Realtime to emit change events.
3. Gateway normalizes payloads and forwards to WebSocket clients.
4. Clients reduce events into local state stores (e.g., Redux/Pinia).

## Presence & Check-in
- Use Supabase Presence API to track connected players per event room.
- Broadcast staff presence separately to enable quick support (`staff-online` indicator).
- Store derived presence snapshots every 5 minutes for analytics.

## Live Timer Synchronization
- Single source of truth stored in `events.scramble_rounds.start_time` + round duration.
- Clients compute remaining time; periodic server heartbeat ensures drift stays <3s.
- Admin can adjust timer; change event published to resync clients.

## Notifications Channels

### Push Notifications
- Integrate with existing mobile push service (Firebase/APNS) via `notifications.queue`.
- Key notifications: registration confirmation, check-in reminder, round start, court change, final results.

### Email
- Use transactional templates stored in `api/lib/notifications/templates/`.
- Provide event-specific merge fields (court, partner, opponent, start time).
- Batch send final summary to reduce rate-limit exposure.

### SMS (Optional Upgrade)
- Pluggable Twilio provider for high-priority alerts (court change, weather delay).
- Respect user preferences stored in `app_auth.notification_settings`.

## Reliability & Retry Strategy
- Notifications service processes messages with exponential backoff and dead-letter queue.
- Store delivery attempts in `events.scramble_notifications` for audit.
- Implement health metrics: `notifications_pending`, `notifications_failed`, `realtime_active_connections`.

## Security & Privacy
- Sign WebSocket tokens with short TTL (15 minutes) and refresh via silent HTTP request.
- Filter sensitive fields before broadcasting (hide payment info, PII beyond names & skill level).
- Provide staff override to pause all outbound notifications during emergencies.

## Monitoring & Alerting
- Set up Grafana dashboard from Supabase metrics: connection count, payload volume, latency.
- Alert when `realtime_active_connections` drops unexpectedly or error rate >2% for 5 minutes.
- Log notification payloads with correlation IDs to match backend requests.

## Acceptance Criteria
- Realtime updates propagate to player clients within 1 second median latency.
- Notification retry queue drains within 10 minutes after transient outage.
- Presence list accuracy verified against manual headcounts at launch events.
- Security review signs off on token policies and payload filtering.
