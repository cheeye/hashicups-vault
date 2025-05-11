#!/bin/bash

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be ready..."
until PGPASSWORD=postgres psql -h postgres -U postgres -d postgres -c '\q'; do
  echo "PostgreSQL is unavailable - sleeping"
  sleep 1
done

echo "PostgreSQL is up - executing setup"

# Execute the initialization SQL file
echo "Executing initialization SQL..."
PGPASSWORD=postgres psql -h postgres -U postgres -d postgres -f /docker-entrypoint-initdb.d/init.sql

echo "PostgreSQL setup completed successfully"