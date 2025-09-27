#!/bin/bash

# Events Module Migration Script
# Run this script to add the events calendar system to your database

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Database connection details
DB_HOST=${DB_HOST:-localhost}
DB_PORT=${DB_PORT:-9432}
DB_NAME=${DB_NAME:-dink_house}
DB_USER=${DB_USER:-postgres}

echo -e "${YELLOW}Starting Events Module Migration...${NC}"
echo "Database: $DB_NAME"
echo "Host: $DB_HOST:$DB_PORT"
echo ""

# Function to run SQL file
run_sql_file() {
    local file=$1
    local description=$2

    echo -e "${YELLOW}Running: $description${NC}"

    if PGPASSWORD=${DB_PASSWORD:-postgres} psql \
        -h $DB_HOST \
        -p $DB_PORT \
        -U $DB_USER \
        -d $DB_NAME \
        -f "$file" \
        --quiet \
        --single-transaction; then
        echo -e "${GREEN}✓ $description completed${NC}"
    else
        echo -e "${RED}✗ Failed to run $description${NC}"
        exit 1
    fi
    echo ""
}

# Check if database is accessible
echo -e "${YELLOW}Checking database connection...${NC}"
if PGPASSWORD=${DB_PASSWORD:-postgres} psql \
    -h $DB_HOST \
    -p $DB_PORT \
    -U $DB_USER \
    -d $DB_NAME \
    -c "SELECT 1" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Database connection successful${NC}"
else
    echo -e "${RED}✗ Cannot connect to database${NC}"
    exit 1
fi
echo ""

# Run migration files in order
run_sql_file "sql/modules/16-events.sql" "Events Schema"
run_sql_file "sql/modules/17-events-api.sql" "Events API Views"
run_sql_file "sql/modules/18-events-rls.sql" "Events RLS Policies"
run_sql_file "sql/modules/19-events-functions.sql" "Events API Functions"

# Insert sample data
echo -e "${YELLOW}Inserting sample data...${NC}"

PGPASSWORD=${DB_PASSWORD:-postgres} psql \
    -h $DB_HOST \
    -p $DB_PORT \
    -U $DB_USER \
    -d $DB_NAME \
    --quiet <<EOF
-- Insert sample courts
INSERT INTO events.courts (court_number, name, surface_type, environment, status, location, max_capacity)
VALUES
    (1, 'Court 1 Indoor', 'hard', 'indoor', 'available', 'Indoor Pavilion', 4),
    (2, 'Court 2 Indoor', 'hard', 'indoor', 'available', 'Indoor Pavilion', 4),
    (3, 'Court 3 Indoor', 'hard', 'indoor', 'available', 'Indoor Pavilion', 4),
    (4, 'Court 4 Indoor', 'hard', 'indoor', 'available', 'Indoor Pavilion', 4),
    (5, 'Court 5 Indoor', 'hard', 'indoor', 'available', 'Indoor Pavilion', 4),
    (6, 'Court 6 Outdoor', 'hard', 'outdoor', 'available', 'Championship Plaza', 4),
    (7, 'Court 7 Outdoor', 'hard', 'outdoor', 'available', 'Championship Plaza', 4),
    (8, 'Court 8 Outdoor', 'hard', 'outdoor', 'available', 'Championship Plaza', 4),
    (9, 'Court 9 Outdoor', 'hard', 'outdoor', 'available', 'Championship Plaza', 4),
    (10, 'Court 10 Outdoor', 'hard', 'outdoor', 'available', 'Championship Plaza', 4)
ON CONFLICT (court_number) DO UPDATE
SET
    name = EXCLUDED.name,
    surface_type = EXCLUDED.surface_type,
    environment = EXCLUDED.environment,
    status = EXCLUDED.status,
    location = EXCLUDED.location,
    max_capacity = EXCLUDED.max_capacity,
    updated_at = CURRENT_TIMESTAMP;

-- Insert sample event templates
INSERT INTO events.event_templates (
    name,
    description,
    event_type,
    duration_minutes,
    max_capacity,
    min_capacity,
    skill_levels,
    price_member,
    price_guest,
    court_preferences,
    dupr_range_label,
    dupr_min_rating,
    dupr_max_rating,
    dupr_open_ended,
    dupr_min_inclusive,
    dupr_max_inclusive,
    equipment_provided
)
VALUES
    (
        'Tuesday Night Scramble',
        'Popular weekly scramble format with mixed skill levels',
        'event_scramble',
        120,
        16,
        8,
        ARRAY['2.5', '3.0', '3.5', '4.0']::events.skill_level[],
        15.00,
        20.00,
        '{"count": 2}'::jsonb,
        NULL,
        NULL,
        NULL,
        false,
        true,
        true,
        true
    ),
    (
        'DUPR Friday Night',
        'Official DUPR-rated matches',
        'dupr_open_play',
        180,
        12,
        4,
        ARRAY['3.0', '3.5', '4.0', '4.5', '5.0']::events.skill_level[],
        20.00,
        25.00,
        '{"count": 4}'::jsonb,
        '3.0 - 3.5',
        3.0,
        3.5,
        false,
        true,
        true,
        false
    ),
    (
        'Beginner Open Play',
        'Relaxed open play for beginners',
        'event_scramble',
        120,
        20,
        4,
        ARRAY['2.0', '2.5', '3.0']::events.skill_level[],
        10.00,
        15.00,
        '{"count": 4}'::jsonb,
        NULL,
        NULL,
        NULL,
        false,
        true,
        true,
        true
    ),
    (
        'Weekend Tournament',
        'Competitive weekend tournament',
        'non_dupr_tournament',
        480,
        32,
        16,
        ARRAY['3.5', '4.0', '4.5', '5.0']::events.skill_level[],
        50.00,
        60.00,
        '{"count": 6}'::jsonb,
        NULL,
        NULL,
        NULL,
        false,
        true,
        true,
        false
    )
ON CONFLICT DO NOTHING;

COMMIT;
EOF

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Sample data inserted${NC}"
else
    echo -e "${YELLOW}⚠ Sample data may already exist${NC}"
fi
echo ""

# Verify installation
echo -e "${YELLOW}Verifying installation...${NC}"

VERIFICATION=$(PGPASSWORD=${DB_PASSWORD:-postgres} psql \
    -h $DB_HOST \
    -p $DB_PORT \
    -U $DB_USER \
    -d $DB_NAME \
    -t \
    -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'events'")

if [ "$VERIFICATION" -gt 0 ]; then
    echo -e "${GREEN}✓ Events module installed successfully!${NC}"
    echo ""
    echo "Tables created in 'events' schema:"
    PGPASSWORD=${DB_PASSWORD:-postgres} psql \
        -h $DB_HOST \
        -p $DB_PORT \
        -U $DB_USER \
        -d $DB_NAME \
        -c "SELECT table_name FROM information_schema.tables WHERE table_schema = 'events' ORDER BY table_name"
else
    echo -e "${RED}✗ Installation verification failed${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}==================================${NC}"
echo -e "${GREEN}Events Module Migration Complete!${NC}"
echo -e "${GREEN}==================================${NC}"
echo ""
echo "You can now use the events calendar system in your application."
echo "API functions available:"
echo "  - api.create_event_with_courts()"
echo "  - api.create_recurring_events()"
echo "  - api.check_court_availability()"
echo "  - api.register_for_event()"
echo "  - api.get_event_calendar()"
echo ""
echo "Views available:"
echo "  - api.events_calendar_view"
echo "  - api.court_availability_view"
echo "  - api.upcoming_events_view"
echo "  - api.daily_schedule_view"
