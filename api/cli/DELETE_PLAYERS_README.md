# Delete All Player Profiles Script

## Overview

This CLI script safely deletes all non-admin player profiles from the Dink House database, including:
- Player profiles (`app_auth.players`)
- User accounts (`app_auth.user_accounts` where `user_type = 'player'`)
- Related records (sessions, refresh tokens, API keys) via CASCADE
- Associated Stripe customers (both from `players.stripe_customer_id` and `crowdfunding.backers`)

## Safety Features

✅ **Admin Protection**: Only deletes accounts where `user_type = 'player'` (never admins or guests)
✅ **Dry-run mode**: Preview what will be deleted without making changes
✅ **Double confirmation**: Requires explicit user confirmation before proceeding
✅ **Transaction safety**: Uses database transactions for atomic operations
✅ **Detailed logging**: Shows progress and summary of deletions
✅ **Schema-aware**: Works with or without `stripe_customer_id` column

## Usage

### Quick Commands (via npm)

```bash
# Preview what will be deleted (safe, no changes)
npm run players:delete:dry

# Interactive deletion with confirmation prompts
npm run players:delete

# Force deletion without confirmation (DANGEROUS!)
npm run players:delete -- --force
```

### Direct Script Execution

```bash
# Preview mode (dry run)
node api/cli/delete-all-players.js --dry-run

# Interactive with confirmation
node api/cli/delete-all-players.js

# Skip confirmation (use with extreme caution!)
node api/cli/delete-all-players.js --force
```

## Command Options

| Option | Description |
|--------|-------------|
| `--dry-run` | Preview what will be deleted without making any changes |
| `--force` | Skip confirmation prompts (dangerous - use only in automated scripts) |

## What Gets Deleted

### Database Records (PostgreSQL)
1. **Player profiles** - `app_auth.players` table
2. **User accounts** - `app_auth.user_accounts` (where `user_type = 'player'`)
3. **Sessions** - `app_auth.sessions` (via CASCADE)
4. **Refresh tokens** - `app_auth.refresh_tokens` (via CASCADE)
5. **API keys** - `app_auth.api_keys` (via CASCADE)
6. **Event registrations** - Set to NULL via existing foreign key

### Stripe Customers
1. **From players table** - `players.stripe_customer_id` (if column exists)
2. **From crowdfunding** - `crowdfunding.backers.stripe_customer_id` (matched by email)

## Example Output

### Dry Run Mode
```
🏓 Dink House - Delete All Player Profiles

════════════════════════════════════════════════════════════
✅ Connected to database

📊 Fetching player accounts...

Found 3 player account(s):

  1. John Doe (john@example.com)
     Stripe Customer: cus_ABC123
     Created: 1/15/2025

  2. Jane Smith (jane@example.com)
     Created: 1/20/2025

  3. Bob Johnson (bob@example.com)
     Stripe Customer: cus_XYZ789
     Created: 1/25/2025

📋 Related records that will be deleted:
   - Sessions: 5
   - Refresh Tokens: 3
   - API Keys: 1

💳 Stripe customers to delete: 2

════════════════════════════════════════════════════════════

🔍 DRY RUN MODE - No changes will be made

Summary of what would be deleted:
  - 3 player profiles
  - 3 user accounts
  - 5 sessions
  - 3 refresh tokens
  - 1 API keys
  - 2 Stripe customers

════════════════════════════════════════════════════════════
```

### Interactive Mode
```
⚠️  WARNING: This action cannot be undone!

? Are you sure you want to delete 3 player account(s) and all related data? (y/N)
? Type "DELETE ALL PLAYERS" to confirm: DELETE ALL PLAYERS

🚀 Starting deletion process...

════════════════════════════════════════════════════════════

💳 Deleting Stripe customers...
  ✅ Deleted Stripe customer: cus_ABC123
  ✅ Deleted Stripe customer: cus_XYZ789

  Total Stripe customers deleted: 2/2

🗑️  Deleting database records...
  ✅ Deleted 3 user accounts
  ✅ Cascade deleted 5 sessions
  ✅ Cascade deleted 3 refresh tokens
  ✅ Cascade deleted 1 API keys

════════════════════════════════════════════════════════════

✅ All player profiles deleted successfully!

Summary:
  - Player profiles: 3
  - Stripe customers: 2
  - Database records: 12

════════════════════════════════════════════════════════════
```

## Environment Variables

The script uses the following environment variables from `.env`:

```bash
# Database Configuration
DB_HOST=localhost
DB_PORT=9432
POSTGRES_DB=dink_house
POSTGRES_USER=postgres
POSTGRES_PASSWORD=DevPassword123!

# Stripe Configuration (optional)
STRIPE_SECRET_KEY=sk_test_...
```

If `STRIPE_SECRET_KEY` is not set, the script will skip Stripe customer deletion and only delete database records.

## Database Schema Compatibility

The script automatically detects and adapts to your database schema:

- ✅ Works with or without `stripe_customer_id` column in `app_auth.players`
- ✅ Works with or without `crowdfunding.backers` table
- ✅ Handles missing columns gracefully

## Important Notes

⚠️ **DANGER**: This operation is irreversible! Always run with `--dry-run` first.

🔒 **Admin Safety**: Admin accounts are NEVER deleted, only player accounts.

💾 **Backup First**: Always backup your database before running this script in production.

🔄 **Transaction Safety**: All database operations are wrapped in a transaction. If any error occurs, all changes are rolled back.

🌐 **Stripe**: Stripe customer deletions happen before database deletions. If Stripe deletion fails, the script continues with database cleanup.

## Troubleshooting

### "Error: column p.stripe_customer_id does not exist"
This error should not occur anymore - the script now detects if the column exists. If you still see this, please report it as a bug.

### "Stripe not configured"
Set the `STRIPE_SECRET_KEY` environment variable in your `.env` file if you want to delete Stripe customers.

### Database connection refused
Ensure your PostgreSQL database is running and the connection details in `.env` are correct.

## Related Scripts

- `npm run admin:create` - Create admin accounts
- `npm run crowdfunding:reset` - Reset crowdfunding data
- `npm run db:seed` - Seed database with test data
