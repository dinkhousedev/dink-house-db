# Tournament Management System - API Endpoints

## API Overview

The Tournament Management System API follows RESTful principles with JSON payloads. All endpoints require authentication except public tournament listings and live scores.

## Base Configuration

```javascript
// Base URL
const API_BASE = process.env.API_URL || 'https://api.dinkhouse.com/v1';

// Headers
const headers = {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer {access_token}',
    'X-API-Version': '1.0',
    'X-Request-ID': '{unique_request_id}'
};

// Rate Limiting
// - Authenticated: 1000 requests per minute
// - Unauthenticated: 100 requests per minute
// - Bulk operations: 10 requests per minute
```

## Authentication Endpoints

### POST /auth/login
Login with email and password

**Request:**
```json
{
    "email": "director@dinkhouse.com",
    "password": "secure_password"
}
```

**Response:**
```json
{
    "access_token": "eyJhbGc...",
    "refresh_token": "eyJhbGc...",
    "user": {
        "id": "uuid",
        "email": "director@dinkhouse.com",
        "role": "tournament_director",
        "permissions": ["create_tournament", "manage_divisions", "view_financials"]
    },
    "expires_in": 3600
}
```

### POST /auth/refresh
Refresh access token

### POST /auth/logout
Invalidate tokens

## Tournament Management Endpoints

### GET /tournaments
List all tournaments with filtering

**Query Parameters:**
- `status` - draft, published, registration_open, in_progress, completed
- `start_date` - ISO date
- `end_date` - ISO date
- `venue_id` - UUID
- `featured` - boolean
- `members_only` - boolean
- `page` - integer (default: 1)
- `limit` - integer (default: 20, max: 100)
- `sort` - event_starts_at, created_at, name
- `order` - asc, desc

**Response:**
```json
{
    "data": [
        {
            "id": "uuid",
            "name": "Summer Championships 2024",
            "slug": "summer-championships-2024",
            "description": "Annual summer tournament",
            "tournament_type": "double_elimination",
            "event_starts_at": "2024-07-15T08:00:00Z",
            "event_ends_at": "2024-07-16T20:00:00Z",
            "registration_opens_at": "2024-06-01T00:00:00Z",
            "registration_closes_at": "2024-07-10T23:59:59Z",
            "venue": {
                "id": "uuid",
                "name": "Dink House Main",
                "address": "123 Pickleball Lane"
            },
            "divisions_count": 8,
            "teams_registered": 124,
            "max_teams_total": 200,
            "base_price_member": 50.00,
            "base_price_guest": 65.00,
            "status": "registration_open",
            "is_featured": true
        }
    ],
    "pagination": {
        "page": 1,
        "limit": 20,
        "total": 45,
        "pages": 3
    }
}
```

### GET /tournaments/{id}
Get tournament details

**Response:**
```json
{
    "id": "uuid",
    "name": "Summer Championships 2024",
    "slug": "summer-championships-2024",
    "description": "Annual summer tournament...",
    "rules_document_url": "https://storage.dinkhouse.com/rules.pdf",
    "tournament_type": "double_elimination",
    "format": "doubles",
    "event_starts_at": "2024-07-15T08:00:00Z",
    "event_ends_at": "2024-07-16T20:00:00Z",
    "registration_opens_at": "2024-06-01T00:00:00Z",
    "registration_closes_at": "2024-07-10T23:59:59Z",
    "early_bird_ends_at": "2024-06-15T23:59:59Z",
    "check_in_starts_at": "2024-07-15T07:00:00Z",
    "venue": {
        "id": "uuid",
        "name": "Dink House Main",
        "address": "123 Pickleball Lane",
        "city": "Austin",
        "state": "TX",
        "parking_info": "Free parking available",
        "amenities": ["restrooms", "pro_shop", "food_court"]
    },
    "divisions": [
        {
            "id": "uuid",
            "name": "Men's Doubles 3.5",
            "code": "MD35",
            "max_teams": 16,
            "current_teams_count": 12,
            "waitlist_count": 2
        }
    ],
    "pricing": {
        "base_price_member": 50.00,
        "base_price_guest": 65.00,
        "early_bird_discount_percent": 20,
        "late_fee_amount": 15.00
    },
    "settings": {
        "allow_substitutes": true,
        "allow_refunds": true,
        "refund_deadline_hours": 48,
        "requires_approval": false
    },
    "contact": {
        "director_name": "John Smith",
        "director_email": "john@dinkhouse.com",
        "support_email": "support@dinkhouse.com"
    },
    "sponsors": [
        {
            "name": "Acme Sports",
            "logo_url": "https://...",
            "level": "gold"
        }
    ],
    "status": "registration_open",
    "statistics": {
        "total_divisions": 8,
        "total_teams_registered": 124,
        "total_players": 248,
        "revenue_collected": 12400.00
    }
}
```

