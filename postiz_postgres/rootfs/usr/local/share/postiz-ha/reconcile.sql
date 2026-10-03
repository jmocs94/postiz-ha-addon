-- -----------------------------------------------------------------------------
-- Postiz PostgreSQL app - idempotent role/database reconciliation.
--
-- Runs on EVERY start against a socket-only temporary server, as the local
-- "postgres" superuser (peer authentication). It never drops anything.
--   * creates roles/databases that are missing
--   * (re)applies the passwords from the app options, so changing a password
--     in the Configuration tab + restart is enough
--   * keeps each role confined to its own databases
--
-- Passwords are read from environment variables with \getenv and interpolated
-- with :'var', which psql quotes as a SQL literal (no injection, no logging).
-- Requires psql >= 15 (\getenv). The image ships psql 16.
-- -----------------------------------------------------------------------------
\set ON_ERROR_STOP on
\getenv postiz_pw POSTIZ_DB_PASSWORD
\getenv temporal_pw TEMPORAL_DB_PASSWORD

-- Roles ----------------------------------------------------------------------
SELECT 'CREATE ROLE postiz LOGIN'
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'postiz') \gexec
ALTER ROLE postiz WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION PASSWORD :'postiz_pw';

SELECT 'CREATE ROLE temporal LOGIN'
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'temporal') \gexec
ALTER ROLE temporal WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION PASSWORD :'temporal_pw';

-- Databases ------------------------------------------------------------------
SELECT 'CREATE DATABASE postiz OWNER postiz'
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'postiz') \gexec
SELECT 'CREATE DATABASE temporal OWNER temporal'
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'temporal') \gexec
SELECT 'CREATE DATABASE temporal_visibility OWNER temporal'
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'temporal_visibility') \gexec

-- Isolation: nobody but the owner may connect to each database ----------------
REVOKE ALL ON DATABASE postiz FROM PUBLIC;
REVOKE ALL ON DATABASE temporal FROM PUBLIC;
REVOKE ALL ON DATABASE temporal_visibility FROM PUBLIC;
GRANT ALL ON DATABASE postiz TO postiz;
GRANT ALL ON DATABASE temporal TO temporal;
GRANT ALL ON DATABASE temporal_visibility TO temporal;

-- Temporal's SQL visibility schema needs btree_gin. It is a trusted extension
-- on PostgreSQL 13+, but creating it here as superuser removes any doubt.
\connect temporal_visibility
CREATE EXTENSION IF NOT EXISTS btree_gin;
