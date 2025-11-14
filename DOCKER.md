# Docker Usage Guide for X.509 Certificate Authority

This project includes a Docker environment that encapsulates all runtime dependencies for running the Certificate Authority.

## Quick Start

### Build the Image

```bash
docker build -t x509-ca:latest .
```

### Run Interactive Shell

```bash
docker run -it --rm x509-ca:latest
```

## Image Details

**Base Image:** Alpine Linux 3.19 (minimal, secure)
**Size:** ~57 MB
**OpenSSL Version:** 3.1.8

**Interactive Welcome:** Container displays quick start guide on launch

### Included Tools

- **OpenSSL** - Certificate management
- **bash** - Shell for scripts
- **vim** - Text editor
- **nano** - Alternative text editor
- **git** - Version control
- **jq** - JSON processor
- **curl** - HTTP client
- **wget** - File downloader
- **ca-certificates** - Root CA certificates
- **tzdata** - Timezone data

## Usage Examples

### 1. Interactive Shell (Recommended for Development)

```bash
# Run with persistent volume for CA data
docker run -it --rm \
  -v ca-data:/ca \
  x509-ca:latest
```

You'll see a welcome message:
```
=== X.509 CA Environment ===
Quick Start:
  1. ./init-ca-database.sh
  2. ./create-root-ca.sh
  3. ./create-server-cert.sh <hostname>

Available scripts:
[list of all scripts]
```

Inside the container:
```bash
# Initialize CA database (first time only)
./init-ca-database.sh

# Create root CA
./create-root-ca.sh

# Create server certificate
./create-server-cert.sh server.example.com

# Create client certificate
./create-client-cert.sh client1@example.com
```

### 2. Run Specific Command

```bash
# Check OpenSSL version
docker run --rm x509-ca:latest openssl version

# View README
docker run --rm x509-ca:latest cat README.txt

# List available scripts
docker run --rm x509-ca:latest ls -l *.sh
```

### 3. Persistent Storage with Volumes

**Option A: Named Volume (Recommended)**
```bash
# Create named volume
docker volume create ca-data

# Run with named volume
docker run -it --rm \
  -v ca-data:/ca \
  x509-ca:latest

# View volume contents
docker run --rm \
  -v ca-data:/ca \
  x509-ca:latest \
  ls -la /ca
```

**Option B: Bind Mount (Local Directory)**
```bash
# Create local directory for CA data
mkdir -p ./ca-data

# Run with bind mount
docker run -it --rm \
  -v $(pwd)/ca-data:/ca \
  x509-ca:latest
```

### 4. Automated Testing

```bash
# Run automated tests
docker run --rm x509-ca:latest bash -c "
  ./test-create-root-ca.sh && \
  ./test-create-server-cert.sh server.example.com && \
  ./test-create-client-cert.sh client1@example.com && \
  openssl verify -CAfile certs/ca-cert.pem certs/test-server.example.com-cert.pem
"
```

### 5. Extract Generated Certificates

```bash
# Run container with volume
docker run -it --rm \
  -v $(pwd)/output:/ca/certs \
  x509-ca:latest

# After creating certificates, they'll be in ./output/
```

## Volume Mounts

The image defines the following volumes:

- `/ca/private` - Private keys (KEEP SECURE!)
- `/ca/certs` - Generated certificates
- `/ca/newcerts` - CA-managed certificate copies
- `/ca/crl` - Certificate Revocation Lists

**Example with separate volumes:**
```bash
docker run -it --rm \
  -v ca-private:/ca/private \
  -v ca-certs:/ca/certs \
  -v ca-newcerts:/ca/newcerts \
  -v ca-crl:/ca/crl \
  x509-ca:latest
```

## Environment Variables

Pre-configured environment variables:

- `OPENSSL_CONF=/ca/openssl.cnf` - OpenSSL configuration path
- `PATH=/ca:$PATH` - Scripts available in PATH

## Security Considerations

### DO:
✓ Use volumes for persistent storage
✓ Backup CA private key regularly
✓ Run container with read-only root filesystem when possible
✓ Use secrets management for passphrases
✓ Limit network access if not needed

### DON'T:
✗ Don't commit generated certificates to Git
✗ Don't share CA private key
✗ Don't run container with --privileged
✗ Don't expose CA volumes to untrusted containers

## Advanced Usage

### Read-Only Root Filesystem

```bash
docker run -it --rm \
  --read-only \
  -v ca-data:/ca \
  --tmpfs /tmp:rw,noexec,nosuid,size=100m \
  x509-ca:latest
```

### Custom OpenSSL Configuration

```bash
docker run -it --rm \
  -v $(pwd)/custom-openssl.cnf:/ca/openssl.cnf:ro \
  -v ca-data:/ca \
  x509-ca:latest
```

### Multi-Stage CA Workflow

```bash
# 1. Create CA in one container
docker run --rm \
  -v ca-data:/ca \
  x509-ca:latest \
  ./test-create-root-ca.sh

# 2. Create server cert in another container
docker run --rm \
  -v ca-data:/ca \
  x509-ca:latest \
  ./test-create-server-cert.sh myserver.com

# 3. Verify certificate
docker run --rm \
  -v ca-data:/ca \
  x509-ca:latest \
  openssl verify -CAfile certs/ca-cert.pem certs/myserver.com-cert.pem
```

### Health Check

The image includes a health check that verifies OpenSSL is working:

```bash
# Check container health
docker inspect --format='{{.State.Health.Status}}' <container-id>
```

## Integration with CI/CD

### GitLab CI Example

```yaml
test-certificates:
  image: x509-ca:latest
  script:
    - ./test-create-root-ca.sh
    - ./test-create-server-cert.sh test.example.com
    - openssl verify -CAfile certs/ca-cert.pem certs/test.example.com-cert.pem
```

### GitHub Actions Example

```yaml
name: Test CA Scripts
on: [push]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Build Docker image
        run: docker build -t x509-ca:latest .
      - name: Test scripts
        run: |
          docker run --rm x509-ca:latest bash -c "
            ./test-create-root-ca.sh && \
            ./test-create-server-cert.sh test.example.com
          "
```

## Troubleshooting

### Container exits immediately
```bash
# Use -it flag for interactive terminal
docker run -it --rm x509-ca:latest
```

### Permission denied errors
```bash
# Check volume permissions
docker run --rm -v ca-data:/ca x509-ca:latest ls -la /ca/private
```

### OpenSSL configuration not found
```bash
# Verify OPENSSL_CONF is set
docker run --rm x509-ca:latest env | grep OPENSSL
```

## Building for Different Architectures

```bash
# Build for multiple platforms
docker buildx build --platform linux/amd64,linux/arm64 -t x509-ca:latest .
```

## Cleanup

```bash
# Remove image
docker rmi x509-ca:latest

# Remove volumes
docker volume rm ca-data

# Remove all unused volumes
docker volume prune
```

## Image Information

```bash
# View image details
docker inspect x509-ca:latest

# View image layers
docker history x509-ca:latest

# View image size
docker images x509-ca:latest
```
