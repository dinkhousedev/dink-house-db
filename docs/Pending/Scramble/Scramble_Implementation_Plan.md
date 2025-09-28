# Pickleball Scramble Implementation Plan

## Executive Summary

This document outlines the complete technical implementation plan for adding scramble functionality to the Dink House pickleball management system. The system currently has event booking and registration capabilities but lacks the specific features needed to run pickleball scrambles with automated pairing, round management, and live scoring.

## Detailed Planning Docs
- [Scramble Database & Migration Plan](Scramble_database_plan.md)
- [Scramble Backend Services Plan](Scramble_backend_services.md)
- [Scramble Admin & Frontend Experience Plan](Scramble_admin_and_frontend.md)
- [Scramble Realtime & Notification Plan](Scramble_realtime_and_notifications.md)
- [Scramble Testing, QA, & Rollout Plan](Scramble_testing_and_rollout.md)

## Current State Analysis

### What Exists
- **Events System**: Complete event creation, scheduling, and management
- **Registration System**: Player registration with payment processing
- **Court Management**: Court scheduling and availability tracking
- **Event Types**: Scramble defined as `event_scramble` type
- **DUPR Integration**: Support for skill-based events
- **Admin Dashboard**: Basic event management interface

### What's Missing
- Match and round management within scrambles
- Player pairing algorithms
- Live scoring system
- Real-time updates and notifications
- Scramble-specific UI components
- Post-event analytics

## Phase 1: Database Schema Extension

### 1.1 Core Scramble Tables

Create new schema module: `/sql/modules/24-scramble-system.sql`

```sql
-- Scramble Configuration (extends events)
CREATE TABLE events.scrambles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL REFERENCES events.events(id) ON DELETE CASCADE,
    format VARCHAR(50) NOT NULL DEFAULT 'round_robin', -- round_robin, swiss, elimination
    scoring_format VARCHAR(50) DEFAULT 'rally_scoring_11', -- rally_scoring_11, rally_scoring_15, traditional
    rounds_planned INTEGER DEFAULT 4,
    minutes_per_round INTEGER DEFAULT 20,
    pairing_method VARCHAR(50) DEFAULT 'balanced', -- balanced, random, king_of_court
    allow_repeat_partners BOOLEAN DEFAULT false,
    min_games_between_repeat INTEGER DEFAULT 3,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- Rounds within a scramble
CREATE TABLE events.scramble_rounds (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    scramble_id UUID NOT NULL REFERENCES events.scrambles(id) ON DELETE CASCADE,
    round_number INTEGER NOT NULL,
    status VARCHAR(30) DEFAULT 'pending', -- pending, active, completed
    start_time TIMESTAMPTZ,
    end_time TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(scramble_id, round_number)
);

-- Individual matches
CREATE TABLE events.matches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    round_id UUID NOT NULL REFERENCES events.scramble_rounds(id) ON DELETE CASCADE,
    court_id UUID REFERENCES events.courts(id),
    match_number INTEGER NOT NULL,
    status VARCHAR(30) DEFAULT 'pending', -- pending, in_progress, completed, cancelled
    start_time TIMESTAMPTZ,
    end_time TIMESTAMPTZ,
    team1_score INTEGER,
    team2_score INTEGER,
    winner_team INTEGER, -- 1 or 2
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- Players in matches
CREATE TABLE events.match_players (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    match_id UUID NOT NULL REFERENCES events.matches(id) ON DELETE CASCADE,
    player_id UUID NOT NULL REFERENCES app_auth.players(id),
    team_number INTEGER NOT NULL CHECK (team_number IN (1, 2)),
    position INTEGER NOT NULL CHECK (position IN (1, 2)), -- 1 or 2 for doubles
    points_scored INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(match_id, player_id),
    UNIQUE(match_id, team_number, position)
);

-- Track partnerships to avoid repeats
CREATE TABLE events.player_partnerships (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    scramble_id UUID NOT NULL REFERENCES events.scrambles(id) ON DELETE CASCADE,
    player1_id UUID NOT NULL REFERENCES app_auth.players(id),
    player2_id UUID NOT NULL REFERENCES app_auth.players(id),
    round_number INTEGER NOT NULL,
    match_id UUID REFERENCES events.matches(id),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    CHECK (player1_id < player2_id), -- Ensure consistent ordering
    UNIQUE(scramble_id, player1_id, player2_id, round_number)
);

-- Live standings
CREATE TABLE events.scramble_standings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    scramble_id UUID NOT NULL REFERENCES events.scrambles(id) ON DELETE CASCADE,
    player_id UUID NOT NULL REFERENCES app_auth.players(id),
    games_played INTEGER DEFAULT 0,
    games_won INTEGER DEFAULT 0,
    points_for INTEGER DEFAULT 0,
    points_against INTEGER DEFAULT 0,
    point_differential INTEGER GENERATED ALWAYS AS (points_for - points_against) STORED,
    ranking INTEGER,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(scramble_id, player_id)
);
```

