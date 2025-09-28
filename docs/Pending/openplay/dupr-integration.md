# DUPR Integration Guide

## Overview
DUPR (Dynamic Universal Pickleball Rating) is the premier rating system for pickleball players worldwide. This guide details how the Dink House system integrates with DUPR to provide rating verification, smart event filtering, and automated match result submission.

## DUPR Rating System Basics

### Rating Scale
DUPR uses a scale from 2.0 to 6.0:
- **2.0-2.49**: Beginner (learning the game, basic rules)
- **2.5-2.99**: Advanced Beginner (consistent serves/returns)
- **3.0-3.49**: Intermediate (developing strategy)
- **3.5-3.99**: Advanced Intermediate (consistent play)
- **4.0-4.49**: Advanced (tournament competitive)
- **4.5-4.99**: Expert (highly competitive)
- **5.0-5.99**: Professional (elite amateur to pro)
- **6.0+**: World Class Professional

### Rating Calculation
DUPR ratings are calculated using:
- Match results (wins/losses)
- Score differentials
- Opponent ratings
- Recency of matches
- Match format (singles/doubles)

## Integration Architecture

### System Components
```
┌─────────────────┐     ┌──────────────┐     ┌─────────────┐
│  Dink House     │────▶│   DUPR API   │────▶│  DUPR       │
│  Application    │◀────│   Gateway    │◀────│  Database   │
└─────────────────┘     └──────────────┘     └─────────────┘
        │                                              │
        │                                              │
        ▼                                              ▼
┌─────────────────┐                          ┌─────────────┐
│  Local Player   │                          │  DUPR       │
│  Database       │                          │  Website    │
└─────────────────┘                          └─────────────┘
```

### API Authentication
```javascript
// DUPR API Configuration
const DUPR_CONFIG = {
  baseUrl: 'https://api.dupr.com/v1',
  clientId: process.env.DUPR_CLIENT_ID,
  clientSecret: process.env.DUPR_CLIENT_SECRET,
  redirectUri: process.env.DUPR_REDIRECT_URI,
  scopes: ['read:ratings', 'write:matches', 'read:players']
};

// OAuth2 Flow
async function authenticateDUPR() {
  const token = await oauth2.getAccessToken({
    client_id: DUPR_CONFIG.clientId,
    client_secret: DUPR_CONFIG.clientSecret,
    grant_type: 'client_credentials'
  });
  return token;
}
```

## Player DUPR Connection

### Initial Setup Flow
1. **Player Initiates Connection**
   ```javascript
   // Frontend: Redirect to DUPR OAuth
   window.location.href = `https://auth.dupr.com/oauth/authorize?
     client_id=${CLIENT_ID}&
     redirect_uri=${REDIRECT_URI}&
     response_type=code&
     scope=read:ratings+read:profile`;
   ```

2. **Handle OAuth Callback**
   ```javascript
   // Backend: Exchange code for token
   async function handleDUPRCallback(code) {
     const tokenResponse = await fetch('https://auth.dupr.com/oauth/token', {
       method: 'POST',
       body: JSON.stringify({
         grant_type: 'authorization_code',
         client_id: DUPR_CONFIG.clientId,
         client_secret: DUPR_CONFIG.clientSecret,
         code: code,
         redirect_uri: DUPR_CONFIG.redirectUri
       })
     });

     const { access_token, refresh_token } = await tokenResponse.json();

     // Store tokens securely
     await savePlayerTokens(playerId, access_token, refresh_token);
   }
   ```

3. **Fetch Player Rating**
   ```javascript
   async function fetchPlayerRating(playerId) {
     const token = await getPlayerToken(playerId);

     const response = await fetch('https://api.dupr.com/v1/players/me', {
       headers: {
         'Authorization': `Bearer ${token}`,
         'Content-Type': 'application/json'
       }
     });

     const playerData = await response.json();

     return {
       duprId: playerData.id,
       rating: playerData.ratings.doubles,
       singlesRating: playerData.ratings.singles,
       lastUpdated: playerData.ratings.lastCalculated,
       reliability: playerData.ratings.reliability
     };
   }
   ```

