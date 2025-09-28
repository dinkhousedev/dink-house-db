#!/bin/bash

# Prepare SQL migration scripts for Supabase Cloud deployment
# This script combines and processes SQL modules for cloud compatibility

set -e

MIGRATION_DIR="./cloud-migration"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="${MIGRATION_DIR}/cloud_migration_${TIMESTAMP}.sql"

# Create migration directory
mkdir -p "${MIGRATION_DIR}"

echo "Preparing migration scripts for Supabase Cloud..."

# Create the combined migration file
cat > "${OUTPUT_FILE}" << 'EOF'
-- Dink House Database Migration Script for Supabase Cloud
-- Generated for cloud deployment
--
-- IMPORTANT: Run this in the Supabase SQL Editor or using psql
-- Some sections may need to be run separately due to transaction boundaries

-- ============================================
-- 1. CREATE SCHEMAS
-- ============================================

-- Create custom schemas (if they don't exist)
CREATE SCHEMA IF NOT EXISTS app_auth;
CREATE SCHEMA IF NOT EXISTS content;
CREATE SCHEMA IF NOT EXISTS contact;
CREATE SCHEMA IF NOT EXISTS launch;
CREATE SCHEMA IF NOT EXISTS system;
CREATE SCHEMA IF NOT EXISTS api;
CREATE SCHEMA IF NOT EXISTS events;

-- Grant usage on schemas
GRANT USAGE ON SCHEMA app_auth TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA content TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA contact TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA launch TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA system TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA api TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA events TO anon, authenticated, service_role;

-- ============================================
-- 2. ENABLE REQUIRED EXTENSIONS
-- ============================================

-- These should already be enabled in Supabase Cloud, but we'll ensure they are
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";

EOF

# Process and append SQL modules
echo "Processing SQL modules..."

# Function to process SQL files
process_sql_file() {
    local file=$1
    local filename=$(basename "$file")

    echo "" >> "${OUTPUT_FILE}"
    echo "-- ============================================" >> "${OUTPUT_FILE}"
    echo "-- MODULE: ${filename}" >> "${OUTPUT_FILE}"
    echo "-- ============================================" >> "${OUTPUT_FILE}"
    echo "" >> "${OUTPUT_FILE}"

    # Skip Supabase init file and certain system files
    if [[ "$filename" == "00-supabase-init.sql" ]]; then
        echo "-- Skipped: Supabase initialization (handled by cloud)" >> "${OUTPUT_FILE}"
        return
    fi

    # Process the file, removing problematic statements for cloud
    cat "$file" | \
        # Remove CREATE EXTENSION statements for extensions managed by Supabase
        sed '/CREATE EXTENSION.*pgsodium/d' | \
        sed '/CREATE EXTENSION.*pg_graphql/d' | \
        sed '/CREATE EXTENSION.*pg_net/d' | \
        sed '/CREATE EXTENSION.*vector/d' | \
        sed '/CREATE EXTENSION.*supabase_vault/d' | \
        # Remove ALTER SYSTEM statements (not allowed in cloud)
        sed '/ALTER SYSTEM/d' | \
        # Remove pg_reload_conf() calls
        sed '/pg_reload_conf()/d' | \
        # Remove SUPERUSER operations
        sed '/SUPERUSER/d' | \
        # Remove auth schema modifications (managed by Supabase)
        sed '/ALTER.*auth\./d' | \
        sed '/CREATE.*auth\./d' | \
        sed '/DROP.*auth\./d' \
        >> "${OUTPUT_FILE}"
}

# Process modules in order
for file in sql/modules/*.sql; do
    if [ -f "$file" ]; then
        process_sql_file "$file"
    fi
done

# Add seed data section
echo "" >> "${OUTPUT_FILE}"
echo "-- ============================================" >> "${OUTPUT_FILE}"
echo "-- SEED DATA (Optional)" >> "${OUTPUT_FILE}"
echo "-- ============================================" >> "${OUTPUT_FILE}"
echo "-- Seed data should be imported separately after schema creation" >> "${OUTPUT_FILE}"
echo "-- See sql/seeds/ directory for seed data files" >> "${OUTPUT_FILE}"

echo "Migration script created: ${OUTPUT_FILE}"

# Create a separate import instruction file
INSTRUCTIONS_FILE="${MIGRATION_DIR}/IMPORT_INSTRUCTIONS.md"
cat > "${INSTRUCTIONS_FILE}" << 'EOF'
# Supabase Cloud Migration Instructions

## Prerequisites
- Supabase Cloud project created
- Database credentials from Supabase Dashboard
- psql or Supabase SQL Editor access

## Migration Steps

### 1. Connect to your Supabase Cloud Database

#### Option A: Using Supabase SQL Editor (Recommended)
1. Go to your Supabase Dashboard
2. Navigate to SQL Editor
3. Create a new query

#### Option B: Using psql
```bash
psql "postgresql://postgres.[your-project-ref]:[your-password]@aws-0-us-west-1.pooler.supabase.com:5432/postgres"
```

### 2. Run Migration Scripts

The migration has been split into manageable sections. Run them in this order:

1. **Schemas and Extensions**: Run first to set up the database structure
2. **Tables and Types**: Create all custom tables and data types
3. **Functions**: Create stored procedures and functions
4. **Permissions**: Set up Row Level Security and permissions
5. **Triggers**: Create database triggers
6. **Seed Data**: (Optional) Import initial data

### 3. Verify Migration

Run these checks after migration:

```sql
-- Check schemas
SELECT schema_name FROM information_schema.schemata
WHERE schema_name IN ('app_auth', 'content', 'contact', 'launch', 'system', 'api', 'events');

-- Check tables
SELECT schemaname, tablename FROM pg_tables
WHERE schemaname IN ('app_auth', 'content', 'contact', 'launch', 'system');

-- Check functions
SELECT routine_schema, routine_name FROM information_schema.routines
WHERE routine_schema = 'api';
```

### 4. Post-Migration Tasks

1. **Update Environment Variables**: Use `.env.cloud` for your application
2. **Deploy Edge Functions**: See `scripts/deploy-edge-functions.sh`
3. **Configure Authentication**: Set up email templates and providers
4. **Set up Storage Buckets**: Create required storage buckets
5. **Configure Realtime**: Enable realtime for required tables

### Common Issues and Solutions

- **Permission Errors**: Ensure you're using the correct database role
- **Extension Conflicts**: Some extensions are pre-installed in Supabase Cloud
- **Schema Already Exists**: Use IF NOT EXISTS clauses
- **RLS Policies**: May need to be recreated if referencing auth.uid()

EOF

echo "Instructions created: ${INSTRUCTIONS_FILE}"

echo ""
echo "Migration preparation complete!"
echo "Files created:"
echo "  - Migration script: ${OUTPUT_FILE}"
echo "  - Instructions: ${INSTRUCTIONS_FILE}"
echo ""
echo "Next steps:"
echo "1. Review the migration script for any custom modifications needed"
echo "2. Follow the instructions in IMPORT_INSTRUCTIONS.md"
echo "3. Test the migration in a development environment first"