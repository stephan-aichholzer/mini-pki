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

> **Note:** All certificate-creation scripts are interactive — they prompt for
> X.509 subject fields and passphrases. Always run them with `-it`. They cannot
> be run unattended.

## Image Details

**Base Image:** Alpine Linux 3.24 (minimal)
**Size:** ~99 MB
**OpenSSL Version:** 3.5.x

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
docker run --rm x509-ca:latest cat README.md

# List available scripts
docker run --rm x509-ca:latest ls -l *.sh
```

### 3. Persistent Storage with Volumes

**Option A: Named Volume (Recommended)**

A named volume is seeded from the image on first use, so the scripts and
`openssl.cnf` are present inside it.

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

**Option B: Bind Mounts (Local Directories)**

Do **not** bind-mount a host directory over `/ca` — that hides the scripts and
`openssl.cnf` baked into the image, leaving an empty working directory. Mount
the individual data directories instead, and keep the CA database on the host
too so `index.txt`, `serial`, and `crlnumber` persist.

```bash
# Create local directories for CA data
mkdir -p ./ca-data/{certs,private,newcerts,crl}

# Run with bind mounts
docker run -it --rm \
  -v $(pwd)/ca-data/certs:/ca/certs \
  -v $(pwd)/ca-data/private:/ca/private \
  -v $(pwd)/ca-data/newcerts:/ca/newcerts \
  -v $(pwd)/ca-data/crl:/ca/crl \
  x509-ca:latest
```

### 4. Extract Generated Certificates

```bash
# Run container with the certs directory bind-mounted
docker run -it --rm \
  -v $(pwd)/output:/ca/certs \
  x509-ca:latest

# After creating certificates, they'll be in ./output/
```

## Volume Mounts

The image declares a single volume:

- `/ca` - the entire CA working directory (scripts, config, database, keys, certs)

Mounting all of `/ca` keeps every piece of CA state together, including the
database files (`index.txt`, `serial`, `crlnumber`) that `openssl ca` needs.

```bash
docker run -it --rm \
  -v ca-data:/ca \
  x509-ca:latest
```

If you prefer to separate the data directories, mount them individually as
shown in Option B above. Note that the CA database files live at the root of
`/ca`, so splitting the mounts means they stay inside the container unless you
mount `/ca` as well.

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
  -v ca-data:/ca \
  -v $(pwd)/custom-openssl.cnf:/ca/openssl.cnf:ro \
  x509-ca:latest
```

### Multi-Stage CA Workflow

Each step runs in its own container against the same named volume. The
creation scripts prompt for input, so they need `-it`.

```bash
# 1. Initialize the database and create the CA
docker run -it --rm -v ca-data:/ca x509-ca:latest ./init-ca-database.sh
docker run -it --rm -v ca-data:/ca x509-ca:latest ./create-root-ca.sh

# 2. Create a server certificate
docker run -it --rm -v ca-data:/ca x509-ca:latest ./create-server-cert.sh myserver.com

# 3. Verify the certificate (non-interactive)
docker run --rm -v ca-data:/ca x509-ca:latest \
  openssl verify -CAfile certs/ca-cert.pem certs/myserver.com-cert.pem
```

### Health Check

The image includes a health check that verifies OpenSSL is working:

```bash
# Check container health
docker inspect --format='{{.State.Health.Status}}' <container-id>
```

## Integration with CI/CD

The certificate-creation scripts are interactive and cannot run unattended, so
CI is limited to building the image and checking that it is sound.

### GitLab CI Example

```yaml
build-ca-image:
  image: docker:latest
  services:
    - docker:dind
  script:
    - docker build -t x509-ca:latest .
    - docker run --rm x509-ca:latest openssl version
    - docker run --rm x509-ca:latest bash -c 'for s in *.sh; do bash -n "$s"; done'
```

### GitHub Actions Example

```yaml
name: Build CA image
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build Docker image
        run: docker build -t x509-ca:latest .
      - name: Check OpenSSL
        run: docker run --rm x509-ca:latest openssl version
      - name: Check script syntax
        run: docker run --rm x509-ca:latest bash -c 'for s in *.sh; do bash -n "$s"; done'
```

## Troubleshooting

### Container exits immediately
```bash
# Use -it flag for interactive terminal
docker run -it --rm x509-ca:latest
```

### Scripts are missing inside the container
You bind-mounted a host directory over `/ca`, which hides the image contents.
Use a named volume, or mount the data subdirectories individually — see
"Persistent Storage with Volumes" above.

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