### POST /tournaments
Create new tournament

**Request:**
```json
{
    "name": "Fall Classic 2024",
    "description": "Season ending tournament",
    "tournament_type": "single_elimination",
    "format": "doubles",
    "registration_opens_at": "2024-09-01T00:00:00Z",
    "registration_closes_at": "2024-10-10T23:59:59Z",
    "early_bird_ends_at": "2024-09-15T23:59:59Z",
    "check_in_starts_at": "2024-10-15T07:00:00Z",
    "event_starts_at": "2024-10-15T08:00:00Z",
    "event_ends_at": "2024-10-15T20:00:00Z",
    "venue_id": "uuid",
    "venue_name": "Dink House Main",
    "venue_address": "123 Pickleball Lane, Austin, TX",
    "max_teams_total": 64,
    "min_teams_total": 16,
    "base_price_member": 60.00,
    "base_price_guest": 75.00,
    "early_bird_discount_percent": 15,
    "director_name": "Jane Doe",
    "director_email": "jane@dinkhouse.com",
    "settings": {
        "allow_substitutes": true,
        "allow_refunds": true,
        "refund_deadline_hours": 72
    }
}
```

### PUT /tournaments/{id}
Update tournament

### DELETE /tournaments/{id}
Delete tournament (only if no registrations)

### POST /tournaments/{id}/publish
Publish tournament for registration

### POST /tournaments/{id}/cancel
Cancel tournament

## Division Management Endpoints

### GET /tournaments/{id}/divisions
List tournament divisions

### GET /divisions/{id}
Get division details with teams

**Response:**
```json
{
    "id": "uuid",
    "tournament_id": "uuid",
    "name": "Men's Doubles 3.5",
    "code": "MD35",
    "description": "Intermediate level men's doubles",
    "skill_level_min": "3.25",
    "skill_level_max": "3.75",
    "age_min": null,
    "age_max": null,
    "gender_restriction": "male",
    "uses_dupr": true,
    "dupr_min_combined": 6.5,
    "dupr_max_combined": 7.5,
    "dupr_max_spread": 0.5,
    "max_teams": 16,
    "min_teams": 4,
    "current_teams_count": 12,
    "waitlist_count": 2,
    "bracket_type": "double_elimination",
    "status": "open",
    "teams": [
        {
            "id": "uuid",
            "team_name": "Dink Dynasty",
            "player1_name": "John Smith",
            "player2_name": "Bob Jones",
            "combined_dupr_rating": 7.2,
            "seed_number": 1,
            "status": "confirmed"
        }
    ]
}
```

### POST /tournaments/{id}/divisions
Create division

**Request:**
```json
{
    "name": "Women's Doubles 4.0",
    "code": "WD40",
    "description": "Advanced women's doubles",
    "skill_level_min": "3.75",
    "skill_level_max": "4.25",
    "gender_restriction": "female",
    "uses_dupr": true,
    "dupr_min_combined": 7.5,
    "dupr_max_combined": 8.5,
    "dupr_max_spread": 0.75,
    "max_teams": 16,
    "min_teams": 4,
    "bracket_type": "double_elimination"
}
```

