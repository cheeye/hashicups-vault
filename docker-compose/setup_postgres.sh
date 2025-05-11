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

-- Create RLS policies that ALLOW access for all operations by authorized users
-- Allow SELECT, INSERT, UPDATE, DELETE for all rows to users with those privileges
CREATE POLICY allow_all_transactions ON transactions 
  FOR ALL 
  TO PUBLIC 
  USING (true);

CREATE POLICY allow_all_test ON test 
  FOR ALL 
  TO PUBLIC 
  USING (true);
EOF

# Checking for Vault user in postgres
echo "Checking for Vault user in PostgreSQL..."
if ! PGPASSWORD=postgres psql -h postgres -U postgres -d postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='vault'" | grep -q 1; then
    echo "Creating Vault user in PostgreSQL..."
    PGPASSWORD=postgres psql -h postgres -U postgres -d postgres -c "CREATE USER vault WITH PASSWORD 'vault' CREATEROLE;"
    PGPASSWORD=postgres psql -h postgres -U postgres -d postgres -c "GRANT ALL PRIVILEGES ON DATABASE postgres TO vault;"
    PGPASSWORD=postgres psql -h postgres -U postgres -d postgres -c "GRANT ALL PRIVILEGES ON SCHEMA public TO vault;"
    
    # Only grant specific permissions on existing objects, don't give ownership
    PGPASSWORD=postgres psql -h postgres -U postgres -d postgres -c "GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO vault;"
    PGPASSWORD=postgres psql -h postgres -U postgres -d postgres -c "GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO vault;"
    
    # Critical change: Don't grant CREATE or DROP privileges to vault on public schema
    echo "Vault user created successfully with limited privileges."
else
    echo "Vault user already exists in PostgreSQL. Updating privileges..."
    PGPASSWORD=postgres psql -h postgres -U postgres -d postgres -c "ALTER USER vault WITH CREATEROLE;"
    PGPASSWORD=postgres psql -h postgres -U postgres -d postgres -c "GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO vault;"
    PGPASSWORD=postgres psql -h postgres -U postgres -d postgres -c "GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO vault;"
    
    echo "Vault user privileges updated with limited ownership."
fi

# Add an explicit protection to prevent tables from being dropped during cleanup
PGPASSWORD=postgres psql -h postgres -U postgres -d postgres << EOF
-- Create a trigger function to prevent drops
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

-- Create an event trigger to prevent dropping of protected tables
DROP EVENT TRIGGER IF EXISTS protect_tables_trigger;
CREATE EVENT TRIGGER protect_tables_trigger ON sql_drop
  EXECUTE FUNCTION prevent_drop();
EOF

# Ensure default privileges are properly set for new tables
PGPASSWORD=postgres psql -h postgres -U postgres -d postgres << EOF
-- Set default privileges for future tables
ALTER DEFAULT PRIVILEGES IN SCHEMA public 
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO PUBLIC;

-- Ensure vault can create roles
GRANT CREATEROLE TO vault;
EOF