# X.509 Certificate Authority

A comprehensive toolkit for managing a self-signed Certificate Authority (CA) and generating various types of X.509 certificates with OpenSSL.

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![OpenSSL](https://img.shields.io/badge/OpenSSL-3.x-green.svg)](https://www.openssl.org/)

## Features

- 🔐 **Self-signed CA** - Create your own Certificate Authority
- 🌐 **Server Certificates** - TLS/HTTPS with Subject Alternative Names (SAN)
- 👤 **Client Certificates** - Mutual TLS authentication
- ✍️ **Code Signing** - Sign software, scripts, and documents
- 🐳 **Docker Support** - Containerized environment (Alpine Linux)
- ✅ **Auto-Verification** - Built-in key/certificate matching checks
- 📝 **Interactive Prompts** - Full control over X.509 certificate details
- 🔒 **AES-256 Encryption** - Password-protected private keys

## Quick Start

### 1. Initialize CA Database

```bash
./init-ca-database.sh
```

Creates required database files (`index.txt`, `serial`, `crlnumber`).

### 2. Create Root CA

```bash
./create-root-ca.sh
```

- Generates 4096-bit RSA key (password protected)
- Creates self-signed root CA certificate (10-year validity)
- Files: `private/ca-key.pem` (keep secure!), `certs/ca-cert.pem`

### 3. Create Certificates

**Server Certificate (TLS/HTTPS):**
```bash
./create-server-cert.sh server.example.com www.example.com api.example.com
```
- Optional passphrase protection
- Multiple DNS names via SAN
- Key Usage: `digitalSignature`, `keyEncipherment`
- Extended Key Usage: `serverAuth`

**Client Certificate (Mutual TLS):**
```bash
./create-client-cert.sh client1@example.com
```
- Optional passphrase protection
- Key Usage: `digitalSignature`, `nonRepudiation`, `keyEncipherment`
- Extended Key Usage: `clientAuth`, `emailProtection`

**Code Signing Certificate:**
```bash
./create-code-signing-cert.sh "Developer Name"
```
- Passphrase required (recommended)
- Key Usage: `digitalSignature`
- Extended Key Usage: `codeSigning`

## Directory Structure

```
x509-ca/
├── certs/              # Generated certificates
├── private/            # Private keys (secure!)
├── newcerts/           # CA-managed certificate copies
├── crl/                # Certificate Revocation Lists
├── openssl.cnf         # OpenSSL configuration
├── index.txt           # CA database
├── serial              # Certificate serial numbers
├── crlnumber           # CRL numbers
│
├── Scripts/
│   ├── init-ca-database.sh
│   ├── create-root-ca.sh
│   ├── create-server-cert.sh
│   ├── create-client-cert.sh
│   ├── create-code-signing-cert.sh
│   ├── verify-key-cert-match.sh
│   ├── create-combined-pem.sh
│   └── test-server-cert-openssl.sh
│
├── Documentation/
│   ├── README.md (this file)
│   ├── DOCKER.md
│   └── POCO-USAGE.md
│
└── Dockerfile
```

## Docker Usage

Build and run in a containerized environment:

```bash
# Build image
docker build -t x509-ca:latest .

# Run interactively
docker run -it --rm -v ca-data:/ca x509-ca:latest

# Inside container
./init-ca-database.sh
./create-root-ca.sh
```

See [DOCKER.md](DOCKER.md) for detailed usage.

## Verification & Troubleshooting

### Verify Key/Certificate Match

```bash
./verify-key-cert-match.sh private/server-key.pem certs/server-cert.pem
```

### Create Combined PEM for Applications

```bash
./create-combined-pem.sh private/server-key.pem certs/server-cert.pem certs/ca-cert.pem
```

Creates `certs/server-combined.pem` with key + certificate + CA chain.

### Test Server Certificate

```bash
./test-server-cert-openssl.sh private/server-key.pem certs/server-cert.pem
```

Verifies and tests certificate with OpenSSL s_server.

## Using Certificates

### View Certificate Details

```bash
# Full details
openssl x509 -noout -text -in certs/server-cert.pem

# Subject and issuer
openssl x509 -noout -subject -issuer -in certs/server-cert.pem

# Validity dates
openssl x509 -noout -dates -in certs/server-cert.pem
```

### Verify Certificate

```bash
openssl verify -CAfile certs/ca-cert.pem certs/server-cert.pem
```

### Test TLS Server

```bash
# Start test server
openssl s_server -accept 4433 -cert certs/server-cert.pem \
  -key private/server-key.pem -CAfile certs/ca-cert.pem

# Test connection
openssl s_client -connect localhost:4433 -CAfile certs/ca-cert.pem
```

### PKCS#12 Bundles

```bash
# Create .p12 bundle
openssl pkcs12 -export -out certs/bundle.p12 \
  -inkey private/server-key.pem \
  -in certs/server-cert.pem \
  -certfile certs/ca-cert.pem
```

## Certificate Revocation

```bash
# Revoke a certificate
openssl ca -config openssl.cnf -revoke certs/server-cert.pem

# Generate CRL
openssl ca -config openssl.cnf -gencrl -out crl/ca-crl.pem

# View CRL
openssl crl -in crl/ca-crl.pem -noout -text
```

## Certificate Extensions

Available in `openssl.cnf`:

| Extension | Purpose |
|-----------|---------|
| `v3_ca` | Root CA certificates |
| `v3_intermediate_ca` | Intermediate CA certificates |
| `v3_server` | Server certificates (TLS/HTTPS) |
| `v3_client` | Client certificates (mutual TLS) |
| `v3_user` | User certificates (signing + encryption) |
| `v3_code_signing` | Code signing certificates |
| `v3_ocsp` | OCSP responder certificates |
| `v3_timestamp` | Time stamping certificates |
| `v3_custom` | Custom capabilities |

## Security Best Practices

1. **Protect CA Private Key** - Store `private/ca-key.pem` offline
2. **Strong Passphrases** - Use for CA and code signing keys
3. **File Permissions** - Automatically set by scripts (400 for keys)
4. **Regular Backups** - Back up entire directory
5. **Certificate Monitoring** - Track and revoke compromised certificates
6. **Intermediate CAs** - Use for production environments
7. **Certificate Rotation** - Rotate before expiration

## Advanced Features

### Optional Email Address

Email field is optional during certificate creation. Press Enter to skip.

### Server Key Passphrase Protection

Choose whether to password-protect server keys during creation.

### Interactive Certificate Details

All X.509 subject fields are prompted interactively:
- Country Name
- State/Province
- Locality/City
- Organization
- Organizational Unit
- Common Name
- Email Address (optional)

### Automatic Verification

All creation scripts verify key/certificate match before completion.

## Troubleshooting

### Database Errors

```bash
# Reinitialize database
./init-ca-database.sh

# Or manually
touch index.txt
echo 1000 > serial
echo 1000 > crlnumber
```

### View Issued Certificates

```bash
cat index.txt
```

Format: `Status | Expiry | Revocation | Serial | Filename | Subject`

### Reset CA

```bash
rm index.txt* serial* crlnumber*
./init-ca-database.sh
```

## Files to Protect

**Never commit or share:**
- `private/*.pem` - Private keys
- `*.p12` - PKCS#12 bundles
- `index.txt` - CA database (contains all issued certs)

**Safe to distribute:**
- `certs/ca-cert.pem` - Root CA certificate
- Public certificates (after removing from git)

## Dependencies

- OpenSSL 3.x (or compatible)
- Bash
- Standard Unix tools (sed, grep, etc.)

**Optional:**
- Docker (for containerized usage)

## Testing

Use the `test-server-cert-openssl.sh` script to validate certificates with OpenSSL before deployment.

## Contributing

This project is designed to be self-contained and production-ready. Contributions welcome for:
- Additional certificate types
- Enhanced security features
- Better error handling
- Documentation improvements

## Resources

- [OpenSSL Documentation](https://www.openssl.org/docs/)
- [X.509 Standard (RFC 5280)](https://tools.ietf.org/html/rfc5280)

## License

This project is provided as-is for certificate management and testing purposes.

---

**Generated with** [Claude Code](https://claude.com/claude-code)
