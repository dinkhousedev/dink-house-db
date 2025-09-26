#!/bin/bash

# Migration script to apply schema changes to running database

echo "=================================================="
echo "Starting Database Migration to Schema Structure"
echo "=================================================="

DB_HOST="localhost"
DB_PORT="9432"
DB_NAME="dink_house"
DB_USER="postgres"
DB_PASS="DevPassword123!"

# Export password for psql
export PGPASSWORD=$DB_PASS

# Function to run SQL files
run_sql_file() {
    local file=$1
    echo "Running: $file"
    psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -f "$file" 2>&1
    if [ $? -eq 0 ]; then
        echo "✓ Completed: $file"
    else
        echo "✗ Failed: $file"
        return 1
    fi
}

# Run schema modules in order
echo ""
echo "Creating schemas..."
run_sql_file "sql/modules/01-schemas.sql"

echo ""
echo "Installing extensions..."
run_sql_file "sql/modules/02-extensions.sql"

echo ""
echo "Creating auth schema..."
run_sql_file "sql/modules/03-auth.sql"

echo ""
echo "Creating content schema..."
run_sql_file "sql/modules/04-content.sql"

echo ""
echo "Creating contact schema..."
run_sql_file "sql/modules/05-contact.sql"

echo ""
echo "Creating launch schema..."
run_sql_file "sql/modules/06-launch.sql"

echo ""
echo "Creating system schema..."
run_sql_file "sql/modules/07-system.sql"

echo ""
echo "Creating functions and triggers..."
run_sql_file "sql/modules/08-functions.sql"

echo ""
echo "Setting up permissions..."
run_sql_file "sql/modules/09-permissions.sql"

echo ""
echo "=================================================="
echo "Loading Seed Data"
echo "=================================================="

echo ""
echo "Loading users..."
run_sql_file "sql/seeds/01-users.sql"

echo ""
echo "Loading content..."
run_sql_file "sql/seeds/02-content.sql"

echo ""
echo "Loading system settings..."
run_sql_file "sql/seeds/03-system.sql"

echo ""
echo "Loading sample data..."
run_sql_file "sql/seeds/04-sample-data.sql"

echo ""
echo "=================================================="
echo "Migration Complete!"
echo "=================================================="

# Verify schemas
echo ""
echo "Verifying schemas created:"
psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -c "\dn"

echo ""
echo "Verifying tables in auth schema:"
psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -c "\dt auth.*"

echo ""
echo "Database migration completed successfully!"
echo "Access Supabase Studio at: http://localhost:9000"