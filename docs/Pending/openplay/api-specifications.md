# API Specifications for Open Play System

## Overview
This document provides comprehensive API specifications for the Pickleball Open Play system, covering all endpoints for player, staff, and DUPR integration operations.

## Base Configuration

### API Base URLs
```
Production: https://api.dinkhouse.com/v1
Staging: https://staging-api.dinkhouse.com/v1
Development: http://localhost:3000/v1
```

### Authentication
All API requests require authentication via JWT tokens in the Authorization header:
```http
Authorization: Bearer <jwt_token>
```

### Common Headers
```http
Content-Type: application/json
Accept: application/json
X-API-Version: 1.0
X-Request-ID: <uuid>
```

### Rate Limiting
```http
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 999
X-RateLimit-Reset: 1614556800
```

## Authentication Endpoints

### POST /auth/register
Create a new player account.

**Request:**
```json
{
  "email": "player@example.com",
  "password": "SecurePassword123!",
  "first_name": "John",
  "last_name": "Doe",
  "phone": "+1234567890",
  "date_of_birth": "1990-01-15",
  "skill_level": "3.5",
  "account_type": "player"
}
```

**Response (201):**
```json
{
  "success": true,
  "data": {
    "user_id": "550e8400-e29b-41d4-a716-446655440000",
    "email": "player@example.com",
    "account_type": "player",
    "created_at": "2024-03-14T10:00:00Z"
  },
  "message": "Registration successful. Please verify your email."
}
```

### POST /auth/login
Authenticate user and receive tokens.

**Request:**
```json
{
  "email": "player@example.com",
  "password": "SecurePassword123!"
}
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "access_token": "eyJhbGciOiJIUzI1NiIs...",
    "refresh_token": "eyJhbGciOiJIUzI1NiIs...",
    "expires_in": 3600,
    "user": {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "email": "player@example.com",
      "first_name": "John",
      "last_name": "Doe",
      "account_type": "player",
      "dupr_rating": 3.45
    }
  }
}
```

### POST /auth/refresh
Refresh access token using refresh token.

**Request:**
```json
{
  "refresh_token": "eyJhbGciOiJIUzI1NiIs..."
}
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "access_token": "eyJhbGciOiJIUzI1NiIs...",
    "expires_in": 3600
  }
}
```

### POST /auth/logout
Invalidate current session.

**Response (200):**
```json
{
  "success": true,
  "message": "Logged out successfully"
}
```

## Player Endpoints

### GET /players/profile
Get current player's profile.

**Response (200):**
```json
{
  "success": true,
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "email": "player@example.com",
    "first_name": "John",
    "last_name": "Doe",
    "phone": "+1234567890",
    "skill_level": "3.5",
    "dupr_rating": 3.45,
    "dupr_id": "DUPR123456",
    "dupr_connected": true,
    "member_since": "2024-01-01T00:00:00Z",
    "total_events": 42,
    "profile_image_url": "https://storage.dinkhouse.com/profiles/550e8400.jpg",
    "preferences": {
      "notifications": {
        "email": true,
        "sms": true,
        "push": false
      },
      "play_style": "competitive",
      "preferred_times": ["evening", "weekend"]
    }
  }
}
```

### PUT /players/profile
Update player profile.

**Request:**
```json
{
  "first_name": "John",
  "last_name": "Smith",
  "phone": "+1234567890",
  "skill_level": "4.0",
  "preferences": {
    "notifications": {
      "email": true,
      "sms": false
    }
  }
}
```

**Response (200):**
```json
{
  "success": true,
  "message": "Profile updated successfully"
}
```

### POST /players/dupr/connect
Initiate DUPR account connection.

**Response (200):**
```json
{
  "success": true,
  "data": {
    "auth_url": "https://auth.dupr.com/oauth/authorize?client_id=...",
    "state": "random_state_string"
  }
}
```

### POST /players/dupr/callback
Handle DUPR OAuth callback.

**Request:**
```json
{
  "code": "auth_code_from_dupr",
  "state": "random_state_string"
}
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "dupr_id": "DUPR123456",
    "doubles_rating": 3.45,
    "singles_rating": 3.25,
    "last_updated": "2024-03-14T10:00:00Z"
  }
}
```