### Data Storage
```sql
-- Store DUPR connection data
ALTER TABLE app_auth.players ADD COLUMN dupr_data JSONB DEFAULT '{}'::jsonb;

-- DUPR data structure
{
  "dupr_id": "12345-67890-abcdef",
  "access_token": "encrypted_token_here",
  "refresh_token": "encrypted_refresh_token",
  "doubles_rating": 3.45,
  "singles_rating": 3.25,
  "reliability": 0.95,
  "last_sync": "2024-03-14T10:00:00Z",
  "total_matches": 127,
  "connection_status": "active"
}
```

## Smart Event Filtering

### Enhanced Filtering Logic
```javascript
class DUPREventFilter {
  /**
   * Filter events based on player's DUPR rating
   * @param {Array} events - All available events
   * @param {Number} playerRating - Player's DUPR rating
   * @param {Object} preferences - Player filter preferences
   */
  filterEvents(events, playerRating, preferences = {}) {
    return events.map(event => {
      // Skip non-DUPR events
      if (!event.requires_dupr) {
        return { ...event, visibility: 'visible', badge: null };
      }

      // Calculate buffer based on event settings
      const buffer = this.calculateBuffer(event);
      const minWithBuffer = (event.dupr_min_rating || 0) - buffer;
      const maxWithBuffer = (event.dupr_max_rating || 6) + buffer;

      // Determine visibility
      if (playerRating < minWithBuffer || playerRating > maxWithBuffer) {
        return { ...event, visibility: 'hidden', reason: 'out_of_range' };
      }

      // Add appropriate badge
      const badge = this.determineBadge(event, playerRating);

      return { ...event, visibility: 'visible', badge };
    }).filter(event => event.visibility === 'visible');
  }

  calculateBuffer(event) {
    // Buffer zones by event type
    const bufferSettings = {
      strict: 0.1,      // Tournament play
      moderate: 0.25,   // Standard open play
      lenient: 0.5,     // Social/learning events
      custom: event.custom_buffer || 0.25
    };

    return bufferSettings[event.buffer_type] || bufferSettings.moderate;
  }

  determineBadge(event, playerRating) {
    const margin = 0.15; // Badge threshold

    // Check if player is near the edge
    if (playerRating <= event.dupr_min_rating + margin) {
      return { type: 'challenging', text: 'Stretch Up', color: 'orange' };
    }

    if (playerRating >= event.dupr_max_rating - margin) {
      return { type: 'easy', text: 'Help Others', color: 'green' };
    }

    // Perfect match
    const midpoint = (event.dupr_min_rating + event.dupr_max_rating) / 2;
    if (Math.abs(playerRating - midpoint) < margin) {
      return { type: 'perfect', text: 'Perfect Match', color: 'blue' };
    }

    return null;
  }
}
```

### Visual Implementation
```typescript
// React Component Example
function EventCard({ event, playerRating }) {
  const filter = new DUPREventFilter();
  const filteredEvent = filter.filterEvents([event], playerRating)[0];

  if (!filteredEvent) return null;

  return (
    <div className="event-card">
      <h3>{event.title}</h3>
      {filteredEvent.badge && (
        <Badge color={filteredEvent.badge.color}>
          {filteredEvent.badge.text}
        </Badge>
      )}
      <div className="dupr-range">
        DUPR: {event.dupr_min_rating} - {event.dupr_max_rating}
      </div>
      <div className="player-rating">
        Your Rating: {playerRating}
      </div>
    </div>
  );
}
```