### PUT /divisions/{id}
Update division

### DELETE /divisions/{id}
Delete division (only if no teams registered)

### POST /divisions/{id}/close-registration
Close division registration

## Team Registration Endpoints

### GET /tournaments/{id}/teams
List tournament teams

### GET /teams/{id}
Get team details

### POST /tournaments/{id}/register
Register team for tournament

**Request:**
```json
{
    "division_id": "uuid",
    "team_name": "Pickle Warriors",
    "player1": {
        "id": "uuid",
        "name": "John Smith",
        "email": "john@example.com",
        "phone": "512-555-0100",
        "dupr_id": "DUPR123456",
        "dupr_rating": 3.75,
        "skill_level": "3.5"
    },
    "player2": {
        "name": "Jane Doe",
        "email": "jane@example.com",
        "phone": "512-555-0101",
        "dupr_id": "DUPR789012",
        "dupr_rating": 3.45,
        "skill_level": "3.5"
    },
    "registration_type": "standard",
    "payment_method": "credit_card",
    "split_payment": false,
    "accepts_terms": true,
    "emergency_contact": {
        "name": "Emergency Contact",
        "phone": "512-555-0102",
        "relationship": "spouse"
    },
    "notes": "First tournament together"
}
```

**Response:**
```json
{
    "team_id": "uuid",
    "team_code": "DH2024-045",
    "division": "Men's Doubles 3.5",
    "status": "pending_payment",
    "payment_required": 120.00,
    "payment_url": "https://checkout.stripe.com/...",
    "confirmation_number": "CONF-2024-0045"
}
```

### PUT /teams/{id}
Update team information

### POST /teams/{id}/withdraw
Withdraw team from tournament

### POST /teams/{id}/substitute
Request player substitution

**Request:**
```json
{
    "substitute_for_player": 2,
    "substitute_player": {
        "name": "Mike Johnson",
        "email": "mike@example.com",
        "phone": "512-555-0103",
        "dupr_id": "DUPR345678",
        "dupr_rating": 3.55,
        "skill_level": "3.5"
    },
    "reason": "Injury"
}
```

### POST /teams/{id}/check-in
Check in team at tournament

**Request:**
```json
{
    "player_number": 1,
    "qr_code": "QR-2024-0045-1",
    "wristband_number": "WB-123",
    "id_verified": true,
    "waiver_signed": true
}
```

## Match Management Endpoints

### GET /tournaments/{id}/matches
List tournament matches

### GET /matches/{id}
Get match details

### POST /matches/{id}/start
Start match

### POST /matches/{id}/score
Submit match score

**Request:**
```json
{
    "games": [
        {
            "game_number": 1,
            "team1_score": 11,
            "team2_score": 9
        },
        {
            "game_number": 2,
            "team1_score": 8,
            "team2_score": 11
        },
        {
            "game_number": 3,
            "team1_score": 11,
            "team2_score": 7
        }
    ],
    "winner_id": "uuid",
    "duration_minutes": 45
}
```

### PUT /matches/{id}/score
Update match score

### POST /matches/{id}/complete
Mark match as complete

### POST /matches/{id}/dispute
Report score dispute

## Bracket Management Endpoints

### GET /divisions/{id}/bracket
Get division bracket

**Response:**
```json
{
    "division_id": "uuid",
    "bracket_type": "double_elimination",
    "total_rounds": 5,
    "consolation_rounds": 3,
    "seeds": [
        {
            "seed": 1,
            "team_id": "uuid",
            "team_name": "Top Seeds"
        }
    ],
    "rounds": [
        {
            "round_number": 1,
            "round_name": "Round of 16",
            "matches": [
                {
                    "match_id": "uuid",
                    "match_number": 1,
                    "team1": {
                        "id": "uuid",
                        "name": "Team A",
                        "seed": 1
                    },
                    "team2": {
                        "id": "uuid",
                        "name": "Team B",
                        "seed": 16
                    },
                    "court_number": 1,
                    "scheduled_time": "2024-07-15T09:00:00Z",
                    "status": "pending"
                }
            ]
        }
    ],
    "consolation_bracket": {
        "rounds": []
    }
}
```

