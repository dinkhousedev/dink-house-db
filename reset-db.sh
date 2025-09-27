#!/bin/bash

# Reset script for Dink House Database
# This script drops and recreates the database

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default database connection parameters
DB_NAME="${DB_NAME:-dink_house}"
DB_USER="${DB_USER:-postgres}"

echo -e "${YELLOW}=================================================="
echo "Dink House Database Reset Script"
echo "=================================================="
echo -e "${NC}"

echo -e "${RED}WARNING: This will DROP and RECREATE the database!"
echo -e "All data will be lost!${NC}"
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirmation

if [ "$confirmation" != "yes" ]; then
    echo "Operation cancelled."
    exit 0
fi

echo ""
echo -e "${YELLOW}Terminating existing connections...${NC}"
docker exec dink-house-db psql -U "$DB_USER" -d postgres -c "SELECT pg_terminate_backend(pg_stat_activity.pid) FROM pg_stat_activity WHERE pg_stat_activity.datname = '$DB_NAME' AND pid <> pg_backend_pid();"
echo -e "${GREEN}✓ Connections terminated${NC}"

echo -e "${YELLOW}Dropping database...${NC}"
docker exec dink-house-db psql -U "$DB_USER" -d postgres -c "DROP DATABASE IF EXISTS $DB_NAME;"
echo -e "${GREEN}✓ Database dropped${NC}"

echo -e "${YELLOW}Creating fresh database...${NC}"
docker exec dink-house-db psql -U "$DB_USER" -d postgres -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"
echo -e "${GREEN}✓ Database created${NC}"

echo ""
echo -e "${GREEN}Database reset complete!${NC}"
echo "You can now run ./migrate.sh to set up the database schema."