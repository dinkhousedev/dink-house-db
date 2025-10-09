# Crowdfunding API Reference

Quick reference for the crowdfunding system API endpoints and database queries.

## REST API Endpoints

### 1. Create Checkout Session

**Endpoint**: `POST /api/stripe/create-checkout`

**Description**: Creates a Stripe checkout session for a contribution tier.

**Request Body**:
```json
{
  "tierId": "uuid",
  "firstName": "John",
  "lastInitial": "S",
  "email": "john@example.com",
  "phone": "555-123-4567",
  "city": "Belton",
  "state": "TX",
  "isPublic": true,
  "showAmount": true
}
```

**Response** (Success):
```json
{
  "success": true,
  "url": "https://checkout.stripe.com/..."
}
```

**Response** (Error):
```json
{
  "success": false,
  "error": "Error message"
}
```

### 2. Stripe Webhook

**Endpoint**: `POST /api/stripe/webhook`

**Description**: Receives Stripe webhook events. Called automatically by Stripe.

**Headers Required**:
- `stripe-signature`: Webhook signature for verification

**Events Handled**:
- `checkout.session.completed` - Payment completed
- `payment_intent.succeeded` - Payment intent succeeded
- `payment_intent.payment_failed` - Payment failed
- `charge.refunded` - Charge refunded

## Supabase Queries

### Fetch Active Campaigns

```sql
SELECT id, name, slug, description, goal_amount, current_amount, backer_count
FROM crowdfunding.campaign_types
WHERE is_active = true
ORDER BY display_order;
```

### Fetch Contribution Tiers for Campaign

```sql
SELECT id, name, amount, description, benefits, current_backers, max_backers
FROM crowdfunding.contribution_tiers
WHERE campaign_type_id = 'campaign-uuid'
  AND is_active = true
  AND (max_backers IS NULL OR current_backers < max_backers)
ORDER BY display_order, amount;
```

### Fetch Founders Wall

```sql
SELECT id, display_name, location, contribution_tier, total_contributed, is_featured
FROM crowdfunding.founders_wall
ORDER BY is_featured DESC, total_contributed DESC;
```

### Get Campaign Progress

```sql
SELECT * FROM crowdfunding.get_campaign_progress('campaign-uuid');
```

### Get Available Tiers

```sql
SELECT * FROM crowdfunding.get_available_tiers('campaign-uuid');
```

## JavaScript/TypeScript Client Examples

### Using Supabase Client

```typescript
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
);

// Fetch campaigns
const { data: campaigns, error } = await supabase
  .from('campaign_types')
  .select('*')
  .eq('is_active', true)
  .order('display_order');

// Fetch tiers for a campaign
const { data: tiers, error } = await supabase
  .from('contribution_tiers')
  .select('*')
  .eq('campaign_type_id', campaignId)
  .eq('is_active', true)
  .order('display_order');

// Fetch founders wall
const { data: founders, error } = await supabase
  .from('founders_wall')
  .select('*')
  .order('is_featured', { ascending: false })
  .order('total_contributed', { ascending: false });
```

### Create Checkout Session

```typescript
const response = await fetch('/api/stripe/create-checkout', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({
    tierId: tier.id,
    firstName: 'John',
    lastInitial: 'S',
    email: 'john@example.com',
    phone: '555-123-4567',
    city: 'Belton',
    state: 'TX',
    isPublic: true,
    showAmount: true,
  }),
});

const data = await response.json();

if (data.success) {
  // Redirect to Stripe Checkout
  window.location.href = data.url;
}
```

## Database Schema Reference

### Table: `crowdfunding.backers`

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| email | CITEXT | Unique email address |
| first_name | VARCHAR(100) | Backer's first name |
| last_initial | VARCHAR(1) | Backer's last initial |
| phone | VARCHAR(30) | Optional phone number |
| city | VARCHAR(100) | Optional city |
| state | VARCHAR(2) | Optional state code |
| stripe_customer_id | TEXT | Stripe customer ID (unique) |
| total_contributed | DECIMAL(10,2) | Total amount contributed |
| contribution_count | INTEGER | Number of contributions |
| created_at | TIMESTAMPTZ | Creation timestamp |
| updated_at | TIMESTAMPTZ | Last update timestamp |

