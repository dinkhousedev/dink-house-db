-- ============================================================================
-- EXTENSIONS MODULE
-- Enable required PostgreSQL extensions in public schema
-- ============================================================================

-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" SCHEMA public;

-- Enable cryptographic functions for password hashing
CREATE EXTENSION IF NOT EXISTS "pgcrypto" SCHEMA public;

-- Enable case-insensitive text
CREATE EXTENSION IF NOT EXISTS "citext" SCHEMA public;