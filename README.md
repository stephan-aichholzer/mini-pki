# X.509 Certificate Authority

A comprehensive toolkit for managing a self-signed Certificate Authority (CA) and generating various types of X.509 certificates with OpenSSL.

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![OpenSSL](https://img.shields.io/badge/OpenSSL-3.x-green.svg)](https://www.openssl.org/)

## Features

- 🔐 **Self-signed CA** - Create your own Certificate Authority
- 🌳 **CA Hierarchy** - Intermediate CAs below the root, any depth, each
  with its key in a file or on a card ([docs/intermediate-ca.md](docs/intermediate-ca.md))
- 🌐 **Server Certificates** - TLS/HTTPS with Subject Alternative Names (SAN)
- 👤 **Client Certificates** - Mutual TLS authentication
- ✍️ **Code Signing** - Sign software, scripts, and documents
- 🐳 **Docker Support** - Containerized environment (Alpine Linux)
- ✅ **Auto-Verification** - Built-in key/certificate matching checks
- 📝 **Interactive Prompts** - Full control over X.509 certificate details
- 📦 **PKCS#12 Bundles** - Cross-platform distribution (.p12/.pfx)
- 🔒 **AES-256 Encryption** - Password-protected private keys
- 💳 **Smartcard CA Key** - Optionally keep the CA key on a PKCS#11 card
  (tested with Thales IDPrime 940); it never leaves the card

## Quick Start

### 0. Get the Project

```bash
git clone https://github.com/stephan-aichholzer/mini-pki.git
cd mini-pki
```

Everything runs from this directory - nothing is installed system-wide. For
a CA key on a smartcard, also follow [docs/card-mode.md](docs/card-mode.md).

Every script explains itself: `./<script>.sh --help` (or `-h`) shows its
arguments, options, the files it creates and examples.

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
- With `--card` (or `CA_BACKEND=card` in `pki.conf`) the key is generated on a
  smartcard instead and never touches the disk - see
  [docs/card-mode.md](docs/card-mode.md)

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

## Documentation

| Document | Content |
|---|---|
| [README.md](README.md) | Overview, file mode, working with certificates (this file) |
| [docs/intermediate-ca.md](docs/intermediate-ca.md) | CA hierarchy: intermediate CAs, one directory per CA |
| [docs/docker.md](docs/docker.md) | Running the CA in a container |
| [docs/card-mode.md](docs/card-mode.md) | CA key on a smartcard: setup, card tools, troubleshooting |
| [docs/card-mode-wsl2.md](docs/card-mode-wsl2.md) | Card mode under WSL2: usbipd-win (PowerShell), SAC, polkit |
| [docs/card-pins.md](docs/card-pins.md) | Which PIN protects which key on an IDPrime 940 |
| [docs/card-references.md](docs/card-references.md) | Sources and measurements behind card mode |
| [CHANGELOG.md](CHANGELOG.md) | Changes per release |

## Directory Structure

```
mini-pki/
├── init-ca-database.sh          # CA database setup
├── create-root-ca.sh            # Root CA (file or card)
├── create-intermediate-ca.sh    # Intermediate CA: request / install
├── sign-intermediate-ca.sh      # Issue an intermediate CA certificate
├── create-server-cert.sh        # TLS server certificates
├── create-client-cert.sh        # Client / mutual TLS certificates
├── create-code-signing-cert.sh  # Code signing certificates
├── create-pkcs12-bundle.sh      # .p12 bundles
├── create-combined-pem.sh       # key + cert + chain in one PEM
├── verify-key-cert-match.sh     # Key/certificate match check
├── test-server-cert-openssl.sh  # TLS test with openssl s_server
├── openssl.cnf                  # OpenSSL configuration and profiles
├── pki.conf                     # CA key backend (file or card) and card settings
│                                #   (a CA directory may add its own pki.conf)
├── lib/
│   ├── ca-key.sh                # Shared CA key handling, card pre-flight check
│   ├── cli.sh                   # Shared --help / --card / --file option parsing
│   ├── pcsc.sh                  # Detects pcscd refusing access (polkit)
│   └── pkcs11-provider.sh       # Locates the OpenSSL pkcs11 provider
├── card-tools/                  # Optional smartcard tools (docs/card-mode.md)
├── docs/                        # Guides beyond this README (see Documentation)
├── README.md, CHANGELOG.md, LICENSE, Dockerfile
│
│   Created at runtime (git-ignored):
├── certs/                       # Certificates and CSRs
├── private/                     # Private keys (secure!)
├── newcerts/                    # Copies of every issued certificate
├── crl/                         # Certificate Revocation Lists
├── index.txt, index.txt.attr    # CA database
├── serial, crlnumber            # Next serial / CRL number
└── ca-card.manifest             # Which card holds the CA key (card mode)
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

See [docs/docker.md](docs/docker.md) for detailed usage.

## Working with Certificates

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

### PKCS#12 Bundle with OpenSSL

The same as `create-pkcs12-bundle.sh`, done by hand:

```bash
openssl pkcs12 -export -out certs/bundle.p12 \
  -inkey private/server.example.com-key.pem \
  -in certs/server.example.com-cert.pem \
  -certfile certs/ca-cert.pem \
  -name "My Certificate"
```

Import into Windows, macOS, browsers, or Java keystores.

### Test Server Certificate

```bash
./test-server-cert-openssl.sh \
  private/server.example.com-key.pem \
  certs/server.example.com-cert.pem
```

Verifies and tests certificate with OpenSSL s_server.

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

## Certificate Revocation

With a card-backed CA ([docs/card-mode.md](docs/card-mode.md)), first run `. lib/ca-key.sh` and add
`"${CA_SIGN_ARGS[@]}"` to both `openssl ca` commands.

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

## Smartcard-Backed CA Key (PKCS#11)

Instead of `private/ca-key.pem`, the CA private key can be generated on and
used from a PKCS#11 smartcard. Signing happens on the card; the key is
created *non-extractable* and cannot be copied. Tested with a
**Thales IDPrime 940** using the SafeNet Authentication Client (SAC) on Linux
and WSL2.

Only the CA key moves to the card. Server, client and code signing keys stay
software keys, and everything else (database, profiles, verification) works
as in file mode.

```bash
card-tools/setup.sh                # checks and builds what card mode needs
./create-root-ca.sh --card         # or CA_BACKEND=card in pki.conf
```

Full guide - installation, factory PIN, key types, card tools,
troubleshooting: [docs/card-mode.md](docs/card-mode.md). On WSL2 start with
[docs/card-mode-wsl2.md](docs/card-mode-wsl2.md).

## Security Best Practices

1. **Protect CA Private Key** - Store `private/ca-key.pem` offline, or keep
   it on a smartcard (`CA_BACKEND=card`)
2. **Strong Passphrases and PINs** - For the CA and code signing keys, and
   the card PIN in card mode (change the factory PIN and admin key)
3. **File Permissions** - Automatically set by scripts: `600` for private
   keys and bundles, `644` for certificates. These are deliberately writable
   by the owner so certificates can be regenerated in place — tighten a key to
   `400` once you move it into production
4. **Regular Backups** - Back up the entire directory. In card mode the CA
   key is only on the card, but `index.txt`, `serial`, `crlnumber`,
   `newcerts/` and `ca-card.manifest` exist only on disk - without them you
   cannot revoke certificates or keep serial numbers unique
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
rm -f index.txt* serial* crlnumber* ca-card.manifest
./init-ca-database.sh
```

This only resets the database. A card-held CA key stays on the card and is
reused by `create-root-ca.sh` unless you choose another `CARD_KEY_LABEL`.

## Files to Protect

**Never commit or share:**
- `private/*.pem` - Private keys
- `*.p12` - PKCS#12 bundles
- `index.txt` - CA database (contains all issued certs)

**Safe to distribute:**
- `certs/ca-cert.pem` - Root CA certificate
- Issued public certificates (`certs/*-cert.pem`)
- `ca-card.manifest` - card serial and fingerprints only (no PINs, no keys)

## Dependencies

- OpenSSL 3.x (or compatible)
- Bash
- Standard Unix tools (sed, grep, etc.)

**Optional:**
- Docker (for containerized usage)
- PC/SC + PKCS#11 module + OpenSSL pkcs11-provider (for a smartcard CA key)

## Testing

Use the `test-server-cert-openssl.sh` script to validate certificates with OpenSSL before deployment.

## Contributing

This project is a self-contained toolkit for running a small CA and
generating certificates. Contributions welcome for:
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