### Table: `crowdfunding.campaign_types`

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| name | VARCHAR(255) | Campaign name |
| slug | VARCHAR(255) | URL-friendly slug (unique) |
| description | TEXT | Campaign description |
| goal_amount | DECIMAL(10,2) | Funding goal |
| current_amount | DECIMAL(10,2) | Current amount raised |
| backer_count | INTEGER | Number of backers |
| display_order | INTEGER | Display order |
| is_active | BOOLEAN | Is campaign active |
| metadata | JSONB | Additional metadata |

### Table: `crowdfunding.contribution_tiers`

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| campaign_type_id | UUID | Foreign key to campaign |
| name | VARCHAR(255) | Tier name |
| amount | DECIMAL(10,2) | Contribution amount |
| description | TEXT | Tier description |
| benefits | JSONB | Array of benefits |
| stripe_price_id | TEXT | Stripe price ID (unique) |
| max_backers | INTEGER | Maximum backers (NULL = unlimited) |
| current_backers | INTEGER | Current backer count |
| display_order | INTEGER | Display order |
| is_active | BOOLEAN | Is tier active |

### Table: `crowdfunding.contributions`

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| backer_id | UUID | Foreign key to backer |
| campaign_type_id | UUID | Foreign key to campaign |
| tier_id | UUID | Foreign key to tier |
| amount | DECIMAL(10,2) | Contribution amount |
| stripe_payment_intent_id | TEXT | Stripe payment intent ID |
| stripe_charge_id | TEXT | Stripe charge ID |
| stripe_checkout_session_id | TEXT | Stripe session ID |
| status | VARCHAR(50) | Status (pending, completed, failed, refunded) |
| payment_method | VARCHAR(50) | Payment method |
| is_public | BOOLEAN | Show on founders wall |
| show_amount | BOOLEAN | Show contribution amount |
| custom_message | TEXT | Optional message |
| created_at | TIMESTAMPTZ | Creation timestamp |
| completed_at | TIMESTAMPTZ | Completion timestamp |
| refunded_at | TIMESTAMPTZ | Refund timestamp |

### Table: `crowdfunding.backer_benefits`

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| backer_id | UUID | Foreign key to backer |
| contribution_id | UUID | Foreign key to contribution |
| benefit_type | VARCHAR(100) | Type of benefit |
| benefit_details | JSONB | Benefit details |
| is_active | BOOLEAN | Is benefit active |
| activated_at | TIMESTAMPTZ | Activation timestamp |
| expires_at | TIMESTAMPTZ | Expiration (NULL for lifetime) |
| redeemed_count | INTEGER | Number of times redeemed |

### Table: `crowdfunding.court_sponsors`

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| backer_id | UUID | Foreign key to backer |
| contribution_id | UUID | Foreign key to contribution |
| sponsor_name | VARCHAR(255) | Sponsor display name |
| sponsor_type | VARCHAR(50) | Type (individual, business, memorial) |
| logo_url | TEXT | Optional logo URL |
| court_number | INTEGER | Court number |
| sponsorship_start | DATE | Start date |
| sponsorship_end | DATE | End date |
| is_active | BOOLEAN | Is sponsorship active |

### Table: `crowdfunding.founders_wall`

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| backer_id | UUID | Foreign key to backer (unique) |
| display_name | VARCHAR(255) | Display name (First L. format) |
| location | VARCHAR(255) | City, State format |
| contribution_tier | VARCHAR(255) | Tier name |
| total_contributed | DECIMAL(10,2) | Total amount contributed |
| is_featured | BOOLEAN | Featured (for $1000+) |
| display_order | INTEGER | Display order |

## Benefit Types

Available benefit types in `crowdfunding.backer_benefits`:

- `lifetime_dink_board` - Lifetime dink board access
- `lifetime_ball_machine` - Lifetime ball machine access
- `founding_membership` - Founding member status
- `court_sponsor` - Court sponsorship
- `pro_shop_discount` - Pro shop discount
- `priority_booking` - Priority court booking
- `name_on_wall` - Name on founders wall
- `free_lessons` - Free lessons/clinics
- `vip_events` - VIP event access
- `custom` - Custom benefit

## Webhook Event Flow

### checkout.session.completed

1. Verify webhook signature
2. Update contribution status to 'completed'
3. Add stripe_payment_intent_id and stripe_checkout_session_id
4. Set completed_at timestamp
5. Create backer_benefits from tier benefits
6. Create court_sponsor entry if amount >= $1000
7. Trigger updates campaign totals (automatic)
8. Trigger updates founders_wall (automatic)

### charge.refunded

1. Verify webhook signature
2. Update contribution status to 'refunded'
3. Set refunded_at timestamp
4. Deactivate all related backer_benefits
5. Deactivate related court_sponsor entry
6. Trigger reverses campaign totals (automatic)
7. Trigger updates founders_wall (automatic)

## Common Queries

### Get Top Contributors

```sql
SELECT display_name, location, total_contributed
FROM crowdfunding.founders_wall
ORDER BY total_contributed DESC
LIMIT 10;
```

### Get Campaign Statistics

```sql
SELECT
  ct.name,
  ct.goal_amount,
  ct.current_amount,
  ct.backer_count,
  ROUND((ct.current_amount / ct.goal_amount * 100)::NUMERIC, 2) AS percentage_funded,
  COUNT(DISTINCT tier.id) AS tier_count
FROM crowdfunding.campaign_types ct
LEFT JOIN crowdfunding.contribution_tiers tier ON tier.campaign_type_id = ct.id
WHERE ct.is_active = true
GROUP BY ct.id, ct.name, ct.goal_amount, ct.current_amount, ct.backer_count;
```

### Get Recent Contributions

```sql
SELECT
  b.first_name || ' ' || b.last_initial || '.' AS name,
  b.city || ', ' || b.state AS location,
  c.amount,
  ct.name AS campaign_name,
  tier.name AS tier_name,
  c.completed_at
FROM crowdfunding.contributions c
JOIN crowdfunding.backers b ON b.id = c.backer_id
JOIN crowdfunding.campaign_types ct ON ct.id = c.campaign_type_id
LEFT JOIN crowdfunding.contribution_tiers tier ON tier.id = c.tier_id
WHERE c.status = 'completed' AND c.is_public = true
ORDER BY c.completed_at DESC
LIMIT 20;
```

### Check Tier Availability

```sql
SELECT
  name,
  amount,
  max_backers,
  current_backers,
  CASE
    WHEN max_backers IS NULL THEN 'Unlimited'
    WHEN current_backers >= max_backers THEN 'Full'
    ELSE CAST(max_backers - current_backers AS TEXT) || ' remaining'
  END AS availability
FROM crowdfunding.contribution_tiers
WHERE campaign_type_id = 'campaign-uuid'
  AND is_active = true
ORDER BY amount;
```

## Testing Commands

### Stripe CLI Testing

```bash
# Trigger test webhook for successful payment
stripe trigger checkout.session.completed

# Trigger test webhook for failed payment
stripe trigger payment_intent.payment_failed

# Trigger test webhook for refund
stripe trigger charge.refunded

# Listen to all webhook events
stripe listen --print-json
```

### Manual Database Cleanup (Development Only)

```sql
-- Reset campaign totals (use with caution)
UPDATE crowdfunding.campaign_types
SET current_amount = 0, backer_count = 0;

-- Clear all contributions
DELETE FROM crowdfunding.contributions;

-- Clear founders wall
DELETE FROM crowdfunding.founders_wall;

-- Clear test backers
DELETE FROM crowdfunding.backers WHERE email LIKE '%test%';
```