### 1.2 Supporting Tables

```sql
-- Check-in tracking
CREATE TABLE events.player_checkins (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL REFERENCES events.events(id) ON DELETE CASCADE,
    player_id UUID NOT NULL REFERENCES app_auth.players(id),
    checkin_time TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    checkin_method VARCHAR(30) DEFAULT 'staff', -- staff, self, qr_code
    checked_in_by UUID REFERENCES app_auth.admin_users(id),
    UNIQUE(event_id, player_id)
);

-- Court assignments for current round
CREATE TABLE events.court_assignments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    round_id UUID NOT NULL REFERENCES events.scramble_rounds(id) ON DELETE CASCADE,
    court_id UUID NOT NULL REFERENCES events.courts(id),
    match_id UUID NOT NULL REFERENCES events.matches(id),
    display_order INTEGER,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(round_id, court_id),
    UNIQUE(match_id)
);

-- Notification queue
CREATE TABLE events.scramble_notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    scramble_id UUID NOT NULL REFERENCES events.scrambles(id) ON DELETE CASCADE,
    player_id UUID REFERENCES app_auth.players(id),
    notification_type VARCHAR(50) NOT NULL, -- round_start, court_assignment, results
    title VARCHAR(200) NOT NULL,
    message TEXT NOT NULL,
    metadata JSONB DEFAULT '{}',
    sent_at TIMESTAMPTZ,
    delivered_at TIMESTAMPTZ,
    read_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);
```

## Phase 2: Pairing Algorithm Implementation

### 2.1 Core Pairing Engine

Location: `/dink-house-admin/lib/scramble/pairingEngine.ts`

```typescript
interface Player {
  id: string;
  name: string;
  rating?: number;
  gamesPlayed: number;
  gamesWon: number;
  partners: Set<string>;
  opponents: Set<string>;
}

interface Pairing {
  court: number;
  team1: [Player, Player];
  team2: [Player, Player];
  skillBalance: number;
}

class PairingEngine {
  constructor(
    private players: Player[],
    private constraints: PairingConstraints
  ) {}

  generatePairings(roundNumber: number): Pairing[] {
    // 1. Handle bye if odd number
    const activePlayers = this.handleBye();

    // 2. Sort by games won for Swiss pairing
    const sorted = this.sortByPerformance(activePlayers);

    // 3. Create teams avoiding repeat partners
    const teams = this.createTeams(sorted, roundNumber);

    // 4. Match teams by skill level
    const matches = this.matchTeams(teams);

    // 5. Assign to courts
    return this.assignCourts(matches);
  }

  private createTeams(players: Player[], round: number): Team[] {
    const teams: Team[] = [];
    const used = new Set<string>();

    for (const player of players) {
      if (used.has(player.id)) continue;

      // Find best partner (haven't played with recently)
      const partner = this.findBestPartner(player, players, used, round);
      if (partner) {
        teams.push({ players: [player, partner] });
        used.add(player.id);
        used.add(partner.id);
      }
    }

    return teams;
  }

  private findBestPartner(
    player: Player,
    pool: Player[],
    used: Set<string>,
    round: number
  ): Player | null {
    // Score potential partners
    const candidates = pool
      .filter(p =>
        p.id !== player.id &&
        !used.has(p.id) &&
        !this.recentlyPartnered(player, p, round)
      )
      .map(p => ({
        player: p,
        score: this.calculatePartnerScore(player, p, round)
      }))
      .sort((a, b) => b.score - a.score);

    return candidates[0]?.player || null;
  }

  private calculatePartnerScore(p1: Player, p2: Player, round: number): number {
    let score = 100;

    // Penalize if played together recently
    const roundsApart = round - this.lastPlayedTogether(p1, p2);
    if (roundsApart < this.constraints.minRoundsBetweenPartners) {
      score -= (50 / roundsApart);
    }

    // Bonus for similar skill level
    if (p1.rating && p2.rating) {
      const diff = Math.abs(p1.rating - p2.rating);
      score += Math.max(0, 20 - diff * 5);
    }

    // Small randomization to prevent predictability
    score += Math.random() * 10;

    return score;
  }
}
```

