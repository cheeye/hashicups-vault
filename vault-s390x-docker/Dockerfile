FROM alpine:3 AS base
ARG NAME=vault

FROM base AS builder
ARG PRODUCT_VERSION=1.19.3+ent
RUN export OS=$(uname -s | tr '[:upper:]' '[:lower:]') && \
    export ARCH=$(uname -m) && \
    wget https://releases.hashicorp.com/${NAME}/${PRODUCT_VERSION}/${NAME}_${PRODUCT_VERSION}_${OS}_${ARCH}.zip -O /tmp/${NAME}.zip && \
    unzip /tmp/${NAME}.zip -d /tmp && \
    chmod +x /tmp/${NAME}


FROM base AS vault
COPY --from=builder /tmp/${NAME} /usr/bin/${NAME}
COPY ./entrypoint.sh /
RUN chmod +x /entrypoint.sh

RUN apk add --no-cache dumb-init 
# Create a group and user
RUN addgroup -S ${NAME}  && adduser -S ${NAME} -G ${NAME}

ARG VAULT_DATA=/opt/vault/data
ENV VAULT_CONFIG=/etc/vault.d

# Create Vault data and configuration directories
# Change directory ownership of the data directory to the vault user
# Grant the vault user full permission on the data directory, search permission for the group, and deny access to others
RUN mkdir -p ${VAULT_DATA} && \
    mkdir -p ${VAULT_CONFIG} && \
    chown -R ${NAME}:${NAME} ${VAULT_DATA} && \
    chmod -R 750 ${VAULT_DATA} 

VOLUME ${VAULT_DATA}

EXPOSE 8200 8201
USER ${NAME}

ENTRYPOINT ["dumb-init", "/entrypoint.sh"]