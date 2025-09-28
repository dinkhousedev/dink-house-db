#!/bin/bash

# Import database to Supabase Cloud
# This script helps import your database structure and data to Supabase Cloud

set -e

# Load cloud environment variables
if [ -f ".env.cloud" ]; then
    export $(cat .env.cloud | grep -v '^#' | xargs)
fi

# Parse Supabase URL to get connection details
PROJECT_REF="wchxzbuuwssrnaxshseu"
SUPABASE_DB_HOST="aws-0-us-west-1.pooler.supabase.com"
SUPABASE_DB_PORT="5432"

echo "==========================================="
echo "Supabase Cloud Database Import Tool"
echo "==========================================="
echo ""
echo "Project Reference: ${PROJECT_REF}"
echo "Database Host: ${SUPABASE_DB_HOST}"
echo ""

# Check if migration files exist
if [ ! -d "./cloud-migration" ]; then
    echo "Error: Migration files not found. Run prepare-cloud-migration.sh first."
    exit 1
fi

# Function to execute SQL file
execute_sql() {
    local sql_file=$1
    local description=$2

    echo "Executing: ${description}..."

    read -p "Enter your Supabase database password: " -s DB_PASSWORD
    echo ""

    PGPASSWORD="${DB_PASSWORD}" psql \
        -h "${SUPABASE_DB_HOST}" \
        -p "${SUPABASE_DB_PORT}" \
        -U "postgres.${PROJECT_REF}" \
        -d "postgres" \
        -f "${sql_file}" \
        --set ON_ERROR_STOP=on \
        --echo-queries

    if [ $? -eq 0 ]; then
        echo "✓ ${description} completed successfully"
    else
        echo "✗ ${description} failed"
        return 1
    fi
}

# Menu for import options
echo "Select import option:"
echo "1. Import complete migration (recommended for new project)"
echo "2. Import structure only"
echo "3. Import data only"
echo "4. Run custom SQL file"
echo "5. Exit"
echo ""
read -p "Enter your choice (1-5): " choice

case $choice in
    1)
        # Find the latest migration file
        MIGRATION_FILE=$(ls -t ./cloud-migration/cloud_migration_*.sql 2>/dev/null | head -1)
        if [ -z "$MIGRATION_FILE" ]; then
            echo "No migration file found. Run prepare-cloud-migration.sh first."
            exit 1
        fi
        execute_sql "${MIGRATION_FILE}" "Complete Migration"
        ;;
    2)
        # Find the latest structure file
        STRUCTURE_FILE=$(ls -t ./db-export/dink_house_structure_*.sql 2>/dev/null | head -1)
        if [ -z "$STRUCTURE_FILE" ]; then
            echo "No structure export found. Run export-local-db.sh first."
            exit 1
        fi
        execute_sql "${STRUCTURE_FILE}" "Database Structure"
        ;;
    3)
        # Find the latest data file
        DATA_FILE=$(ls -t ./db-export/dink_house_data_*.sql 2>/dev/null | head -1)
        if [ -z "$DATA_FILE" ]; then
            echo "No data export found. Run export-local-db.sh first."
            exit 1
        fi
        execute_sql "${DATA_FILE}" "Database Data"
        ;;
    4)
        read -p "Enter path to SQL file: " custom_file
        if [ -f "$custom_file" ]; then
            execute_sql "$custom_file" "Custom SQL"
        else
            echo "File not found: $custom_file"
            exit 1
        fi
        ;;
    5)
        echo "Exiting..."
        exit 0
        ;;
    *)
        echo "Invalid choice"
        exit 1
        ;;
esac

echo ""
echo "==========================================="
echo "Import process completed!"
echo "==========================================="
echo ""
echo "Next steps:"
echo "1. Verify the import in Supabase Dashboard > SQL Editor"
echo "2. Deploy Edge Functions using deploy-edge-functions.sh"
echo "3. Update your application to use .env.cloud"
echo "4. Test all functionality"