### 2.2 Pairing Constraints

Location: `/dink-house-admin/lib/scramble/pairingConstraints.ts`

```typescript
interface PairingConstraints {
  minRoundsBetweenPartners: number;
  maxSkillDifference?: number;
  balanceGamesPlayed: boolean;
  courtPreferences?: Map<string, number[]>;
  avoidPairings?: Set<string>; // "player1_id:player2_id"
}

class ConstraintValidator {
  validate(pairing: Pairing, constraints: PairingConstraints): ValidationResult {
    const errors: string[] = [];
    const warnings: string[] = [];

    // Check partner history
    if (this.hasRecentPartnership(pairing, constraints)) {
      errors.push('Players recently partnered');
    }

    // Check skill balance
    const balance = this.calculateSkillBalance(pairing);
    if (Math.abs(balance) > (constraints.maxSkillDifference || 2)) {
      warnings.push('Teams may be unbalanced');
    }

    return { valid: errors.length === 0, errors, warnings };
  }
}
```

## Phase 3: Admin Dashboard Components

### 3.1 Scramble Control Center

Location: `/dink-house-admin/app/dashboard/scrambles/page.tsx`

```typescript
export default function ScrambleControlCenter() {
  return (
    <div className="flex gap-6 h-screen">
      {/* Main Control Panel */}
      <div className="flex-1 flex flex-col gap-4">
        <ScrambleHeader />
        <RoundControls />
        <PlayerGrid />
        <PairingPreview />
      </div>

      {/* Live Sidebar */}
      <div className="w-96 flex flex-col gap-4">
        <LiveLeaderboard />
        <CourtStatus />
        <QuickActions />
      </div>
    </div>
  );
}
```

### 3.2 Live Scoring Interface

Location: `/dink-house-admin/components/scramble/scoring/ScoringPanel.tsx`

```typescript
interface ScoringPanelProps {
  match: Match;
  onScoreUpdate: (matchId: string, scores: Scores) => void;
}

export function ScoringPanel({ match, onScoreUpdate }: ScoringPanelProps) {
  const [team1Score, setTeam1Score] = useState(match.team1_score || 0);
  const [team2Score, setTeam2Score] = useState(match.team2_score || 0);

  // Optimistic update with debounced server sync
  const updateScore = useDebouncedCallback(
    (team: 1 | 2, delta: number) => {
      if (team === 1) {
        setTeam1Score(prev => Math.max(0, prev + delta));
      } else {
        setTeam2Score(prev => Math.max(0, prev + delta));
      }

      onScoreUpdate(match.id, { team1Score, team2Score });
    },
    500
  );

  return (
    <Card className="border-2 border-dink-lime">
      <CardHeader>
        <div className="flex justify-between">
          <span>Court {match.court_number}</span>
          <MatchTimer startTime={match.start_time} />
        </div>
      </CardHeader>
      <CardBody>
        <div className="grid grid-cols-2 gap-8">
          {/* Team 1 */}
          <TeamScore
            team={match.team1}
            score={team1Score}
            onIncrement={() => updateScore(1, 1)}
            onDecrement={() => updateScore(1, -1)}
          />

          {/* Team 2 */}
          <TeamScore
            team={match.team2}
            score={team2Score}
            onIncrement={() => updateScore(2, 1)}
            onDecrement={() => updateScore(2, -1)}
          />
        </div>

        {/* Quick Score Buttons */}
        <div className="flex gap-2 mt-4">
          <Button size="sm" onClick={() => finishMatch(11, 9)}>11-9</Button>
          <Button size="sm" onClick={() => finishMatch(11, 7)}>11-7</Button>
          <Button size="sm" onClick={() => finishMatch(11, 5)}>11-5</Button>
          <Button size="sm" onClick={() => finishMatch(15, 13)}>15-13</Button>
        </div>
      </CardBody>
    </Card>
  );
}
```

## Phase 4: Real-time Features

### 4.1 Supabase Realtime Configuration

Location: `/dink-house-admin/lib/realtime/scrambleChannels.ts`