### Database Query Optimization
```sql
-- Efficient event filtering query
CREATE OR REPLACE FUNCTION get_eligible_events(
  p_player_rating NUMERIC,
  p_buffer NUMERIC DEFAULT 0.25
)
RETURNS TABLE(
  event_id UUID,
  title VARCHAR,
  event_type events.event_type,
  start_time TIMESTAMPTZ,
  dupr_min NUMERIC,
  dupr_max NUMERIC,
  match_quality VARCHAR
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    e.id,
    e.title,
    e.event_type,
    e.start_time,
    e.dupr_min_rating,
    e.dupr_max_rating,
    CASE
      WHEN p_player_rating BETWEEN
           (e.dupr_min_rating + 0.15) AND
           (e.dupr_max_rating - 0.15) THEN 'perfect'
      WHEN p_player_rating <= (e.dupr_min_rating + 0.15) THEN 'challenging'
      WHEN p_player_rating >= (e.dupr_max_rating - 0.15) THEN 'easy'
      ELSE 'good'
    END as match_quality
  FROM events.events e
  WHERE
    e.status = 'published' AND
    e.start_time > NOW() AND
    (
      e.event_type NOT IN ('dupr_open_play', 'dupr_tournament') OR
      (
        p_player_rating >= (e.dupr_min_rating - p_buffer) AND
        p_player_rating <= (e.dupr_max_rating + p_buffer)
      )
    )
  ORDER BY
    e.start_time ASC,
    match_quality DESC;
END;
$$ LANGUAGE plpgsql;
```

## Match Result Submission

### Post-Event Processing
```javascript
class DUPRMatchSubmitter {
  constructor(apiClient) {
    this.api = apiClient;
    this.batchSize = 50; // DUPR API batch limit
  }

  async submitEventResults(eventId) {
    try {
      // 1. Fetch event and match data
      const event = await getEvent(eventId);
      const matches = await getEventMatches(eventId);

      // 2. Validate all matches
      const validatedMatches = this.validateMatches(matches);

      // 3. Format for DUPR API
      const duprMatches = this.formatForDUPR(validatedMatches, event);

      // 4. Submit in batches
      const results = await this.submitBatches(duprMatches);

      // 5. Update local database
      await this.updateSubmissionStatus(eventId, results);

      return {
        success: true,
        submitted: results.successful.length,
        failed: results.failed.length,
        details: results
      };
    } catch (error) {
      console.error('DUPR submission failed:', error);
      return {
        success: false,
        error: error.message
      };
    }
  }

  validateMatches(matches) {
    return matches.filter(match => {
      // Ensure all required fields
      const hasPlayers = match.team1_players?.length === 2 &&
                        match.team2_players?.length === 2;
      const hasScores = match.team1_score !== null &&
                       match.team2_score !== null;
      const isComplete = match.status === 'completed';

      return hasPlayers && hasScores && isComplete;
    });
  }

  formatForDUPR(matches, event) {
    return matches.map(match => ({
      match_id: match.id,
      event_name: event.title,
      event_date: event.start_time,
      location: event.location || 'Dink House Facility',
      format: 'doubles',
      scoring_format: event.scoring_format || 'rally_to_11',
      team1: {
        player1_id: match.team1_players[0].dupr_id,
        player2_id: match.team1_players[1].dupr_id,
        score: match.team1_score
      },
      team2: {
        player1_id: match.team2_players[0].dupr_id,
        player2_id: match.team2_players[1].dupr_id,
        score: match.team2_score
      },
      verified: true,
      source: 'dink_house_system'
    }));
  }

  async submitBatches(matches) {
    const results = { successful: [], failed: [] };

    // Process in batches
    for (let i = 0; i < matches.length; i += this.batchSize) {
      const batch = matches.slice(i, i + this.batchSize);

      try {
        const response = await this.api.post('/matches/batch', {
          matches: batch,
          validate_only: false
        });

        results.successful.push(...response.data.successful);
        results.failed.push(...response.data.failed);
      } catch (error) {
        // Log batch failure but continue
        console.error(`Batch ${i / this.batchSize} failed:`, error);
        results.failed.push(...batch.map(m => ({
          match_id: m.match_id,
          error: error.message
        })));
      }
    }

    return results;
  }

  async updateSubmissionStatus(eventId, results) {
    // Update event status
    await db.query(
      `UPDATE events.events
       SET dupr_submission_status = $1,
           dupr_submission_time = NOW(),
           dupr_submission_results = $2
       WHERE id = $3`,
      [
        results.failed.length === 0 ? 'completed' : 'partial',
        JSON.stringify(results),
        eventId
      ]
    );

    // Update individual match records
    for (const match of results.successful) {
      await db.query(
        `UPDATE events.match_results
         SET dupr_submitted = true,
             dupr_submission_id = $1
         WHERE id = $2`,
        [match.dupr_match_id, match.match_id]
      );
    }
  }
}
```

