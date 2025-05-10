#!/bin/bash

# Check if OS parameter is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <os_user>"
    exit 1
fi

DISTRO="linux1"

OS_USER="$1"

# Check if system is registered with Red Hat Subscription Management
if command -v subscription-manager &> /dev/null; then
    SUBSCRIPTION_STATUS=$(sudo subscription-manager status 2>&1 | grep -c "Overall Status: Current")
    if [ "$SUBSCRIPTION_STATUS" -eq 0 ]; then
        echo "WARNING: This system is not registered with Red Hat Subscription Management."
        echo "Some packages may not be available. We'll use alternative repositories where possible."
        
        # Configure EPEL repository if not already installed
        if ! rpm -qa | grep -q epel-release; then
            echo "Installing EPEL repository..."
            sudo yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-$(rpm -E %rhel).noarch.rpm
        fi
    fi
fi

# Update system packages with error handling
echo "Updating system packages..."
sudo yum update -y || echo "WARNING: Unable to update all packages. Continuing with installation."

# Install required packages- jq
if ! command -v jq &> /dev/null; then
    echo "Installing jq..."
    sudo yum install jq -y || {
        echo "Failed to install jq using default repositories."
        echo "Attempting to install from EPEL repository..."
        sudo yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-$(rpm -E %rhel).noarch.rpm
        sudo yum install jq -y || echo "WARNING: Unable to install jq. Some functionality may be limited."
    }
fi



###########
# Install Docker
###########
if ! command -v docker &> /dev/null; then
    echo "Docker not found. Installing..."
    sudo yum install -y yum-utils || echo "Failed to install yum-utils, continuing anyway"
    
    # Determine OS version and type
    if [ -f /etc/redhat-release ]; then
        if grep -q "Red Hat Enterprise Linux" /etc/redhat-release; then
            # RHEL system
            OS_TYPE="rhel"
        elif grep -q "CentOS Stream" /etc/redhat-release; then
            # CentOS Stream
            OS_TYPE="centos"
        elif grep -q "CentOS Linux" /etc/redhat-release; then
            # CentOS Linux
            OS_TYPE="centos"
        elif grep -q "Rocky Linux" /etc/redhat-release || grep -q "AlmaLinux" /etc/redhat-release; then
            # Rocky/Alma Linux (RHEL clones)
            OS_TYPE="centos"
        else
            # Default to CentOS for unknown RHEL-like systems
            OS_TYPE="centos"
        fi
    else
        # Default to CentOS if can't determine
        OS_TYPE="centos"
    fi
    
    # Add Docker repository based on OS type
    if [ "$OS_TYPE" = "rhel" ]; then
        echo "Adding Docker repository for RHEL..."
        sudo yum-config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo || {
            echo "Failed to add official Docker RHEL repository, falling back to CentOS repository"
            sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        }
    else
        echo "Adding Docker repository for CentOS..."
        sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    fi
    
    # Install Docker
    echo "Installing Docker packages..."
    sudo yum install -y docker-ce docker-ce-cli containerd.io || {
        echo "Failed to install Docker with standard repositories"
        echo "Installing Docker using alternative method..."
        curl -fsSL https://get.docker.com/ | sh
    }

    # Add current user to docker group
    sudo usermod -aG docker $USER
    
    # Enable and start Docker service
    sudo systemctl enable docker
    sudo systemctl start docker

    newgrp docker <<EONG
echo "Docker installation complete and sudo is no longer required."
EONG

    echo "Docker installation complete."
else
    echo "Docker is already installed."
fi

