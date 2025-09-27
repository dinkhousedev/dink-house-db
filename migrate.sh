#!/bin/bash

# Migration script for Dink House Database
# This script runs all SQL modules and seed data in the correct order

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default database connection parameters
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-9432}"
DB_NAME="${DB_NAME:-dink_house}"
DB_USER="${DB_USER:-postgres}"
DB_PASSWORD="${DB_PASSWORD:-DevPassword123!}"

echo -e "${GREEN}=================================================="
echo "Dink House Database Migration Script"
echo "=================================================="
echo -e "${NC}"

# Export password for psql
export PGPASSWORD="$DB_PASSWORD"

# Connection string for display (without password)
echo "Database: ${DB_NAME}"
echo "Host: ${DB_HOST}:${DB_PORT}"
echo "User: ${DB_USER}"
echo ""

# Test database connection
echo -e "${YELLOW}Testing database connection...${NC}"
if docker exec dink-house-db psql -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Connection successful${NC}"
else
    echo -e "${RED}✗ Failed to connect to database${NC}"
    echo "Please check your connection parameters and ensure the database is running."
    exit 1
fi

echo ""
echo -e "${GREEN}=================================================="
echo "Running SQL Modules"
echo "=================================================="
echo -e "${NC}"

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_DIR="$SCRIPT_DIR/sql"

# Execute SQL modules in order
for module in "$SQL_DIR"/modules/*.sql; do
    if [ -f "$module" ]; then
        MODULE_NAME=$(basename "$module")
        echo -e "${YELLOW}Running $MODULE_NAME...${NC}"

        if docker exec -i dink-house-db psql -U "$DB_USER" -d "$DB_NAME" \
               -v ON_ERROR_STOP=1 < "$module"; then
            echo -e "${GREEN}✓ Completed $MODULE_NAME${NC}"
        else
            echo -e "${RED}✗ Failed to execute $MODULE_NAME${NC}"
            exit 1
        fi
    fi
done

echo ""
echo -e "${GREEN}=================================================="
echo "Running Seed Data"
echo "=================================================="
echo -e "${NC}"

# Execute seed data files
for seed in "$SQL_DIR"/seeds/*.sql; do
    if [ -f "$seed" ]; then
        SEED_NAME=$(basename "$seed")
        echo -e "${YELLOW}Running $SEED_NAME...${NC}"

        if docker exec -i dink-house-db psql -U "$DB_USER" -d "$DB_NAME" \
               -v ON_ERROR_STOP=1 < "$seed"; then
            echo -e "${GREEN}✓ Completed $SEED_NAME${NC}"
        else
            echo -e "${RED}✗ Failed to execute $SEED_NAME${NC}"
            exit 1
        fi
    fi
done

echo ""
echo -e "${GREEN}=================================================="
echo "Migration Complete!"
echo "=================================================="
echo -e "${NC}"

# Clean up
unset PGPASSWORD