```typescript
import { createClient } from '@supabase/supabase-js';

export class ScrambleRealtimeManager {
  private supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  private channels = new Map<string, RealtimeChannel>();

  subscribeToScramble(scrambleId: string) {
    const channel = this.supabase
      .channel(`scramble:${scrambleId}`)
      .on('broadcast', { event: 'score_update' }, (payload) => {
        this.handleScoreUpdate(payload);
      })
      .on('broadcast', { event: 'round_change' }, (payload) => {
        this.handleRoundChange(payload);
      })
      .on('broadcast', { event: 'pairing_ready' }, (payload) => {
        this.handlePairingReady(payload);
      })
      .on('presence', { event: 'sync' }, () => {
        this.handlePresenceSync();
      })
      .subscribe();

    this.channels.set(scrambleId, channel);
    return channel;
  }

  broadcastScoreUpdate(scrambleId: string, matchId: string, scores: Scores) {
    const channel = this.channels.get(scrambleId);
    if (channel) {
      channel.send({
        type: 'broadcast',
        event: 'score_update',
        payload: { matchId, scores, timestamp: Date.now() }
      });
    }
  }

  trackPlayerPresence(scrambleId: string, playerId: string) {
    const channel = this.channels.get(scrambleId);
    if (channel) {
      channel.track({
        player_id: playerId,
        online_at: new Date().toISOString(),
      });
    }
  }
}
```

### 4.2 Live Components

Location: `/dink-house-admin/components/scramble/live/`

```typescript
// LiveLeaderboard.tsx
export function LiveLeaderboard({ scrambleId }: { scrambleId: string }) {
  const [standings, setStandings] = useState<Standing[]>([]);

  useEffect(() => {
    const manager = new ScrambleRealtimeManager();
    const channel = manager.subscribeToScramble(scrambleId);

    // Listen for updates
    channel.on('broadcast', { event: 'standings_update' }, (payload) => {
      setStandings(payload.standings);
    });

    return () => {
      channel.unsubscribe();
    };
  }, [scrambleId]);

  return (
    <Table>
      <TableHeader>
        <TableColumn>Rank</TableColumn>
        <TableColumn>Player</TableColumn>
        <TableColumn>W-L</TableColumn>
        <TableColumn>+/-</TableColumn>
      </TableHeader>
      <TableBody>
        {standings.map((player, index) => (
          <TableRow key={player.id}>
            <TableCell>{index + 1}</TableCell>
            <TableCell>{player.name}</TableCell>
            <TableCell>{player.wins}-{player.losses}</TableCell>
            <TableCell>{player.pointDiff > 0 ? '+' : ''}{player.pointDiff}</TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}

// LiveCourtStatus.tsx
export function LiveCourtStatus({ courts }: { courts: Court[] }) {
  const [matches, setMatches] = useState<Map<string, Match>>();

  return (
    <div className="grid grid-cols-2 gap-4">
      {courts.map(court => {
        const match = matches?.get(court.id);
        return (
          <CourtCard
            key={court.id}
            court={court}
            match={match}
            status={match ? 'active' : 'available'}
          />
        );
      })}
    </div>
  );
}
```

## Phase 5: API Endpoints

### 5.1 Scramble Management Routes

Location: `/dink-house-db/api/routes/scrambles.js`

```javascript
const express = require('express');
const router = express.Router();
const { supabase } = require('../lib/supabase');

// Start a scramble
router.post('/:id/start', async (req, res) => {
  const { id } = req.params;

  try {
    // 1. Verify all players checked in
    const { data: registrations } = await supabase
      .from('event_registrations')
      .select('*, player_checkins(*)')
      .eq('event_id', id)
      .eq('status', 'registered');

    const notCheckedIn = registrations.filter(r => !r.player_checkins);
    if (notCheckedIn.length > 0) {
      return res.status(400).json({
        error: `${notCheckedIn.length} players not checked in`
      });
    }

    // 2. Create scramble record
    const { data: scramble } = await supabase
      .from('scrambles')
      .insert({ event_id: id, ...req.body })
      .select()
      .single();

    // 3. Initialize first round
    const { data: round } = await supabase
      .from('scramble_rounds')
      .insert({
        scramble_id: scramble.id,
        round_number: 1,
        status: 'pending'
      })
      .select()
      .single();

    // 4. Generate pairings
    const pairings = await generatePairings(scramble.id, round.id, registrations);

    res.json({ scramble, round, pairings });
  } catch (error) {
    console.error('Error starting scramble:', error);
    res.status(500).json({ error: 'Failed to start scramble' });
  }
});

// Submit match scores
router.post('/matches/:matchId/scores', async (req, res) => {
  const { matchId } = req.params;
  const { team1Score, team2Score } = req.body;

  try {
    // Update match
    const { data: match } = await supabase
      .from('matches')
      .update({
        team1_score: team1Score,
        team2_score: team2Score,
        winner_team: team1Score > team2Score ? 1 : 2,
        status: 'completed',
        end_time: new Date()
      })
      .eq('id', matchId)
      .select()
      .single();

    // Update standings
    await updateStandings(match);

    // Broadcast update
    await broadcastScoreUpdate(match);

    res.json({ match });
  } catch (error) {
    console.error('Error updating scores:', error);
    res.status(500).json({ error: 'Failed to update scores' });
  }
});

// Get live leaderboard
router.get('/:id/leaderboard', async (req, res) => {
  const { id } = req.params;

  try {
    const { data: standings } = await supabase
      .from('scramble_standings')
      .select('*, players(*)')
      .eq('scramble_id', id)
      .order('games_won', { ascending: false })
      .order('point_differential', { ascending: false });

    res.json({ standings });
  } catch (error) {
    console.error('Error fetching leaderboard:', error);
    res.status(500).json({ error: 'Failed to fetch leaderboard' });
  }
});
```