### POST /divisions/{id}/generate-bracket
Generate bracket for division

**Request:**
```json
{
    "seeding_method": "dupr",
    "include_consolation": true,
    "court_assignments": "automatic"
}
```

### PUT /divisions/{id}/bracket
Update bracket (reseeding)

### POST /divisions/{id}/bracket/finalize
Lock bracket from changes

## Payment Endpoints

### GET /tournaments/{id}/payments
List tournament payments

### GET /payments/{id}
Get payment details

### POST /teams/{id}/payment
Process team payment

**Request:**
```json
{
    "amount": 120.00,
    "payment_method": "credit_card",
    "payment_token": "stripe_token_xxx",
    "split_payment": true,
    "player1_amount": 60.00,
    "player2_amount": 60.00
}
```

### POST /payments/{id}/refund
Process refund

**Request:**
```json
{
    "amount": 120.00,
    "reason": "Tournament cancelled"
}
```

### GET /tournaments/{id}/financial-report
Get tournament financial summary

**Response:**
```json
{
    "tournament_id": "uuid",
    "summary": {
        "total_revenue": 12400.00,
        "total_refunds": 240.00,
        "net_revenue": 12160.00,
        "processing_fees": 372.00,
        "pending_payments": 480.00
    },
    "breakdown": {
        "by_division": [],
        "by_payment_method": [],
        "by_date": []
    }
}
```

## Communication Endpoints

### GET /tournaments/{id}/communications
List tournament messages

### POST /tournaments/{id}/communicate
Send tournament communication

**Request:**
```json
{
    "subject": "Tournament Update - Court Changes",
    "content": "Due to weather, courts 5-8 will be used...",
    "message_type": "update",
    "channel": "email",
    "recipient_type": "all",
    "recipient_filters": {
        "divisions": ["uuid1", "uuid2"]
    },
    "send_immediately": true
}
```

### GET /templates
List communication templates

### POST /templates
Create communication template

## Staff Management Endpoints

### GET /tournaments/{id}/staff
List tournament staff

### POST /tournaments/{id}/staff
Add staff member

**Request:**
```json
{
    "user_id": "uuid",
    "role": "court_monitor",
    "assigned_courts": [1, 2, 3],
    "shift_start": "2024-07-15T07:00:00Z",
    "shift_end": "2024-07-15T14:00:00Z"
}
```

### PUT /staff/{id}
Update staff assignment

### POST /staff/{id}/check-in
Staff check-in

### DELETE /staff/{id}
Remove staff member

## Live Scoring Endpoints (WebSocket)

### WS /live/tournaments/{id}
Connect to tournament live updates

**Subscribe Events:**
```json
{
    "action": "subscribe",
    "channels": ["scores", "brackets", "announcements"]
}
```

**Score Update Event:**
```json
{
    "type": "score_update",
    "match_id": "uuid",
    "game_number": 1,
    "team1_score": 5,
    "team2_score": 3,
    "timestamp": "2024-07-15T09:15:30Z"
}
```

**Bracket Update Event:**
```json
{
    "type": "bracket_update",
    "division_id": "uuid",
    "match_id": "uuid",
    "winner_id": "uuid",
    "next_match_id": "uuid"
}
```

## DUPR Integration Endpoints

### POST /dupr/verify
Verify DUPR ratings

**Request:**
```json
{
    "players": [
        {
            "dupr_id": "DUPR123456",
            "name": "John Smith"
        },
        {
            "dupr_id": "DUPR789012",
            "name": "Jane Doe"
        }
    ]
}
```

**Response:**
```json
{
    "valid": true,
    "players": [
        {
            "dupr_id": "DUPR123456",
            "name": "John Smith",
            "singles_rating": 3.85,
            "doubles_rating": 3.75,
            "verified": true
        }
    ],
    "combined_rating": 7.5,
    "rating_spread": 0.1
}
```

