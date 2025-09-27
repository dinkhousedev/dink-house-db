# Authentication Split Migration Plan

## 1. Current State Summary
- Single table `app_auth.users` stores auth credentials, staff profile fields, and role flags for every account.
- Downstream schemas (`content`, `contact`, `events`, `launch`, `system`, etc.) reference `app_auth.users.id` for ownership and auditing (see `sql/modules/*` definitions).
- Session infrastructure (`app_auth.sessions`, `app_auth.refresh_tokens`, API keys, activity logging, RLS policies, RPC functions) depend directly on `app_auth.users`.
- Supabase JWT claims rely on the `role` string sourced from `app_auth.users.role`.

## 2. Target Architecture Overview
```
app_auth.user_accounts      -- canonical credentials & status per login identity
app_auth.admin_users        -- internal/staff profile + admin role tier
app_auth.players            -- member profile, club specific data
app_auth.guest_users        -- lightweight temp profiles for drop-in guests
app_auth.user_type enum     -- constrains identity types ('admin', 'player', 'guest')
```
- `user_accounts` remains the single entry point for login/credentials and is referenced by sessions, refresh tokens, and API keys.
- `admin_users` and `players` keep 1:1 rows with a `account_id` FK into `user_accounts`; profile-specific data lives here.
- Postgres enums replace free-form role columns where practical to harden data integrity.
- Legacy callers that still expect `app_auth.users` will be migrated to the new tables; a compatibility view can be created temporarily if absolutely required.

## 3. Detailed Schema Design

### 3.1 Shared Types
```sql
CREATE TYPE app_auth.user_type AS ENUM ('admin', 'player', 'guest');
CREATE TYPE app_auth.admin_role AS ENUM ('super_admin', 'admin', 'manager', 'coach', 'editor', 'viewer');
CREATE TYPE app_auth.membership_level AS ENUM ('guest', 'basic', 'premium', 'vip');
CREATE TYPE app_auth.skill_level AS ENUM ('beginner', 'intermediate', 'advanced', 'pro');
```

### 3.2 `app_auth.user_accounts`
- Columns: `id UUID PK DEFAULT uuid_generate_v4()`, `email CITEXT UNIQUE NOT NULL`, `password_hash TEXT NOT NULL`, `user_type app_auth.user_type NOT NULL`, `is_active BOOLEAN DEFAULT true`, `is_verified BOOLEAN DEFAULT false`, `last_login TIMESTAMPTZ`, `failed_login_attempts INT DEFAULT 0`, `locked_until TIMESTAMPTZ`, `temporary_expires_at TIMESTAMPTZ`, `metadata JSONB DEFAULT '{}'::jsonb`, `created_at TIMESTAMPTZ DEFAULT now()`, `updated_at TIMESTAMPTZ DEFAULT now()`.
- Constraints/Indexes: unique index on `email`, partial unique on `(user_type, metadata->>'external_id')` if external ids exist, trigger to auto-update `updated_at`, partial index on `(temporary_expires_at)` for batch cleanup of guest accounts.
- Application invariant: `temporary_expires_at IS NOT NULL` only when `user_type = 'guest'`; conversion to full player clears the field and updates `user_type`.

### 3.3 `app_auth.admin_users`
- Columns: `id UUID PRIMARY KEY DEFAULT uuid_generate_v4()`, `account_id UUID NOT NULL UNIQUE REFERENCES app_auth.user_accounts(id) ON DELETE CASCADE`, `username CITEXT UNIQUE NOT NULL`, `first_name TEXT NOT NULL`, `last_name TEXT NOT NULL`, `role app_auth.admin_role NOT NULL DEFAULT 'viewer'`, `department TEXT`, `phone TEXT`, `created_at TIMESTAMPTZ DEFAULT now()`, `updated_at TIMESTAMPTZ DEFAULT now()`.
- Optional JSONB for additional admin preferences.
- Index on `role`, on `(last_name, first_name)` for lookup.

### 3.4 `app_auth.players`
- Columns: `id UUID PRIMARY KEY DEFAULT uuid_generate_v4()`, `account_id UUID NOT NULL UNIQUE REFERENCES app_auth.user_accounts(id) ON DELETE CASCADE`, `first_name TEXT NOT NULL`, `last_name TEXT NOT NULL`, `display_name TEXT`, `phone TEXT`, `date_of_birth DATE`, `membership_level app_auth.membership_level DEFAULT 'guest'`, `membership_started_on DATE`, `membership_expires_on DATE`, `skill_level app_auth.skill_level`, `club_id UUID` (if multi-club future), `created_at TIMESTAMPTZ DEFAULT now()`, `updated_at TIMESTAMPTZ DEFAULT now()`, `profile JSONB DEFAULT '{}'::jsonb`.
- Index on `(membership_level)`, `(skill_level)`, `(last_name, first_name)`.