### 5.2 Helper Functions

Location: `/dink-house-db/api/lib/scrambleHelpers.js`

```javascript
async function generatePairings(scrambleId, roundId, players) {
  // Get partnership history
  const { data: partnerships } = await supabase
    .from('player_partnerships')
    .select('*')
    .eq('scramble_id', scrambleId);

  // Run pairing algorithm
  const engine = new PairingEngine(players, {
    minRoundsBetweenPartners: 3,
    balanceGamesPlayed: true
  });

  const pairings = engine.generatePairings(roundNumber);

  // Save to database
  for (const pairing of pairings) {
    const { data: match } = await supabase
      .from('matches')
      .insert({
        round_id: roundId,
        court_id: pairing.courtId,
        match_number: pairing.matchNumber,
        status: 'pending'
      })
      .select()
      .single();

    // Add players to match
    for (const [team, players] of pairing.teams.entries()) {
      for (const [position, player] of players.entries()) {
        await supabase
          .from('match_players')
          .insert({
            match_id: match.id,
            player_id: player.id,
            team_number: team + 1,
            position: position + 1
          });
      }
    }
  }

  return pairings;
}

async function updateStandings(match) {
  // Get match players
  const { data: matchPlayers } = await supabase
    .from('match_players')
    .select('*')
    .eq('match_id', match.id);

  // Update each player's standings
  for (const player of matchPlayers) {
    const won =
      (player.team_number === 1 && match.team1_score > match.team2_score) ||
      (player.team_number === 2 && match.team2_score > match.team1_score);

    const pointsFor = player.team_number === 1 ? match.team1_score : match.team2_score;
    const pointsAgainst = player.team_number === 1 ? match.team2_score : match.team1_score;

    await supabase.rpc('update_player_standings', {
      p_scramble_id: match.scramble_id,
      p_player_id: player.player_id,
      p_games_played: 1,
      p_games_won: won ? 1 : 0,
      p_points_for: pointsFor,
      p_points_against: pointsAgainst
    });
  }
}
```

## Phase 6: Player-Facing Features

### 6.1 Check-in Flow

Location: `/dink-house-admin/app/player/checkin/page.tsx`

```typescript
export default function PlayerCheckIn() {
  const [checkInCode, setCheckInCode] = useState('');
  const [player, setPlayer] = useState<Player | null>(null);

  const handleCheckIn = async () => {
    const response = await fetch('/api/player/checkin', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ code: checkInCode })
    });

    if (response.ok) {
      const data = await response.json();
      setPlayer(data.player);

      // Subscribe to updates
      subscribeToPlayerUpdates(data.player.id, data.scrambleId);
    }
  };

  return (
    <div className="flex flex-col items-center justify-center min-h-screen">
      {!player ? (
        <CheckInForm
          code={checkInCode}
          onCodeChange={setCheckInCode}
          onSubmit={handleCheckIn}
        />
      ) : (
        <PlayerDashboard player={player} />
      )}
    </div>
  );
}
```

### 6.2 Player Dashboard

Location: `/dink-house-admin/components/player/PlayerDashboard.tsx`

