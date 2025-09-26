#!/bin/bash

# Migrate to Supabase Script
# This script helps migrate your local Dink House database to Supabase cloud

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_DIR="$SCRIPT_DIR/sql"
BACKUP_DIR="$SCRIPT_DIR/backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Load environment variables
if [ -f "$SCRIPT_DIR/.env" ]; then
    export $(cat "$SCRIPT_DIR/.env" | sed 's/#.*//g' | xargs)
else
    echo -e "${RED}Error: .env file not found${NC}"
    exit 1
fi

# Function to print colored messages
print_message() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    print_message "Checking prerequisites..."

    # Check for required tools
    command -v psql >/dev/null 2>&1 || { print_error "psql is required but not installed."; exit 1; }
    command -v pg_dump >/dev/null 2>&1 || { print_error "pg_dump is required but not installed."; exit 1; }
    command -v docker >/dev/null 2>&1 || { print_error "docker is required but not installed."; exit 1; }

    # Check if local database is running
    docker ps | grep dink-house-db >/dev/null 2>&1 || { print_error "Local database container is not running."; exit 1; }

    print_message "All prerequisites met."
}

# Function to create backup directory
create_backup_dir() {
    if [ ! -d "$BACKUP_DIR" ]; then
        mkdir -p "$BACKUP_DIR"
        print_message "Created backup directory: $BACKUP_DIR"
    fi
}

# Function to backup local database
backup_local_database() {
    print_message "Creating backup of local database..."

    local backup_file="$BACKUP_DIR/dink_house_backup_${TIMESTAMP}.sql"

    docker exec dink-house-db pg_dump \
        -U ${POSTGRES_USER:-postgres} \
        --clean \
        --if-exists \
        --no-owner \
        --no-privileges \
        ${POSTGRES_DB:-dink_house} > "$backup_file"

    if [ $? -eq 0 ]; then
        print_message "Backup created: $backup_file"
        echo "$backup_file"
    else
        print_error "Failed to create backup"
        exit 1
    fi
}

# Function to export schema only
export_schema() {
    print_message "Exporting database schema..."

    local schema_file="$BACKUP_DIR/dink_house_schema_${TIMESTAMP}.sql"

    docker exec dink-house-db pg_dump \
        -U ${POSTGRES_USER:-postgres} \
        --schema-only \
        --no-owner \
        --no-privileges \
        ${POSTGRES_DB:-dink_house} > "$schema_file"

    if [ $? -eq 0 ]; then
        print_message "Schema exported: $schema_file"
        echo "$schema_file"
    else
        print_error "Failed to export schema"
        exit 1
    fi
}

# Function to export data only
export_data() {
    print_message "Exporting database data..."

    local data_file="$BACKUP_DIR/dink_house_data_${TIMESTAMP}.sql"

    docker exec dink-house-db pg_dump \
        -U ${POSTGRES_USER:-postgres} \
        --data-only \
        --no-owner \
        --no-privileges \
        --disable-triggers \
        ${POSTGRES_DB:-dink_house} > "$data_file"

    if [ $? -eq 0 ]; then
        print_message "Data exported: $data_file"
        echo "$data_file"
    else
        print_error "Failed to export data"
        exit 1
    fi
}

# Function to prepare SQL for Supabase
prepare_for_supabase() {
    local input_file=$1
    local output_file="${input_file%.sql}_supabase.sql"

    print_message "Preparing SQL for Supabase compatibility..."

    # Create modified SQL file for Supabase
    cat "$input_file" | \
        # Remove or comment out incompatible commands
        sed 's/^CREATE ROLE/-- CREATE ROLE/g' | \
        sed 's/^ALTER ROLE/-- ALTER ROLE/g' | \
        sed 's/^GRANT ALL/-- GRANT ALL/g' | \
        sed 's/^REVOKE ALL/-- REVOKE ALL/g' | \
        # Replace postgres user references with current user
        sed 's/OWNER TO postgres/-- OWNER TO postgres/g' | \
        # Handle Supabase-specific schemas
        sed 's/CREATE SCHEMA IF NOT EXISTS auth/-- CREATE SCHEMA IF NOT EXISTS auth/g' | \
        # Add Supabase-specific settings
        sed '1i -- Supabase Migration Script\n-- Generated: '$(date)'\n' \
        > "$output_file"

    print_message "Supabase-compatible SQL created: $output_file"
    echo "$output_file"
}

# Function to connect to Supabase
connect_to_supabase() {
    print_message "Connecting to Supabase..."

    read -p "Enter your Supabase project URL (e.g., xyz.supabase.co): " SUPABASE_HOST
    read -p "Enter your Supabase database password: " -s SUPABASE_PASSWORD
    echo

    # Test connection
    PGPASSWORD=$SUPABASE_PASSWORD psql \
        -h "$SUPABASE_HOST" \
        -p 5432 \
        -d postgres \
        -U postgres \
        -c "SELECT version();" >/dev/null 2>&1

    if [ $? -eq 0 ]; then
        print_message "Successfully connected to Supabase"
    else
        print_error "Failed to connect to Supabase. Please check your credentials."
        exit 1
    fi
}