### GET /players/dupr/sync
Manually sync DUPR rating.

**Response (200):**
```json
{
  "success": true,
  "data": {
    "previous_rating": 3.45,
    "current_rating": 3.52,
    "change": 0.07,
    "last_updated": "2024-03-14T15:30:00Z"
  }
}
```

## Event Endpoints

### GET /events
List all available events with smart filtering.

**Query Parameters:**
```
?start_date=2024-03-14
&end_date=2024-03-21
&event_type=dupr_open_play,recreational
&skill_level=3.0,3.5,4.0
&court_surface=hard,indoor
&available_only=true
&page=1
&limit=20
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "events": [
      {
        "id": "650e8400-e29b-41d4-a716-446655440001",
        "title": "Thursday Night DUPR 3.0-3.5",
        "event_type": "dupr_open_play",
        "description": "Competitive doubles round-robin",
        "start_time": "2024-03-14T18:00:00Z",
        "end_time": "2024-03-14T20:00:00Z",
        "location": "Courts 1-4",
        "dupr_min_rating": 3.0,
        "dupr_max_rating": 3.5,
        "visibility_badge": "perfect_match",
        "capacity": 24,
        "registered": 18,
        "available_spots": 6,
        "price_member": 15.00,
        "price_guest": 25.00,
        "courts": [
          {
            "id": "750e8400-e29b-41d4-a716-446655440001",
            "number": 1,
            "surface": "hard"
          }
        ],
        "registration_deadline": "2024-03-14T17:30:00Z",
        "can_register": true
      }
    ],
    "pagination": {
      "page": 1,
      "limit": 20,
      "total": 45,
      "pages": 3
    }
  }
}
```

### GET /events/{id}
Get detailed event information.

**Response (200):**
```json
{
  "success": true,
  "data": {
    "id": "650e8400-e29b-41d4-a716-446655440001",
    "title": "Thursday Night DUPR 3.0-3.5",
    "event_type": "dupr_open_play",
    "description": "Competitive doubles round-robin format...",
    "start_time": "2024-03-14T18:00:00Z",
    "end_time": "2024-03-14T20:00:00Z",
    "check_in_time": "2024-03-14T17:30:00Z",
    "location": {
      "facility": "Dink House Main",
      "address": "123 Pickleball Way, Austin, TX",
      "courts": "1-4"
    },
    "format": {
      "type": "round_robin",
      "rounds": 8,
      "game_to": 11,
      "win_by": 2,
      "time_per_round": 15
    },
    "requirements": {
      "dupr_min_rating": 3.0,
      "dupr_max_rating": 3.5,
      "skill_levels": ["3.0", "3.5"],
      "member_only": false
    },
    "capacity": {
      "min": 8,
      "max": 24,
      "registered": 18,
      "waitlist": 3
    },
    "pricing": {
      "member": 15.00,
      "guest": 25.00,
      "early_bird_discount": 20,
      "early_bird_deadline": "2024-03-07T23:59:59Z"
    },
    "courts": [
      {
        "id": "750e8400-e29b-41d4-a716-446655440001",
        "number": 1,
        "surface": "hard",
        "environment": "indoor"
      }
    ],
    "equipment": {
      "balls_provided": true,
      "loaner_paddles": true,
      "water_stations": true
    },
    "instructions": "Please arrive 15 minutes early for warm-up...",
    "weather_policy": "Indoor courts - event runs rain or shine",
    "cancellation_policy": "Full refund up to 24 hours before event",
    "registered_players": [
      {
        "id": "550e8400-e29b-41d4-a716-446655440000",
        "name": "John D.",
        "dupr_rating": 3.45
      }
    ]
  }
}
```

### POST /events/{id}/register
Register for an event.

**Request:**
```json
{
  "payment_method": "card",
  "payment_token": "stripe_token_xyz",
  "notes": "First time at this venue",
  "emergency_contact": {
    "name": "Jane Doe",
    "phone": "+1234567891"
  }
}
```

