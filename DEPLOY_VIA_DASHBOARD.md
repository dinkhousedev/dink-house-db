## Deploy Open Play System via Supabase Dashboard

Since the CLI is having network issues, deploy via the dashboard instead.

### Step 1: Open Supabase SQL Editor
Go to: https://supabase.com/dashboard/project/wchxzbuuwssrnaxshseu/sql

### Step 2: Run the consolidated file

Copy and paste the entire contents of `deploy-open-play-consolidated.sql` into the SQL editor and click "Run".

This will deploy:
- ✅ Module 35: Courts permissions fix (fixes "permission denied for table courts")
- ✅ Module 36: Open play schedule tables

### Step 3: Deploy the remaining modules individually

Run each of these files in order by copying contents to SQL Editor:

```bash
# 37: API functions (large file)
cat sql/modules/37-open-play-schedule-api.sql

# 38: RLS policies (use the fixed version)
cat supabase/migrations/20251008180003_38-open-play-schedule-rls.sql

# 39: Views
cat sql/modules/39-open-play-schedule-views.sql

# 40: Seed data (optional)
cat sql/modules/40-open-play-schedule-seed.sql

# 41: Public wrappers
cat sql/modules/41-open-play-public-wrappers.sql

# 42-43: Constraint fixes
cat sql/modules/42-fix-schedule-overrides-constraint.sql
cat sql/modules/43-schedule-override-upsert.sql

# 44: Registrations
cat sql/modules/44-open-play-registrations.sql
```

### Step 4: Verify

Run this query to verify tables exist:

```sql
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'events'
AND table_name LIKE 'open_play%'
ORDER BY table_name;
```

You should see:
- open_play_court_allocations
- open_play_instances
- open_play_registrations
- open_play_schedule_blocks
- open_play_schedule_overrides

### Alternative: Quick fix for current error

If you just want to fix the **"permission denied for table courts"** error immediately:

```sql
-- Quick fix
GRANT SELECT ON events.courts TO authenticated;
GRANT SELECT ON events.courts TO anon;

DROP POLICY IF EXISTS "courts_select_all" ON events.courts;
CREATE POLICY "courts_select_all" ON events.courts
    FOR SELECT USING (true);
```

This will let you access courts immediately. The full open play system can be deployed later.
