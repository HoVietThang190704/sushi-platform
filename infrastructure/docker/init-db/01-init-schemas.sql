-- =============================================================================
-- Sushi Platform - Initial PostgreSQL Schemas and Roles Setup
-- =============================================================================

-- Enable pgcrypto for UUID generation
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 1. Create service schemas
CREATE SCHEMA IF NOT EXISTS identity;
CREATE SCHEMA IF NOT EXISTS catalog;
CREATE SCHEMA IF NOT EXISTS ordering;
CREATE SCHEMA IF NOT EXISTS inventory;
CREATE SCHEMA IF NOT EXISTS purchasing;
CREATE SCHEMA IF NOT EXISTS finance;

-- 2. Create service-specific users if not exists
DO
$do$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'identity_app') THEN
      CREATE ROLE identity_app WITH LOGIN PASSWORD 'change_me_local';
   END IF;
   IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'catalog_app') THEN
      CREATE ROLE catalog_app WITH LOGIN PASSWORD 'change_me_local';
   END IF;
   IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'ordering_app') THEN
      CREATE ROLE ordering_app WITH LOGIN PASSWORD 'change_me_local';
   END IF;
   IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'inventory_app') THEN
      CREATE ROLE inventory_app WITH LOGIN PASSWORD 'change_me_local';
   END IF;
   IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'purchasing_app') THEN
      CREATE ROLE purchasing_app WITH LOGIN PASSWORD 'change_me_local';
   END IF;
   IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'finance_app') THEN
      CREATE ROLE finance_app WITH LOGIN PASSWORD 'change_me_local';
   END IF;
END
$do$;

-- 3. Grant schema permissions
GRANT ALL ON SCHEMA identity TO identity_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA identity GRANT ALL ON TABLES TO identity_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA identity GRANT ALL ON SEQUENCES TO identity_app;

GRANT ALL ON SCHEMA catalog TO catalog_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA catalog GRANT ALL ON TABLES TO catalog_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA catalog GRANT ALL ON SEQUENCES TO catalog_app;

GRANT ALL ON SCHEMA ordering TO ordering_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA ordering GRANT ALL ON TABLES TO ordering_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA ordering GRANT ALL ON SEQUENCES TO ordering_app;

GRANT ALL ON SCHEMA inventory TO inventory_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA inventory GRANT ALL ON TABLES TO inventory_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA inventory GRANT ALL ON SEQUENCES TO inventory_app;

GRANT ALL ON SCHEMA purchasing TO purchasing_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA purchasing GRANT ALL ON TABLES TO purchasing_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA purchasing GRANT ALL ON SEQUENCES TO purchasing_app;

GRANT ALL ON SCHEMA finance TO finance_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA finance GRANT ALL ON TABLES TO finance_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA finance GRANT ALL ON SEQUENCES TO finance_app;
