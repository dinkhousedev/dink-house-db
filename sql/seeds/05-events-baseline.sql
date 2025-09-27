-- ============================================================================
-- SEED DATA: Events Baseline
-- Courts and DUPR bracket catalog for scheduling
-- ============================================================================

SET search_path TO events, public;

-- Upsert courts (5 indoor, 5 outdoor)
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

-- Seed DUPR brackets
INSERT INTO events.dupr_brackets (
    label,
    min_rating,
    min_inclusive,
    max_rating,
    max_inclusive
) VALUES
    ('2.0 - 2.5', 2.0, true, 2.5, true),
    ('3.0 - 3.5', 3.0, true, 3.5, true),
    ('3.5 - 4.0', 3.5, true, 4.0, true),
    ('4.0 - 4.5', 4.0, true, 4.5, true),
    ('3.25+', 3.25, true, NULL, true),
    ('Up to 3.25', NULL, true, 3.25, true)
ON CONFLICT (label) DO UPDATE
SET
    min_rating = EXCLUDED.min_rating,
    min_inclusive = EXCLUDED.min_inclusive,
    max_rating = EXCLUDED.max_rating,
    max_inclusive = EXCLUDED.max_inclusive,
    updated_at = CURRENT_TIMESTAMP;
