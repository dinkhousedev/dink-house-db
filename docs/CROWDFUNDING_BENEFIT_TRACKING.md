# Crowdfunding Benefit Tracking System

Complete guide to tracking, managing, and fulfilling crowdfunding perks and benefits.

## Table of Contents
1. [Overview](#overview)
2. [Database Schema](#database-schema)
3. [API Endpoints](#api-endpoints)
4. [Admin Dashboard](#admin-dashboard)
5. [Workflows](#workflows)
6. [Usage Examples](#usage-examples)

---

## Overview

The benefit tracking system provides comprehensive management of crowdfunding perks from allocation to fulfillment. It handles both consumable benefits (sessions, hours) and non-consumable benefits (discounts, recognition items).

### Key Features
- ✅ Automatic benefit allocation when donations complete
- ✅ Track usage and remaining quantities
- ✅ Expiration date management
- ✅ Staff verification and notes
- ✅ Recognition item workflow (pending → ordered → installed → verified)
- ✅ Usage history and audit trail
- ✅ Admin dashboard for fulfillment tracking

---

## Database Schema

### Core Tables

#### `benefit_allocations`
Tracks what benefits each backer has and their current status.

```sql
CREATE TABLE crowdfunding.benefit_allocations (
    id UUID PRIMARY KEY,
    backer_id UUID REFERENCES crowdfunding.backers(id),
    contribution_id UUID REFERENCES crowdfunding.contributions(id),
    tier_id UUID REFERENCES crowdfunding.contribution_tiers(id),

    -- Benefit details
    benefit_type VARCHAR(100),  -- 'court_time_hours', 'dink_board_sessions', etc.
    benefit_name TEXT,

    -- Quantity tracking
    total_allocated INTEGER,    -- NULL for unlimited/non-consumable
    total_used INTEGER DEFAULT 0,
    remaining INTEGER,          -- Auto-calculated

    -- Time constraints
    valid_from DATE DEFAULT CURRENT_DATE,
    valid_until DATE,           -- NULL for no expiration

    -- Fulfillment tracking (NEW)
    fulfillment_status VARCHAR(50) DEFAULT 'allocated',
    fulfilled_by UUID,
    fulfilled_at TIMESTAMP WITH TIME ZONE,
    fulfillment_notes TEXT,

    -- Status
    is_active BOOLEAN DEFAULT true,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
```

**Benefit Types:**
- `court_time_hours` - Court rental time
- `dink_board_sessions` - Dink board practice sessions
- `ball_machine_sessions` - Ball machine sessions
- `pro_shop_discount` - Pro shop discounts (percentage stored in metadata)
- `membership_months` - Membership duration
- `private_lessons` - Private coaching sessions
- `guest_passes` - Guest access passes
- `priority_booking` - Priority court booking access
- `dink_clinics` - Clinic sessions
- `recognition` - Plaques, wall engravings, etc.
- `custom` - Other custom benefits

**Fulfillment Statuses:**
- `allocated` - Benefit assigned but not started
- `in_progress` - Staff is working on fulfillment
- `fulfilled` - Benefit fully delivered
- `expired` - Benefit expired before use
- `cancelled` - Benefit cancelled (e.g., refund)

#### `benefit_usage_log`
Records every redemption for audit trail.

```sql
CREATE TABLE crowdfunding.benefit_usage_log (
    id UUID PRIMARY KEY,
    allocation_id UUID REFERENCES crowdfunding.benefit_allocations(id),
    backer_id UUID REFERENCES crowdfunding.backers(id),

    -- Usage details
    quantity_used INTEGER DEFAULT 1,
    usage_date DATE DEFAULT CURRENT_DATE,
    usage_time TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Context
    used_for TEXT,              -- "Court 3 booking", "Ball machine reservation"
    staff_verified BOOLEAN DEFAULT false,
    staff_id UUID,
    notes TEXT,
    metadata JSONB DEFAULT '{}',

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
```

#### `recognition_items`
Tracks physical recognition items from order to installation.

```sql
CREATE TABLE crowdfunding.recognition_items (
    id UUID PRIMARY KEY,
    allocation_id UUID REFERENCES crowdfunding.benefit_allocations(id),
    backer_id UUID REFERENCES crowdfunding.backers(id),

    -- Item details
    item_type VARCHAR(50),      -- 'plaque', 'wall_engraving', 'court_sign', etc.
    item_description TEXT,
    display_text VARCHAR(500),  -- What will be engraved/displayed
    custom_message TEXT,

    -- Fulfillment tracking
    status VARCHAR(50) DEFAULT 'pending',
    order_date DATE,
    ordered_by UUID,
    vendor VARCHAR(255),
    order_number VARCHAR(100),

    -- Production tracking
    production_started DATE,
    expected_completion DATE,
    actual_completion DATE,

    -- Installation tracking
    installation_date DATE,
    installed_by UUID,
    installation_location TEXT,
    installation_photo_url TEXT,

    -- Verification
    verified_by UUID,
    verified_at TIMESTAMP WITH TIME ZONE,

    -- Cost tracking
    estimated_cost DECIMAL(10, 2),
    actual_cost DECIMAL(10, 2),

    notes TEXT,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
```

**Item Types:**
- `plaque` - Donor plaques
- `wall_engraving` - Wall engravings
- `court_sign` - Court signage
- `brick_paver` - Brick pavers
- `donor_plaque` - Donor recognition plaques
- `custom` - Other custom items

**Item Statuses:**
- `pending` - Awaiting order
- `ordered` - Order placed with vendor
- `in_production` - Being manufactured
- `received` - Received from vendor
- `installed` - Installed at facility
- `verified` - Installation verified and complete
- `cancelled` - Order cancelled

### Views

#### `v_pending_fulfillment`
Shows all benefits requiring staff action, sorted by urgency.

```sql
SELECT
    ba.id AS allocation_id,
    b.email, b.first_name, b.last_initial, b.phone,
    ba.benefit_type, ba.benefit_name,
    ba.total_allocated, ba.remaining,
    ba.valid_until, ba.fulfillment_status,
    ct.name AS tier_name,
    c.amount AS contribution_amount,
    CASE
        WHEN ba.valid_until IS NOT NULL
        THEN ba.valid_until - CURRENT_DATE
        ELSE NULL
    END AS days_until_expiration
FROM crowdfunding.benefit_allocations ba
JOIN crowdfunding.backers b ON ba.backer_id = b.id
JOIN crowdfunding.contributions c ON ba.contribution_id = c.id
JOIN crowdfunding.contribution_tiers ct ON ba.tier_id = ct.id
WHERE ba.fulfillment_status IN ('allocated', 'in_progress')
    AND ba.is_active = true
    AND (ba.valid_until IS NULL OR ba.valid_until >= CURRENT_DATE)
ORDER BY days_until_expiration ASC NULLS LAST, ba.created_at ASC;
```

#### `v_active_backer_benefits`
Shows all active benefits available for redemption.

#### `v_backer_benefit_summary`
Summarizes remaining benefits by backer.

#### `v_pending_recognition_items`
Shows recognition items needing action.

#### `v_fulfillment_summary`
Statistics by benefit type.

---

## API Endpoints

### Benefit Management

#### Get Backer's Benefits
```http
GET /api/crowdfunding/backer/:backerId/benefits
```

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "id": "uuid",
      "backer_id": "uuid",
      "email": "john@example.com",
      "first_name": "John",
      "last_initial": "S",
      "benefit_type": "court_time_hours",
      "benefit_name": "10 hours of court time",
      "total_allocated": 10,
      "total_used": 3,
      "remaining": 7,
      "valid_until": "2025-12-31",
      "is_valid": true
    }
  ]
}
```

#### Redeem Benefit
```http
POST /api/crowdfunding/benefits/redeem
Content-Type: application/json

{
  "allocationId": "uuid",
  "backerId": "uuid",
  "quantityUsed": 2,
  "usedFor": "Court 3 reservation - 2pm-4pm",
  "notes": "Birthday event",
  "staffId": "uuid",
  "staffVerified": true
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "usageLog": {
      "id": "uuid",
      "quantity_used": 2,
      "used_for": "Court 3 reservation - 2pm-4pm",
      "staff_verified": true,
      "created_at": "2025-10-04T12:00:00Z"
    },
    "updatedAllocation": {
      "remaining": 5,
      "total_used": 5
    }
  },
  "message": "Benefit redeemed successfully"
}
```

#### Get Usage History
```http
GET /api/crowdfunding/benefits/usage-history/:allocationId
```

#### Update Benefit Status
```http
PATCH /api/crowdfunding/benefits/:allocationId/status
Content-Type: application/json

{
  "status": "fulfilled",
  "staffId": "uuid",
  "notes": "All sessions completed"
}
```

#### Get Pending Benefits
```http
GET /api/crowdfunding/benefits/pending?benefitType=court_time_hours
```

#### Get Fulfillment Summary
```http
GET /api/crowdfunding/benefits/summary
```

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "benefit_type": "court_time_hours",
      "total_allocations": 45,
      "pending_count": 12,
      "in_progress_count": 8,
      "fulfilled_count": 23,
      "expired_count": 2,
      "total_units_allocated": 450,
      "total_units_used": 287,
      "total_units_remaining": 163
    }
  ]
}
```

### Recognition Items

#### Get Recognition Items
```http
GET /api/crowdfunding/recognition-items?status=pending
```

#### Get Pending Recognition Items
```http
GET /api/crowdfunding/recognition-items/pending
```

#### Update Recognition Item
```http
PATCH /api/crowdfunding/recognition-items/:itemId
Content-Type: application/json

{
  "vendor": "ABC Engraving",
  "order_number": "ORD-12345",
  "expected_completion": "2025-11-15",
  "actual_cost": 125.00,
  "notes": "Rush order placed"
}
```

#### Update Recognition Item Status
```http
PATCH /api/crowdfunding/recognition-items/:itemId/status
Content-Type: application/json

{
  "status": "ordered",
  "staffId": "uuid",
  "notes": "Ordered from ABC Engraving"
}
```

**Status Workflow:**
1. `pending` → `ordered` (sets order_date, ordered_by)
2. `ordered` → `in_production` (sets production_started)
3. `in_production` → `received`
4. `received` → `installed` (sets installation_date, installed_by)
5. `installed` → `verified` (sets verified_at, verified_by, marks benefit as fulfilled)

### Backer Search

#### Search Backer by Email
```http
GET /api/crowdfunding/backers/search?email=john@example.com
```

---

## Admin Dashboard

### Pages

#### `/dashboard/crowdfunding/benefits`
**Benefit Fulfillment Dashboard**
- Summary cards by benefit type
- Filter by benefit type
- Search by backer name/email
- View pending benefits sorted by expiration
- Update fulfillment status
- View benefit details

#### `/dashboard/crowdfunding/recognition`
**Recognition Items Management**
- Status workflow cards (pending → verified)
- Filter by status
- Track vendor orders
- Monitor production progress
- Record installation details
- Upload installation photos
- Verify completion

#### `/dashboard/crowdfunding/redeem`
**Benefit Redemption Tool**
- Search backers by email
- View all available benefits
- Quick redemption interface
- Real-time quantity tracking
- Usage history display
- Staff verification

---

## Workflows

### 1. Automatic Benefit Allocation

When a contribution is completed:

1. **Stripe webhook** receives `checkout.session.completed`
2. **Contribution status** updated to `'completed'`
3. **Trigger** `auto_allocate_backer_benefits()` fires
4. **Parses tier benefits** from JSONB array
5. **Creates allocations** in `benefit_allocations` table:
   - Extracts quantities from text (e.g., "10 hours" → 10)
   - Sets expiration dates for time-limited benefits
   - Determines benefit type from text patterns
6. **For recognition benefits**, creates entry in `recognition_items` table

### 2. Benefit Redemption Workflow

**At the Front Desk:**

1. Staff opens redemption tool (`/dashboard/crowdfunding/redeem`)
2. Enters backer's email address
3. System displays all available benefits
4. Staff selects benefit to redeem
5. Enters:
   - Quantity used
   - What it was used for (e.g., "Court 3 - 2pm-4pm")
   - Optional notes
   - Staff verification checkbox
6. Clicks "Redeem Benefit"
7. **System automatically:**
   - Creates usage log entry
   - Updates `total_used` and `remaining`
   - Marks as `fulfilled` if fully consumed
   - Updates `fulfillment_status` if expired

### 3. Recognition Item Workflow

**Plaque/Engraving Order Process:**

1. **Pending** → Staff reviews new recognition items
   - View backer details
   - Review display text
   - Set vendor and estimated cost

2. **Ordered** → Place order with vendor
   - Record vendor name
   - Record order number
   - Set expected completion date
   - Status auto-updates order_date and ordered_by

3. **In Production** → Vendor is manufacturing
   - Track production start date
   - Monitor expected completion

4. **Received** → Item delivered
   - Record actual cost
   - Verify item matches order

5. **Installed** → Item installed at facility
   - Record installation location
   - Upload installation photo
   - Record installed_by and installation_date

6. **Verified** → Final verification
   - Staff verifies installation
   - System automatically marks benefit allocation as `fulfilled`
   - Records verified_by and verified_at

---

## Usage Examples

### Example 1: Court Time Redemption

**Scenario:** John S. donated $100 and received 10 hours of court time. He wants to use 2 hours today.

```javascript
// 1. Staff searches for backer
const backerResponse = await fetch(
  '/api/crowdfunding/backers/search?email=john@example.com'
);
const { data: backer } = await backerResponse.json();

// 2. Get backer's benefits
const benefitsResponse = await fetch(
  `/api/crowdfunding/backer/${backer.id}/benefits`
);
const { data: benefits } = await benefitsResponse.json();

// 3. Find court time benefit
const courtTime = benefits.find(b => b.benefit_type === 'court_time_hours');
// courtTime.remaining = 10

// 4. Redeem 2 hours
await fetch('/api/crowdfunding/benefits/redeem', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    allocationId: courtTime.id,
    backerId: backer.id,
    quantityUsed: 2,
    usedFor: 'Court 3 - Friday 2pm-4pm',
    notes: 'Birthday event with friends',
    staffId: currentUser.id,
    staffVerified: true
  })
});

// 5. Updated remaining: 8 hours
```

### Example 2: Plaque Order

**Scenario:** Sarah D. donated $1,000 and gets a donor plaque. Track from order to installation.

```javascript
// 1. Get pending recognition items
const response = await fetch('/api/crowdfunding/recognition-items/pending');
const { data: items } = await response.json();

// 2. Find Sarah's plaque
const sarahPlaque = items.find(i =>
  i.backer.email === 'sarah@example.com' && i.item_type === 'plaque'
);

// 3. Place order with vendor
await fetch(`/api/crowdfunding/recognition-items/${sarahPlaque.id}`, {
  method: 'PATCH',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    vendor: 'Premium Engraving Co.',
    order_number: 'PE-2025-10-001',
    expected_completion: '2025-11-15',
    estimated_cost: 150.00
  })
});

// 4. Update status to ordered
await fetch(`/api/crowdfunding/recognition-items/${sarahPlaque.id}/status`, {
  method: 'PATCH',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    status: 'ordered',
    staffId: currentUser.id,
    notes: 'Rush order for grand opening'
  })
});

// ... Later: production → received → installed → verified
// When status changes to 'verified', benefit allocation automatically
// updates to fulfillment_status: 'fulfilled'
```

### Example 3: Monthly Fulfillment Report

```sql
-- Get summary of benefit fulfillment for the month
SELECT
    benefit_type,
    COUNT(*) as total_benefits,
    SUM(CASE WHEN fulfillment_status = 'fulfilled' THEN 1 ELSE 0 END) as fulfilled_count,
    SUM(total_allocated) as total_units_allocated,
    SUM(total_used) as total_units_redeemed,
    SUM(remaining) as total_units_remaining
FROM crowdfunding.benefit_allocations
WHERE created_at >= DATE_TRUNC('month', CURRENT_DATE)
GROUP BY benefit_type
ORDER BY total_benefits DESC;
```

---

## Migration Instructions

### Running the Migration

```bash
# Apply the new migration
psql <connection-string> -f dink-house-db/supabase/migrations/20251004070000_benefit_fulfillment_tracking.sql

# Verify tables created
psql <connection-string> -c "
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'crowdfunding'
AND table_name IN ('benefit_allocations', 'recognition_items');"
```

### Post-Migration Checks

```sql
-- Check that new columns exist
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'crowdfunding'
AND table_name = 'benefit_allocations'
AND column_name IN ('fulfillment_status', 'fulfilled_by', 'fulfilled_at');

-- Verify triggers
SELECT trigger_name
FROM information_schema.triggers
WHERE event_object_schema = 'crowdfunding'
AND event_object_table IN ('benefit_allocations', 'recognition_items');

-- Check views
SELECT table_name
FROM information_schema.views
WHERE table_schema = 'crowdfunding'
AND table_name LIKE 'v_%';
```

---

## Troubleshooting

### Issue: Benefits Not Auto-Allocating

**Check:**
1. Verify contribution status is `'completed'`
2. Check tier has benefits in JSONB array
3. Review trigger `auto_allocate_backer_benefits` exists
4. Check database logs for trigger errors

```sql
-- Test trigger manually
UPDATE crowdfunding.contributions
SET status = 'completed'
WHERE id = 'test-contribution-id';

-- Check allocations created
SELECT * FROM crowdfunding.benefit_allocations
WHERE contribution_id = 'test-contribution-id';
```

### Issue: Remaining Quantity Not Updating

**Check:**
1. Verify `trigger_log_benefit_usage` exists
2. Check `benefit_usage_log` entries created
3. Review `update_benefit_remaining()` function

```sql
-- Check usage log
SELECT * FROM crowdfunding.benefit_usage_log
WHERE allocation_id = 'allocation-id'
ORDER BY created_at DESC;

-- Manually recalculate
UPDATE crowdfunding.benefit_allocations
SET total_used = (
    SELECT COALESCE(SUM(quantity_used), 0)
    FROM crowdfunding.benefit_usage_log
    WHERE allocation_id = benefit_allocations.id
)
WHERE id = 'allocation-id';
```

### Issue: Recognition Items Not Creating

**Check:**
1. Verify benefit_type is `'recognition'`
2. Check trigger `auto_create_recognition_item` exists
3. Review benefit_name text patterns

```sql
-- Check recognition benefits
SELECT * FROM crowdfunding.benefit_allocations
WHERE benefit_type = 'recognition'
AND id NOT IN (SELECT allocation_id FROM crowdfunding.recognition_items);
```

---

## Best Practices

### For Staff

1. **Always verify redemptions** - Check email and confirm identity
2. **Be specific in "Used For"** - Include court number, date, time
3. **Add notes for unusual cases** - Document special circumstances
4. **Check expiration dates** - Warn backers about upcoming expirations
5. **Photo documentation** - Always upload photos for recognition items

### For Administrators

1. **Monitor pending benefits** - Check dashboard weekly
2. **Track expiring benefits** - Send reminders 30 days before expiration
3. **Review fulfillment summary** - Monthly reports on benefit usage
4. **Vendor relationships** - Maintain vendor contact info in metadata
5. **Audit trail** - Regularly review usage logs for discrepancies

### For Developers

1. **Always use service role** - Client should never have direct DB access
2. **Validate quantities** - Check remaining before redemption
3. **Handle edge cases** - Expired benefits, overage attempts
4. **Log all actions** - Maintain complete audit trail
5. **Test workflows** - Verify trigger chains work correctly

---

## Future Enhancements

### Potential Features

- [ ] Email notifications when benefits allocated
- [ ] SMS reminders for expiring benefits
- [ ] QR codes for quick redemption
- [ ] Mobile app for backers to view benefits
- [ ] Automated vendor ordering integration
- [ ] Photo gallery for recognition items
- [ ] Analytics dashboard with charts
- [ ] Export reports (PDF, CSV)
- [ ] Bulk benefit operations
- [ ] Benefit transfer/gifting

---

## Support

For questions or issues:
1. Check this documentation
2. Review API error messages
3. Check database logs
4. Review Supabase Studio for RLS issues
5. Consult CROWDFUNDING_API_REFERENCE.md
