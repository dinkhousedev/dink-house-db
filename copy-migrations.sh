#!/bin/bash
# Copy open play modules to Supabase migrations folder

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

COUNTER=0
for MODULE in "${MODULES[@]}"; do
    SRC="sql/modules/$MODULE"
    if [ -f "$SRC" ]; then
        TIMESTAMP=$(date -d "2025-10-08 18:00:00 + $COUNTER minutes" +%Y%m%d%H%M%S)
        DEST="supabase/migrations/${TIMESTAMP}_${MODULE}"
        cp "$SRC" "$DEST"
        echo "Copied: $MODULE -> $DEST"
        ((COUNTER++))
    fi
done
