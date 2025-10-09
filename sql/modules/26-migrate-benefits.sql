-- Module 26: Migrate benefits column to prevent qty regex errors
-- Created: 2025-10-05
-- Purpose: Move benefits data to backup column and clear original to prevent
--          quantity regex from concatenating numbers (e.g., "2 months ($200 value)" → "2200")

BEGIN;

-- Step 1: Add backup column for benefits data
ALTER TABLE crowdfunding.contribution_tiers
ADD COLUMN IF NOT EXISTS benefits_backup jsonb;

-- Step 2: Copy all benefits data to the backup column
UPDATE crowdfunding.contribution_tiers
SET benefits_backup = benefits
WHERE benefits IS NOT NULL;

-- Step 3: Clear the original benefits column to prevent qty regex errors
UPDATE crowdfunding.contribution_tiers
SET benefits = '[]'::jsonb;

COMMIT;

-- Verification query (uncomment to check results):
-- SELECT id, name, benefits, benefits_backup FROM crowdfunding.contribution_tiers ORDER BY display_order;