# Install Docker-Compose with better error handling
###########
install_docker_compose() {
  echo "Installing Docker Compose..."
  
  # First, remove any existing failed installation
  sudo rm -f /usr/local/bin/docker-compose
  
  # Detect architecture
  ARCH=$(uname -m)
  OS=$(uname -s)
  
  # Latest stable version (you can change this as needed)
  COMPOSE_VERSION="v2.24.5"
  
  # For newer Docker Compose v2 (recommended)
  echo "Downloading Docker Compose ${COMPOSE_VERSION}..."
  
  # Create a temporary directory for downloads
  TEMP_DIR=$(mktemp -d)
  cd "$TEMP_DIR" || exit 1
  
  # Download Docker Compose binary appropriate for this architecture
  if [ "$ARCH" = "x86_64" ]; then
    echo "Detected x86_64 architecture"
    sudo curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-${OS}-${ARCH}" -o /usr/local/bin/docker-compose
  elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    echo "Detected ARM64 architecture"
    sudo curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-${OS}-aarch64" -o /usr/local/bin/docker-compose
  elif [ "$ARCH" = "s390x" ]; then
    echo "Detected s390x architecture"
    sudo curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-${OS}-s390x" -o /usr/local/bin/docker-compose
  elif [ "$ARCH" = "ppc64le" ]; then
    echo "Detected ppc64le architecture"
    sudo curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-${OS}-ppc64le" -o /usr/local/bin/docker-compose
  else
    echo "Architecture $ARCH not directly supported - trying x86_64 version"
    sudo curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-${OS}-x86_64" -o /usr/local/bin/docker-compose
  fi
  
  # Verify the download was successful
  if [ ! -s /usr/local/bin/docker-compose ]; then
    echo "Docker Compose download failed or resulted in empty file."
    echo "Trying alternative approach with Docker Compose plugin..."
    
    # Alternative: Use Docker CLI plugin
    mkdir -p ~/.docker/cli-plugins/
    curl -SL "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-${OS}-${ARCH}" -o ~/.docker/cli-plugins/docker-compose
    chmod +x ~/.docker/cli-plugins/docker-compose
    
    # Create symlink for compatibility
    sudo ln -sf ~/.docker/cli-plugins/docker-compose /usr/local/bin/docker-compose
    
    # Alternative 2: Install through package manager if available
    if command -v apt-get &> /dev/null; then
      echo "Trying installation through apt..."
      sudo apt-get update
      sudo apt-get install -y docker-compose
    elif command -v yum &> /dev/null; then
      echo "Trying installation through yum..."
      sudo yum install -y docker-compose
    fi
  fi
  
  # Make executable
  sudo chmod +x /usr/local/bin/docker-compose
  
  # Clean up
  cd - > /dev/null
  rm -rf "$TEMP_DIR"
  
  # Test installation
  if docker-compose --version; then
    echo "Docker Compose installation successful."
  else
    echo "WARNING: Docker Compose installation may have failed. Please install manually."
  fi
}

# Check if docker-compose is installed and working
if ! command -v docker-compose &> /dev/null || ! docker-compose --version &> /dev/null; then
  echo "Docker Compose not found or not working properly. Installing..."
  install_docker_compose
else
  echo "Docker Compose is already installed. Version: $(docker-compose --version)"
fi
echo "Setup complete. Please log out and log back in for group changes to take effect."

###########
# Install Postgres client for testing
###########
if ! command -v psql &> /dev/null; then
    echo "PostgreSQL client not found. Installing..."
    sudo yum install -y postgresql
    echo "PostgreSQL client installation complete."
else
    echo "PostgreSQL client is already installed."
fi

###########
# Install Vault Enterprise using direct binary download
###########
if ! command -v vault &> /dev/null; then
    echo "Vault not found. Installing Vault Enterprise..."
    
    # Install required packages for downloading and unzipping
    echo "Installing required tools..."
    sudo yum install -y curl unzip wget
    
    # Create a temporary directory for download
    TEMP_DIR=$(mktemp -d)
    cd $TEMP_DIR
    
    # Detect system architecture
    ARCH=$(uname -m)
    VAULT_VERSION="1.19.2+ent"
    
    if [ "$ARCH" = "s390x" ]; then
        echo "Detected s390x architecture. Downloading appropriate Vault binary..."
        VAULT_URL="https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_s390x.zip"
    else
        echo "Detected ${ARCH} architecture. Defaulting to amd64 Vault binary..."
        VAULT_URL="https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip"
    fi
    
    echo "Downloading Vault from ${VAULT_URL}..."
    wget $VAULT_URL -O vault.zip || curl -o vault.zip $VAULT_URL
    
    if [ ! -f vault.zip ]; then
        echo "Failed to download Vault binary. Please check the URL and try again."
        exit 1
    fi
    
    echo "Extracting Vault binary..."
    unzip vault.zip
    
    echo "Installing Vault binary..."
    sudo mv vault /usr/local/bin/
    sudo chmod +x /usr/local/bin/vault
    
    # Create vault user and group
    echo "Creating vault user and group..."
    if ! getent group vault >/dev/null; then
        sudo groupadd vault
    fi
    if ! getent passwd vault >/dev/null; then
        sudo useradd -r -g vault -s /bin/false vault
    fi
    
    # Create necessary directories
    echo "Creating Vault directories..."
    sudo mkdir -p /etc/vault.d
    sudo mkdir -p /opt/vault/data
    
    # Set Vault version command
    /usr/local/bin/vault version
    
    # Clean up
    cd - >/dev/null
    rm -rf $TEMP_DIR
    
    echo "Vault Enterprise installation complete."
