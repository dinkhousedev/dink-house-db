# Badge System API Usage

## Getting User Badge for Profile Display

### Option 1: Get Badge Info for Specific User

```javascript
// Get badge info with image URL for a user profile
const { data: badgeInfo } = await supabase
  .rpc('get_backer_badge_info', { p_backer_id: userId });

// badgeInfo contains:
// {
//   badge_tier: 'gold',
//   badge_name: 'Gold Benefactor',
//   badge_color: '#FFD700',
//   badge_icon: '🥇',
//   badge_image_url: 'https://wchxzbuuwssrnaxshseu.supabase.co/storage/v1/object/public/dink-files/gold_badge.png',
//   total_contributed: 250.00,
//   badge_earned_at: '2025-10-07T12:00:00Z'
// }
```

### Option 2: Get Badge from Backers Table

```javascript
// Query backer directly
const { data: backer } = await supabase
  .from('backers')
  .select('badge_level, total_contributed, badge_earned_at')
  .eq('id', userId)
  .single();

// Then get badge details
const { data: badges } = await supabase
  .rpc('get_badge_tier_info');

const userBadge = badges.find(b => b.badge === backer.badge_level);
```

## React Component Example

### Simple Badge Display

```jsx
import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';

export function UserBadge({ userId }) {
  const [badge, setBadge] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function loadBadge() {
      const { data } = await supabase
        .rpc('get_backer_badge_info', { p_backer_id: userId });

      if (data && data.length > 0) {
        setBadge(data[0]);
      }
      setLoading(false);
    }

    loadBadge();
  }, [userId]);

  if (loading) return <div>Loading...</div>;
  if (!badge || !badge.badge_tier) return null;

  return (
    <div className="flex items-center gap-2">
      {badge.badge_image_url ? (
        <img
          src={badge.badge_image_url}
          alt={badge.badge_name}
          className="w-8 h-8 object-contain"
        />
      ) : (
        <span className="text-2xl">{badge.badge_icon}</span>
      )}
      <span
        className="font-semibold"
        style={{ color: badge.badge_color }}
      >
        {badge.badge_name}
      </span>
    </div>
  );
}
```

### Badge with Tooltip

```jsx
import { Tooltip } from '@heroui/react';

export function UserBadgeWithTooltip({ userId }) {
  const [badge, setBadge] = useState(null);

  useEffect(() => {
    async function loadBadge() {
      const { data } = await supabase
        .rpc('get_backer_badge_info', { p_backer_id: userId });

      if (data?.[0]) setBadge(data[0]);
    }
    loadBadge();
  }, [userId]);

  if (!badge?.badge_tier) return null;

  return (
    <Tooltip content={
      <div className="p-2">
        <p className="font-bold">{badge.badge_name}</p>
        <p className="text-sm">Total: ${badge.total_contributed}</p>
        <p className="text-xs text-gray-400">
          Earned {new Date(badge.badge_earned_at).toLocaleDateString()}
        </p>
      </div>
    }>
      <div className="inline-flex items-center cursor-help">
        <img
          src={badge.badge_image_url}
          alt={badge.badge_name}
          className="w-6 h-6"
        />
      </div>
    </Tooltip>
  );
}
```

### Compact Profile Badge

```jsx
export function ProfileBadge({ userId, size = 'md' }) {
  const [badge, setBadge] = useState(null);

  useEffect(() => {
    async function loadBadge() {
      const { data } = await supabase
        .rpc('get_backer_badge_info', { p_backer_id: userId });
      if (data?.[0]) setBadge(data[0]);
    }
    loadBadge();
  }, [userId]);

  if (!badge?.badge_image_url) return null;

  const sizeClasses = {
    sm: 'w-4 h-4',
    md: 'w-6 h-6',
    lg: 'w-8 h-8',
    xl: 'w-12 h-12'
  };

  return (
    <img
      src={badge.badge_image_url}
      alt={badge.badge_name}
      className={`${sizeClasses[size]} object-contain`}
      title={`${badge.badge_name} - $${badge.total_contributed}`}
    />
  );
}
```

## Usage in Profile Component

```jsx
function UserProfile({ user }) {
  return (
    <div className="profile-card">
      <div className="flex items-center gap-3">
        <img
          src={user.avatar_url}
          alt={user.name}
          className="w-16 h-16 rounded-full"
        />
        <div>
          <div className="flex items-center gap-2">
            <h2 className="text-xl font-bold">{user.name}</h2>
            <ProfileBadge userId={user.id} size="md" />
          </div>
          <p className="text-gray-600">{user.email}</p>
        </div>
      </div>

      {/* Full badge details */}
      <div className="mt-4">
        <UserBadge userId={user.id} />
      </div>
    </div>
  );
}
```

