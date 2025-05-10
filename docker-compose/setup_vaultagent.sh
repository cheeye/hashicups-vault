#!/bin/sh

# CREDS_DIR="$1"
CREDS_DIR="/scripts/vault-creds"
AGENT_DIR="/etc/vault-agent"
SECRETS_DIR="/app/secrets"

# Set Vault address
export VAULT_ADDR="http://vault:8200"
export VAULT_TOKEN=$(cat "$CREDS_DIR/root_token.txt")


# Get the role ID and secret ID
echo "Generating role ID and secret ID..."
ROLE_ID=$(vault read -field=role_id auth/approle/role/vault-agent/role-id)
SECRET_ID=$(vault write -f -field=secret_id auth/approle/role/vault-agent/secret-id)

# Create Vault agent configuration directory
echo "Creating Vault agent configuration..."
mkdir -p "$AGENT_DIR"
mkdir -p "$SECRETS_DIR"
# chown vault:vault $AGENT_DIR
# touch $AGENT_DIR/secrets.json
# chmod 777 $AGENT_DIR/secrets.json

# Create Vault agent configuration file
cat << EOF | tee "$AGENT_DIR/config.hcl"
auto_auth {
  method "approle" {
    mount_path = "auth/approle"
    config = {
      role_id_file_path = "$AGENT_DIR/role-id"
      secret_id_file_path = "$AGENT_DIR/secret-id"
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
  source = "$AGENT_DIR/template.ctmpl"
  destination = "$SECRETS_DIR/secrets.json"
}
EOF

# Create template file for Vault agent
cat << EOF | tee $AGENT_DIR/template.ctmpl
{
  "database_creds": {
    "username": "{{ with secret "database/creds/dynamic-creds" }}{{ .Data.username }}{{ end }}",
    "password": "{{ with secret "database/creds/dynamic-creds" }}{{ .Data.password }}{{ end }}"
  }
}
EOF

# Save role ID and secret ID
echo "$ROLE_ID" | tee "$AGENT_DIR/role-id"
echo "$SECRET_ID" | tee "$AGENT_DIR/secret-id"

exec vault agent -config="$AGENT_DIR/config.hcl"