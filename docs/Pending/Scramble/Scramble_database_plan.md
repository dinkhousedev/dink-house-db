# Scramble Database & Migration Plan

## Objectives
- Extend the events schema to support scramble-specific configuration, scheduling, and live results.
- Preserve data integrity through relational constraints, triggers, and row-level security (RLS).
- Provide migration artifacts and seed data that align with existing `sql/modules` conventions.

## Schema Modules

### 1. Core Tables (`24-scramble-system.sql`)
- `events.scrambles`: Stores per-event configuration including format, pairing options, and tempo controls.
- `events.scramble_rounds`: Tracks round lifecycle, enforce unique `(scramble_id, round_number)` to prevent duplicates.
- `events.matches`: Represents individual matches with status transitions and timing metadata.
- `events.match_players`: Joins players to matches, records team allocation and per-player stats.
- `events.player_partnerships`: Records historical pairings per round to enforce spacing constraints.
- `events.scramble_standings`: Materializes live standings and point differentials.
- `events.player_checkins`: Captures attendance metadata prior to pairing generation.

### 2. Supporting Artifacts (`25-scramble-support.sql`)
- `events.scramble_courts`: Optional override when courts are reserved for scramble rounds.
- `events.scramble_notifications`: Persists notification state for auditing and retries.
- Views for admin dashboards:
  - `events.v_scramble_rounds`: Joins scrambles, rounds, and metadata for quick admin queries.
  - `events.v_scramble_leaderboard`: Aggregates standings and recent results.

## Data Integrity Controls

### Constraints & Indexes
- Foreign keys cascade on delete to keep orphan data out.
- Partial indexes on `events.matches(status)` and `events.scramble_rounds(status)` for quick filtering.
- Composite index on `events.match_players (player_id, match_id)` to accelerate participation queries.
- Unique index on `events.player_partnerships (scramble_id, player1_id, player2_id)` to prevent duplicate histories.

### Triggers
- `events.matches` trigger to auto-update `updated_at` and write audit records to `events.match_audit_log`.
- `events.scramble_rounds` trigger to set `start_time` when status moves to `active`.
- `events.match_players` trigger to sync accumulative stats into `events.scramble_standings`.

### Row-Level Security
- Enable RLS on all new tables.
- Policies:
  - **Admin Access**: Staff can read/write scrambles for events they manage.
  - **Player Access**: Players can read their own matches, standings, and check-in records.
  - **Public Restriction**: Deny by default to keep scramble data private.
- Update `api/config/supabase-policies.sql` with new policy definitions and helper roles.

## Stored Procedures & Functions
- `events.generate_scramble_round(scramble_id UUID)`: Builds next round pairings and writes to `events.matches`.
- `events.calculate_scramble_standings(scramble_id UUID)`: Recomputes leaderboard, supports manual recalculation.
- `events.cancel_scramble_round(round_id UUID)`: Rolls back matches, returns players to available pool.
- `events.record_scramble_score(match_id UUID, team1_score INT, team2_score INT)`: Validates inputs, updates standings, logs audit entry.
- Add PL/pgSQL unit tests via `pgTAP` in `sql/tests/24-scramble-system.sql` to cover edge cases (odd player counts, court overflow).

## Migration Process
1. Create `sql/modules/24-scramble-system.sql` with core tables and constraints.
2. Create `sql/modules/25-scramble-support.sql` for auxiliary tables, views, and functions.
3. Update `sql/modules/_meta/manifest.json` with new modules to maintain deterministic ordering.
4. Run `npm run db:migrate` locally against fresh container to validate dependencies.
5. Add rollback scripts in `sql/modules/24-scramble-system.down.sql` and `.down` companion for module 25.

## Seed Data & Fixtures
- Extend `sql/seeds/05-events.sql` with a sample scramble event to exercise pairing pipeline.
- Create `sql/seeds/06-scramble-fixtures.sql` including:
  - 24 demo players across DUPR bands.
  - Pre-populated check-ins for QA scenarios.
  - Snapshot of 3 completed rounds for analytics testing.
- Ensure seeds align with `events.season_id` constraints and avoid collisions with existing fixtures.

## Operational Considerations
- Size columns for future growth (`UUID` keys, `TIMESTAMPTZ`).
- Schedule routine vacuum/analyze on scramble tables due to frequent updates during live play.
- Configure Supabase `realtime.replication` for `events.matches`, `events.match_players`, and `events.scramble_standings`.
- Document data retention (archive scrambles older than 18 months to cold storage via nightly job).

## Acceptance Criteria
- Migrations apply cleanly on staging and production without blocking existing events.
- RLS policies verified through automated tests and manual Supabase policy inspector.
- Stored procedures return deterministic results for standard test inputs in CI.
- Seed scripts provision test scrambles that power end-to-end QA flows.
