#!/bin/bash

# Export local Supabase database for cloud migration
# This script exports schema and data from your local Docker Supabase instance

set -e

# Configuration
LOCAL_DB_HOST="${DB_HOST:-localhost}"
LOCAL_DB_PORT="${DB_PORT:-9432}"
LOCAL_DB_NAME="${POSTGRES_DB:-dink_house}"
LOCAL_DB_USER="${POSTGRES_USER:-postgres}"
LOCAL_DB_PASSWORD="${POSTGRES_PASSWORD:-DevPassword123!}"

EXPORT_DIR="./db-export"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
EXPORT_FILE="${EXPORT_DIR}/dink_house_export_${TIMESTAMP}.sql"

# Create export directory
mkdir -p "${EXPORT_DIR}"

echo "Starting database export from local Supabase..."
echo "Database: ${LOCAL_DB_NAME}"
echo "Host: ${LOCAL_DB_HOST}:${LOCAL_DB_PORT}"

# Export database with custom schemas
# Excluding Supabase system schemas that will already exist in cloud
PGPASSWORD="${LOCAL_DB_PASSWORD}" pg_dump \
  -h "${LOCAL_DB_HOST}" \
  -p "${LOCAL_DB_PORT}" \
  -U "${LOCAL_DB_USER}" \
  -d "${LOCAL_DB_NAME}" \
  --no-owner \
  --no-privileges \
  --no-tablespaces \
  --no-unlogged-table-data \
  --schema=public \
  --schema=app_auth \
  --schema=content \
  --schema=contact \
  --schema=launch \
  --schema=system \
  --schema=api \
  --schema=events \
  --exclude-schema=auth \
  --exclude-schema=storage \
  --exclude-schema=extensions \
  --exclude-schema=graphql \
  --exclude-schema=graphql_public \
  --exclude-schema=pgbouncer \
  --exclude-schema=pgsodium \
  --exclude-schema=pgsodium_masks \
  --exclude-schema=realtime \
  --exclude-schema=supabase_functions \
  --exclude-schema=supabase_migrations \
  --exclude-schema=vault \
  --file="${EXPORT_FILE}"

echo "Database exported successfully to: ${EXPORT_FILE}"

# Create a structure-only export (no data)
STRUCTURE_FILE="${EXPORT_DIR}/dink_house_structure_${TIMESTAMP}.sql"
PGPASSWORD="${LOCAL_DB_PASSWORD}" pg_dump \
  -h "${LOCAL_DB_HOST}" \
  -p "${LOCAL_DB_PORT}" \
  -U "${LOCAL_DB_USER}" \
  -d "${LOCAL_DB_NAME}" \
  --no-owner \
  --no-privileges \
  --no-tablespaces \
  --schema-only \
  --schema=public \
  --schema=app_auth \
  --schema=content \
  --schema=contact \
  --schema=launch \
  --schema=system \
  --schema=api \
  --schema=events \
  --exclude-schema=auth \
  --exclude-schema=storage \
  --exclude-schema=extensions \
  --exclude-schema=graphql \
  --exclude-schema=graphql_public \
  --exclude-schema=pgbouncer \
  --exclude-schema=pgsodium \
  --exclude-schema=pgsodium_masks \
  --exclude-schema=realtime \
  --exclude-schema=supabase_functions \
  --exclude-schema=supabase_migrations \
  --exclude-schema=vault \
  --file="${STRUCTURE_FILE}"

echo "Database structure exported to: ${STRUCTURE_FILE}"

# Create a data-only export
DATA_FILE="${EXPORT_DIR}/dink_house_data_${TIMESTAMP}.sql"
PGPASSWORD="${LOCAL_DB_PASSWORD}" pg_dump \
  -h "${LOCAL_DB_HOST}" \
  -p "${LOCAL_DB_PORT}" \
  -U "${LOCAL_DB_USER}" \
  -d "${LOCAL_DB_NAME}" \
  --no-owner \
  --no-privileges \
  --data-only \
  --disable-triggers \
  --schema=public \
  --schema=app_auth \
  --schema=content \
  --schema=contact \
  --schema=launch \
  --schema=system \
  --schema=api \
  --schema=events \
  --exclude-schema=auth \
  --exclude-schema=storage \
  --exclude-schema=extensions \
  --exclude-schema=graphql \
  --exclude-schema=graphql_public \
  --exclude-schema=pgbouncer \
  --exclude-schema=pgsodium \
  --exclude-schema=pgsodium_masks \
  --exclude-schema=realtime \
  --exclude-schema=supabase_functions \
  --exclude-schema=supabase_migrations \
  --exclude-schema=vault \
  --file="${DATA_FILE}"

echo "Database data exported to: ${DATA_FILE}"

echo ""
echo "Export complete! Files created:"
echo "  - Full export: ${EXPORT_FILE}"
echo "  - Structure only: ${STRUCTURE_FILE}"
echo "  - Data only: ${DATA_FILE}"
echo ""
echo "Next steps:"
echo "1. Review the exported SQL files"
echo "2. Run the migration script to prepare for cloud deployment"
echo "3. Import to Supabase cloud using the SQL editor or psql"