**Response (201):**
```json
{
  "success": true,
  "data": {
    "registration_id": "850e8400-e29b-41d4-a716-446655440001",
    "event_id": "650e8400-e29b-41d4-a716-446655440001",
    "status": "confirmed",
    "payment_status": "paid",
    "amount_paid": 15.00,
    "check_in_code": "CHK-2024-0314-1823",
    "qr_code_url": "https://api.dinkhouse.com/qr/CHK-2024-0314-1823",
    "confirmation_sent": true
  }
}
```

### DELETE /events/{id}/register
Cancel event registration.

**Response (200):**
```json
{
  "success": true,
  "data": {
    "refund_amount": 15.00,
    "refund_status": "processed",
    "cancellation_time": "2024-03-13T10:00:00Z"
  }
}
```

### POST /events/{id}/check-in
Check in to an event.

**Request:**
```json
{
  "method": "qr_code",
  "check_in_code": "CHK-2024-0314-1823"
}
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "check_in_time": "2024-03-14T17:35:00Z",
    "court_assignment": 2,
    "warm_up_time": "17:45",
    "first_match_time": "18:00"
  }
}
```

## Staff/Admin Endpoints

### POST /admin/events
Create a new event.

**Request:**
```json
{
  "title": "Friday Night DUPR 3.5-4.0",
  "event_type": "dupr_open_play",
  "description": "Competitive round-robin for intermediate players",
  "template_id": null,
  "start_time": "2024-03-15T18:00:00Z",
  "end_time": "2024-03-15T20:00:00Z",
  "check_in_time": "2024-03-15T17:30:00Z",
  "court_ids": [
    "750e8400-e29b-41d4-a716-446655440001",
    "750e8400-e29b-41d4-a716-446655440002"
  ],
  "capacity": {
    "min": 8,
    "max": 16
  },
  "requirements": {
    "dupr_min_rating": 3.5,
    "dupr_max_rating": 4.0,
    "dupr_buffer": 0.25,
    "skill_levels": ["3.5", "4.0"],
    "member_only": false
  },
  "pricing": {
    "member": 15.00,
    "guest": 25.00
  },
  "format": {
    "type": "round_robin",
    "rounds": 6,
    "game_to": 11,
    "win_by": 2
  },
  "recurrence": {
    "enabled": true,
    "frequency": "weekly",
    "days": ["friday"],
    "end_date": "2024-06-30"
  }
}
```

**Response (201):**
```json
{
  "success": true,
  "data": {
    "event_id": "650e8400-e29b-41d4-a716-446655440002",
    "created_events": 12,
    "first_event": "2024-03-15T18:00:00Z",
    "last_event": "2024-06-28T18:00:00Z"
  }
}
```

### PUT /admin/events/{id}
Update event details.

**Request:**
```json
{
  "title": "Updated Event Title",
  "capacity": {
    "max": 20
  },
  "pricing": {
    "member": 12.00
  }
}
```

**Response (200):**
```json
{
  "success": true,
  "message": "Event updated successfully"
}
```

### DELETE /admin/events/{id}
Cancel an event.

**Request:**
```json
{
  "reason": "Court maintenance required",
  "notify_players": true,
  "issue_refunds": true
}
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "players_notified": 18,
    "refunds_issued": 18,
    "total_refunded": 270.00
  }
}
```

### GET /admin/events/{id}/registrations
Get all registrations for an event.

**Response (200):**
```json
{
  "success": true,
  "data": {
    "registrations": [
      {
        "registration_id": "850e8400-e29b-41d4-a716-446655440001",
        "player": {
          "id": "550e8400-e29b-41d4-a716-446655440000",
          "name": "John Doe",
          "email": "john@example.com",
          "phone": "+1234567890",
          "dupr_rating": 3.45,
          "skill_level": "3.5"
        },
        "status": "confirmed",
        "payment_status": "paid",
        "amount_paid": 15.00,
        "registered_at": "2024-03-10T14:00:00Z",
        "check_in_status": "pending",
        "notes": "First time player"
      }
    ],
    "waitlist": [
      {
        "player_id": "550e8400-e29b-41d4-a716-446655440003",
        "name": "Jane Smith",
        "position": 1,
        "added_at": "2024-03-12T10:00:00Z"
      }
    ],
    "summary": {
      "total": 18,
      "confirmed": 18,
      "waitlisted": 3,
      "checked_in": 0,
      "no_shows": 0
    }
  }
}
```