### 3.5 `app_auth.guest_users`
- Represents lightweight, limited-duration access for drop-in guests who need to check in and pay without completing full onboarding.
- Columns: `id UUID PRIMARY KEY DEFAULT uuid_generate_v4()`, `account_id UUID NOT NULL UNIQUE REFERENCES app_auth.user_accounts(id) ON DELETE CASCADE`, `display_name TEXT`, `email CITEXT`, `phone TEXT`, `invited_by_admin UUID REFERENCES app_auth.admin_users(id)`, `expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '48 hours')`, `converted_to_player_at TIMESTAMPTZ`, `created_at TIMESTAMPTZ DEFAULT now()`, `updated_at TIMESTAMPTZ DEFAULT now()`, `metadata JSONB DEFAULT '{}'::jsonb`.
- Constraints: `CHECK (expires_at > created_at)`, partial index on `expires_at` for cleanup, unique partial index on `email` where `converted_to_player_at IS NULL` to avoid duplicate active guests.
- Add trigger to purge/lock accounts when `expires_at` passes; conversion flow copies guest profile into `players` and updates `user_accounts.user_type` → `'player'`.

### 3.6 Session & Token Tables
- `app_auth.sessions`: add `account_id UUID REFERENCES app_auth.user_accounts(id) ON DELETE CASCADE`, `user_type app_auth.user_type NOT NULL`, `context JSONB DEFAULT '{}'::jsonb`. Keep `user_id` for transitional compatibility; eventually drop in favor of `account_id`. Enforce reduced TTL for guest sessions via check constraint or application logic (e.g., 6 hours) to limit exposure.
- `app_auth.refresh_tokens`: add `account_id UUID REFERENCES app_auth.user_accounts(id) ON DELETE CASCADE`, `user_type app_auth.user_type`.
- `app_auth.api_keys`: ensure `account_id` column referencing `user_accounts`, restrict usage to `user_type = 'admin'` via constraint or trigger.
- Update indexes to cover new columns (`idx_sessions_account_id`, `idx_sessions_user_type`, etc.).

### 3.7 Reference Tables Adjustments
- Rename `app_auth.users` → `app_auth.admin_users` so existing FK constraints retarget automatically.
- After rename, add `account_id` column described above and backfill with a migration.
- For other schemas referencing staff identities (`content.*`, `contact.*`, `system.*`, `launch.*`, `events.*`), retain FK to `app_auth.admin_users(id)`; adjust column comments to reflect staff-only usage.
- For areas that should reference players (e.g. event participants), add dedicated `player_id` columns referencing `app_auth.players(id)` while preserving admin audit columns.

## 4. Migration Strategy

### 4.1 High-Level Phases
1. **Preparation**: create new enum types, new `user_accounts` table, and placeholder `admin_users`/`players` tables. Introduce `account_id` columns on sessions/tokens/api keys with NULL defaults.
2. **Data Backfill**: populate `user_accounts` from current `app_auth.users`; populate `admin_users` using existing profile data; set `sessions.account_id` and `refresh_tokens.account_id`; ensure constraints satisfied.
3. **Cut-over**: enforce NOT NULL/UNIQUE constraints, update functions/views/RLS to use new tables, drop legacy columns that moved, and update Supabase JWT triggers to reference `user_accounts` + `admin_users`.
4. **Player & Guest Rollout**: enable public signup path writing to `players`, introduce guest invitation/checkout flow that provisions `guest_users`, expand RLS to cover both personas, and re-test.
5. **Cleanup**: remove deprecated columns (e.g., `sessions.user_id`), drop `app_auth.users` compatibility view if created, schedule guest auto-expiration jobs, and vacuum indexes.

### 4.2 Detailed Steps
- Wrap schema changes in an idempotent migration script (e.g., new SQL module or migration file) that guards with `IF NOT EXISTS` checks.
- Backfill script outline:
  ```sql
  INSERT INTO app_auth.user_accounts (id, email, password_hash, user_type, is_active, is_verified,
                                      last_login, failed_login_attempts, locked_until, created_at, updated_at)
  SELECT id, email, password_hash, 'admin', is_active, is_verified,
         last_login, failed_login_attempts, locked_until, created_at, updated_at
  FROM app_auth.users;

  UPDATE app_auth.admin_users
  SET account_id = user_accounts.id
  FROM app_auth.user_accounts
  WHERE app_auth.admin_users.id = user_accounts.id;

  UPDATE app_auth.sessions s
  SET account_id = u.id,
      user_type = 'admin'
  FROM app_auth.user_accounts u
  WHERE s.user_id = u.id;
  ```
