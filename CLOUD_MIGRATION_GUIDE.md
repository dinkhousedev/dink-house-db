# Dink House Database - Cloud Migration Guide

## Overview

This guide provides step-by-step instructions for migrating your local Supabase setup to Supabase Cloud.

## Prerequisites

- [ ] Local Supabase instance running with Docker Compose
- [ ] Supabase Cloud account created at [app.supabase.com](https://app.supabase.com)
- [ ] PostgreSQL client tools installed (`psql`, `pg_dump`)
- [ ] Supabase CLI installed (for Edge Functions deployment)

## Migration Architecture

Your local setup includes:
- PostgreSQL with custom schemas (app_auth, content, contact, launch, system, api, events)
- Supabase services (Auth, Realtime, Storage, Edge Functions)
- Custom SQL modules and seed data
- Edge Functions (auth-webhook, main, send-email)

## Step-by-Step Migration Process

### 1. Create Supabase Cloud Project

1. Sign up/login at [app.supabase.com](https://app.supabase.com)
2. Create a new project
3. Save your credentials:
   - Project URL: `https://wchxzbuuwssrnaxshseu.supabase.co`
   - Anon Key: (public client key)
   - Service Role Key: (server-side key)
   - Database Password: (set during project creation)

### 2. Configure Environment Variables

Your cloud credentials have been saved in `.env.cloud`. Review and update as needed:

```bash
# Use the cloud environment
cp .env.cloud .env

# Edit if needed
nano .env
```

### 3. Export Local Database

Export your local database structure and data:

```bash
# Make sure your local Supabase is running
docker-compose up -d

# Run the export script
./scripts/export-local-db.sh
```

This creates three files in `db-export/`:
- Full export (structure + data)
- Structure only
- Data only

### 4. Prepare Migration Scripts

Generate cloud-compatible SQL scripts:

```bash
./scripts/prepare-cloud-migration.sh
```

This creates:
- `cloud-migration/cloud_migration_*.sql` - Combined migration script
- `cloud-migration/IMPORT_INSTRUCTIONS.md` - Detailed import instructions

### 5. Import to Cloud Database

#### Option A: Using Supabase SQL Editor (Recommended for small databases)

1. Go to Supabase Dashboard > SQL Editor
2. Create a new query
3. Copy contents of `cloud-migration/cloud_migration_*.sql`
4. Run the query in sections (schemas, tables, functions, etc.)

#### Option B: Using psql (Recommended for large databases)

```bash
# Run the import script
./scripts/import-to-cloud.sh

# Follow the prompts to select import option
```

#### Option C: Manual psql import

```bash
# Get your database password from Supabase Dashboard
export PGPASSWORD="your-database-password"

# Import the migration
psql "postgresql://postgres.wchxzbuuwssrnaxshseu:[password]@aws-0-us-west-1.pooler.supabase.com:5432/postgres" \
  -f cloud-migration/cloud_migration_*.sql
```

### 6. Deploy Edge Functions

Install Supabase CLI if not already installed:

```bash
# macOS
brew install supabase/tap/supabase

# npm
npm install -g supabase
```

Deploy your Edge Functions:

```bash
./scripts/deploy-edge-functions.sh
```

### 7. Configure Cloud Services

#### Email Service
1. Go to Supabase Dashboard > Authentication > Email Templates
2. Configure email templates for:
   - Confirmation emails
   - Password reset
   - Magic links

#### Storage Buckets
1. Go to Supabase Dashboard > Storage
2. Create required buckets
3. Set bucket policies

#### Authentication Providers
1. Go to Supabase Dashboard > Authentication > Providers
2. Configure OAuth providers if needed
3. Set redirect URLs

### 8. Update Application Code

Update your application to use cloud endpoints:

```javascript
// Before (local)
const supabase = createClient(
  'http://localhost:9002',
  'local-anon-key'
)

// After (cloud)
const supabase = createClient(
  'https://wchxzbuuwssrnaxshseu.supabase.co',
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...'
)
```

### 9. Verify Migration

Run these checks in SQL Editor:

```sql
-- Check custom schemas
SELECT schema_name FROM information_schema.schemata
WHERE schema_name IN ('app_auth', 'content', 'contact', 'launch', 'system', 'api', 'events');

-- Check tables
SELECT schemaname, tablename FROM pg_tables
WHERE schemaname IN ('app_auth', 'content', 'contact', 'launch', 'system')
ORDER BY schemaname, tablename;

-- Check functions
SELECT routine_schema, routine_name FROM information_schema.routines
WHERE routine_schema IN ('api', 'public')
ORDER BY routine_schema, routine_name;

-- Check RLS policies
SELECT schemaname, tablename, policyname FROM pg_policies
ORDER BY schemaname, tablename;
```

### 10. Post-Migration Cleanup

1. Test all application features
2. Set up monitoring and alerts
3. Configure backups
4. Update CI/CD pipelines
5. Document any custom configurations

## Rollback Plan

If issues occur during migration:

1. **Cloud Issues**: Delete and recreate the Supabase project
2. **Local Backup**: Your local Docker setup remains unchanged
3. **Database Restore**: Use the exported SQL files to restore

## Environment Management

### Development
- Continue using Docker Compose for local development
- Use `.env.example` for local configuration

### Staging/Production
- Use Supabase Cloud
- Use `.env.cloud` for cloud configuration

## Scripts Reference

| Script | Purpose |
|--------|---------|
| `export-local-db.sh` | Export local database to SQL files |
| `prepare-cloud-migration.sh` | Prepare cloud-compatible migration scripts |
| `import-to-cloud.sh` | Import database to Supabase Cloud |
| `deploy-edge-functions.sh` | Deploy Edge Functions to cloud |

## Troubleshooting

### Common Issues

1. **Permission Errors**
   - Ensure you're using the correct database password
   - Check that custom schemas have proper grants

2. **Extension Conflicts**
   - Supabase Cloud pre-installs many extensions
   - Remove CREATE EXTENSION statements for system extensions

3. **RLS Policy Errors**
   - Update policies referencing `auth.uid()` to use cloud auth

4. **Edge Function Deployment**
   - Ensure Supabase CLI is authenticated
   - Check function code compatibility with Deno runtime

### Getting Help

- [Supabase Documentation](https://supabase.com/docs)
- [Supabase Discord](https://discord.supabase.com)
- [GitHub Issues](https://github.com/supabase/supabase/issues)

## Security Checklist

- [ ] Remove development keys from production code
- [ ] Enable RLS on all tables
- [ ] Configure proper CORS settings
- [ ] Set up rate limiting
- [ ] Enable 2FA on Supabase account
- [ ] Rotate API keys regularly
- [ ] Monitor database activity

## Next Steps

After successful migration:

1. Set up CI/CD for automatic deployments
2. Configure monitoring and alerting
3. Implement backup strategies
4. Document API endpoints
5. Create runbooks for common operations