## Badge Progress Component

```jsx
function BadgeProgress({ currentAmount }) {
  const [badges, setBadges] = useState([]);
  const [currentBadge, setCurrentBadge] = useState(null);
  const [nextBadge, setNextBadge] = useState(null);

  useEffect(() => {
    async function loadBadges() {
      const { data } = await supabase.rpc('get_badge_tier_info');

      if (data) {
        setBadges(data);

        // Find current and next badge
        const sorted = [...data].sort((a, b) => b.min_amount - a.min_amount);
        const current = sorted.find(b => currentAmount >= b.min_amount);
        const next = data.find(b => currentAmount < b.min_amount);

        setCurrentBadge(current);
        setNextBadge(next);
      }
    }
    loadBadges();
  }, [currentAmount]);

  return (
    <div className="badge-progress">
      {currentBadge && (
        <div className="current-badge mb-4">
          <p className="text-sm text-gray-600">Current Badge</p>
          <div className="flex items-center gap-2 mt-1">
            {currentBadge.badge_image_url && (
              <img
                src={currentBadge.badge_image_url}
                alt={currentBadge.badge_name}
                className="w-8 h-8"
              />
            )}
            <span className="font-bold">{currentBadge.badge_name}</span>
          </div>
        </div>
      )}

      {nextBadge && (
        <div className="next-badge">
          <p className="text-sm text-gray-600">Next Badge</p>
          <div className="flex items-center gap-2 mt-1">
            {nextBadge.badge_image_url && (
              <img
                src={nextBadge.badge_image_url}
                alt={nextBadge.badge_name}
                className="w-6 h-6 opacity-50"
              />
            )}
            <span className="text-sm">
              ${(nextBadge.min_amount - currentAmount).toFixed(2)} to {nextBadge.badge_name}
            </span>
          </div>

          {/* Progress bar */}
          <div className="mt-2 bg-gray-200 rounded-full h-2">
            <div
              className="bg-athletic h-2 rounded-full transition-all"
              style={{
                width: `${(currentAmount / nextBadge.min_amount) * 100}%`
              }}
            />
          </div>
        </div>
      )}
    </div>
  );
}
```

## Founders Wall with Badges

```jsx
function FoundersWall() {
  const [founders, setFounders] = useState([]);

  useEffect(() => {
    async function loadFounders() {
      const { data } = await supabase
        .from('founders_wall')
        .select('*')
        .order('total_contributed', { ascending: false });

      setFounders(data);
    }
    loadFounders();
  }, []);

  // Get badge info for display
  const [badgeInfo, setBadgeInfo] = useState({});

  useEffect(() => {
    async function loadBadgeInfo() {
      const { data } = await supabase.rpc('get_badge_tier_info');
      const info = {};
      data.forEach(b => {
        info[b.badge] = b;
      });
      setBadgeInfo(info);
    }
    loadBadgeInfo();
  }, []);

  return (
    <div className="founders-grid grid grid-cols-1 md:grid-cols-3 gap-4">
      {founders.map((founder) => {
        const badge = badgeInfo[founder.badge_tier];

        return (
          <div key={founder.id} className="founder-card p-4 border rounded-lg">
            <div className="flex items-center justify-between mb-2">
              <h3 className="font-bold">{founder.display_name}</h3>
              {badge?.badge_image_url && (
                <img
                  src={badge.badge_image_url}
                  alt={badge.badge_name}
                  className="w-6 h-6"
                />
              )}
            </div>
            <p className="text-sm text-gray-600">{founder.location}</p>
            <p className="text-lg font-semibold mt-2">
              ${founder.total_contributed}
            </p>
            {badge && (
              <p
                className="text-xs font-medium mt-1"
                style={{ color: badge.badge_color }}
              >
                {badge.badge_name}
              </p>
            )}
          </div>
        );
      })}
    </div>
  );
}
```

## Automatic Badge Updates

Badges are automatically updated when:
- A contribution is completed
- A backer's `total_contributed` changes
- The founders wall is updated

No manual badge assignment needed!

## Testing in Supabase Studio

You can test badge queries directly in the SQL Editor:

```sql
-- Get all badge info
SELECT * FROM crowdfunding.get_badge_tier_info();

-- Get badge for specific user
SELECT * FROM crowdfunding.get_backer_badge_info('USER_ID_HERE');

-- Get badge statistics
SELECT * FROM crowdfunding.get_badge_stats();

-- Check all backers with badges
SELECT
  first_name || ' ' || last_initial || '.' as name,
  badge_level,
  total_contributed
FROM crowdfunding.backers
WHERE badge_level IS NOT NULL;
```