```typescript
export function PlayerDashboard({ player, scrambleId }: Props) {
  const [nextMatch, setNextMatch] = useState<Match | null>(null);
  const [standing, setStanding] = useState<Standing | null>(null);

  useEffect(() => {
    const channel = supabase
      .channel(`player:${player.id}`)
      .on('broadcast', { event: 'court_assignment' }, (payload) => {
        setNextMatch(payload.match);
        showNotification('Court Assignment', `Report to Court ${payload.court}`);
      })
      .on('broadcast', { event: 'standings_update' }, (payload) => {
        setStanding(payload.standing);
      })
      .subscribe();

    return () => {
      channel.unsubscribe();
    };
  }, [player.id]);

  return (
    <div className="p-6 max-w-md mx-auto">
      <Card>
        <CardHeader>
          <h2 className="text-2xl font-bold">Welcome, {player.name}!</h2>
        </CardHeader>
        <CardBody className="space-y-4">
          {nextMatch ? (
            <NextMatchCard match={nextMatch} />
          ) : (
            <WaitingCard message="Waiting for next round..." />
          )}

          <StandingCard standing={standing} />

          <MatchHistory playerId={player.id} scrambleId={scrambleId} />
        </CardBody>
      </Card>
    </div>
  );
}
```

## Phase 7: Notification System

### 7.1 Push Notification Service

Location: `/dink-house-admin/lib/notifications/pushService.ts`

```typescript
import * as webpush from 'web-push';

export class PushNotificationService {
  constructor() {
    webpush.setVapidDetails(
      'mailto:admin@dinkhouse.com',
      process.env.VAPID_PUBLIC_KEY!,
      process.env.VAPID_PRIVATE_KEY!
    );
  }

  async sendCourtAssignment(player: Player, court: number, opponent: string) {
    const subscription = await this.getPlayerSubscription(player.id);

    if (subscription) {
      const payload = {
        title: 'Court Assignment',
        body: `Report to Court ${court} - Playing against ${opponent}`,
        icon: '/icon-192x192.png',
        badge: '/badge-72x72.png',
        data: {
          type: 'court_assignment',
          court,
          url: `/player/match/${court}`
        }
      };

      await webpush.sendNotification(subscription, JSON.stringify(payload));
    }
  }

  async sendRoundStarting(players: Player[], roundNumber: number, delay: number) {
    const payload = {
      title: `Round ${roundNumber} Starting`,
      body: `Round starts in ${delay} minutes. Check your court assignment!`,
      icon: '/icon-192x192.png',
    };

    const notifications = players.map(player =>
      this.sendToPlayer(player.id, payload)
    );

    await Promise.all(notifications);
  }
}
```

### 7.2 In-App Notifications

Location: `/dink-house-admin/components/notifications/NotificationProvider.tsx`

```typescript
export function NotificationProvider({ children }: { children: ReactNode }) {
  const [notifications, setNotifications] = useState<Notification[]>([]);

  const showNotification = useCallback((notification: Notification) => {
    const id = crypto.randomUUID();
    const newNotification = { ...notification, id };

    setNotifications(prev => [...prev, newNotification]);

    // Auto-dismiss after 5 seconds
    setTimeout(() => {
      setNotifications(prev => prev.filter(n => n.id !== id));
    }, 5000);
  }, []);

  return (
    <NotificationContext.Provider value={{ showNotification }}>
      {children}
      <NotificationContainer notifications={notifications} />
    </NotificationContext.Provider>
  );
}
```

## Phase 8: Analytics & Reporting

### 8.1 Event Analytics

Location: `/dink-house-admin/components/scramble/analytics/EventReport.tsx`

```typescript
interface EventMetrics {
  totalPlayers: number;
  totalMatches: number;
  averageMatchDuration: number;
  totalRevenue: number;
  playerRetention: number;
  courtUtilization: number;
}

export function EventReport({ scrambleId }: { scrambleId: string }) {
  const [metrics, setMetrics] = useState<EventMetrics>();
  const [playerStats, setPlayerStats] = useState<PlayerStat[]>();

  useEffect(() => {
    fetchEventMetrics(scrambleId).then(setMetrics);
    fetchPlayerStatistics(scrambleId).then(setPlayerStats);
  }, [scrambleId]);

  return (
    <div className="space-y-6">
      {/* Summary Cards */}
      <div className="grid grid-cols-4 gap-4">
        <MetricCard
          title="Total Players"
          value={metrics?.totalPlayers}
          icon="users"
        />
        <MetricCard
          title="Matches Played"
          value={metrics?.totalMatches}
          icon="trophy"
        />
        <MetricCard
          title="Revenue"
          value={`$${metrics?.totalRevenue}`}
          icon="dollar"
        />
        <MetricCard
          title="Court Usage"
          value={`${metrics?.courtUtilization}%`}
          icon="court"
        />
      </div>

      {/* Player Performance Table */}
      <Card>
        <CardHeader>
          <h3 className="text-lg font-semibold">Player Performance</h3>
        </CardHeader>
        <CardBody>
          <PlayerStatsTable stats={playerStats} />
        </CardBody>
      </Card>

      {/* Charts */}
      <div className="grid grid-cols-2 gap-4">
        <ScoreDistributionChart scrambleId={scrambleId} />
        <MatchDurationChart scrambleId={scrambleId} />
      </div>
    </div>
  );
}
```

