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

# Check and create Vault user in PostgreSQL if it doesn't exist
echo "Checking for Vault user in PostgreSQL..."
if ! PGPASSWORD=postgres psql -h postgres -U postgres -d postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='vault'" | grep -q 1; then
    echo "Creating Vault user in PostgreSQL..."
    PGPASSWORD=postgres psql -h postgres -U postgres -d postgres -c "CREATE USER vault WITH PASSWORD 'vault' CREATEDB CREATEROLE SUPERUSER;"
    PGPASSWORD=postgres psql -h postgres -U postgres -d postgres -c "GRANT ALL PRIVILEGES ON DATABASE postgres TO vault WITH GRANT OPTION;"
    PGPASSWORD=postgres psql -h postgres -U postgres -d postgres -c "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO vault WITH GRANT OPTION;"
    PGPASSWORD=postgres psql -h postgres -U postgres -d postgres -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON TABLES TO vault WITH GRANT OPTION;"
    PGPASSWORD=postgres psql -h postgres -U postgres -d postgres -c "GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO vault WITH GRANT OPTION;"
    PGPASSWORD=postgres psql -h postgres -U postgres -d postgres -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO vault WITH GRANT OPTION;"
    echo "Vault user created successfully with CREATEROLE privilege."
else
    echo "Vault user already exists in PostgreSQL. Updating privileges..."
    PGPASSWORD=postgres psql -h postgres -U postgres -d postgres -c "ALTER USER vault WITH CREATEROLE SUPERUSER;"
    PGPASSWORD=postgres psql -h postgres -U postgres -d postgres -c "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO vault WITH GRANT OPTION;"
    PGPASSWORD=postgres psql -h postgres -U postgres -d postgres -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON TABLES TO vault WITH GRANT OPTION;"
    PGPASSWORD=postgres psql -h postgres -U postgres -d postgres -c "GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO vault WITH GRANT OPTION;"
    PGPASSWORD=postgres psql -h postgres -U postgres -d postgres -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO vault WITH GRANT OPTION;"
    echo "Vault user privileges updated."
fi
