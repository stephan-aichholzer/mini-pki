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
COPY *.sh ./
COPY *.md ./

# Make scripts executable
RUN chmod +x *.sh

# Create CA directory structure
# Note: Database files (index.txt, serial, crlnumber) should be created
# at runtime using init-ca-database.sh to persist in volumes
RUN mkdir -p certs private newcerts crl && \
    chmod 700 private

# Set environment variables
ENV OPENSSL_CONF=/ca/openssl.cnf
ENV PATH=/ca:$PATH

# Volume for persistent CA data
# Mount entire /ca to preserve all state (database, certs, keys)
# This ensures index.txt, serial, and crlnumber persist
VOLUME ["/ca"]

# Expose port for testing (optional)
EXPOSE 4433

# Create a welcome script
RUN echo '#!/bin/bash' > /ca/welcome.sh && \
    echo 'echo "=== X.509 CA Environment ==="' >> /ca/welcome.sh && \
    echo 'echo "Quick Start:"' >> /ca/welcome.sh && \
    echo 'echo "  1. ./init-ca-database.sh"' >> /ca/welcome.sh && \
    echo 'echo "  2. ./create-root-ca.sh"' >> /ca/welcome.sh && \
    echo 'echo "  3. ./create-server-cert.sh <hostname>"' >> /ca/welcome.sh && \
    echo 'echo ""' >> /ca/welcome.sh && \
    echo 'echo "Available scripts:"' >> /ca/welcome.sh && \
    echo 'ls -1 *.sh | grep -v welcome' >> /ca/welcome.sh && \
    echo 'echo ""' >> /ca/welcome.sh && \
    chmod +x /ca/welcome.sh

# Set bash to show welcome message on interactive shells
RUN echo 'if [ "$PS1" ]; then /ca/welcome.sh; fi' >> /root/.bashrc

# Default command: bash shell for interactive use
CMD ["/bin/bash"]

# Health check (verify OpenSSL is working)
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD openssl version || exit 1
