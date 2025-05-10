#!/bin/sh
set -e

exec &> /proc/1/fd/1

# Check if VAULT_CONFIG environment variable is set
if [ -z "${VAULT_CONFIG}" ]; then
    echo "Error: VAULT_CONFIG environment variable is not set"
    exit 1
fi

# Create Vault configuration directory if it doesn't exist
if [ ! -d "${VAULT_CONFIG}" ]; then
    echo "Creating Vault configuration directory: ${VAULT_CONFIG}"
    mkdir -p "${VAULT_CONFIG}"
fi


# Execute the main command
exec vault server -config "${VAULT_CONFIG}"
