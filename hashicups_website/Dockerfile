FROM python:3.9-slim

# Set working directory
WORKDIR /app

# Install necessary system dependencies
RUN apt-get update && apt-get install -y \
    libpq-dev \
    gcc \
    iproute2 \
    iputils-ping \
    curl \
    telnet \
    postgresql-client \
    postgresql-client-common \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements file
COPY requirements.txt .

# Install dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Create directory for Vault agent secrets
RUN mkdir -p /etc/vault-agent

# Set default environment variables
ENV VAULT_ADDR=http://127.0.0.1:8100
ENV DB_HOST=localhost

# Expose port for the Flask application
EXPOSE 5000

# Run the application
CMD ["python", "app.py"]