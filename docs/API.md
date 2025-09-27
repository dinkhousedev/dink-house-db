# Dink House API Documentation

> **Master API Reference** - Last Updated: 2025-09-26
> This document serves as the comprehensive API bible for the Dink House system, continuously updated as development progresses.

## Table of Contents

1. [Overview](#overview)
2. [Authentication System](#authentication-system)
3. [User Types](#user-types)
4. [API Endpoints](#api-endpoints)
5. [Database Schema](#database-schema)
6. [Security](#security)
7. [Development Notes](#development-notes)

---

## Overview

The Dink House API provides a comprehensive backend for managing a pickleball facility, including separate authentication systems for different user types, booking management, and administrative functions.

### Base URLs
- **Local Development**: `http://localhost:3000/api`
- **Database API**: `http://localhost:9002` (Supabase/PostgreSQL)
- **Production**: TBD

### Technology Stack
- **Framework**: Next.js 15 with App Router
- **Database**: PostgreSQL (via Docker)
- **Authentication**: Custom app_auth schema (not Supabase GoTrue)
- **Session Management**: Database-backed sessions in `app_auth.sessions`

---

## Authentication System

### Current Issues (TO BE FIXED)
⚠️ **CRITICAL SECURITY ISSUE**: The current login endpoint does NOT verify passwords properly.
- Accepts ANY password for emails in allowed_emails table
- Creates weak base64 JSON sessions instead of database sessions
- Does not use the proper `app_auth.users` table

### Planned Architecture

The system will use a **multi-table user architecture** to separate different user types:

#### User Types Structure
```
app_auth.user_accounts (Unified Auth Table)
├── user_type: 'admin' → links to → app_auth.admin_users
└── user_type: 'player' → links to → app_auth.players
```

### Authentication Flow

```mermaid
graph TD
    A[User Login] --> B{Check user_accounts}
    B --> C[Identify user_type]
    C --> D{User Type?}
    D -->|Admin| E[Verify against admin_users]
    D -->|Player| F[Verify against players]
    E --> G[Create admin session]
    F --> H[Create player session]
    G --> I[Route to Admin Dashboard]
    H --> J[Route to Player Portal]
```

---

## User Types

### 1. Admin Users (Internal Staff)
**Table**: `app_auth.admin_users`
**Access**: Admin Dashboard
**Roles**:
- `super_admin` - Full system access
- `admin` - Administrative access
- `manager` - Facility management
- `coach` - Coaching staff access

**Registration**: Pre-authorized via `allowed_emails` table

### 2. Players/Customers (Club Members)
**Table**: `app_auth.players` (to be created)
**Access**: Player Portal, Booking System
**Features**:
- Public signup (no pre-authorization needed)
- Membership levels
- Booking capabilities
- Play statistics tracking

---

## API Endpoints

### Authentication Endpoints

#### POST `/api/auth/login`
Authenticate a user and create a session.

**Current Implementation** (INSECURE):
```typescript
// Request
{
  "email": "string",
  "password": "string"  // Currently not verified!
}

// Response
{
  "success": true,
  "user": {
    "id": "uuid",
    "email": "string",
    "first_name": "string",
    "last_name": "string",
    "role": "string"
  }
}
```

**Planned Implementation**:
- Will use `api.login_safe()` database function
- Proper password verification
- Database session creation
- User type identification

#### POST `/api/auth/admin/signup`
Create a new admin user account (requires pre-authorization).

**Request**:
```typescript
{
  "email": "string",      // Must be in allowed_emails
  "password": "string",
  "firstName": "string",
  "lastName": "string"
}
```

**Response**:
```typescript
{
  "success": true,
  "user": {
    "id": "uuid",
    "email": "string",
    "role": "string",
    "user_type": "admin"
  }
}
```

#### POST `/api/auth/player/signup` (TO BE IMPLEMENTED)
Public registration for players/customers.

**Request**:
```typescript
{
  "email": "string",
  "password": "string",
  "firstName": "string",
  "lastName": "string",
  "phone": "string",
  "membershipType": "string"  // basic, premium, vip
}
```

**Response**:
```typescript
{
  "success": true,
  "user": {
    "id": "uuid",
    "email": "string",
    "user_type": "player",
    "membershipType": "string"
  }
}
```

#### POST `/api/auth/signout`
Clear user session and log out.

**Request**: No body required

**Response**:
```typescript
{
  "success": true,
  "message": "Signed out successfully"
}
```

#### POST `/api/auth/check-email`
Check if an email is authorized for admin signup.

**Request**:
```typescript
{
  "email": "string"
}
```

**Response**:
```typescript
{
  "allowed": boolean,
  "firstName": "string | null",
  "lastName": "string | null",
  "role": "string | null"
}
```

### Admin Management Endpoints

#### GET `/api/admin/allowed-emails`
Get list of pre-authorized emails for admin signup.

**Response**:
```typescript
{
  "emails": [
    {
      "id": "uuid",
      "email": "string",
      "first_name": "string",
      "last_name": "string",
      "role": "string",
      "is_active": boolean,
      "used_at": "timestamp | null",
      "created_at": "timestamp"
    }
  ]
}
```

#### POST `/api/admin/allowed-emails`
Add a new email to the allowed list.

**Request**:
```typescript
{
  "email": "string",
  "firstName": "string",
  "lastName": "string",
  "role": "admin | manager | coach"
}
```

### Events Endpoints

#### GET `/api/events`
Get all events.

#### GET `/api/events/:id`
Get specific event by ID.

#### POST `/api/events`
Create a new event.

#### PUT `/api/events/:id`
Update an existing event.

#### DELETE `/api/events/:id`
Delete an event.

---

## Database Schema

### Authentication Schema (`app_auth`)

#### `app_auth.user_accounts`
Canonical identity record shared by every persona (admin, player, guest).

```sql
CREATE TABLE app_auth.user_accounts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email CITEXT UNIQUE,
    password_hash TEXT NOT NULL,
    user_type app_auth.user_type NOT NULL,
    is_active BOOLEAN DEFAULT true,
    is_verified BOOLEAN DEFAULT false,
    last_login TIMESTAMPTZ,
    failed_login_attempts INT DEFAULT 0,
    locked_until TIMESTAMPTZ,
    temporary_expires_at TIMESTAMPTZ,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);
```

#### `app_auth.admin_users`
Profile data for internal staff. `id` mirrors `user_accounts.id` for admins so existing FKs remain valid.

```sql
CREATE TABLE app_auth.admin_users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    account_id UUID NOT NULL UNIQUE REFERENCES app_auth.user_accounts(id) ON DELETE CASCADE,
    username CITEXT UNIQUE NOT NULL,
    first_name TEXT NOT NULL,
    last_name TEXT NOT NULL,
    role app_auth.admin_role NOT NULL DEFAULT 'viewer',
    department TEXT,
    phone TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);
```

#### `app_auth.players`
Member-facing profile tied 1:1 with a `user_account`.

```sql
CREATE TABLE app_auth.players (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    account_id UUID NOT NULL UNIQUE REFERENCES app_auth.user_accounts(id) ON DELETE CASCADE,
    first_name TEXT NOT NULL,
    last_name TEXT NOT NULL,
    display_name TEXT,
    phone TEXT,
    membership_level app_auth.membership_level DEFAULT 'guest',
    membership_started_on DATE,
    membership_expires_on DATE,
    skill_level app_auth.skill_level,
    profile JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);
```

#### `app_auth.guest_users`
Lightweight drop-in profile used for temporary checkout flows.

```sql
CREATE TABLE app_auth.guest_users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    account_id UUID NOT NULL UNIQUE REFERENCES app_auth.user_accounts(id) ON DELETE CASCADE,
    display_name TEXT,
    email CITEXT,
    phone TEXT,
    invited_by_admin UUID REFERENCES app_auth.admin_users(id) ON DELETE SET NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    converted_to_player_at TIMESTAMPTZ,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);
```

#### `app_auth.sessions`
```sql
CREATE TABLE app_auth.sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    account_id UUID NOT NULL REFERENCES app_auth.user_accounts(id) ON DELETE CASCADE,
    user_type app_auth.user_type NOT NULL,
    token_hash TEXT UNIQUE NOT NULL,
    ip_address INET,
    user_agent TEXT,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);
```

#### `app_auth.refresh_tokens`
```sql
CREATE TABLE app_auth.refresh_tokens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    account_id UUID NOT NULL REFERENCES app_auth.user_accounts(id) ON DELETE CASCADE,
    user_type app_auth.user_type NOT NULL,
    token_hash TEXT UNIQUE NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);
```

#### `app_auth.allowed_emails`
```sql
CREATE TABLE app_auth.allowed_emails (
    id UUID PRIMARY KEY,
    email CITEXT UNIQUE NOT NULL,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    role VARCHAR(50),
    is_active BOOLEAN DEFAULT true,
    used_at TIMESTAMP,
    added_by UUID REFERENCES app_auth.admin_users(id),
    used_by UUID REFERENCES app_auth.admin_users(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### Database Functions

#### `api.login_safe(email, password)`
Secure login function that:
- Verifies password using bcrypt
- Checks account status (active, verified, locked)
- Creates database session
- Tracks failed login attempts
- Returns JSON response

#### `verify_password(password, hash)`
Verifies a password against a bcrypt hash.

#### `hash_password(password)`
Creates a bcrypt hash of a password.

#### `app_auth.is_email_allowed(email)`
Checks if an email is in the allowed_emails table.

---

## Security

### Current Security Issues
1. ❌ **No Password Verification**: Login accepts any password
2. ❌ **Weak Sessions**: Using base64 JSON instead of secure tokens
3. ❌ **Mixed User Types**: No separation between admin and customer data
4. ❌ **Development Bypass**: Auto-allows all emails in dev mode

### Planned Security Improvements
1. ✅ Implement proper password verification using bcrypt
2. ✅ Use database-backed sessions with secure tokens
3. ✅ Separate admin and player authentication flows
4. ✅ Remove development bypasses in production
5. ✅ Implement rate limiting on login attempts
6. ✅ Add account lockout after failed attempts

### Session Management
- Sessions stored in database (`app_auth.sessions`)
- HTTP-only cookies for session tokens
- 24-hour session expiry for regular sessions
- 7-day refresh token expiry
- Automatic cleanup of expired sessions

---

## Development Notes

### Environment Variables
```env
# Database Connection
DATABASE_URL=postgresql://postgres:DevPassword123!@localhost:9432/dink_house
NEXT_PUBLIC_SUPABASE_URL=http://localhost:9002
NEXT_PUBLIC_SUPABASE_ANON_KEY=<anon_key>
SUPABASE_SERVICE_ROLE_KEY=<service_key>

# JWT Settings
JWT_SECRET=<secret>
JWT_EXPIRY=3600
```

### Local Database Access
- **PostgreSQL**: `localhost:9432`
- **Supabase Studio**: `localhost:9000`
- **Default Password**: `DevPassword123!`

### Testing Credentials
```
Admin User:
- Email: admin@dinkhouse.com
- Password: DevPassword123!
- Role: super_admin

Test Users:
- editor@dinkhouse.com / DevPassword123!
- viewer@dinkhouse.com / DevPassword123!
```

### Pending Implementation Tasks

#### High Priority
1. [ ] Fix password verification in login endpoint
2. [ ] Implement proper database sessions
3. [ ] Create separate user tables (admin_users, players)
4. [ ] Implement player signup endpoint
5. [ ] Add user_type to session management

#### Medium Priority
1. [ ] Implement password reset functionality
2. [ ] Add email verification for new accounts
3. [ ] Create player dashboard endpoints
4. [ ] Add booking system APIs
5. [ ] Implement membership management

#### Low Priority
1. [ ] Add OAuth providers (Google, Apple)
2. [ ] Implement 2FA for admin accounts
3. [ ] Create audit logging for all actions
4. [ ] Add API rate limiting
5. [ ] Implement webhook system

---

## Version History

### v0.1.0 (2025-09-26)
- Initial API documentation created
- Identified critical security issues in current implementation
- Designed multi-table user architecture
- Planned separation of admin and player authentication

---

## Notes for Developers

This document should be updated whenever:
- New endpoints are added or modified
- Database schema changes
- Authentication flow is updated
- Security improvements are implemented
- New user types or roles are added

Keep this document as the single source of truth for API development.