### Automated Submission Schedule
```javascript
// Cron job for automatic DUPR submission
const cron = require('node-cron');

// Run every hour to submit completed events
cron.schedule('0 * * * *', async () => {
  console.log('Starting DUPR submission job...');

  // Find events ready for submission
  const events = await db.query(`
    SELECT id FROM events.events
    WHERE end_time < NOW() - INTERVAL '30 minutes'
      AND end_time > NOW() - INTERVAL '24 hours'
      AND event_type IN ('dupr_open_play', 'dupr_tournament')
      AND dupr_submission_status IS NULL
  `);

  const submitter = new DUPRMatchSubmitter(duprApiClient);

  for (const event of events.rows) {
    await submitter.submitEventResults(event.id);
  }
});
```

## Rating Synchronization

### Scheduled Rating Updates
```javascript
class DUPRRatingSync {
  async syncAllPlayerRatings() {
    const players = await this.getPlayersWithDUPR();
    const updates = [];

    for (const player of players) {
      try {
        const newRating = await this.fetchCurrentRating(player.dupr_id);

        if (this.hasRatingChanged(player, newRating)) {
          updates.push({
            playerId: player.id,
            oldRating: player.dupr_rating,
            newRating: newRating,
            change: newRating - player.dupr_rating
          });

          await this.updatePlayerRating(player.id, newRating);
          await this.notifyRatingChange(player, newRating);
        }
      } catch (error) {
        console.error(`Failed to sync player ${player.id}:`, error);
      }
    }

    return updates;
  }

  async fetchCurrentRating(duprId) {
    const response = await duprApi.get(`/players/${duprId}/rating`);
    return response.data.doubles_rating;
  }

  hasRatingChanged(player, newRating) {
    // Consider significant changes only (0.01 or more)
    return Math.abs(player.dupr_rating - newRating) >= 0.01;
  }

  async notifyRatingChange(player, newRating) {
    const change = newRating - player.dupr_rating;
    const direction = change > 0 ? 'increased' : 'decreased';

    await emailService.send({
      to: player.email,
      subject: 'Your DUPR Rating Has Updated!',
      template: 'rating-change',
      data: {
        name: player.name,
        oldRating: player.dupr_rating,
        newRating: newRating,
        change: Math.abs(change).toFixed(2),
        direction: direction
      }
    });
  }
}
```

## Exception Handling

### Request to Play Up/Down
```javascript
async function handlePlayException(playerId, eventId, reason) {
  const player = await getPlayer(playerId);
  const event = await getEvent(eventId);

  // Validate request
  const validation = validateException(player, event);

  if (!validation.allowed) {
    return {
      approved: false,
      reason: validation.reason
    };
  }

  // Create exception request
  const exception = await db.query(
    `INSERT INTO events.rating_exceptions
     (player_id, event_id, requested_rating, actual_rating, reason, status)
     VALUES ($1, $2, $3, $4, $5, 'pending')
     RETURNING *`,
    [playerId, eventId, event.dupr_min_rating, player.dupr_rating, reason]
  );

  // Auto-approve within reasonable range
  const difference = Math.abs(player.dupr_rating - event.dupr_min_rating);

  if (difference <= 0.5 && validation.autoApprove) {
    await approveException(exception.id);
    return { approved: true, auto: true };
  }

  // Notify staff for manual review
  await notifyStaffOfException(exception);

  return {
    approved: false,
    status: 'pending_review',
    message: 'Your request has been submitted for review'
  };
}

function validateException(player, event) {
  const reasons = {
    allowed: true,
    autoApprove: false
  };

  // Check if player is close enough
  const ratingDiff = Math.abs(player.dupr_rating - event.dupr_min_rating);

  if (ratingDiff > 1.0) {
    reasons.allowed = false;
    reasons.reason = 'Rating difference too large';
  } else if (ratingDiff <= 0.3) {
    reasons.autoApprove = true;
  }

  // Check player history
  if (player.exception_count > 3) {
    reasons.autoApprove = false;
    reasons.reason = 'Too many recent exceptions';
  }

  return reasons;
}
```

## Error Handling & Fallbacks