else
    echo "Vault is already installed. Version:"
    vault version
fi

# Create vault directory and configuration
[ ! -d "/etc/vault.d" ] && sudo mkdir -p /etc/vault.d

sudo chcon -t bin_t /usr/local/bin/vault

# Create vault user and group if they don't exist
if ! getent group vault >/dev/null; then
    sudo groupadd vault
fi
if ! getent passwd vault >/dev/null; then
    sudo useradd -r -g vault -s /bin/false vault
fi

# Create license directory and set permissions
[ ! -d "/etc/vault.d/license" ] && sudo mkdir -p /etc/vault.d/license
sudo chown -R vault:vault /etc/vault.d/license
sudo chmod 750 /etc/vault.d/license

# Copy license file to vault directory if it exists
if [ -f "/home/$OS_USER/license.hclic" ]; then
    echo "Copying license file to Vault directory..."
    sudo cp "/home/$OS_USER/license.hclic" /etc/vault.d/license/
    sudo chown vault:vault /etc/vault.d/license/license.hclic
    sudo chmod 640 /etc/vault.d/license/license.hclic
else
    echo "Warning: License file not found at /home/$OS_USER/license.hclic"
    echo "Please ensure the license file is present before starting Vault"
fi

# Get host IP addressa
HOST_IP=$(hostname -I | awk '{print $1}')

sudo tee /etc/vault.d/vault.hcl > /dev/null << EOF
storage "raft" {
  path = "/opt/vault/data"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1
}

api_addr = "http://${HOST_IP}:8200"
cluster_addr = "http://${HOST_IP}:8201"
ui = true
disable_mlock = true
license_path  = "/etc/vault.d/license/license.hclic"
EOF

# Set proper permissions
sudo chown -R vault:vault /etc/vault.d
sudo chmod 640 /etc/vault.d/vault.hcl

# Copy license file to vault directory if it exists
echo "Checking for license file..."
if [ -f "/home/${OS_USER}/license.hclic" ]; then
    echo "Copying license file to Vault directory..."
    sudo cp "/home/${OS_USER}/license.hclic" /etc/vault.d/license/
    sudo chown vault:vault /etc/vault.d/license/license.hclic
    sudo chmod 640 /etc/vault.d/license/license.hclic
else
    echo "Warning: License file not found at /home/${OS_USER}/license.hclic"
    echo "Please ensure the license file is present before starting Vault"
fi

# Create data directory
[ ! -d "/opt/vault/data" ] && sudo mkdir -p /opt/vault/data
sudo chown -R vault:vault /opt/vault/data

# Create and configure systemd service
sudo tee /usr/lib/systemd/system/vault-enterprise.service > /dev/null << EOF
[Unit]
Description="HashiCorp Vault - A tool for managing secrets"
Documentation=https://developer.hashicorp.com/vault/docs
Requires=network-online.target
After=network-online.target

[Service]
ExecStart=/usr/local/bin/vault server -config=/etc/vault.d/vault.hcl
User=vault
Group=vault
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and start Vault
echo "Configuring Vault service..."
sudo systemctl daemon-reload
sudo systemctl enable vault-enterprise

echo "Starting Vault service..."
sudo systemctl start vault-enterprise

# Wait for Vault to be ready
echo "Waiting for Vault to be ready..."
sleep 10

# Set Vault address
export VAULT_ADDR="http://127.0.0.1:8200"
echo "export VAULT_ADDR=http://127.0.0.1:8200" >> ~/.bashrc

# Check if Vault is already initialized
if vault status | grep -q "Initialized.*true"; then
    echo "Vault is already initialized."
    # Set VAULT_TOKEN from existing root token if available
    if [ -f "/home/$OS_USER/vault-creds/root_token.txt" ]; then
        export VAULT_TOKEN=$(cat "/home/$OS_USER/vault-creds/root_token.txt")
        echo "export VAULT_TOKEN=$VAULT_TOKEN" >> ~/.bashrc
    fi
