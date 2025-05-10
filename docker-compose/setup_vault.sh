#!/bin/sh

# Check if OS parameter is provided
# if [ -z "$1" ]; then
#     echo "Usage: $0 <CREDS_DIR>"
#     echo "Example: $0 linux1 or $0 ubuntu"
#     exit 1
# fi

# CREDS_DIR="$1"
CREDS_DIR="/scripts/vault-creds"

# Set Vault address
export VAULT_ADDR="http://vault:8200"
# echo "export VAULT_ADDR=http://vault:8200" >> ~/.bashrc
# until vault status; do sleep 1; done;

# Check if Vault is already initialized
if vault status | grep -q "Initialized.*true"; then
    echo "Vault is already initialized."
    # Set VAULT_TOKEN from existing root token if available
    if [ -f "$CREDS_DIR/root_token.txt" ]; then
        export VAULT_TOKEN=$(cat "$CREDS_DIR/root_token.txt")
        # echo "export VAULT_TOKEN=$VAULT_TOKEN" >> ~/.bashrc
    fi
else
    # Initialize Vault and save keys
    echo "Initializing Vault..."
    [ ! -d "$CREDS_DIR" ] && mkdir -p "$CREDS_DIR"
    # sudo chown -R "$CREDS_DIR:$CREDS_DIR" "CREDS_DIR"

    # Initialize Vault and capture output
    INIT_OUTPUT=$(vault operator init -key-shares=3 -key-threshold=2 -format=json)
    
    # Save the complete initialization output for reference
    echo "$INIT_OUTPUT" > "$CREDS_DIR/init_output.json"
    
    # Extract and save keys and root token
    echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[0]' > "$CREDS_DIR/key1.txt"
    echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[1]' > "$CREDS_DIR/key2.txt"
    echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[2]' > "$CREDS_DIR/key3.txt"
    echo "$INIT_OUTPUT" | jq -r '.root_token' > "$CREDS_DIR/root_token.txt"

    # Set VAULT_TOKEN from newly generated root token
    export VAULT_TOKEN=$(cat "$CREDS_DIR/root_token.txt")
    # echo "export VAULT_TOKEN=$VAULT_TOKEN" >> ~/.bashrc

    # Set proper permissions for the credentials
    # sudo chown -R "$CREDS_DIR:$CREDS_DIR" "CREDS_DIR/vault-creds"
    # sudo chmod 600 "CREDS_DIR/vault-creds"/*
fi

# Check if Vault is sealed and unseal if necessary
if vault status | grep -q "Sealed.*true"; then
    echo "Vault is sealed. Unsealing..."
    # Use the first two keys to unseal (since threshold is 2)
    vault operator unseal $(cat "$CREDS_DIR/key1.txt")
    vault operator unseal $(cat "$CREDS_DIR/key2.txt")
    echo "Vault has been unsealed."
else
    echo "Vault is already unsealed."
fi

echo "Vault setup complete. You can access the UI at http://${HOST_IP}:8200"
echo "Unseal keys and root token have been saved to ${CREDS_DIR}"

export VAULT_TOKEN=$(cat "$CREDS_DIR/root_token.txt")
###########
# Enable Transform Secrets Engine
###########
if ! vault secrets list | grep -q "transform/"; then
    echo "Enabling Transform Secrets Engine..."
    vault secrets enable transform
else
    echo "Transform Secrets Engine is already enabled."
fi

###########
# Create Role for Payments
###########
if ! vault read transform/role/payments &>/dev/null; then
    echo "Creating Role for Payments..."
    vault write transform/role/payments transformations=card-number
else
    echo "Payments role already exists."
fi

###########
# Create Transformation for Card Number
###########
if ! vault read transform/transformation/card-number &>/dev/null; then
    echo "Creating Transformation for Card Number..."
    vault write transform/transformation/card-number \
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
if ! vault read transform/template/masked-all-last4-card-number &>/dev/null; then
    echo "Creating template for masked transformation..."
    vault write transform/template/masked-all-last4-card-number type=regex \
      pattern='(\d{4})[-]?(\d{4})[-]?(\d{4})[-]?\d{4}' \
      alphabet=numerics
else
    echo "Masked transformation template already exists."
fi

###########
# Create masked-card-number transformation
###########
if ! vault read transform/transformation/masked-card-number &>/dev/null; then
    echo "Creating masked-card-number transformation..."
    vault write transform/transformation/masked-card-number \
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
if ! vault read transform/role/custsupport &>/dev/null; then
    echo "Adding masked-card-number transformation to custsupport role..."
    vault write transform/role/custsupport \
        transformations=masked-card-number
else
    echo "Custsupport role already exists."
fi


###########
# Enable Transit Secrets Engine for Card Encryption
###########
echo "Setting up Transit Secrets Engine for card number encryption..."

# Enable Transit secrets engine if not already enabled
if ! vault secrets list | grep -q "transit/"; then
    echo "Enabling Transit Secrets Engine..."
    vault secrets enable transit
    echo "Transit Secrets Engine enabled."
else
    echo "Transit Secrets Engine already enabled."
fi

# Create encryption key for card numbers if it doesn't exist
if ! vault read transit/keys/card-encrypt &>/dev/null; then
    echo "Creating encryption key for card numbers..."
    vault write -f transit/keys/card-encrypt \
        type=aes256-gcm96 \
        auto_rotate_period="168h"  # Auto-rotate every 7 days
    echo "Encryption key created with 7-day auto-rotation policy."
else
    echo "Encryption key for card numbers already exists."
fi

# Enable database secrets engine if not already enabled
if ! vault secrets list | grep -q "database/"; then
    echo "Enabling database secrets engine..."
    vault secrets enable database
    echo "Database secrets engine enabled."
else
    echo "Database secrets engine is already enabled."
fi

# Check and configure PostgreSQL connection if not already configured
if ! vault read database/config/postgres &>/dev/null; then
    echo "Configuring PostgreSQL connection in Vault..."
    vault write database/config/postgres \
        plugin_name=postgresql-database-plugin \
        connection_url="postgresql://{{username}}:{{password}}@postgres:5432/postgres?sslmode=disable" \
        allowed_roles="*" \
        username="vault" \
        password="vault" \
        rotation_schedule="0 0 * * SAT" \
        rotation_window="1h"
    echo "PostgreSQL connection configured with weekly rotation on Saturday at midnight."
else
    echo "PostgreSQL connection is already configured."
fi

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


###########
# Setup AppRole Authentication
###########
echo "Setting up AppRole authentication..."

# Enable AppRole auth method if not already enabled
if ! vault auth list | grep -q "approle/"; then
    echo "Enabling AppRole authentication..."
    vault auth enable approle
    echo "AppRole authentication enabled."
else
    echo "AppRole authentication is already enabled."
fi



# Update policy to allow using the transit engine

echo "Checking for existing Encryption policy..."
if ! vault policy read transit-encrypt &>/dev/null; then
    echo "Creating Encryption policy..."
    cat << EOF | vault policy write transit-encrypt -
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
if ! vault policy read db-secrets &>/dev/null; then
    echo "Creating database secrets policy..."
    cat << EOF | vault policy write db-secrets -
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
vault write auth/approle/role/vault-agent \
    token_policies="default,db-secrets,transit-encrypt" \
    token_ttl=720h \
    token_max_ttl=720h