### 8.2 Database Functions for Analytics

Location: `/dink-house-db/sql/modules/25-scramble-analytics.sql`

```sql
-- Calculate player statistics for a scramble
CREATE OR REPLACE FUNCTION events.calculate_player_stats(p_scramble_id UUID)
RETURNS TABLE (
    player_id UUID,
    player_name VARCHAR,
    matches_played INTEGER,
    matches_won INTEGER,
    win_percentage NUMERIC,
    total_points_scored INTEGER,
    total_points_against INTEGER,
    point_differential INTEGER,
    average_margin NUMERIC,
    best_partner_id UUID,
    best_partner_name VARCHAR,
    best_partner_wins INTEGER
) AS $$
BEGIN
    RETURN QUERY
    WITH player_matches AS (
        SELECT
            mp.player_id,
            m.id as match_id,
            mp.team_number,
            m.team1_score,
            m.team2_score,
            m.winner_team
        FROM events.match_players mp
        JOIN events.matches m ON mp.match_id = m.id
        JOIN events.scramble_rounds sr ON m.round_id = sr.id
        WHERE sr.scramble_id = p_scramble_id
        AND m.status = 'completed'
    ),
    player_stats AS (
        SELECT
            pm.player_id,
            COUNT(DISTINCT pm.match_id) as matches_played,
            SUM(CASE WHEN pm.team_number = pm.winner_team THEN 1 ELSE 0 END) as matches_won,
            SUM(CASE
                WHEN pm.team_number = 1 THEN pm.team1_score
                ELSE pm.team2_score
            END) as points_scored,
            SUM(CASE
                WHEN pm.team_number = 1 THEN pm.team2_score
                ELSE pm.team1_score
            END) as points_against
        FROM player_matches pm
        GROUP BY pm.player_id
    ),
    partnerships AS (
        SELECT
            mp1.player_id as player1_id,
            mp2.player_id as player2_id,
            COUNT(*) as games_together,
            SUM(CASE WHEN m.winner_team = mp1.team_number THEN 1 ELSE 0 END) as wins_together
        FROM events.match_players mp1
        JOIN events.match_players mp2 ON mp1.match_id = mp2.match_id
            AND mp1.team_number = mp2.team_number
            AND mp1.player_id < mp2.player_id
        JOIN events.matches m ON mp1.match_id = m.id
        JOIN events.scramble_rounds sr ON m.round_id = sr.id
        WHERE sr.scramble_id = p_scramble_id
        GROUP BY mp1.player_id, mp2.player_id
    )
    SELECT
        ps.player_id,
        p.name as player_name,
        ps.matches_played,
        ps.matches_won,
        ROUND((ps.matches_won::NUMERIC / NULLIF(ps.matches_played, 0)) * 100, 1) as win_percentage,
        ps.points_scored as total_points_scored,
        ps.points_against as total_points_against,
        ps.points_scored - ps.points_against as point_differential,
        ROUND((ps.points_scored - ps.points_against)::NUMERIC / NULLIF(ps.matches_played, 0), 1) as average_margin,
        bp.partner_id as best_partner_id,
        bp.partner_name as best_partner_name,
        bp.wins_together as best_partner_wins
    FROM player_stats ps
    JOIN app_auth.players p ON ps.player_id = p.id
    LEFT JOIN LATERAL (
        SELECT
            COALESCE(p1.player2_id, p2.player1_id) as partner_id,
            p_partner.name as partner_name,
            COALESCE(p1.wins_together, p2.wins_together) as wins_together
        FROM partnerships p1
        FULL JOIN partnerships p2 ON p2.player2_id = ps.player_id
        LEFT JOIN app_auth.players p_partner ON p_partner.id = COALESCE(p1.player2_id, p2.player1_id)
        WHERE p1.player1_id = ps.player_id OR p2.player2_id = ps.player_id
        ORDER BY COALESCE(p1.wins_together, p2.wins_together) DESC
        LIMIT 1
    ) bp ON true
    ORDER BY ps.matches_won DESC, point_differential DESC;
END;
$$ LANGUAGE plpgsql;

-- Event summary metrics
CREATE OR REPLACE FUNCTION events.get_scramble_metrics(p_scramble_id UUID)
RETURNS JSONB AS $$
DECLARE
    result JSONB;
BEGIN
    SELECT jsonb_build_object(
        'total_players', COUNT(DISTINCT er.user_id),
        'total_matches', COUNT(DISTINCT m.id),
        'completed_matches', COUNT(DISTINCT m.id) FILTER (WHERE m.status = 'completed'),
        'average_match_duration', AVG(EXTRACT(EPOCH FROM (m.end_time - m.start_time)) / 60),
        'total_revenue', SUM(er.amount_paid),
        'average_score_difference', AVG(ABS(m.team1_score - m.team2_score)),
        'total_points_scored', SUM(m.team1_score + m.team2_score),
        'court_utilization', (
            COUNT(DISTINCT ca.court_id)::NUMERIC /
            (SELECT COUNT(*) FROM events.courts WHERE status = 'available')
        ) * 100
    ) INTO result
    FROM events.event_registrations er
    LEFT JOIN events.scrambles s ON s.event_id = er.event_id
    LEFT JOIN events.scramble_rounds sr ON sr.scramble_id = s.id
    LEFT JOIN events.matches m ON m.round_id = sr.id
    LEFT JOIN events.court_assignments ca ON ca.match_id = m.id
    WHERE s.id = p_scramble_id;

    RETURN result;
END;
$$ LANGUAGE plpgsql;
```

