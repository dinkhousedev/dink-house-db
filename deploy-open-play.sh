#!/bin/bash
# ============================================================================
# DEPLOY OPEN PLAY SYSTEM TO SUPABASE CLOUD
# ============================================================================
# This script deploys all open play modules (35-44) to Supabase Cloud
# Run from: dink-house-db directory
# Usage: bash deploy-open-play.sh
# ============================================================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Load environment variables
if [ -f .env.cloud ]; then
    export $(grep -v '^#' .env.cloud | xargs)
    echo -e "${GREEN}✓${NC} Loaded Supabase Cloud configuration"
else
    echo -e "${RED}✗${NC} .env.cloud not found!"
    exit 1
fi

# Check if DATABASE_URL is set
if [ -z "$DATABASE_URL" ]; then
    echo -e "${RED}✗${NC} DATABASE_URL not set in .env.cloud"
    exit 1
fi

echo ""
echo "========================================"
echo "OPEN PLAY SYSTEM DEPLOYMENT"
echo "========================================"
echo "Target: Supabase Cloud"
echo "Project: wchxzbuuwssrnaxshseu"
echo ""

# Modules to deploy (in order)
MODULES=(
    "35-events-comprehensive-permissions-fix.sql"
    "36-open-play-schedule.sql"
    "37-open-play-schedule-api.sql"
    "38-open-play-schedule-rls.sql"
    "39-open-play-schedule-views.sql"
    "40-open-play-schedule-seed.sql"
    "41-open-play-public-wrappers.sql"
    "42-fix-schedule-overrides-constraint.sql"
    "43-schedule-override-upsert.sql"
    "44-open-play-registrations.sql"
)

# Check if psql is installed
if ! command -v psql &> /dev/null; then
    echo -e "${RED}✗${NC} psql not found!"
    echo ""
    echo "Please install PostgreSQL client:"
    echo "  Ubuntu/Debian: sudo apt-get install postgresql-client"
    echo "  macOS: brew install postgresql"
    echo ""
    echo "Or deploy manually via Supabase Dashboard:"
    echo "https://supabase.com/dashboard/project/wchxzbuuwssrnaxshseu/sql"
    exit 1
fi

echo "Deploying ${#MODULES[@]} modules..."
echo ""

# Deploy each module
SUCCESS_COUNT=0
FAILED_MODULES=()

for MODULE in "${MODULES[@]}"; do
    MODULE_PATH="sql/modules/$MODULE"

    if [ ! -f "$MODULE_PATH" ]; then
        echo -e "${RED}✗${NC} $MODULE not found, skipping..."
        FAILED_MODULES+=("$MODULE (not found)")
        continue
    fi

    echo -e "${YELLOW}→${NC} Deploying $MODULE..."

    if psql "$DATABASE_URL" -f "$MODULE_PATH" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} $MODULE deployed successfully"
        ((SUCCESS_COUNT++))
    else
        echo -e "${RED}✗${NC} $MODULE failed to deploy"
        FAILED_MODULES+=("$MODULE")
    fi
done

echo ""
echo "========================================"
echo "DEPLOYMENT SUMMARY"
echo "========================================"
echo -e "Successfully deployed: ${GREEN}${SUCCESS_COUNT}/${#MODULES[@]}${NC} modules"

if [ ${#FAILED_MODULES[@]} -gt 0 ]; then
    echo -e "${RED}Failed modules:${NC}"
    for FAILED in "${FAILED_MODULES[@]}"; do
        echo "  - $FAILED"
    done
    exit 1
else
    echo -e "${GREEN}✓ All modules deployed successfully!${NC}"
    echo ""
    echo "Open play system is now available in Supabase Cloud."
    echo "Dashboard: https://supabase.com/dashboard/project/wchxzbuuwssrnaxshseu"
fi
