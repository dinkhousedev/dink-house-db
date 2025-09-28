# Scramble Backend Services Plan

## Service Overview
- Extend existing Express gateway in `api/` with scramble-specific routes, controllers, and Supabase service wrappers.
- Maintain separation between HTTP handlers, business logic (pairing engine), and data access (Supabase client + SQL functions).
- Ensure idempotent operations for critical paths (round generation, score submission) to support retries.

## API Surface

### REST Endpoints (Express)
- `POST /events/:eventId/scramble/setup`
  - Validates event eligibility, creates `events.scrambles` record, seeds default configuration.
- `POST /events/:eventId/scramble/rounds`
  - Triggers `events.generate_scramble_round`, returns match assignments.
- `PATCH /events/:eventId/scramble/rounds/:roundId`
  - Allows admin to update round status (`pending` → `active` → `completed`).
- `POST /matches/:matchId/score`
  - Validates payload, writes score via stored procedure, emits realtime updates.
- `POST /events/:eventId/scramble/checkins`
  - Records player check-in, handles walk-ins, responds with updated roster.
- `GET /events/:eventId/scramble/leaderboard`
  - Returns aggregated standings, includes pagination for large events.

### Admin GraphQL (Optional Future)
- Extend Supabase GraphQL with views `v_scramble_rounds` and `v_scramble_leaderboard` for low-latency dashboards.

## Pairing Engine

### Responsibilities
- Accepts player pool, historical partnerships, and configuration constraints.
- Produces balanced teams and court assignments using heuristic algorithm.
- Supports fallback strategies for odd player counts (bye, rotating referee, ghost player).

### Implementation Sketch
```ts
class PairingEngine {
  constructor(config, players, history, courts) {}
  generateRound() {
    // 1. Bucket players by skill band.
    // 2. Seed pairs using ELO/DUPR differentials.
    // 3. Resolve conflicts (repeat partners, court conflicts) via simulated annealing.
    // 4. Assign courts based on availability + preference weightings.
  }
}
```
- Provide deterministic random seed per round for reproducibility in audits.
- Emit debug telemetry (pairing cost, iterations) for Ops review.

## Background Jobs & Schedulers
- Use existing job runner (BullMQ or Supabase Edge Function) for asynchronous tasks:
  - Auto-generate next round when all matches complete.
  - Send pre-round reminders 2 minutes before start.
  - Archive completed scrambles nightly.
- Store job definitions in `api/lib/jobs/scramble/` with unit tests for payload validation.

## Integration Points
- **Supabase**: Rely on row-level policies; use service role for admin endpoints.
- **Stripe**: Ensure scramble creation respects payment settlement status before allowing check-in.
- **Notifications**: Publish events to `notifications.queue` (Redis or Supabase functions).
- **Analytics**: Push round/match events to Segment via existing telemetry middleware.

## Error Handling & Observability
- Standardize error responses with codes (`SCRAMBLE_CONFLICT`, `SCRAMBLE_NOT_FOUND`, etc.).
- Implement retries for transient Supabase errors with exponential backoff.
- Log structured events (JSON) with correlation IDs for each scramble session.
- Emit Prometheus metrics: `scramble_round_generation_duration`, `scramble_score_submissions_total`, `scramble_api_errors_total`.

## Security Considerations
- Ensure admin endpoints require JWT with `role=staff` claim; verify against Supabase `app_auth.admins` table.
- Prevent score tampering by verifying player participation before accepting results.
- Rate limit score submission endpoint (max 10/min per client) via middleware in `api/lib/middleware/rateLimit.js`.
- Audit log all admin interventions (manual court reassignments, score overrides).

## Acceptance Criteria
- API handlers covered by integration tests in `api/tests/scramble/*.test.js` using Supertest.
- Pairing engine handles 3 canonical scenarios (16 players even skill, 21 players mixed skill, 8 players high skill) within <250ms.
- Background jobs recover gracefully after process restarts (persisted state in Redis/Supabase).
- Grafana dashboards display pairing duration and score submission error rate before launch.
