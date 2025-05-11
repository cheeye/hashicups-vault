#!/bin/sh
###########
# Create PostgreSQL Tables and Configure Access
###########
echo "Creating PostgreSQL tables..."

# Create SQL file for table creation
cat << EOF > /tmp/create_tables.sql
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
EOF

# Execute SQL file to create tables
echo "Executing SQL file to create tables..."
PGPASSWORD=postgres psql -h postgres -U postgres -d postgres -f /tmp/create_tables.sql

# Remove the temporary SQL file
rm /tmp/create_tables.sql

echo "PostgreSQL tables created successfully."

###########
# Create permanent owner for tables
###########
echo "Creating permanent user for table ownership..."
PGPASSWORD=postgres psql -h postgres -U postgres -d postgres << EOF
-- Create permanent user for table ownership
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'permanent_owner') THEN
    CREATE ROLE permanent_owner WITH LOGIN PASSWORD 'secure_permanent_password';
  END IF;
END
\$\$;

-- Grant necessary permissions
GRANT ALL PRIVILEGES ON DATABASE postgres TO permanent_owner;
GRANT ALL PRIVILEGES ON SCHEMA public TO permanent_owner;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO permanent_owner;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO permanent_owner;

-- Change ownership of existing tables to permanent_owner
DO \$\$
DECLARE
  r RECORD;
BEGIN
  FOR r IN SELECT tablename FROM pg_tables WHERE schemaname = 'public'
  LOOP
    EXECUTE 'ALTER TABLE public.' || quote_ident(r.tablename) || ' OWNER TO permanent_owner';
  END LOOP;
END
\$\$;

-- Change ownership of sequences to permanent_owner
DO \$\$
DECLARE
  r RECORD;
BEGIN
  FOR r IN SELECT sequence_name FROM information_schema.sequences WHERE sequence_schema = 'public'
  LOOP
    EXECUTE 'ALTER SEQUENCE public.' || quote_ident(r.sequence_name) || ' OWNER TO permanent_owner';
  END LOOP;
END
\$\$;

-- Set default privileges for permanent_owner
ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT ALL PRIVILEGES ON TABLES TO permanent_owner;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT ALL PRIVILEGES ON SEQUENCES TO permanent_owner;

-- CRITICAL: Enable row-level security on tables (corrected syntax)
ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE test ENABLE ROW LEVEL SECURITY;

-- Create more explicit RLS policies
DROP POLICY IF EXISTS allow_all_transactions ON transactions;
CREATE POLICY allow_all_transactions ON transactions 
  FOR ALL 
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS allow_all_test ON test;
CREATE POLICY allow_all_test ON test 
  FOR ALL 
  USING (true)
  WITH CHECK (true);

-- Grant usage on schema to public role (needed for dynamic users)
GRANT USAGE ON SCHEMA public TO public;

-- Grant specific privileges to public role (needed for dynamic users)
GRANT SELECT, INSERT, UPDATE, DELETE ON transactions TO public;
GRANT SELECT, INSERT, UPDATE, DELETE ON test TO public;
GRANT USAGE, SELECT ON transactions_id_seq TO public;
GRANT USAGE, SELECT ON test_id_seq TO public;
EOF

###########
# Create and configure Vault user
###########
echo "Checking for Vault user in PostgreSQL..."

# Check if vault user exists
VAULT_EXISTS=$(PGPASSWORD=postgres psql -h postgres -U postgres -d postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='vault'")

if [ -z "$VAULT_EXISTS" ]; then
    echo "Creating Vault user in PostgreSQL..."
    PGPASSWORD=postgres psql -h postgres -U postgres -d postgres << EOF
    -- Create vault user with necessary privileges
    CREATE USER vault WITH PASSWORD 'vault' CREATEROLE BYPASSRLS;
    
    -- Grant database privileges
    GRANT ALL PRIVILEGES ON DATABASE postgres TO vault;
    GRANT ALL PRIVILEGES ON SCHEMA public TO vault;
    GRANT CONNECT ON DATABASE postgres TO vault;
    GRANT USAGE ON SCHEMA public TO vault;
EOF
    echo "Vault user created successfully with limited privileges."
else
    echo "Vault user already exists in PostgreSQL. Updating privileges..."
    PGPASSWORD=postgres psql -h postgres -U postgres -d postgres << EOF
    -- Update vault user privileges
    ALTER USER vault WITH CREATEROLE BYPASSRLS;
    GRANT ALL PRIVILEGES ON SCHEMA public TO vault;
    GRANT USAGE ON SCHEMA public TO vault;
EOF
    echo "Vault user privileges updated with limited ownership."
fi

# Grant specific privileges on existing objects
echo "Granting specific privileges on existing objects..."
PGPASSWORD=postgres psql -h postgres -U postgres -d postgres << EOF
-- Grant specific privileges on tables
GRANT SELECT, INSERT, UPDATE, DELETE ON transactions TO vault;
GRANT SELECT, INSERT, UPDATE, DELETE ON test TO vault;

-- Grant specific privileges on sequences
GRANT USAGE, SELECT ON transactions_id_seq TO vault;
GRANT USAGE, SELECT ON test_id_seq TO vault;

-- Set default privileges for future objects
ALTER DEFAULT PRIVILEGES IN SCHEMA public 
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO vault;

ALTER DEFAULT PRIVILEGES IN SCHEMA public 
GRANT USAGE, SELECT ON SEQUENCES TO vault;
EOF

# Create trigger function and event trigger
echo "Creating protection triggers..."
PGPASSWORD=postgres psql -h postgres -U postgres -d postgres << EOF
-- Create trigger function to prevent drops
CREATE OR REPLACE FUNCTION prevent_drop()
RETURNS event_trigger AS \$\$
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
\$\$ LANGUAGE plpgsql;

-- Drop existing event trigger if it exists
DO \$\$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_event_trigger WHERE evtname = 'protect_tables_trigger') THEN
    DROP EVENT TRIGGER protect_tables_trigger;
  END IF;
END
\$\$;

-- Create the event trigger
CREATE EVENT TRIGGER protect_tables_trigger ON sql_drop
  EXECUTE FUNCTION prevent_drop();

-- Set tables to allow everyone to bypass RLS (for testing)
ALTER TABLE transactions FORCE ROW LEVEL SECURITY;
ALTER TABLE test FORCE ROW LEVEL SECURITY;
EOF

echo "PostgreSQL setup completed successfully"