# Dockerfile for X.509 Certificate Authority Environment
# Provides OpenSSL and basic tools for certificate management

FROM alpine:3.19

# Set labels
LABEL maintainer="X.509 CA Project"
LABEL description="Containerized Certificate Authority environment with OpenSSL"
LABEL version="1.0"

# Install OpenSSL and basic utilities
RUN apk add --no-cache \
    openssl \
    bash \
    vim \
    nano \
    git \
    jq \
    curl \
    wget \
    ca-certificates \
    tzdata \
    && rm -rf /var/cache/apk/*

# Create working directory for CA
WORKDIR /ca

# Copy CA scripts and configuration
COPY openssl.cnf ./
COPY create-*.sh ./
COPY test-create-*.sh ./
COPY README.txt ./

# Make scripts executable
RUN chmod +x create-*.sh test-create-*.sh

# Create CA directory structure
RUN mkdir -p certs private newcerts crl && \
    chmod 700 private && \
    touch index.txt && \
    echo 1000 > serial && \
    echo 1000 > crlnumber

# Set environment variables
ENV OPENSSL_CONF=/ca/openssl.cnf
ENV PATH=/ca:$PATH

# Volume for persistent CA data (private keys, certificates, database)
VOLUME ["/ca/private", "/ca/certs", "/ca/newcerts", "/ca/crl"]

# Default command: bash shell for interactive use
CMD ["/bin/bash"]

# Health check (verify OpenSSL is working)
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD openssl version || exit 1
