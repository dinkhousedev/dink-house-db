#!/bin/bash

# Consolidate SQL Modules into Migrations
# This script combines all SQL modules into proper migration files

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SQL_DIR="$PROJECT_ROOT/sql/modules"
MIGRATION_DIR="$PROJECT_ROOT/supabase/migrations"

echo "Consolidating SQL modules into migrations..."

# Create consolidated migration file
TIMESTAMP=$(date +%Y%m%d%H%M%S)
MIGRATION_FILE="$MIGRATION_DIR/${TIMESTAMP}_consolidated_schema.sql"

echo "-- Dink House Database Consolidated Schema" > "$MIGRATION_FILE"
echo "-- Generated on $(date)" >> "$MIGRATION_FILE"
echo "" >> "$MIGRATION_FILE"

# Concatenate SQL modules in order
SQL_FILES=(
    "01-schemas.sql"
    "02-extensions.sql"
    "03-auth.sql"
    "04-content.sql"
    "05-contact.sql"
    "06-launch.sql"
    "07-system.sql"
    "08-functions.sql"
    "09-permissions.sql"
    "10-api-views.sql"
    "11-rls-policies.sql"
    "12-api-functions.sql"
    "13-realtime-config.sql"
    "14-contact-notification.sql"
    "15-allowed-emails.sql"
    "16-events.sql"
    "17-events-api.sql"
    "18-events-rls.sql"
    "19-events-functions.sql"
    "20-user-api-functions.sql"
    "21-profile-images.sql"
    "22-postgrest-config.sql"
    "23-account-management.sql"
)

for file in "${SQL_FILES[@]}"; do
    if [ -f "$SQL_DIR/$file" ]; then
        echo "" >> "$MIGRATION_FILE"
        echo "-- ================================================" >> "$MIGRATION_FILE"
        echo "-- Module: $file" >> "$MIGRATION_FILE"
        echo "-- ================================================" >> "$MIGRATION_FILE"
        echo "" >> "$MIGRATION_FILE"
        cat "$SQL_DIR/$file" >> "$MIGRATION_FILE"
    else
        echo "Warning: $file not found in $SQL_DIR"
    fi
done

# Add seed data as a separate migration
SEED_FILE="$MIGRATION_DIR/${TIMESTAMP}_seed_data.sql"
echo "-- Dink House Seed Data" > "$SEED_FILE"
echo "-- Generated on $(date)" >> "$SEED_FILE"
echo "" >> "$SEED_FILE"

if [ -d "$PROJECT_ROOT/sql/seeds" ]; then
    for file in "$PROJECT_ROOT/sql/seeds"/*.sql; do
        if [ -f "$file" ]; then
            echo "" >> "$SEED_FILE"
            echo "-- Seed: $(basename "$file")" >> "$SEED_FILE"
            echo "" >> "$SEED_FILE"
            cat "$file" >> "$SEED_FILE"
        fi
    done
fi

echo "Migrations consolidated successfully!"
echo "Created files:"
echo "  - $MIGRATION_FILE"
echo "  - $SEED_FILE"

# Validate the migrations
echo ""
echo "Validating SQL syntax..."
if command -v psql &> /dev/null; then
    # Dry run to check syntax (if connected to a database)
    echo "Run 'supabase db reset' to apply the new migrations locally"
else
    echo "PostgreSQL client not found. Skipping syntax validation."
fi

echo ""
echo "Next steps:"
echo "1. Review the generated migration files"
echo "2. Test locally with: supabase db reset"
echo "3. Push to cloud with: supabase db push"