## Implementation Timeline

### Week 1-2: Database Foundation
- [ ] Create scramble schema and tables
- [ ] Set up database migrations
- [ ] Create test data generators
- [ ] Implement core database functions

### Week 2-3: Pairing Algorithm
- [ ] Implement PairingEngine class
- [ ] Create constraint validators
- [ ] Build partnership tracking
- [ ] Test with various player counts

### Week 3-4: Admin Control Center
- [ ] Build scramble dashboard layout
- [ ] Implement round controls
- [ ] Create player grid view
- [ ] Add pairing preview interface

### Week 4-5: Live Scoring
- [ ] Build scoring components
- [ ] Implement optimistic updates
- [ ] Create court status displays
- [ ] Add match timer functionality

### Week 5-6: Real-time Features
- [ ] Set up Supabase channels
- [ ] Implement live leaderboard
- [ ] Create presence tracking
- [ ] Build notification system

### Week 6-7: Player Experience
- [ ] Design check-in flow
- [ ] Build player dashboard
- [ ] Create court assignment views
- [ ] Implement match history

### Week 7-8: Testing & Polish
- [ ] End-to-end testing
- [ ] Performance optimization
- [ ] Error handling
- [ ] Documentation

## Technical Decisions

### Architecture Choices
1. **Supabase Realtime** for WebSocket communications
2. **Optimistic UI updates** for responsive scoring
3. **PostgreSQL functions** for complex calculations
4. **TypeScript** for type safety across the stack

### Performance Considerations
1. **Cache pairing calculations** between rounds
2. **Batch database updates** for standings
3. **Use indexes** on frequently queried columns
4. **Implement connection pooling** for database

### Security Measures
1. **Row-level security** on all tables
2. **API rate limiting** on score submissions
3. **Input validation** on all endpoints
4. **Audit logging** for admin actions

## Testing Strategy

### Unit Tests
- Pairing algorithm edge cases
- Score calculation accuracy
- Constraint validation logic
- Database function outputs

### Integration Tests
- API endpoint responses
- Real-time message delivery
- Database transaction integrity
- Payment processing flow

### End-to-End Tests
- Complete scramble workflow
- Player check-in process
- Live scoring updates
- Result distribution

## Monitoring & Analytics

### Key Metrics
- Average pairing generation time
- Real-time message latency
- Database query performance
- User engagement rates

### Error Tracking
- Sentry for application errors
- Database query logging
- API request/response logging
- User action tracking

## Future Enhancements

### Phase 2 Features
- Mobile native app
- Advanced analytics dashboard
- AI-powered pairing suggestions
- Video replay integration
- Tournament bracket visualization
- Social features (chat, photos)
- Equipment checkout system
- Automated DUPR sync

### Scalability Considerations
- Microservice architecture
- Database sharding
- CDN for static assets
- Queue-based processing
- Horizontal scaling ready

## Conclusion

This implementation plan provides a comprehensive roadmap for building a full-featured pickleball scramble management system. The phased approach allows for iterative development while maintaining system stability. The architecture is designed to scale with growing user demands while providing real-time responsiveness essential for live event management.