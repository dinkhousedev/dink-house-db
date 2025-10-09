# Contribution Badge System

## Overview

The badge system provides automatic tier classification for contributions and backers based on contribution amounts. Badges are automatically assigned and updated as contributions are made.

## Badge Tiers

| Badge | Icon | Min Amount | Color Code | Description |
|-------|------|------------|------------|-------------|
| Bronze | 🥉 | $25 | #CD7F32 | Entry-level supporter |
| Silver | 🥈 | $100 | #C0C0C0 | Significant contributor |
| Gold | 🥇 | $250 | #FFD700 | Major benefactor |
| Platinum | 💎 | $1,000 | #E5E4E2 | Elite sponsor |
| Founding Pillar | 👑 | $5,000 | #B3FF00 | Ultimate legacy status |

## Database Schema

### New Columns

#### `contribution_tiers` table
- `badge_tier` - Badge classification for each tier (bronze, silver, gold, platinum, founding_pillar)

#### `backers` table
- `badge_level` - Highest badge tier achieved based on total contributions
- `badge_earned_at` - Timestamp when current badge was earned

#### `founders_wall` table
- `badge_tier` - Badge tier displayed on public founders wall

## Functions

### Calculate Badge Tier
```sql
SELECT crowdfunding.calculate_badge_tier(500.00);
-- Returns: 'gold'
```

### Get Badge Statistics
```sql
SELECT * FROM crowdfunding.get_badge_stats();
```

Returns:
```
badge           | backer_count | total_amount | avg_contribution
----------------|--------------|--------------|------------------
founding_pillar | 2            | 10000.00     | 5000.00
platinum        | 5            | 7500.00      | 1500.00
gold            | 15           | 4500.00      | 300.00
silver          | 30           | 3600.00      | 120.00
bronze          | 50           | 1500.00      | 30.00
```

### Get Backers by Badge
```sql
SELECT * FROM crowdfunding.get_backers_by_badge('platinum');
```

Returns all platinum-level backers with their contribution details.

### Get Badge Tier Information
```sql
SELECT * FROM crowdfunding.get_badge_tier_info();
```

Returns badge metadata including names, colors, icons, and minimum amounts.

## Automatic Updates

### Badge Assignment

Badges are automatically calculated and assigned:

1. **On Initial Contribution**: When a contribution is completed, the tier's badge is recorded
2. **On Backer Update**: When a backer's `total_contributed` changes, their badge level is recalculated
3. **On Founders Wall**: Badge tier is included when entries are created or updated

### Triggers

- `trigger_update_backer_badge` - Updates backer badge when total contributions change
- `trigger_upsert_founders_wall` - Includes badge tier when updating founders wall

## API Usage Examples

### Get All Tiers with Badges
```javascript
const { data: tiers } = await supabase
  .from('contribution_tiers')
  .select('*')
  .order('amount', { ascending: true });

// Returns tiers with badge_tier field
```

### Get Backers by Badge Level
```javascript
const { data: platinumBackers } = await supabase
  .rpc('get_backers_by_badge', { p_badge: 'platinum' });
```

### Get Badge Statistics for Dashboard
```javascript
const { data: stats } = await supabase
  .rpc('get_badge_stats');

// Display badge distribution chart
```

### Get Badge Info for UI
```javascript
const { data: badgeInfo } = await supabase
  .rpc('get_badge_tier_info');

// Use badge_color and badge_icon for UI elements
```

## Frontend Integration

### Display Badge on Founders Wall

```jsx
import { getBadgeColor, getBadgeIcon } from '@/utils/badges';

function FoundersWallEntry({ backer }) {
  return (
    <div className="backer-card">
      <div className="badge" style={{ color: getBadgeColor(backer.badge_tier) }}>
        {getBadgeIcon(backer.badge_tier)} {backer.badge_tier.toUpperCase()}
      </div>
      <h3>{backer.display_name}</h3>
      <p>{backer.location}</p>
      <p className="amount">${backer.total_contributed}</p>
    </div>
  );
}
```

### Badge Utility Functions

```javascript
// utils/badges.js
const BADGE_INFO = {
  bronze: { color: '#CD7F32', icon: '🥉', name: 'Bronze' },
  silver: { color: '#C0C0C0', icon: '🥈', name: 'Silver' },
  gold: { color: '#FFD700', icon: '🥇', name: 'Gold' },
  platinum: { color: '#E5E4E2', icon: '💎', name: 'Platinum' },
  founding_pillar: { color: '#B3FF00', icon: '👑', name: 'Founding Pillar' }
};

export function getBadgeColor(tier) {
  return BADGE_INFO[tier]?.color || '#999';
}

export function getBadgeIcon(tier) {
  return BADGE_INFO[tier]?.icon || '';
}

export function getBadgeName(tier) {
  return BADGE_INFO[tier]?.name || 'Supporter';
}
```

### Badge Progress Component

```jsx
function BadgeProgress({ currentAmount }) {
  const badges = [
    { tier: 'bronze', amount: 25 },
    { tier: 'silver', amount: 100 },
    { tier: 'gold', amount: 250 },
    { tier: 'platinum', amount: 1000 },
    { tier: 'founding_pillar', amount: 5000 }
  ];

  const currentBadge = badges
    .reverse()
    .find(b => currentAmount >= b.amount) || null;

  const nextBadge = badges.find(b => currentAmount < b.amount);

  return (
    <div className="badge-progress">
      {currentBadge && (
        <div className="current-badge">
          {getBadgeIcon(currentBadge.tier)} {getBadgeName(currentBadge.tier)}
        </div>
      )}
      {nextBadge && (
        <div className="next-badge">
          Next: ${nextBadge.amount - currentAmount} to {getBadgeName(nextBadge.tier)}
        </div>
      )}
    </div>
  );
}
```

## Migration

To apply the badge system:

```bash
# Run the migration
psql -d dink_house -f sql/migrations/20251007000000_add_contribution_badges.sql

# Or using Supabase CLI
supabase db push
```

The migration will:
1. Create the badge_tier enum type
2. Add badge columns to relevant tables
3. Backfill existing data with appropriate badges
4. Create triggers for automatic badge updates
5. Add helper functions for badge queries
6. Create indexes for performance

## Testing

### Test Badge Calculation
```sql
-- Test badge calculation
SELECT
    amount,
    crowdfunding.calculate_badge_tier(amount) as badge
FROM (VALUES (10), (25), (100), (250), (1000), (5000)) AS t(amount);
```

### Test Badge Update on Contribution
```sql
-- Simulate a contribution completing
UPDATE crowdfunding.contributions
SET status = 'completed'
WHERE id = 'YOUR_CONTRIBUTION_ID';

-- Check backer badge was updated
SELECT badge_level, badge_earned_at
FROM crowdfunding.backers
WHERE id = 'YOUR_BACKER_ID';
```

### Verify Founders Wall Badge
```sql
SELECT
    display_name,
    badge_tier,
    total_contributed
FROM crowdfunding.founders_wall
ORDER BY total_contributed DESC
LIMIT 10;
```

## Performance Considerations

- Indexes are created on badge columns for efficient queries
- Badge calculation function is marked as IMMUTABLE for query optimization
- Triggers only fire when total_contributed actually changes
- Badge updates are batched within contribution transactions

## Future Enhancements

- **Badge Notifications**: Send email/notification when backer earns new badge
- **Badge Leaderboard**: Public leaderboard showing top contributors by badge
- **Time-Limited Badges**: Special badges for early supporters
- **Custom Badges**: Allow custom badges for special contributions
- **Badge Analytics**: Track badge progression over time
