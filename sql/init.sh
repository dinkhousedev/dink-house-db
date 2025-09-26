#!/bin/bash
set -e

echo "=================================================="
echo "Starting Dink House Database Initialization"
echo "=================================================="

# Execute SQL modules in order
for f in /docker-entrypoint-initdb.d/modules/*.sql; do
    if [ -f "$f" ]; then
        echo "Running $f..."
        psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -f "$f"
        echo "✓ Completed $f"
    fi
done

echo ""
echo "=================================================="
echo "Loading Seed Data"
echo "=================================================="

# Execute seed data files
for f in /docker-entrypoint-initdb.d/seeds/*.sql; do
    if [ -f "$f" ]; then
        echo "Running $f..."
        psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -f "$f"
        echo "✓ Completed $f"
    fi
done

echo ""
echo "=================================================="
echo "Database Initialization Complete!"
echo "=================================================="
echo "Database: $POSTGRES_DB"
echo "User: $POSTGRES_USER"
echo "Port: 5432"
echo ""
echo "Supabase Studio available at: http://localhost:9000"
echo "Kong API Gateway available at: http://localhost:9002"
echo ""
echo "Default dev password: DevPassword123!"
echo "=================================================="