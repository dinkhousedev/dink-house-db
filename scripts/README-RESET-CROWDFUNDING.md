# Crowdfunding Reset Script

This script completely erases all crowdfunding data from both your database and Stripe account to allow for fresh testing.

## ⚠️ WARNING

**This operation is IRREVERSIBLE!** All crowdfunding data will be permanently deleted.

Use this script only in development/testing environments or when you're absolutely certain you want to start fresh.

## Prerequisites

Ensure the following environment variables are set in `dink-house-db/.env.local`:

```bash
SUPABASE_URL=your_supabase_url
SUPABASE_SERVICE_KEY=your_service_role_key
STRIPE_SECRET_KEY=your_stripe_secret_key
```

## Usage

### Quick Start

```bash
cd dink-house-db

# Dry run to see what would be deleted (recommended first step)
npm run crowdfunding:reset:dry

# Reset everything (DB + Stripe)
npm run crowdfunding:reset

# Reset database only
npm run crowdfunding:reset:db

# Reset Stripe only
npm run crowdfunding:reset:stripe
```

### Command Line Options

```bash
node scripts/reset-crowdfunding.js [options]

Options:
  --db-only       Only reset database (skip Stripe)
  --stripe-only   Only reset Stripe (skip database)
  --dry-run       Show what would be deleted without actually deleting
  --yes           Skip confirmation prompt (use with caution!)
```

### Examples

```bash
# See what would be deleted without making changes
node scripts/reset-crowdfunding.js --dry-run

# Reset database and Stripe with confirmation prompt
node scripts/reset-crowdfunding.js

# Reset only database, skip confirmation
node scripts/reset-crowdfunding.js --db-only --yes

# Reset only Stripe data
node scripts/reset-crowdfunding.js --stripe-only
```

## What Gets Deleted

### Database (PostgreSQL/Supabase)

The script deletes data in this order (respecting foreign key dependencies):

1. **Backer Benefits** - All lifetime benefits and tracking records
2. **Court Sponsors** - All court sponsorship records
3. **Founders Wall** - All public display entries
4. **Contributions** - All payment records and pledges
5. **Backers** - All supporter/customer records
6. **Campaign Counters** - Resets `current_amount` and `backer_count` to 0

**Note:** Campaign types and contribution tiers are NOT deleted, only their counters are reset.

### Stripe

The script removes:

1. **Customers** - All Stripe customers tagged with `metadata.source = 'crowdfunding'`
2. **Payment Intents** - All payment intents (cancelled if still pending)
3. **Checkout Sessions** - All checkout sessions (expired if still open)
4. **Prices** - All prices (archived, not deleted)
5. **Products** - All products tagged with `metadata.source = 'crowdfunding'`

## Safety Features

### Confirmation Prompt
By default, the script requires you to type "yes" to confirm deletion unless you use `--yes` flag.

### Dry Run Mode
Always test with `--dry-run` first to see exactly what will be deleted:

```bash
npm run crowdfunding:reset:dry
```

### Metadata Filtering
For Stripe, the script looks for `metadata.source = 'crowdfunding'` to avoid deleting unrelated data. Make sure to tag your Stripe resources appropriately:

```javascript
// When creating Stripe resources, add metadata
const customer = await stripe.customers.create({
  email: 'backer@example.com',
  metadata: { source: 'crowdfunding' }
});
```

## After Reset

After running the reset, your crowdfunding system will be in a clean state:

- ✅ Campaign types and tiers remain configured
- ✅ All counters reset to 0
- ✅ No backer or contribution data
- ✅ No Stripe customer/payment data
- ✅ Ready for fresh testing

## Testing Workflow

Recommended workflow for development:

```bash
# 1. See what you have
npm run crowdfunding:reset:dry

# 2. Test your crowdfunding flow
# (make test contributions)

# 3. Reset when done testing
npm run crowdfunding:reset

# 4. Repeat testing cycle
```

## Troubleshooting

### "Missing Supabase credentials"
Make sure `.env.local` exists and contains `SUPABASE_URL` and `SUPABASE_SERVICE_KEY`.

### "Missing STRIPE_SECRET_KEY"
Either add `STRIPE_SECRET_KEY` to `.env.local` or use `--db-only` flag to skip Stripe cleanup.

### "Error during database cleanup"
Check that:
- Supabase is running (local or cloud)
- Service role key has admin permissions
- Database schema exists

### "Error during Stripe cleanup"
Check that:
- Stripe secret key is valid
- You have API access permissions
- Rate limits aren't exceeded

## Schema Reference

Tables affected (in `crowdfunding` schema):

```sql
crowdfunding.backer_benefits
crowdfunding.court_sponsors
crowdfunding.founders_wall
crowdfunding.contributions
crowdfunding.backers
crowdfunding.campaign_types (counters only)
crowdfunding.contribution_tiers (counters only)
```

## Related Scripts

- `seed-crowdfunding.js` - Seed fresh crowdfunding data after reset
- `test-contribution-sql.js` - Test contribution flow

## Support

For issues or questions:
1. Check this README
2. Review the script comments in `scripts/reset-crowdfunding.js`
3. Check `dink-house-db/docs/CROWDFUNDING_*.md` documentation
