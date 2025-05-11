-- Create transactions table
CREATE TABLE IF NOT EXISTS transactions (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    card_number VARCHAR(25),
    card_number_transit VARCHAR(100),
    card_number_fpe VARCHAR(25),
    card_number_masked VARCHAR(25)
);

-- Create test table with dummy data (restricted access)
CREATE TABLE IF NOT EXISTS test (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100)
);

-- Insert dummy data into test table
INSERT INTO test (name) VALUES 
    ('Test User 1'),
    ('Test User 2'),
    ('Test User 3'),
    ('Test User 4');

-- Create permanent user for table ownership
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'permanent_owner') THEN
    CREATE ROLE permanent_owner WITH LOGIN PASSWORD 'secure_permanent_password';
  END IF;
END
$$;

-- Grant necessary permissions
GRANT ALL PRIVILEGES ON DATABASE postgres TO permanent_owner;
GRANT ALL PRIVILEGES ON SCHEMA public TO permanent_owner;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO permanent_owner;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO permanent_owner;

-- Change ownership of existing tables to permanent_owner
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN SELECT tablename FROM pg_tables WHERE schemaname = 'public'
  LOOP
    EXECUTE 'ALTER TABLE public.' || quote_ident(r.tablename) || ' OWNER TO permanent_owner';
  END LOOP;
END
$$;

-- Change ownership of sequences to permanent_owner
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN SELECT sequence_name FROM information_schema.sequences WHERE sequence_schema = 'public'
  LOOP
    EXECUTE 'ALTER SEQUENCE public.' || quote_ident(r.sequence_name) || ' OWNER TO permanent_owner';
  END LOOP;
END
$$;

-- Set default privileges for permanent_owner
ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT ALL PRIVILEGES ON TABLES TO permanent_owner;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT ALL PRIVILEGES ON SEQUENCES TO permanent_owner;

-- Enable row-level security on tables
ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE test ENABLE ROW LEVEL SECURITY;

-- Create RLS policies
CREATE POLICY allow_all_transactions ON transactions 
  FOR ALL 
  USING (true);

CREATE POLICY allow_all_test ON test 
  FOR ALL 
  USING (true);

-- Create Vault user if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'vault') THEN
    CREATE USER vault WITH PASSWORD 'vault' CREATEROLE;
  END IF;
END
$$;

-- Grant basic privileges
GRANT ALL PRIVILEGES ON DATABASE postgres TO vault;
GRANT ALL PRIVILEGES ON SCHEMA public TO vault;
GRANT CONNECT ON DATABASE postgres TO vault;
GRANT USAGE ON SCHEMA public TO vault;

-- Grant specific permissions on existing objects
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO vault;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO vault;

-- Create trigger function to prevent drops
CREATE OR REPLACE FUNCTION prevent_drop()
RETURNS event_trigger AS $$
DECLARE
  obj record;
BEGIN
  FOR obj IN SELECT * FROM pg_event_trigger_dropped_objects()
  LOOP
    IF obj.object_type = 'table' AND obj.schema_name = 'public' THEN
      IF obj.object_name IN ('transactions', 'test') THEN
        RAISE EXCEPTION 'Cannot drop protected table %', obj.object_name;
      END IF;
    END IF;
  END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Create the event trigger
DROP EVENT TRIGGER IF EXISTS protect_tables_trigger;
CREATE EVENT TRIGGER protect_tables_trigger ON sql_drop
  EXECUTE FUNCTION prevent_drop();

-- Set default privileges for future objects
ALTER DEFAULT PRIVILEGES IN SCHEMA public 
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO vault;

ALTER DEFAULT PRIVILEGES IN SCHEMA public 
GRANT USAGE, SELECT ON SEQUENCES TO vault;

-- Ensure vault can create roles
GRANT CREATEROLE TO vault;

-- Set tables to allow everyone to bypass RLS (for testing)
ALTER TABLE transactions FORCE ROW LEVEL SECURITY;
ALTER TABLE test FORCE ROW LEVEL SECURITY; 