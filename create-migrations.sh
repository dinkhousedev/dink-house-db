#!/bin/bash
# Create properly ordered migrations for open play system

cd /home/ert/dink-house/dink-house-db

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

BASE_TS="20251008180000"

for i in "${!MODULES[@]}"; do
    MODULE="${MODULES[$i]}"
    SRC="sql/modules/$MODULE"
    if [ -f "$SRC" ]; then
        # Create timestamps that increment by 1 second
        TS=$(date -d "2025-10-08 18:00:00 + $i seconds" +%Y%m%d%H%M%S)
        DEST="supabase/migrations/${TS}_${MODULE}"
        cp "$SRC" "$DEST"
        echo "$TS -> $MODULE"
    fi
done

echo ""
echo "Created $(ls -1 supabase/migrations/202510081800* 2>/dev/null | wc -l) migration files"
