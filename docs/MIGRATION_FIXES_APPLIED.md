# Supabase Migration Fixes Applied

## Date: September 29, 2025

### Issues Fixed

1. **Storage Function Error**: Fixed `storage.enforce_bucket_name_length()` function not found error
2. **Duplicate Table Definitions**: Removed duplicate `CREATE TABLE` statements from seed data
3. **Schema Path Issues**: Fixed references to `public.allowed_emails` (changed to `app_auth.allowed_emails`)
4. **UUID Function References**: Updated all `public.uuid_generate_v4()` to `extensions.uuid_generate_v4()`
5. **Crypto Function References**: Updated all crypto functions to use `extensions.` prefix
6. **Migration Version Conflicts**: Reorganized migrations with clean sequential numbering

### New Migration Structure

```
supabase/
├── migrations/
│   ├── 00001_initial_schema.sql     # All schemas and tables
│   ├── 00002_functions_and_policies.sql  # Functions, triggers, RLS
│   └── 00003_initial_data.sql       # Optional seed data
└── migrations_old/                  # Archived problematic migrations
```

### Key Changes Made

#### 1. Clean Schema Creation
- All schemas created with `CREATE SCHEMA IF NOT EXISTS`
- Proper role grants to `anon`, `authenticated`, and `service_role`
- Fixed search path configuration

#### 2. Function Prefixes
- All UUID functions: `extensions.uuid_generate_v4()`
- All crypto functions: `extensions.crypt()`, `extensions.gen_salt()`
- Proper schema qualification for all functions

#### 3. Seed Data Fixes
- Removed duplicate table creations
- Fixed schema references (`app_auth.allowed_emails` instead of `public.allowed_emails`)
- Added proper `ON CONFLICT` clauses

#### 4. Storage Compatibility
- Added storage schema compatibility checks
- Removed problematic storage triggers from migrations
- Let Supabase handle storage schema internally

### Testing Results

✅ **Local Development**: `supabase start` runs successfully
✅ **Migrations Applied**: All 3 migrations apply without errors
✅ **No Duplicate Keys**: No primary key violations
✅ **Storage Working**: Storage container starts properly
✅ **Studio Available**: http://127.0.0.1:54323

### Database URLs

- **Database**: `postgresql://postgres:postgres@127.0.0.1:54322/postgres`
- **Studio**: http://127.0.0.1:54323
- **Mailpit**: http://127.0.0.1:54324

### Commands for Testing

```bash
# Clean start
supabase stop --no-backup
docker volume prune -f
supabase start

# Check status
supabase status

# Reset database
supabase db reset

# Push to cloud (when ready)
supabase db push
```

### Next Steps for Cloud Deployment

1. **Test migrations locally**: ✅ Complete
2. **Link to cloud project**: Already linked to `wchxzbuuwssrnaxshseu`
3. **Push to cloud**:
   ```bash
   supabase db push --dry-run  # Test first
   supabase db push            # Actually push
   ```
4. **Deploy Edge Functions**:
   ```bash
   supabase functions deploy
   ```

### Important Notes

- Always use `extensions.` prefix for UUID and crypto functions
- Keep migrations simple and sequential
- Test locally before pushing to cloud
- Use `ON CONFLICT DO NOTHING` for idempotent seed data

### Troubleshooting

If you encounter issues:
1. Stop all containers: `supabase stop --no-backup`
2. Clean Docker volumes: `docker volume prune -f`
3. Remove conflicting containers: `docker ps -aq | xargs -r docker rm`
4. Start fresh: `supabase start`

### Version Information
- Supabase CLI: v2.45.5 (v2.47.2 available)
- PostgreSQL: 17
- Project ID: wchxzbuuwssrnaxshseu