# HashiCups with Vault Integration

This repository contains shell scripts for deploying HashiCups with HashiCorp Vault integration on Ubuntu and RHEL operating systems.

**Note**: Any docker images used as a part of this repository are sandbox images and not officially supported images, They are not recommended to be used for production environments

## Architecture Overview

The deployment consists of:

- **HashiCups**: A demo application running in Docker containers with a web UI
- **HashiCorp Vault**: Running as a supervised process via supervisorctl
- **Vault Agent**: Acts as a cache and API proxy for the HashiCups application to securely interact with Vault

## Architecture Diagram

![HashiCups Vault Architecture](./images/reference-architecture.png)

*Figure 1: High-level architecture diagram showing HashiCups, Vault, and Vault Agent integration*

## Prerequisites

- A new virtual machine with Ubuntu or RHEL OS
- Sufficient permissions to execute scripts and install packages
- Internet connectivity for downloading dependencies

## Deployment Instructions for Docker Compose

### 1. Clone this github repository

```bash
git clone https://github.com/shriram2712/hashicups-vault.git
```

### 2. Create and place the license file in the docker-compose/vault-config directory in the cloned github repo. An example file has been placed where the license.hclic is expected to be

```bash
touch $(pwd)/hashicups-vault/docker-compose/vault-config/license.hclic
```

### 3. Create a .env file in the docker-compose directory in the cloned github repo. An example file has been placed where the .env file is expected. Replace the values with the actual values you would like to deploy Postgres with and the host path

```
#Example values
POSTGRES_USER=<PG_USER>
POSTGRES_PASSWORD=<PG_PASSWORD>
POSTGRES_DB=<PG_DB
HOST_PATH=.
```

### 4. Make sure the docker and docker-compose are installed in the host machine. Reference scripts are in the demo-setup-docker-scripts folder.

### 5. Start the containers

```bash
cd $(pwd)/hashicups-vault/docker-compose
docker-compose up -d
```

### 6. Accessing the Application

Once deployment is complete:
* **HashiCups UI**: http://[VM-IP]:8080
* **Vault UI**: http://[VM-IP]:8200

### 7. Important: Firewall Configuration

You must configure your firewall to expose ports 8200 and 5000 externally to access the user interfaces:
* **Port 8200**: Required for accessing the Vault UI
* **Port 5000**: Required for accessing parts of the HashiCups application

Depending on your environment, you may need to:
* Configure security groups (AWS/cloud)
* Update iptables rules (Linux)
* Modify network ACLs

Example for iptables:

```bash
sudo iptables -A INPUT -p tcp --dport 8200 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 5000 -j ACCEPT
```

### 8. Troubleshooting

If you encounter issues during setup:
1. Check logs with `docker logs [container_id]` for all container issues 
2. Ensure the license file is properly formatted and has correct permissions
3. Verify network connectivity between components


## Deployment Instructions for Docker

### 1. Set Up License File

First, create and place the license file in the home directory of your OS user:

```bash
# For Ubuntu on AWS
/home/ubuntu/license.hclic

# For RHEL or Ubuntu on IBM Cloud
/home/linux1/license.hclic
```

Set appropriate permissions on the license file:

```bash
chmod 644 /home/$(whoami)/license.hclic
```

### 2. Create and Run setup script

Choose the appropriate script for your operating system (Ubuntu or RHEL) from the repository, create it on your VM, and make it executable:

```bash
# Download the script and choose your OS Type : currently ubuntu/debian and redhat/centos are supported
curl -o setup.sh https://raw.githubusercontent.com/shriram2712/hashicups-vault/main/demo-setup-docker-scripts/setup-vault-[ubuntu|redhat].sh

# Make it executable and replace the command with your chosen OS
chmod +x setup-vault-[ubuntu|redhat].sh

# Run the script and replace the command with your chosen OS
sudo ./setup-vault-[ubuntu|redhat].sh
```

### 3. Setup Script Overview

The setup scripts perform the following operations:

1. **System preparation**:
   * Update system packages
   * Install dependencies (Docker, supervisord, curl, jq, etc.)
   * Setup Postgres Containers and setup the user for Vault DB Secrets engine
2. **HashiCorp Vault installation**:
   * Download and install Vault
   * Configure Vault server
   * Set up supervisord to manage Vault process
   * Initialize and unseal Vault
   * Setup the Vault Transit, Transform and DB Secrets engine
3. **Vault Agent configuration**:
   * Install Vault Agent
   * Configure it as a cache and API proxy
   * Set up necessary authentication methods
4. **HashiCups deployment**:
   * Pull and start HashiCups Docker containers
   * Configure HashiCups to communicate with Vault via Vault Agent

### 4. Accessing the Application

Once deployment is complete:
* **HashiCups UI**: http://[VM-IP]:8080
* **Vault UI**: http://[VM-IP]:8200

### 5. Important: Firewall Configuration

You must configure your firewall to expose ports 8200 and 5000 externally to access the user interfaces:
* **Port 8200**: Required for accessing the Vault UI
* **Port 5000**: Required for accessing parts of the HashiCups application

Depending on your environment, you may need to:
* Configure security groups (AWS/cloud)
* Update iptables rules (Linux)
* Modify network ACLs

Example for iptables:

```bash
sudo iptables -A INPUT -p tcp --dport 8200 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 5000 -j ACCEPT
```

### 6. Troubleshooting

If you encounter issues during setup:
1. Check logs with `docker logs [container_id]` for HashiCups issues
2. Check Vault server logs with `sudo supervisorctl status vault-enterprise` and `journalctl -fu vault-enterprise`
3. Check Vault agent logs with `sudo supervisorctl status vault-agent` and `journalctl -fu vault-agent`
4. Ensure the license file is properly formatted and has correct permissions
5. Verify network connectivity between components

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project uses HashiCorp Vault which requires a license for some features. Ensure you have the proper licensing before deployment.