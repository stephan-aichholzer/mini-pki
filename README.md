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
- 📦 **PKCS#12 Bundles** - Cross-platform distribution (.p12/.pfx)
- 🔒 **AES-256 Encryption** - Password-protected private keys

## Quick Start

> **Run all scripts from the repository root.** `openssl.cnf` resolves the CA
> directories relative to the current directory (`dir = .`), so running a
> script from anywhere else writes the database and certificates to the wrong
> place.

### 1. Initialize CA Database

```bash
./init-ca-database.sh
```

Creates required database files (`index.txt`, `index.txt.attr`, `serial`,
`crlnumber`). The attributes file sets `unique_subject = no` so a certificate
can be re-issued for a name that already exists in the database.

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
- `localhost`, `127.0.0.1`, and `::1` are always added to the SAN for local
  testing — drop them from the generated certificate if you don't want them in
  a production certificate

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
- Passphrase required
- Key Usage: `digitalSignature`
- Extended Key Usage: `codeSigning`

## Directory Structure

```
mini-pki/
├── certs/              # Generated certificates
├── private/            # Private keys (secure!)
├── newcerts/           # CA-managed certificate copies
├── crl/                # Certificate Revocation Lists
├── openssl.cnf         # OpenSSL configuration
├── index.txt           # CA database
├── index.txt.attr      # CA database attributes
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
│   ├── create-pkcs12-bundle.sh
│   └── test-server-cert-openssl.sh
│
├── Documentation/
│   ├── README.md (this file)
│   ├── DOCKER.md
│   └── CHANGELOG.md
│
├── Dockerfile
└── LICENSE
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
./verify-key-cert-match.sh \
  private/server.example.com-key.pem \
  certs/server.example.com-cert.pem
```

### Create Combined PEM for Server Applications

```bash
./create-combined-pem.sh \
  private/server.example.com-key.pem \
  certs/server.example.com-cert.pem \
  certs/ca-cert.pem
```

Creates `certs/server.example.com-combined.pem` with key + certificate + CA
chain for nginx, Apache, etc.

### Create PKCS#12 Bundle for Cross-Platform Distribution

```bash
./create-pkcs12-bundle.sh \
  private/server.example.com-key.pem \
  certs/server.example.com-cert.pem \
  certs/ca-cert.pem
```

Creates `certs/server.example.com.p12` bundle for Windows IIS, browsers, Java
keystores, and mobile devices.

### Test Server Certificate

```bash
./test-server-cert-openssl.sh \
  private/server.example.com-key.pem \
  certs/server.example.com-cert.pem
```

Verifies and tests certificate with OpenSSL s_server.

## Using Certificates

### View Certificate Details

```bash
# Full details
openssl x509 -noout -text -in certs/server.example.com-cert.pem

# Subject and issuer
openssl x509 -noout -subject -issuer -in certs/server.example.com-cert.pem

# Validity dates
openssl x509 -noout -dates -in certs/server.example.com-cert.pem
```

### Verify Certificate

```bash
openssl verify -CAfile certs/ca-cert.pem certs/server.example.com-cert.pem
```

### Test TLS Server

```bash
# Start test server
openssl s_server -accept 4433 -cert certs/server.example.com-cert.pem \
  -key private/server.example.com-key.pem -CAfile certs/ca-cert.pem

# Test connection
openssl s_client -connect localhost:4433 -CAfile certs/ca-cert.pem
```

### PKCS#12 Bundles

Use the `create-pkcs12-bundle.sh` script for an interactive way to create bundles:

```bash
./create-pkcs12-bundle.sh \
  private/server.example.com-key.pem \
  certs/server.example.com-cert.pem \
  certs/ca-cert.pem
```

Or manually with OpenSSL:

```bash
openssl pkcs12 -export -out certs/bundle.p12 \
  -inkey private/server.example.com-key.pem \
  -in certs/server.example.com-cert.pem \
  -certfile certs/ca-cert.pem \
  -name "My Certificate"
```

Import into Windows, macOS, browsers, or Java keystores.

## Certificate Revocation

```bash
# Revoke a certificate
openssl ca -config openssl.cnf -revoke certs/server.example.com-cert.pem

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
3. **File Permissions** - Automatically set by scripts: `600` for private
   keys and bundles, `644` for certificates. These are deliberately writable
   by the owner so certificates can be regenerated in place — tighten a key to
   `400` once you move it into production
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

### Leftover CSRs

Each creation script leaves its signing request at `certs/<name>.csr`. These
are not secret and can be deleted once the certificate has been issued.

## Troubleshooting

### Database Errors

```bash
# Reinitialize database
./init-ca-database.sh

# Or manually
touch index.txt
echo "unique_subject = no" > index.txt.attr
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
- Issued public certificates (`certs/*-cert.pem`)

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

MIT — see [LICENSE](LICENSE).

---

**Generated with** [Claude Code](https://claude.com/claude-code)
