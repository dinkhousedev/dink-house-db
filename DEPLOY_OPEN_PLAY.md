# Open Play System Deployment Guide

This guide explains how to deploy the Open Play system to Supabase Cloud.

## What's Being Deployed

The Open Play system includes:
- **Module 35**: Events & Courts permissions fix (fixes "permission denied for table courts")
- **Modules 36-44**: Complete Open Play scheduling and registration system
  - Schedule blocks (recurring weekly sessions)
  - Court allocations by skill level
  - Schedule overrides (holidays, special events)
  - Instance generation for conflict detection
  - Player registrations (members FREE, guests pay)
  - API functions for schedule management

## Deployment Methods

### Method 1: Automated Script (Recommended)

If you have PostgreSQL client (`psql`) installed:

```bash
cd dink-house-db
bash deploy-open-play.sh
```

The script will:
- Load your `.env.cloud` configuration
- Connect to Supabase Cloud
- Deploy all 10 modules in order
- Report success/failure for each module

### Method 2: Manual Deployment via Supabase Dashboard

If you don't have `psql` or prefer manual deployment:

1. Go to: https://supabase.com/dashboard/project/wchxzbuuwssrnaxshseu/sql

2. Run each SQL file in order by copying and pasting the contents:

   ```
   35-events-comprehensive-permissions-fix.sql
   36-open-play-schedule.sql
   37-open-play-schedule-api.sql
   38-open-play-schedule-rls.sql
   39-open-play-schedule-views.sql
   40-open-play-schedule-seed.sql
   41-open-play-public-wrappers.sql
   42-fix-schedule-overrides-constraint.sql
   43-schedule-override-upsert.sql
   44-open-play-registrations.sql
   ```

3. For each file:
   - Open the file from `sql/modules/`
   - Copy all contents
   - Paste into Supabase SQL Editor
   - Click "Run" (or press Ctrl+Enter)
   - Wait for success message
   - Move to next file

## Verification

After deployment, verify the tables exist:

```sql
-- Check open play tables
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'events'
AND table_name LIKE 'open_play%';

-- Should return:
-- open_play_schedule_blocks
-- open_play_court_allocations
-- open_play_schedule_overrides
-- open_play_instances
-- open_play_registrations
```

## Testing

Test the API functions:

```sql
-- Get weekly schedule
SELECT api.get_weekly_schedule();

-- Get upcoming schedule (next 7 days)
SELECT api.get_upcoming_open_play_schedule();
```

## Troubleshooting

### Error: "permission denied for table courts"
- Module 35 fixes this. Make sure it's deployed first.

### Error: "relation does not exist"
- Tables are created in modules 36-44. Deploy them in order.

### Error: "type already exists"
- This is safe to ignore if rerunning migrations.

### Error: "function does not exist"
- Make sure module 37 (API functions) is deployed.

## Next Steps

After successful deployment:

1. **Seed sample data** (optional):
   - Module 40 includes sample schedule blocks
   - Review and modify as needed

2. **Configure your schedule**:
   - Use `api.create_schedule_blocks_multi_day()` to create recurring sessions
   - Define court allocations by skill level

3. **Test registrations**:
   - Members can register for free
   - Guests pay per session (configurable pricing)

## API Endpoints

The following API functions are available:

### Schedule Management
- `api.get_weekly_schedule()` - View weekly schedule
- `api.get_upcoming_open_play_schedule()` - Upcoming sessions with availability
- `api.create_schedule_blocks_multi_day()` - Create recurring schedule
- `api.update_schedule_block()` - Update schedule block
- `api.delete_schedule_block()` - Delete schedule block

### Registrations
- `api.register_for_open_play()` - Register player for session
- `api.cancel_open_play_registration()` - Cancel registration
- `api.get_open_play_registrations()` - View registrations for session
- `api.get_player_open_play_history()` - Player's session history

### Overrides
- `api.create_schedule_override()` - Create one-off override (holiday, etc.)

## Support

For issues or questions:
- Check the troubleshooting section above
- Review SQL module files for detailed comments
- Check Supabase logs: https://supabase.com/dashboard/project/wchxzbuuwssrnaxshseu/logs
