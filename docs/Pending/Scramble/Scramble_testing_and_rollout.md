# Scramble Testing, QA, & Rollout Plan

## Automated Testing Strategy

### Unit Tests
- **Pairing Engine**: deterministic outputs for seed inputs, coverage for edge cases (odd players, late check-ins).
- **Score Validation**: ensure scoring formats reject invalid totals, handle forfeits gracefully.
- **Notification Builders**: snapshot tests for email/push templates.

### Integration Tests
- Use Supertest + Jest against Express handlers:
  - End-to-end round generation (setup → pair → score → standings).
  - Check-in flow with concurrent requests.
  - Score submission conflict resolution.
- Mock Supabase HTTP responses with `nock` to simulate realtime hooks.

### Database Tests
- `pgTAP` suites for stored procedures (`generate_scramble_round`, `calculate_scramble_standings`).
- Verify RLS policies deny unauthorized access and allow legitimate roles.
- Regression tests around migrations applying in sequence.

### UI Tests
- Component tests with Testing Library for core UI pieces (RoundTimer, ScoreInput).
- Cypress or Playwright smoke tests covering admin round workflow and player match view.

## Manual QA
- Staging environment seeded with 24-player scramble scenario.
- Guided scripts for QA team:
  1. Register and check in as player.
  2. Run three rounds, submit scores, validate leaderboard.
  3. Perform manual score correction and confirm audit trail.
  4. Trigger notifications and confirm across channels.
- Capture screenshots and note performance observations.

## Performance & Load Testing
- Simulate 8 concurrent admins submitting scores and 150 player clients receiving realtime updates.
- Target metrics:
  - Round generation <300ms p95.
  - WebSocket latency <1.5s p95.
  - API error rate <0.5%.
- Use k6 scripts stored in `api/tests/perf/scramble/`.

## Deployment Strategy
- Feature flag `scramble.enabled` stored in configuration service; disabled by default in production.
- Rollout phases:
  1. **Internal Beta**: Staff-only events, limited player base.
  2. **Soft Launch**: Select clubs, monitor metrics for 2 weeks.
  3. **General Availability**: Enable toggle for all tenants.
- Provide rollback plan: disable feature flag, revert to previous schema snapshot if critical failure (use `npm run db:rollback -- to=23`).

## Monitoring Post-Launch
- Key dashboards:
  - Round duration vs planned minutes.
  - Notifications failure rate.
  - Player engagement (check-in rate, matches completed).
- Alert thresholds shared with Ops; integrate with PagerDuty for P1 incidents.

## Documentation & Training
- Update `docs/operations/scramble-runbook.md` with procedures for staff.
- Produce quick-start video or Loom for admin workflow (host in internal knowledge base).
- Provide FAQ for players in app support center.

## Acceptance Criteria
- All automated tests added for scramble features run in CI (`npm test`) and pass reliably.
- Manual QA sign-off documented with test run IDs.
- Feature flag present and controllable via admin config interface.
- Runbook published and shared with operations stakeholders before GA.