### API Failure Scenarios
```javascript
class DUPRErrorHandler {
  async handleAPIError(error, context) {
    const errorType = this.classifyError(error);

    switch (errorType) {
      case 'rate_limit':
        await this.handleRateLimit(context);
        break;

      case 'auth_expired':
        await this.refreshAuthentication(context);
        break;

      case 'network':
        await this.queueForRetry(context);
        break;

      case 'invalid_data':
        await this.logValidationError(error, context);
        break;

      default:
        await this.handleGenericError(error, context);
    }
  }

  classifyError(error) {
    if (error.response?.status === 429) return 'rate_limit';
    if (error.response?.status === 401) return 'auth_expired';
    if (error.code === 'ECONNREFUSED') return 'network';
    if (error.response?.status === 400) return 'invalid_data';
    return 'unknown';
  }

  async handleRateLimit(context) {
    // Implement exponential backoff
    const delay = Math.min(1000 * Math.pow(2, context.retryCount), 60000);

    await new Promise(resolve => setTimeout(resolve, delay));

    // Retry the operation
    return this.retryOperation(context);
  }

  async queueForRetry(context) {
    // Store in retry queue
    await db.query(
      `INSERT INTO system.api_retry_queue
       (service, operation, payload, retry_count, next_retry)
       VALUES ('dupr', $1, $2, 0, NOW() + INTERVAL '5 minutes')`,
      [context.operation, JSON.stringify(context.payload)]
    );
  }
}
```

## Testing & Validation

### Test Suite
```javascript
describe('DUPR Integration Tests', () => {
  test('Player rating fetch', async () => {
    const rating = await duprService.fetchPlayerRating('test-player-id');

    expect(rating).toHaveProperty('doubles_rating');
    expect(rating.doubles_rating).toBeGreaterThanOrEqual(1.0);
    expect(rating.doubles_rating).toBeLessThanOrEqual(6.0);
  });

  test('Event filtering logic', () => {
    const events = [
      { dupr_min_rating: 3.0, dupr_max_rating: 3.5 },
      { dupr_min_rating: 4.0, dupr_max_rating: 4.5 },
      { dupr_min_rating: 2.5, dupr_max_rating: 3.0 }
    ];

    const filter = new DUPREventFilter();
    const filtered = filter.filterEvents(events, 3.2);

    expect(filtered).toHaveLength(2);
    expect(filtered[0].badge.type).toBe('perfect');
  });

  test('Match submission format', async () => {
    const match = {
      team1_players: [
        { dupr_id: 'player1' },
        { dupr_id: 'player2' }
      ],
      team2_players: [
        { dupr_id: 'player3' },
        { dupr_id: 'player4' }
      ],
      team1_score: 11,
      team2_score: 9
    };

    const formatted = duprService.formatForDUPR([match], mockEvent);

    expect(formatted[0]).toHaveProperty('team1.score', 11);
    expect(formatted[0]).toHaveProperty('format', 'doubles');
  });
});
```

## Configuration & Settings

### Environment Variables
```bash
# DUPR API Configuration
DUPR_CLIENT_ID=your_client_id_here
DUPR_CLIENT_SECRET=your_client_secret_here
DUPR_REDIRECT_URI=https://yourapp.com/auth/dupr/callback
DUPR_WEBHOOK_SECRET=webhook_secret_here

# DUPR API Endpoints
DUPR_API_BASE_URL=https://api.dupr.com/v1
DUPR_AUTH_URL=https://auth.dupr.com

# Rate Limiting
DUPR_RATE_LIMIT=100
DUPR_RATE_WINDOW=60000

# Sync Settings
DUPR_SYNC_INTERVAL=3600000
DUPR_BATCH_SIZE=50
```

### Admin Configuration Panel
```typescript
interface DUPRSettings {
  // Event Defaults
  defaultBufferZone: number;        // 0.25
  autoApproveThreshold: number;     // 0.3
  maxExceptionRange: number;        // 1.0

  // Submission Settings
  submitDelay: number;              // 30 minutes after event
  retryAttempts: number;            // 3
  batchSize: number;                // 50

  // Sync Settings
  ratingSyncInterval: number;       // 1 hour
  fullSyncTime: string;            // "03:00" (3 AM)
  notifyOnRatingChange: boolean;    // true

  // Display Settings
  showReliabilityScore: boolean;    // true
  showSinglesRating: boolean;       // false
  requireMinMatches: number;        // 10
}
```