# Function to import to Supabase
import_to_supabase() {
    local sql_file=$1

    print_message "Importing to Supabase..."

    read -p "Are you sure you want to import to Supabase? This will modify your Supabase database. (y/N): " confirm

    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        print_warning "Import cancelled."
        return
    fi

    PGPASSWORD=$SUPABASE_PASSWORD psql \
        -h "$SUPABASE_HOST" \
        -p 5432 \
        -d postgres \
        -U postgres \
        -f "$sql_file" \
        --single-transaction \
        -v ON_ERROR_STOP=1

    if [ $? -eq 0 ]; then
        print_message "Import completed successfully!"
    else
        print_error "Import failed. Please check the error messages above."
        exit 1
    fi
}

# Function to verify migration
verify_migration() {
    print_message "Verifying migration..."

    local verification_sql="
    SELECT
        schemaname,
        COUNT(*) as table_count
    FROM pg_tables
    WHERE schemaname IN ('auth', 'content', 'contact', 'launch', 'system', 'api')
    GROUP BY schemaname
    ORDER BY schemaname;
    "

    print_message "Tables in Supabase:"
    PGPASSWORD=$SUPABASE_PASSWORD psql \
        -h "$SUPABASE_HOST" \
        -p 5432 \
        -d postgres \
        -U postgres \
        -c "$verification_sql"

    print_message "Migration verification complete."
}

# Function to generate migration report
generate_report() {
    local report_file="$BACKUP_DIR/migration_report_${TIMESTAMP}.txt"

    print_message "Generating migration report..."

    cat > "$report_file" << EOF
=================================================================
Dink House Database Migration Report
=================================================================
Generated: $(date)
Source: Local Docker Container (${POSTGRES_DB:-dink_house})
Target: Supabase ($SUPABASE_HOST)

Files Generated:
- Schema: $BACKUP_DIR/dink_house_schema_${TIMESTAMP}.sql
- Data: $BACKUP_DIR/dink_house_data_${TIMESTAMP}.sql
- Full Backup: $BACKUP_DIR/dink_house_backup_${TIMESTAMP}.sql
- Supabase SQL: $BACKUP_DIR/dink_house_backup_${TIMESTAMP}_supabase.sql

Next Steps:
1. Review the generated SQL files
2. Test the migration in a Supabase development project first
3. Enable Row Level Security (RLS) on all tables
4. Configure authentication in Supabase Dashboard
5. Update your application's environment variables:
   - SUPABASE_URL
   - SUPABASE_ANON_KEY
   - SUPABASE_SERVICE_KEY

Important Notes:
- Remember to update your API endpoints to use Supabase
- Configure email templates in Supabase Dashboard
- Set up storage buckets if using file uploads
- Enable realtime subscriptions for required tables
- Review and adjust RLS policies as needed

=================================================================
EOF

    print_message "Report generated: $report_file"
    cat "$report_file"
}

# Main migration menu
show_menu() {
    echo
    echo "========================================="
    echo "    Dink House Supabase Migration Tool   "
    echo "========================================="
    echo "1. Full Migration (Recommended)"
    echo "2. Export Schema Only"
    echo "3. Export Data Only"
    echo "4. Create Local Backup"
    echo "5. Connect to Supabase (Test Connection)"
    echo "6. Import Existing Backup to Supabase"
    echo "7. Verify Migration"
    echo "8. Exit"
    echo "========================================="
    read -p "Select an option [1-8]: " choice
}

# Main execution
main() {
    check_prerequisites
    create_backup_dir

    while true; do
        show_menu

        case $choice in
            1)
                print_message "Starting full migration..."
                backup_file=$(backup_local_database)
                supabase_file=$(prepare_for_supabase "$backup_file")
                connect_to_supabase
                import_to_supabase "$supabase_file"
                verify_migration
                generate_report
                ;;
            2)
                schema_file=$(export_schema)
                prepare_for_supabase "$schema_file"
                ;;
            3)
                export_data
                ;;
            4)
                backup_local_database
                ;;
            5)
                connect_to_supabase
                ;;
            6)
                read -p "Enter the path to SQL file to import: " import_file
                if [ -f "$import_file" ]; then
                    connect_to_supabase
                    import_to_supabase "$import_file"
                    verify_migration
                else
                    print_error "File not found: $import_file"
                fi
                ;;
            7)
                connect_to_supabase
                verify_migration
                ;;
            8)
                print_message "Exiting..."
                exit 0
                ;;
            *)
                print_error "Invalid option. Please select 1-8."
                ;;
        esac

        echo
        read -p "Press Enter to continue..."
    done
}

# Run main function
main "$@"