### POST /admin/events/{id}/check-in/{player_id}
Manually check in a player.

**Request:**
```json
{
  "method": "manual",
  "notes": "Walk-in registration"
}
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "check_in_time": "2024-03-14T17:40:00Z",
    "court_assignment": 3
  }
}
```

### POST /admin/events/{id}/sessions/start
Start an event session.

**Request:**
```json
{
  "actual_start_time": "2024-03-14T18:05:00Z",
  "total_players": 18,
  "courts_in_use": [1, 2, 3, 4]
}
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "session_id": "950e8400-e29b-41d4-a716-446655440001",
    "status": "in_progress",
    "round_1_assignments": [
      {
        "court": 1,
        "team_1": ["player_1_id", "player_2_id"],
        "team_2": ["player_3_id", "player_4_id"]
      }
    ]
  }
}
```

### POST /admin/events/{id}/matches
Record match results.

**Request:**
```json
{
  "matches": [
    {
      "round": 1,
      "court": 1,
      "team_1": {
        "players": ["550e8400-e29b-41d4-a716-446655440001", "550e8400-e29b-41d4-a716-446655440002"],
        "score": 11
      },
      "team_2": {
        "players": ["550e8400-e29b-41d4-a716-446655440003", "550e8400-e29b-41d4-a716-446655440004"],
        "score": 9
      }
    }
  ]
}
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "matches_recorded": 4,
    "ready_for_dupr": true
  }
}
```

### POST /admin/events/{id}/dupr/submit
Submit match results to DUPR.

**Request:**
```json
{
  "validate_only": false,
  "include_matches": "all"
}
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "submission_id": "DUPR-SUB-20240314-001",
    "matches_submitted": 36,
    "successful": 36,
    "failed": 0,
    "estimated_processing": "2024-03-15T00:00:00Z"
  }
}
```

## Court Management Endpoints

### GET /courts
List all courts.

**Response (200):**
```json
{
  "success": true,
  "data": {
    "courts": [
      {
        "id": "750e8400-e29b-41d4-a716-446655440001",
        "number": 1,
        "name": "Court 1 - Championship",
        "surface": "hard",
        "environment": "indoor",
        "status": "available",
        "features": ["lights", "scoreboard"],
        "capacity": 4,
        "current_event": null
      }
    ]
  }
}
```

### GET /courts/availability
Check court availability for a time range.

**Query Parameters:**
```
?start_time=2024-03-14T18:00:00Z
&end_time=2024-03-14T20:00:00Z
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "available_courts": [5, 6],
    "occupied_courts": [
      {
        "court": 1,
        "event": "Thursday Night DUPR",
        "time": "18:00-20:00"
      }
    ]
  }
}
```

### PUT /courts/{id}/status
Update court status.

**Request:**
```json
{
  "status": "maintenance",
  "reason": "Net replacement",
  "estimated_available": "2024-03-15T12:00:00Z"
}
```

**Response (200):**
```json
{
  "success": true,
  "message": "Court status updated"
}
```

## Analytics Endpoints

### GET /analytics/events/summary
Get event performance summary.

**Query Parameters:**
```
?start_date=2024-03-01
&end_date=2024-03-31
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "total_events": 45,
    "total_registrations": 810,
    "total_revenue": 12150.00,
    "average_fill_rate": 0.84,
    "popular_times": {
      "thursday_evening": 0.92,
      "saturday_morning": 0.88,
      "sunday_afternoon": 0.79
    },
    "event_types": {
      "dupr_open_play": 25,
      "recreational": 15,
      "clinic": 5
    },
    "player_metrics": {
      "unique_players": 245,
      "average_events_per_player": 3.3,
      "retention_rate": 0.67
    }
  }
}
```

