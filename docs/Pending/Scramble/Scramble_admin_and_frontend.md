# Scramble Admin & Frontend Experience Plan

## Admin Dashboard Enhancements

### Layout & Navigation
- Add "Scramble Control" section within existing event management area.
- Tabs: `Overview`, `Rounds`, `Players`, `Courts`, `Leaderboard`, `Settings`.
- Persist state in URL query params to support deep links for staff.

### Key Components
- **Round Manager Panel**
  - Display current round status, timer, and controls (start, pause, complete, regenerate).
  - Show readiness checklist (players checked in, courts available, notifications sent).
- **Match Grid**
  - Responsive table with match cards grouped by court.
  - Inline score entry with validation (min/max based on scoring format).
- **Player Roster**
  - Filterable list by status (checked-in, waitlist, no-show).
  - Actions: mark late, substitute, assign bye.
- **Leaderboard Widget**
  - Real-time standings with highlight for tie-break explanations.
  - Export to CSV for post-event reporting.

### Administrative Workflows
1. **Pre-Event Setup**: Configure scramble options, confirm court inventory, import waitlist.
2. **Round Execution**: Start timer, monitor match progress, adjust pairings when players drop.
3. **Exception Handling**: Manual court reassignment, score correction with audit trail.
4. **Post-Event Wrap-up**: Publish results, trigger email summary, archive event assets.

## Player-Facing Experience

### Mobile Web App
- Single entry point: `events/:eventId/scramble` with dynamic content based on auth state.
- Responsive design optimized for quick scans and large fonts for court assignments.

### Core Screens
- **Event Lobby**
  - Countdown to start, check-in button, event announcements.
- **My Matches**
  - Current assignment highlighted, upcoming match preview, historical results.
- **Live Leaderboard**
  - Compact card view with rank, wins, point differential.
- **Notifications Center**
  - In-app feed mirroring push/email alerts, includes "I'm on my way" quick response.

### Interaction Details
- Check-in uses location + time to prevent early check-ins (optional feature toggle).
- Provide accessibility features: high-contrast mode, screen reader landmarks, clear focus states.
- Offline fallback caches latest assignments via service worker; warns users when data is stale.

## Shared UI Components
- Build reusable Vue/React (whichever stack is in repo) components in `api/lib/ui/scramble/`:
  - `RoundTimer` with pause/resume.
  - `CourtAssignmentCard` with QR code for quick scanning at courts.
  - `ScoreInput` with validation and quick presets.
  - `LeaderboardTable` that supports virtualization for large events.

## Content Management
- Support dynamic announcements managed by staff, stored in `events.scramble_notifications` and displayed across admin/player views.
- Provide Markdown support for rich text (links, emphasis) with sanitized rendering on frontend.

## Analytics & Feedback
- Track front-end events (check-in clicks, score entry, leaderboard views) via existing analytics client.
- Post-event survey embedded in app; responses stored in `events.scramble_feedback` table (future module).

## Acceptance Criteria
- Admin dashboard usable on tablet devices (min width 768px) with touch-friendly controls.
- Player UI loads within 2 seconds on 4G network and passes Lighthouse PWA baseline.
- Accessibility checklist: WCAG AA contrast, keyboard navigable, ARIA labels on timers and score controls.
- Usability testing with staff produces <3 critical issues before production rollout.