### POST /dupr/submit-results
Submit match results to DUPR

**Request:**
```json
{
    "match_id": "uuid",
    "tournament_name": "Summer Championships 2024",
    "division": "Men's Doubles 3.5",
    "team1_players": ["DUPR123456", "DUPR234567"],
    "team2_players": ["DUPR345678", "DUPR456789"],
    "scores": [
        {
            "game": 1,
            "team1": 11,
            "team2": 9
        }
    ],
    "winner": "team1",
    "match_date": "2024-07-15T09:00:00Z"
}
```

## Reports & Analytics Endpoints

### GET /tournaments/{id}/analytics
Get tournament analytics

**Response:**
```json
{
    "registration": {
        "total_views": 2450,
        "conversion_rate": 0.12,
        "abandonment_rate": 0.35,
        "avg_time_to_register": "4:32",
        "by_source": {
            "direct": 450,
            "email": 820,
            "social": 380
        }
    },
    "demographics": {
        "age_ranges": {},
        "skill_levels": {},
        "geographic": {}
    },
    "performance": {
        "avg_match_duration": 42,
        "total_games_played": 324,
        "upsets": 12
    }
}
```

### GET /tournaments/{id}/export
Export tournament data

**Query Parameters:**
- `format` - csv, xlsx, pdf
- `include` - teams, matches, payments, analytics

### POST /tournaments/{id}/survey
Send post-tournament survey

## Error Responses

All error responses follow this format:

```json
{
    "error": {
        "code": "VALIDATION_ERROR",
        "message": "Invalid request parameters",
        "details": [
            {
                "field": "dupr_rating",
                "message": "Rating must be between 1.0 and 6.0"
            }
        ],
        "request_id": "req_abc123",
        "timestamp": "2024-07-15T09:00:00Z"
    }
}
```

### Error Codes
- `AUTHENTICATION_REQUIRED` - 401
- `INSUFFICIENT_PERMISSIONS` - 403
- `RESOURCE_NOT_FOUND` - 404
- `VALIDATION_ERROR` - 400
- `DUPLICATE_RESOURCE` - 409
- `RATE_LIMIT_EXCEEDED` - 429
- `INTERNAL_SERVER_ERROR` - 500
- `SERVICE_UNAVAILABLE` - 503

## Webhook Events

The system can send webhooks for various events:

### Tournament Events
- `tournament.created`
- `tournament.published`
- `tournament.registration_opened`
- `tournament.registration_closed`
- `tournament.started`
- `tournament.completed`
- `tournament.cancelled`

### Registration Events
- `team.registered`
- `team.confirmed`
- `team.waitlisted`
- `team.withdrawn`
- `team.checked_in`

### Match Events
- `match.scheduled`
- `match.started`
- `match.score_updated`
- `match.completed`
- `bracket.updated`

### Payment Events
- `payment.completed`
- `payment.failed`
- `payment.refunded`

### Webhook Payload Example:
```json
{
    "event": "team.registered",
    "timestamp": "2024-07-15T09:00:00Z",
    "data": {
        "tournament_id": "uuid",
        "team_id": "uuid",
        "division_id": "uuid",
        "team_name": "Pickle Warriors"
    },
    "signature": "sha256_hash"
}
```

## Rate Limiting

API rate limits are enforced per API key:

| Endpoint Type | Rate Limit | Window |
|--------------|------------|--------|
| Read endpoints | 1000 req | 1 minute |
| Write endpoints | 100 req | 1 minute |
| Bulk operations | 10 req | 1 minute |
| Export operations | 5 req | 10 minutes |
| WebSocket connections | 10 | concurrent |

Rate limit headers:
```
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 999
X-RateLimit-Reset: 1625592000
```

## Versioning

The API uses URL versioning. Current version is v1.

Deprecated endpoints will include:
```
Deprecation: true
Sunset: 2024-12-31T00:00:00Z
Link: <https://api.dinkhouse.com/v2/tournaments>; rel="successor-version"
```