### GET /analytics/players/engagement
Get player engagement metrics.

**Response (200):**
```json
{
  "success": true,
  "data": {
    "active_players": 245,
    "new_players_this_month": 42,
    "dupr_connected": 156,
    "skill_distribution": {
      "2.0-2.5": 15,
      "2.5-3.0": 48,
      "3.0-3.5": 87,
      "3.5-4.0": 65,
      "4.0-4.5": 25,
      "4.5+": 5
    },
    "engagement_levels": {
      "highly_engaged": 78,
      "moderately_engaged": 112,
      "low_engagement": 55
    }
  }
}
```

### GET /analytics/revenue
Get revenue analytics.

**Query Parameters:**
```
?period=monthly
&year=2024
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "revenue_by_month": [
      {
        "month": "2024-01",
        "total": 10500.00,
        "member": 8400.00,
        "guest": 2100.00,
        "events": 38
      },
      {
        "month": "2024-02",
        "total": 11200.00,
        "member": 8960.00,
        "guest": 2240.00,
        "events": 42
      },
      {
        "month": "2024-03",
        "total": 12150.00,
        "member": 9720.00,
        "guest": 2430.00,
        "events": 45
      }
    ],
    "payment_methods": {
      "card": 0.78,
      "cash": 0.15,
      "other": 0.07
    },
    "refunds": {
      "total": 450.00,
      "count": 12,
      "rate": 0.015
    }
  }
}
```

## WebSocket Events

### Connection
```javascript
const ws = new WebSocket('wss://api.dinkhouse.com/ws');

ws.on('open', () => {
  ws.send(JSON.stringify({
    type: 'auth',
    token: 'jwt_token_here'
  }));
});
```

### Event Updates
```javascript
// Subscribe to event updates
ws.send(JSON.stringify({
  type: 'subscribe',
  channel: 'event:650e8400-e29b-41d4-a716-446655440001'
}));

// Receive updates
ws.on('message', (data) => {
  const message = JSON.parse(data);

  switch(message.type) {
    case 'registration_update':
      // New registration or cancellation
      console.log(`Spots remaining: ${message.data.available_spots}`);
      break;

    case 'check_in_update':
      // Player checked in
      console.log(`${message.data.player_name} checked in`);
      break;

    case 'round_start':
      // New round starting
      console.log(`Round ${message.data.round} starting`);
      break;

    case 'court_assignment':
      // Court assignment for player
      console.log(`Assigned to court ${message.data.court}`);
      break;
  }
});
```

### Live Scores
```javascript
// Subscribe to live scores
ws.send(JSON.stringify({
  type: 'subscribe',
  channel: 'scores:650e8400-e29b-41d4-a716-446655440001'
}));

// Score update format
{
  "type": "score_update",
  "data": {
    "court": 1,
    "team_1_score": 7,
    "team_2_score": 5,
    "serving_team": 1
  }
}
```

## Error Responses

### Standard Error Format
```json
{
  "success": false,
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Invalid input data",
    "details": [
      {
        "field": "email",
        "message": "Invalid email format"
      }
    ]
  },
  "request_id": "req_123456789"
}
```

### Common Error Codes
| Code | HTTP Status | Description |
|------|------------|-------------|
| `UNAUTHORIZED` | 401 | Missing or invalid authentication |
| `FORBIDDEN` | 403 | Insufficient permissions |
| `NOT_FOUND` | 404 | Resource not found |
| `VALIDATION_ERROR` | 400 | Invalid request data |
| `DUPR_ERROR` | 502 | DUPR API error |
| `PAYMENT_FAILED` | 402 | Payment processing failed |
| `CAPACITY_REACHED` | 409 | Event is full |
| `RATING_MISMATCH` | 403 | Player rating outside event range |
| `ALREADY_REGISTERED` | 409 | Player already registered |
| `RATE_LIMIT` | 429 | Too many requests |
| `SERVER_ERROR` | 500 | Internal server error |

## SDK Examples

