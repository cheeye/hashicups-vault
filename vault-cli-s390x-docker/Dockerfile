FROM alpine:3 AS base
ARG NAME=vault

FROM base AS builder
ARG PRODUCT_VERSION=1.19.3+ent

RUN apk add --no-cache \
    jq \
    curl \
    && rm -rf /var/cache/apk/*

RUN export OS=$(uname -s | tr '[:upper:]' '[:lower:]') && \
    export ARCH=$(uname -m) && \
    wget https://releases.hashicorp.com/${NAME}/${PRODUCT_VERSION}/${NAME}_${PRODUCT_VERSION}_${OS}_${ARCH}.zip -O /tmp/${NAME}.zip && \
    unzip /tmp/${NAME}.zip -d /usr/local/bin && \
    chmod +x /usr/local/bin/${NAME}