- Perform transactional backup: snapshot `app_auth.users` before transformation, e.g., `CREATE TABLE app_auth.users_backup AS SELECT * FROM app_auth.users;` (drop once stable).
- For rollback: drop new tables, rename backup -> users.
- After verifying data, enforce `NOT NULL` on `account_id`, add foreign key constraints, and drop redundant columns (e.g., `sessions.user_id`).
- For new players, initial data import can run via dedicated script once the API endpoints exist.
- Guest provisioning: seed migration should leave `app_auth.guest_users` empty; runtime flow inserts on demand with `user_accounts.user_type = 'guest'` and `temporary_expires_at` set. Provide conversion script that promotes a guest to a player by creating a `players` row, copying metadata, clearing guest constraints, and updating references.

### 4.3 Dependency Audit Checklist
- Update every occurrence of `app_auth.users` in SQL functions/views to point to `app_auth.admin_users` or `app_auth.user_accounts` depending on intent (see references in `sql/modules/04-content.sql`, `05-contact.sql`, `06-launch.sql`, `07-system.sql`, `10-api-views.sql`, `12-api-functions.sql`, `13-realtime-config.sql`, `16-events.sql`, `18-events-rls.sql`, `19-events-functions.sql`).
- Regenerate Supabase publication definitions once tables renamed (notably `sql/modules/13-realtime-config.sql`).
- Revise RLS definitions in `sql/modules/11-rls-policies.sql` to cover new tables and to supply separate policies for admin vs player access.
- Audit any logic that assumes every authenticated UUID has full admin privileges; update to respect `user_type`, particularly when handling guest payments or invitations.

## 5. Authentication & Session Flow Updates
- Modify `api.login_safe` / `api.login` (see `sql/modules/12-api-functions.sql`) to fetch from `app_auth.user_accounts`, join to the appropriate profile table, and embed `user_type` in returned JSON + tokens.
- Add new RPC `api.player_register` mapped to `/api/auth/player/signup` and adjust `api.register_user` to become admin-only invite flow referencing `allowed_emails` (see `sql/modules/15-allowed-emails.sql`).
- Add `api.guest_check_in` flow: creates/refreshes a guest account tied to an invited session, sets short-lived session expiry, and returns payment links without exposing full portal features.
- Extend JWT generation to include `user_type`, `admin_role`, `player_metadata` as needed; ensure Supabase Auth hooks propagate the new claims.
- Update session management functions to read/write `sessions.account_id` and `sessions.user_type`, and to block cross-type session reuse.
- Revise middleware (Express, Supabase edge functions) to branch on `user_type` and route to correct dashboards.

## 6. Security & RLS Adjustments
- Enable RLS on `app_auth.user_accounts`, `app_auth.admin_users`, `app_auth.players`, and `app_auth.guest_users` with policies such as:
  - Admin accounts: self-read/update, admin-manage, service-role full access.
  - Player accounts: allow self-read/update on `players` and limited read on their own `user_accounts` row.
  - Guest accounts: allow self-read, deny update beyond payment details, enforce automatic revocation when `temporary_expires_at` lapses.
  - Sessions: ensure `user_type` column participates in policies to prevent admin tokens from introspecting player sessions and vice versa.
- Update existing policies that check `auth.jwt()->>'role'` to also validate `auth.jwt()->>'user_type'`.
- Add rate limiting and allowed-email enforcement for admin signup endpoint; maintain separate throttle buckets for player signup (application layer responsibility).

## 7. Testing Strategy
- Expand integration tests in `api/tests/auth.test.js` and `api/tests/setup.js` to cover:
  - Admin login/signup, verifying `user_type = 'admin'` claims.
  - Player signup flow, verifying `players` row creation and portal access restrictions.
  - Guest check-in flow, verifying short-lived sessions, payment access, and upgrade-to-player path.
  - Session creation per user type, including lockout/failed login behaviors.
  - RLS: ensure admin queries cannot fetch player-only data unless intended.
- Add database regression tests (SQL unit tests or plpgsql assertions) for triggers/backfill.
- Include migration smoke tests to validate that existing admin accounts remain functional after the data move.

## 8. Operational Considerations
- Seed data updates (`sql/seeds/01-users.sql`) must now populate both `user_accounts` and `admin_users`; add optional seed for demo player accounts and a time-bound guest example for QA.
- Document new architecture for developers (update `docs/API.md`, add ER diagram snippet).
- Update monitoring/analytics to distinguish between admin and player logins.
- Communicate downtime expectations: run migration during maintenance window due to session table rewrites.
- Prepare rollback script and automated backup prior to running production migration.
- Schedule background job (cron or Supabase task) that disables expired guest accounts and clears associated sessions; track metrics for guest conversions to players.

## 9. Next Actions
1. Implement preparation migration SQL module with new types/tables + backfill scaffolding.
2. Refactor authentication PL/pgSQL functions and RLS policies to use new structures.
3. Update API layer (Express/Supabase functions) to surface user type, add new signup/guest check-in endpoints, and amend tests.
4. Perform dry-run migration locally, fix issues, then schedule production deployment with backup and monitoring.