## Monitoring & Analytics

### Key Metrics
```sql
-- DUPR Integration Dashboard Queries

-- Connection Success Rate
SELECT
  COUNT(*) FILTER (WHERE dupr_data->>'connection_status' = 'active') AS connected,
  COUNT(*) AS total,
  ROUND(
    100.0 * COUNT(*) FILTER (WHERE dupr_data->>'connection_status' = 'active') / COUNT(*),
    2
  ) AS connection_rate
FROM app_auth.players
WHERE dupr_data IS NOT NULL;

-- Match Submission Success
SELECT
  DATE(created_at) as date,
  COUNT(*) FILTER (WHERE dupr_submitted = true) AS submitted,
  COUNT(*) AS total,
  ROUND(100.0 * COUNT(*) FILTER (WHERE dupr_submitted = true) / COUNT(*), 2) AS success_rate
FROM events.match_results
WHERE created_at > NOW() - INTERVAL '30 days'
GROUP BY DATE(created_at)
ORDER BY date DESC;

-- Rating Distribution
SELECT
  FLOOR(CAST(dupr_rating AS numeric)) as rating_floor,
  COUNT(*) as player_count
FROM app_auth.players
WHERE dupr_rating IS NOT NULL
GROUP BY FLOOR(CAST(dupr_rating AS numeric))
ORDER BY rating_floor;

-- Event Filtering Effectiveness
SELECT
  e.id,
  e.title,
  e.dupr_min_rating,
  e.dupr_max_rating,
  COUNT(r.id) as registrations,
  ROUND(AVG(p.dupr_rating::numeric), 2) as avg_player_rating
FROM events.events e
JOIN events.registrations r ON e.id = r.event_id
JOIN app_auth.players p ON r.player_id = p.id
WHERE e.event_type IN ('dupr_open_play', 'dupr_tournament')
GROUP BY e.id
ORDER BY e.start_time DESC;
```

## Troubleshooting Guide

### Common Issues and Solutions

| Issue | Cause | Solution |
|-------|-------|----------|
| Player can't connect DUPR | OAuth timeout | Clear cookies, retry connection |
| Rating not updating | API rate limit | Wait for next sync cycle |
| Matches not submitting | Invalid player IDs | Verify all players have DUPR IDs |
| Wrong rating shown | Cache issue | Force refresh from DUPR |
| Event not visible | Outside buffer zone | Check rating requirements |
| Submission rejected | Score format error | Verify scoring format matches |
| Sync failing | Expired tokens | Refresh OAuth tokens |
| Duplicate submissions | Retry logic error | Check submission logs |

## Future Enhancements

### Planned Features
1. **Real-time Rating Updates**: WebSocket connection for instant rating changes
2. **Predictive Matching**: AI-based opponent suggestions
3. **Rating Progression Tracking**: Visual charts and milestone notifications
4. **Tournament Seeding**: Automatic bracket generation based on DUPR
5. **Club Rankings**: Aggregate facility ratings and leaderboards
6. **Mobile SDK**: Native integration for iOS/Android apps

### API v2 Preparation
- GraphQL endpoint support
- Webhook event subscriptions
- Bulk operations optimization
- Enhanced error reporting
- Metric streaming

## Compliance & Best Practices

### Data Privacy
- Store minimal DUPR data locally
- Encrypt all tokens at rest
- Regular token rotation
- Audit log all rating changes
- GDPR-compliant data handling

### Rate Limiting
- Respect DUPR API limits
- Implement backoff strategies
- Cache responses appropriately
- Batch operations when possible
- Monitor usage patterns

### Quality Assurance
- Validate all match data before submission
- Implement idempotency for submissions
- Regular reconciliation audits
- Automated testing suite
- Performance monitoring

## Conclusion

The DUPR integration is a critical component of the Dink House Open Play system, providing accurate skill-based matchmaking and official rating management. This comprehensive integration ensures fair play, competitive balance, and seamless user experience while maintaining data integrity and system reliability.