### JavaScript/TypeScript
```typescript
import { DinkHouseAPI } from '@dinkhouse/api-client';

const api = new DinkHouseAPI({
  apiKey: process.env.DINKHOUSE_API_KEY,
  environment: 'production'
});

// Get events
const events = await api.events.list({
  startDate: '2024-03-14',
  eventType: ['dupr_open_play'],
  skillLevel: ['3.0', '3.5']
});

// Register for event
const registration = await api.events.register(eventId, {
  paymentMethod: 'card',
  paymentToken: stripeToken
});

// Check in
const checkIn = await api.events.checkIn(eventId, {
  method: 'qr_code',
  code: registration.checkInCode
});
```

### Python
```python
from dinkhouse import DinkHouseClient

client = DinkHouseClient(
    api_key=os.environ['DINKHOUSE_API_KEY'],
    environment='production'
)

# Get player profile
profile = client.players.get_profile()

# Connect DUPR
dupr_url = client.players.connect_dupr()
print(f"Connect your DUPR account: {dupr_url}")

# List events
events = client.events.list(
    start_date='2024-03-14',
    event_type=['dupr_open_play'],
    skill_level=[3.0, 3.5]
)

# Register for event
registration = client.events.register(
    event_id,
    payment_method='card',
    payment_token=stripe_token
)
```

## Postman Collection
A complete Postman collection is available at:
```
https://api.dinkhouse.com/docs/postman-collection.json
```

Import this collection to test all API endpoints with pre-configured examples and environment variables.

## API Versioning

The API uses URL versioning. The current version is `v1`.

### Version Header
Include the API version in requests:
```http
X-API-Version: 1.0
```

### Deprecation Policy
- Deprecated endpoints will be marked with a `Deprecation` header
- Minimum 6 months notice before removing endpoints
- Migration guides provided for breaking changes

## Rate Limiting

### Limits by Plan
| Plan | Requests/Hour | Burst |
|------|--------------|-------|
| Basic | 1,000 | 50/min |
| Pro | 5,000 | 200/min |
| Enterprise | Unlimited | Custom |

### Rate Limit Headers
```http
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 999
X-RateLimit-Reset: 1614556800
Retry-After: 3600
```

## Webhooks

### Configuration
Configure webhooks in the admin dashboard or via API:

```json
POST /admin/webhooks
{
  "url": "https://yourapp.com/webhooks/dinkhouse",
  "events": [
    "player.registered",
    "event.created",
    "event.cancelled",
    "check_in.completed",
    "match.submitted_to_dupr"
  ],
  "secret": "webhook_secret_key"
}
```

### Webhook Payload
```json
{
  "id": "evt_123456789",
  "type": "player.registered",
  "created": "2024-03-14T10:00:00Z",
  "data": {
    "player_id": "550e8400-e29b-41d4-a716-446655440000",
    "event_id": "650e8400-e29b-41d4-a716-446655440001",
    "registration_id": "850e8400-e29b-41d4-a716-446655440001"
  }
}
```

### Webhook Verification
```javascript
const crypto = require('crypto');

function verifyWebhook(payload, signature, secret) {
  const hash = crypto
    .createHmac('sha256', secret)
    .update(payload)
    .digest('hex');

  return hash === signature;
}
```

## Testing

### Test Environment
```
Base URL: https://sandbox-api.dinkhouse.com/v1
Test API Key: test_pk_1234567890
```

### Test Data
Use these test values in the sandbox:
- Test DUPR ID: `DUPR_TEST_123`
- Test Player Email: `test@dinkhouse.com`
- Test Card: `4242 4242 4242 4242`

## Support

### Documentation
Full documentation available at: https://docs.dinkhouse.com/api

### Contact
- Email: api-support@dinkhouse.com
- Slack: dinkhouse-api.slack.com
- GitHub: github.com/dinkhouse/api-issues

## Changelog

### Version 1.0 (Current)
- Initial release
- Complete event management
- DUPR integration
- Player profiles
- Check-in system
- Analytics endpoints

### Roadmap
- v1.1: Advanced matchmaking algorithms
- v1.2: Tournament bracket management
- v1.3: Live streaming integration
- v2.0: GraphQL API