else
    # Initialize Vault and save keys
    echo "Initializing Vault..."
    [ ! -d "/home/$OS_USER/vault-creds" ] && sudo mkdir -p "/home/$OS_USER/vault-creds"
    sudo chown -R "$OS_USER:$OS_USER" "/home/$OS_USER/vault-creds"

    # Initialize Vault and capture output
    INIT_OUTPUT=$(/usr/local/bin/vault operator init -key-shares=3 -key-threshold=2 -format=json)
    
    # Save the complete initialization output for reference
    echo "$INIT_OUTPUT" > "/home/$OS_USER/vault-creds/init_output.json"
    
    # Extract and save keys and root token
    echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[0]' > "/home/$OS_USER/vault-creds/key1.txt"
    echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[1]' > "/home/$OS_USER/vault-creds/key2.txt"
    echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[2]' > "/home/$OS_USER/vault-creds/key3.txt"
    echo "$INIT_OUTPUT" | jq -r '.root_token' > "/home/$OS_USER/vault-creds/root_token.txt"

    # Set VAULT_TOKEN from newly generated root token
    export VAULT_TOKEN=$(cat "/home/$OS_USER/vault-creds/root_token.txt")
    echo "export VAULT_TOKEN=$VAULT_TOKEN" >> ~/.bashrc

    # Set proper permissions for the credentials
    sudo chown -R "$OS_USER:$OS_USER" "/home/$OS_USER/vault-creds"
    sudo chmod 600 "/home/$OS_USER/vault-creds"/*
fi

# Check if Vault is sealed and unseal if necessary
if /usr/local/bin/vault status | grep -q "Sealed.*true"; then
    echo "Vault is sealed. Unsealing..."
    # Use the first two keys to unseal (since threshold is 2)
    /usr/local/bin/vault operator unseal $(cat "/home/$OS_USER/vault-creds/key1.txt")
    /usr/local/bin/vault operator unseal $(cat "/home/$OS_USER/vault-creds/key2.txt")
    echo "Vault has been unsealed."
else
    echo "Vault is already unsealed."
fi

# Check Vault status and exit
echo "Checking Vault service status..."
sudo systemctl status vault-enterprise --no-pager

echo "Vault setup complete. You can access the UI at http://${HOST_IP}:8200"
echo "Unseal keys and root token have been saved to /home/${OS_USER}/vault-creds/"

###########
# Enable Transform Secrets Engine
###########
if ! /usr/local/bin/vault secrets list | grep -q "transform/"; then
    echo "Enabling Transform Secrets Engine..."
    /usr/local/bin/vault secrets enable transform
else
    echo "Transform Secrets Engine is already enabled."
fi

###########
# Create Role for Payments
###########
if ! /usr/local/bin/vault read transform/role/payments &>/dev/null; then
    echo "Creating Role for Payments..."
    /usr/local/bin/vault write transform/role/payments transformations=card-number
else
    echo "Payments role already exists."
fi

###########
# Create Transformation for Card Number
###########
if ! /usr/local/bin/vault read transform/transformation/card-number &>/dev/null; then
    echo "Creating Transformation for Card Number..."
    /usr/local/bin/vault write transform/transformation/card-number \
        type=fpe \
        template="builtin/creditcardnumber" \
        tweak_source=internal \
        allowed_roles=payments
else
    echo "Card Number transformation already exists."
fi

###########
# Create template for masked transformation
###########
if ! /usr/local/bin/vault read transform/template/masked-all-last4-card-number &>/dev/null; then
    echo "Creating template for masked transformation..."
    /usr/local/bin/vault write transform/template/masked-all-last4-card-number type=regex \
      pattern='(\d{4})[-]?(\d{4})[-]?(\d{4})[-]?\d{4}' \
      alphabet=numerics
else
    echo "Masked transformation template already exists."
fi

###########
# Create masked-card-number transformation
###########
if ! /usr/local/bin/vault read transform/transformation/masked-card-number &>/dev/null; then
    echo "Creating masked-card-number transformation..."
    /usr/local/bin/vault write transform/transformation/masked-card-number \
        type=masking \
        template=masked-all-last4-card-number \
        tweak_source=internal \
        allowed_roles=custsupport \
        masking_character="X"
else
    echo "Masked-card-number transformation already exists."
fi

###########
# Add masked-card-number transformation to payments role
###########
if ! /usr/local/bin/vault read transform/role/custsupport &>/dev/null; then
    echo "Adding masked-card-number transformation to custsupport role..."
    /usr/local/bin/vault write transform/role/custsupport \
        transformations=masked-card-number
else
    echo "Custsupport role already exists."
fi


###########
# Enable Transit Secrets Engine for Card Encryption
###########
echo "Setting up Transit Secrets Engine for card number encryption..."

# Enable Transit secrets engine if not already enabled
if ! /usr/local/bin/vault secrets list | grep -q "transit/"; then
    echo "Enabling Transit Secrets Engine..."
    /usr/local/bin/vault secrets enable transit
    echo "Transit Secrets Engine enabled."
else
    echo "Transit Secrets Engine already enabled."
fi

# Create encryption key for card numbers if it doesn't exist
if ! /usr/local/bin/vault read transit/keys/card-encrypt &>/dev/null; then
    echo "Creating encryption key for card numbers..."
    /usr/local/bin/vault write -f transit/keys/card-encrypt \
        type=aes256-gcm96 \
        auto_rotate_period="168h"  # Auto-rotate every 7 days
    echo "Encryption key created with 7-day auto-rotation policy."
else
    echo "Encryption key for card numbers already exists."
fi

###########
# Start PostgreSQL container with persistence if not running
###########
echo "Checking PostgreSQL container..."
if ! sudo docker ps | grep -q "postgres.*5432"; then
    echo "Starting PostgreSQL container with data persistence..."
    
    # Create data directory for PostgreSQL persistence
    sudo mkdir -p /var/lib/postgresql/data
    sudo chmod 777 /var/lib/postgresql/data
    
    sudo docker run --name postgres \
      -e POSTGRES_PASSWORD=postgres \
      -e POSTGRES_USER=postgres \
      -e POSTGRES_DB=postgres \
      -p 5432:5432 \
      -v /var/lib/postgresql/data:/var/lib/postgresql/data \
      -d postgres:latest
      
    echo "PostgreSQL container started with persistent storage."
    
    # Wait for PostgreSQL to be ready
    echo "Waiting for PostgreSQL to initialize..."
    sleep 15
else
    echo "PostgreSQL container is already running."
fi

###########
# Setup Database Credentials Engine
###########
echo "Setting up Database Credentials Engine..."

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be ready..."
sleep 10

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
PGPASSWORD=postgres psql -h localhost -U postgres -d postgres -f /tmp/create_tables.sql

# Remove the temporary SQL file
rm /tmp/create_tables.sql

echo "PostgreSQL tables created successfully."

###########
# Create permanent owner for tables
###########
echo "Creating permanent user for table ownership..."
PGPASSWORD=postgres psql -h localhost -U postgres -d postgres << EOF
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

-- Change ownership of existing tables
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

-- Change ownership of sequences
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

-- Set default privileges
ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT ALL PRIVILEGES ON TABLES TO permanent_owner;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT ALL PRIVILEGES ON SEQUENCES TO permanent_owner;
EOF

# Check and create Vault user in PostgreSQL if it doesn't exist
echo "Checking for Vault user in PostgreSQL..."
if ! PGPASSWORD=postgres psql -h localhost -U postgres -d postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='vault'" | grep -q 1; then
    echo "Creating Vault user in PostgreSQL..."
    PGPASSWORD=postgres psql -h localhost -U postgres -d postgres -c "CREATE USER vault WITH PASSWORD 'vault' CREATEDB CREATEROLE;"
    PGPASSWORD=postgres psql -h localhost -U postgres -d postgres -c "GRANT ALL PRIVILEGES ON DATABASE postgres TO vault WITH GRANT OPTION;"
    PGPASSWORD=postgres psql -h localhost -U postgres -d postgres -c "GRANT ALL PRIVILEGES ON SCHEMA public TO vault WITH GRANT OPTION;"
    
    # Only grant permissions on existing objects, don't give ownership
    PGPASSWORD=postgres psql -h localhost -U postgres -d postgres -c "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO vault WITH GRANT OPTION;"
    PGPASSWORD=postgres psql -h localhost -U postgres -d postgres -c "GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO vault WITH GRANT OPTION;"
    
    # Critical change: Don't set vault as the default owner of future objects
    # Instead of using ALTER DEFAULT PRIVILEGES with GRANT ALL, use more specific permissions
    PGPASSWORD=postgres psql -h localhost -U postgres -d postgres -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO vault WITH GRANT OPTION;"
    PGPASSWORD=postgres psql -h localhost -U postgres -d postgres -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO vault WITH GRANT OPTION;"
    
    echo "Vault user created successfully with limited privileges."
else
    echo "Vault user already exists in PostgreSQL. Updating privileges..."
    PGPASSWORD=postgres psql -h localhost -U postgres -d postgres -c "ALTER USER vault WITH CREATEROLE;"
    PGPASSWORD=postgres psql -h localhost -U postgres -d postgres -c "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO vault WITH GRANT OPTION;"
    PGPASSWORD=postgres psql -h localhost -U postgres -d postgres -c "GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO vault WITH GRANT OPTION;"
    
    # Same change for existing user: Don't set vault as the default owner
    PGPASSWORD=postgres psql -h localhost -U postgres -d postgres -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO vault WITH GRANT OPTION;"
    PGPASSWORD=postgres psql -h localhost -U postgres -d postgres -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO vault WITH GRANT OPTION;"
    
    echo "Vault user privileges updated with limited ownership."
fi

# Enable database secrets engine if not already enabled
if ! /usr/local/bin/vault secrets list | grep -q "database/"; then
    echo "Enabling database secrets engine..."
    /usr/local/bin/vault secrets enable database
    echo "Database secrets engine enabled."
else
    echo "Database secrets engine is already enabled."
fi

# Check and configure PostgreSQL connection if not already configured
if ! /usr/local/bin/vault read database/config/postgres &>/dev/null; then
    echo "Configuring PostgreSQL connection in Vault..."
    /usr/local/bin/vault write database/config/postgres \
        plugin_name=postgresql-database-plugin \
        connection_url="postgresql://{{username}}:{{password}}@localhost:5432/postgres?sslmode=disable" \
        allowed_roles="*" \
        username="vault" \
        password="vault" \
        rotation_schedule="0 0 * * SAT" \
        rotation_window="1h"
    echo "PostgreSQL connection configured with weekly rotation on Saturday at midnight."
else
    echo "PostgreSQL connection is already configured."
fi

# Check and create dynamic credentials role if it doesn't exist
###########
# Check and create dynamic credentials role for database access
###########
if ! /usr/local/bin/vault read database/roles/dynamic-creds &>/dev/null; then
    echo "Creating dynamic credentials role..."
    /usr/local/bin/vault write database/roles/dynamic-creds \
        db_name=postgres \
        creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';
          GRANT USAGE ON SCHEMA public TO \"{{name}}\";
          GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO \"{{name}}\";
          GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO \"{{name}}\";" \
        revocation_statements="REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM \"{{name}}\";
          REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public FROM \"{{name}}\";
          REVOKE USAGE ON SCHEMA public FROM \"{{name}}\";
          DROP ROLE IF EXISTS \"{{name}}\";" \
        default_ttl="8h" \
        max_ttl="72h"        
    echo "Dynamic credentials role created with 8-hour TTL."
else
    echo "Dynamic credentials role already exists."
fi

echo "Database credentials engine setup complete."
echo "You can now generate dynamic credentials using: vault read database/creds/dynamic-creds"

###########
# Setup AppRole Authentication
###########
echo "Setting up AppRole authentication..."

# Enable AppRole auth method if not already enabled
if ! /usr/local/bin/vault auth list | grep -q "approle/"; then
    echo "Enabling AppRole authentication..."
    /usr/local/bin/vault auth enable approle
    echo "AppRole authentication enabled."
else
    echo "AppRole authentication is already enabled."
fi

# Update policy to allow using the transit engine
echo "Checking for existing Encryption policy..."
if ! /usr/local/bin/vault policy read transit-encrypt &>/dev/null; then
    echo "Creating Encryption policy..."
    cat << EOF | /usr/local/bin/vault policy write transit-encrypt -
path "transit/encrypt/card-encrypt" {
  capabilities = ["create", "update"]
}

path "transit/decrypt/card-encrypt" {
  capabilities = ["create", "update"]
}

path "transform/*" {
  capabilities = ["create", "update", "read"]
}
EOF
echo "Encryption policy created."
else
    echo "Encryption policy already exists."
fi

# Create database secrets policy
echo "Checking for existing database secrets policy..."
if ! /usr/local/bin/vault policy read db-secrets &>/dev/null; then
    echo "Creating database secrets policy..."
    cat << EOF | /usr/local/bin/vault policy write db-secrets -
path "database/creds/dynamic-creds" {
  capabilities = ["read"]
}

path "database/roles/dynamic-creds" {
  capabilities = ["read"]
}

path "auth/approle/login" {
  capabilities = ["create", "read"]
}
EOF
    echo "Database secrets policy created."
else
    echo "Database secrets policy already exists."
fi

# Update AppRole with the new policy
echo "Updating AppRole with database secrets policy..."
/usr/local/bin/vault write auth/approle/role/vault-agent \
    token_policies="default,db-secrets,transit-encrypt" \
    token_ttl=720h \
    token_max_ttl=720h

# Get the role ID and secret ID
echo "Generating role ID and secret ID..."
ROLE_ID=$(/usr/local/bin/vault read -field=role_id auth/approle/role/vault-agent/role-id)
SECRET_ID=$(/usr/local/bin/vault write -f -field=secret_id auth/approle/role/vault-agent/secret-id)

# Create Vault agent configuration directory
echo "Creating Vault agent configuration..."
sudo mkdir -p /etc/vault-agent
sudo chown vault:vault /etc/vault-agent
sudo touch /etc/vault-agent/secrets.json
sudo chmod 777 /etc/vault-agent/secrets.json

# Create Vault agent configuration file
cat << EOF | sudo tee /etc/vault-agent/config.hcl
auto_auth {
  method "approle" {
    mount_path = "auth/approle"
    config = {
      role_id_file_path = "/etc/vault-agent/role-id"
      secret_id_file_path = "/etc/vault-agent/secret-id"
      remove_secret_id_file_after_reading = false
    }
  }
}

vault {
  address = "http://127.0.0.1:8200"
}

listener "tcp" {
  address = "0.0.0.0:8100"
  tls_disable = true
}

cache {
  use_auto_auth_token = true
}

template {
  source = "/etc/vault-agent/template.ctmpl"
  destination = "/etc/vault-agent/secrets.json"
}
EOF

# Create template file for Vault agent
cat << EOF | sudo tee /etc/vault-agent/template.ctmpl
{
  "database_creds": {
    "username": "{{ with secret "database/creds/dynamic-creds" }}{{ .Data.username }}{{ end }}",
    "password": "{{ with secret "database/creds/dynamic-creds" }}{{ .Data.password }}{{ end }}"
  }
}
EOF

# Save role ID and secret ID
echo "$ROLE_ID" | sudo tee /etc/vault-agent/role-id

echo "$SECRET_ID" | sudo tee /etc/vault-agent/secret-id

# Set proper permissions
sudo chown -R vault:vault /etc/vault-agent
sudo chmod 600 /etc/vault-agent/role-id /etc/vault-agent/secret-id
sudo chmod 640 /etc/vault-agent/config.hcl /etc/vault-agent/template.ctmpl

# Create systemd service for Vault agent
if [ ! -f "/etc/systemd/system/vault-agent.service" ]; then
    echo "Creating Vault agent systemd service..."
    sudo tee /usr/lib/systemd/system/vault-agent.service > /dev/null << EOF
[Unit]
Description="HashiCorp Vault Agent - A tool for managing secrets"
Documentation=https://developer.hashicorp.com/vault/docs
Requires=network-online.target
After=network-online.target

[Service]
ExecStart=/usr/local/bin/vault agent -config=/etc/vault-agent/config.hcl
User=vault
Group=vault
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    echo "Vault agent service file created."
else
    echo "Vault agent service already exists."
fi

# Enable and start Vault agent if not already running
if ! systemctl is-active --quiet vault-agent; then
    echo "Starting Vault agent..."
    sudo systemctl daemon-reload
    sudo systemctl enable vault-agent
    sudo systemctl start vault-agent
    echo "Vault agent started successfully."
else
    echo "Vault agent is already running."
fi

echo "Vault agent setup complete."
echo "You can check the status with: systemctl status vault-agent"
echo "The agent will automatically manage database credentials at /etc/vault-agent/secrets.json"

# Configure firewall for required ports
if systemctl status firewalld &>/dev/null; then
    echo "Configuring firewalld rules..."
    # Check if firewalld is running
    if systemctl is-active --quiet firewalld; then
        # Vault UI (port 8200)
        sudo firewall-cmd --permanent --add-port=8200/tcp || echo "WARNING: Failed to add port 8200 to firewall"
        # Flask app (port 5000)
        sudo firewall-cmd --permanent --add-port=5000/tcp || echo "WARNING: Failed to add port 5000 to firewall"
        # Postgres
        sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="172.20.0.0/16" port protocol="tcp" port="5432" accept' || echo "WARNING: Failed to add PostgreSQL firewall rule"
        # Vault agent
        sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="172.20.0.0/16" port protocol="tcp" port="8100" accept' || echo "WARNING: Failed to add Vault agent firewall rule"
        sudo firewall-cmd --reload || echo "WARNING: Failed to reload firewall rules"
    else
        echo "Firewalld is installed but not running. Starting firewalld..."
        sudo systemctl start firewalld
        sudo systemctl enable firewalld
        
        # Retry adding rules
        sudo firewall-cmd --permanent --add-port=8200/tcp || echo "WARNING: Failed to add port 8200 to firewall"
        sudo firewall-cmd --permanent --add-port=5000/tcp || echo "WARNING: Failed to add port 5000 to firewall"
        sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="172.20.0.0/16" port protocol="tcp" port="5432" accept' || echo "WARNING: Failed to add PostgreSQL firewall rule"
        sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="172.20.0.0/16" port protocol="tcp" port="8100" accept' || echo "WARNING: Failed to add Vault agent firewall rule"
        sudo firewall-cmd --reload || echo "WARNING: Failed to reload firewall rules"
    fi
elif command -v iptables &> /dev/null; then
    echo "Firewalld not found. Configuring iptables rules..."
    # Vault UI (port 8200)
    sudo iptables -I INPUT -p tcp --dport 8200 -j ACCEPT
    # Flask app (port 5000)
    sudo iptables -I INPUT -p tcp --dport 5000 -j ACCEPT
    # Postgres
    sudo iptables -I INPUT 4 -p tcp -s 172.20.0.0/16 --dport 5432 -j ACCEPT
    #Vault Agent
    sudo iptables -I INPUT 4 -p tcp -s 172.20.0.0/16 --dport 8100 -j ACCEPT
    
    # Save iptables rules to make them persistent
    if command -v iptables-save &> /dev/null; then
        if [ -d "/etc/sysconfig" ]; then
            # RHEL/CentOS 7 and older
            sudo iptables-save | sudo tee /etc/sysconfig/iptables > /dev/null
            echo "Saved iptables rules to /etc/sysconfig/iptables"
        elif [ -d "/etc/iptables" ]; then
            # Newer systems
            sudo mkdir -p /etc/iptables
            sudo iptables-save | sudo tee /etc/iptables/rules.v4 > /dev/null
            echo "Saved iptables rules to /etc/iptables/rules.v4"
        else
            # Generic location
            sudo iptables-save | sudo tee /etc/iptables.rules > /dev/null
            echo "Saved iptables rules to /etc/iptables.rules"
        fi
    else
        echo "WARNING: iptables-save command not found. Firewall rules may not persist after reboot."
    fi
else
    echo "WARNING: No firewall management tool found. Ports need to be opened manually."
    echo "Required ports: 8200/tcp (Vault UI), 5000/tcp (Flask app), 5432/tcp (PostgreSQL from Docker network), 8100/tcp (Vault agent)"
fi

# Ensure SELinux allows container connections if it's enabled
if command -v getenforce &> /dev/null && [ "$(getenforce)" != "Disabled" ]; then
    echo "SELinux is enabled. Configuring container permissions..."
    
    # Install SELinux policy packages if they don't exist
    if ! rpm -q container-selinux &> /dev/null; then
        echo "Installing container-selinux package..."
        sudo yum install -y container-selinux || echo "WARNING: Failed to install container-selinux. Container networking might be restricted."
    fi
    
    # Set SELinux boolean to allow container networking
    sudo setsebool -P container_connect_any 1 || echo "WARNING: Failed to set SELinux boolean. Container networking might be restricted."
fi

# Create Docker network
sudo docker network create --driver bridge \
  --subnet=172.20.0.0/16 \
  --gateway=172.20.0.1 \
  hashicups-bridge

# Run Docker container with volume mount
echo "Starting HashiCups container..."
HOST_IP=$(hostname -I | awk '{print $1}')
sudo docker run -d \
  --name hashicups-container \
  --network hashicups-bridge \
  -p 5000:5000 \
  -v /etc/vault-agent:/etc/vault-agent:ro \
  -e VAULT_ADDR=http://host.docker.internal:8100 \
  -e DB_HOST=host.docker.internal \
  --add-host=host.docker.internal:$HOST_IP \
  shriramrajaraman/hashicups-python:$OS_USER || {
    echo "ERROR: Failed to start HashiCups container."
    echo "Checking for issues..."
    
    # Check if the container already exists
    if sudo docker ps -a | grep -q hashicups-container; then
        echo "Container already exists. Removing and trying again..."
        sudo docker rm -f hashicups-container
        
        # Try again
        sudo docker run -d \
          --name hashicups-container \
          --network hashicups-bridge \
          -p 5000:5000 \
          -v /etc/vault-agent:/etc/vault-agent:ro \
          -e VAULT_ADDR=http://host.docker.internal:8100 \
          -e DB_HOST=host.docker.internal \
          --add-host=host.docker.internal:$HOST_IP \
          shriramrajaraman/hashicups-python:$DISTRO || echo "ERROR: Failed to start HashiCups container after retry."
    fi
  }

echo ""
echo "======================================================================"
echo "Setup complete! Summary of services:"
echo "----------------------------------------------------------------------"
echo "Vault UI: http://${HOST_IP}:8200"
echo "HashiCups App: http://${HOST_IP}:5000"
echo "----------------------------------------------------------------------"
echo "Vault credentials are saved in: /home/${OS_USER}/vault-creds/"
echo "Database credentials are managed by Vault Agent at: /etc/vault-agent/secrets.json"
echo "======================================================================"