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
- 💳 **Smartcard CA Key** - Optionally keep the CA key on a PKCS#11 card
  (tested with Thales IDPrime 940); it never leaves the card

## Quick Start

### 0. Get the Project

```bash
git clone https://github.com/stephan-aichholzer/mini-pki.git
cd mini-pki
```

Everything runs from this directory - nothing is installed system-wide. For
a CA key on a smartcard, also follow
[Smartcard-Backed CA Key](#smartcard-backed-ca-key-pkcs11).

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
  [Smartcard-Backed CA Key](#smartcard-backed-ca-key-pkcs11)

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
├── init-ca-database.sh          # CA database setup
├── create-root-ca.sh            # Root CA (file or card)
├── create-server-cert.sh        # TLS server certificates
├── create-client-cert.sh        # Client / mutual TLS certificates
├── create-code-signing-cert.sh  # Code signing certificates
├── create-pkcs12-bundle.sh      # .p12 bundles
├── create-combined-pem.sh       # key + cert + chain in one PEM
├── verify-key-cert-match.sh     # Key/certificate match check
├── test-server-cert-openssl.sh  # TLS test with openssl s_server
├── openssl.cnf                  # OpenSSL configuration and profiles
├── pki.conf                     # CA key backend (file or card) and card settings
├── lib/
│   ├── ca-key.sh                # Shared CA key handling, card pre-flight check
│   ├── cli.sh                   # Shared --help / --card / --file option parsing
│   └── pkcs11-provider.sh       # Locates the OpenSSL pkcs11 provider
├── card-tools/                  # Optional smartcard helpers (see Card tools)
├── docs/PIN_USAGE.md            # Which PIN protects which key on the card
├── README.md, DOCKER.md, CHANGELOG.md, LICENSE, Dockerfile
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

With a card-backed CA (see below), first run `. lib/ca-key.sh` and add
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
**Thales IDPrime 940** using the SafeNet Authentication Client (SAC) on Linux.

Only the CA key moves to the card. Server, client and code signing keys stay
software keys, and everything else (database, profiles, verification) works
as in file mode.

### Step 1 - Install

Card mode is **portable**: the OpenSSL pkcs11 provider and the Python card
tools are built into `card-tools/` inside the project (git-ignored). Only the
smartcard stack, the vendor module and build tools come from the system.

```bash
card-tools/setup.sh
```

`setup.sh` checks and builds everything in order and is safe to run again:

| | Part | Source |
|---|---|---|
| 1 | Smartcard stack: `pcscd`, CCID driver, OpenSC tools | system packages |
| 2 | Vendor PKCS#11 module (`PKCS11_MODULE` in `pki.conf`) - for IDPrime: SafeNet Authentication Client, `/usr/lib/libeTPkcs11.so` | Thales or your card supplier |
| 3 | Build tools (only if the provider must be built) | system packages |
| 4 | OpenSSL pkcs11 provider `card-tools/pkcs11-provider/pkcs11.so` | built by `build-pkcs11-provider.sh` |
| 5 | Python card tools in `card-tools/.venv` | `requirements.txt` |
| 6 | Final check | `card-status.sh` |

It never uses `sudo`: missing system packages are listed as one ready-made
command, e.g. `sudo apt install opensc build-essential curl` (Debian/Ubuntu).
OpenSC alone can use keys on the card but cannot create them - the vendor
module is needed for key generation.

`build-pkcs11-provider.sh` downloads
[pkcs11-provider](https://github.com/openssl-projects/pkcs11-provider) 1.3.0,
checks its SHA-256, compiles it (about 10 seconds; meson and ninja go into
`card-tools/.venv`) and verifies that OpenSSL can load it. The scripts find
it automatically. Alternatives: the distribution package
(`apt install pkcs11-provider`; Ubuntu 24.04 ships the older 0.3), or any
build of your own via `PKCS11_PROVIDER_DIR` in `pki.conf`.

### Step 2 - Check the card

```bash
card-tools/card-status.sh
```

Read-only - it never logs in. It checks pcscd, reader, card, PKCS#11
module, OpenSSL provider, PIN state and remaining tries, and whether the CA
key from `pki.conf` is already on the card. Without the script:
`pkcs11-tool --module /usr/lib/libeTPkcs11.so -T`.

### Step 3 - Change the factory PIN (new cards)

IDPrime cards ship with user PIN `0000`, flagged *"user PIN to be changed"*.
Until it is changed, every login fails with `CKR_PIN_EXPIRED` - which means
the PIN is correct but expired. `pkcs11-tool --change-pin` cannot fix this
because it logs in first; use:

```bash
card-tools/.venv/bin/python card-tools/card-set-expired-pin.py
```

The factory admin key (48 hex zeros) unblocks the user PIN. Change it for
production cards and keep it safe: **a locked admin key makes the IDPrime
940 permanently unusable.**

### Step 4 - Configure `pki.conf`

Choose **one** of the two key types and set it in `pki.conf` (not per
command - every script must use the same values):

```bash
# RSA CA key (default) - widest compatibility, key generation ~2 minutes
CA_BACKEND=card
CARD_KEY_TYPE=rsa:4096
CARD_KEY_LABEL=mini-pki-ca
CARD_KEY_ID=01
```

```bash
# ECC P-256 CA key - key generation in seconds, smaller certificates
CA_BACKEND=card
CARD_KEY_TYPE=EC:prime256v1
CARD_KEY_LABEL=mini-pki-ca-ec
CARD_KEY_ID=02
```

- **Supported key types depend on the card's factory configuration**, not on
  the software. A standard IDPrime 940 generates **RSA-2048, RSA-4096 and
  EC P-256**. EC P-384/P-521 and RSA-3072 are refused - Thales: *"P-384 &
  P-521 bits ECDSA, ECDH are available via a custom configuration"*, i.e.
  cards ordered with a different profile. SAC's mechanism list
  (`pkcs11-tool --module /usr/lib/libeTPkcs11.so -M`) shows the curve limit
  (ECDSA 256-256) but advertises RSA 2048-4096 as a range; OpenSC lists
  curves 256-521 for every IDPrime 940 regardless of the card.
- **One CA per directory.** `certs/ca-cert.pem`, `index.txt` and `serial`
  belong to exactly one CA key. For an RSA and an ECC CA side by side, use
  two copies of this directory, each with its own `pki.conf`.
- Give every key on the card its own `CARD_KEY_LABEL` **and** `CARD_KEY_ID`;
  the ID links a key to its certificate.
- `CARD_TOKEN` (the token label) is only needed when more than one token is
  connected. `CARD_PIN` lets scripts run without prompting - test cards only.
- **Per run:** `--card` or `--file` on `init-ca-database.sh`,
  `create-root-ca.sh` and the issuing scripts overrides `CA_BACKEND` from
  `pki.conf` and the environment for that call, e.g.
  `./create-root-ca.sh --card`. The other card settings still come from
  `pki.conf`.

### Step 5 - Create the root CA

```bash
./init-ca-database.sh
./create-root-ca.sh
```

The key is generated on the card (or reused if a key with `CARD_KEY_LABEL`
already exists), the CA certificate is self-signed **by the card** and then
stored on the card next to its key. You are asked for the **card PIN**
wherever file mode asks for the CA passphrase.

### Step 6 - Issue certificates

Unchanged from file mode - the card signs:

```bash
./create-server-cert.sh server.example.com www.example.com
./create-client-cert.sh alice
./create-code-signing-cert.sh build-bot
openssl verify -CAfile certs/ca-cert.pem certs/server.example.com-cert.pem
```

An ECC CA can issue certificates for the RSA leaf keys - mixing is fine.

**Pre-flight check.** In card mode every script checks the card *before* the
first prompt - read-only, no PIN, under a second:

```
Card pre-flight check...
  ✓ card 1178F12543E0C897 ready
  ✓ CA key 'mini-pki-ca' on the card matches certs/ca-cert.pem
```

`init-ca-database.sh` and `create-root-ca.sh` check that the card is present
(the right one, if `CARD_TOKEN` is set) and its PIN is neither expired nor
locked. The issuing scripts also check that the CA key is on the card and
that `certs/ca-cert.pem` belongs to it - so a wrong card or a wrong
`CARD_KEY_LABEL` stops the script instead of producing certificates that do
not verify.

**Which card belongs to this CA?** `create-root-ca.sh` records the card in
`ca-card.manifest` - serial number, model, key label/ID/type, public key and
CA certificate fingerprints. Public information only, git-ignored like
`index.txt`; keep it in the CA backup. It answers the question while the card
is *not* inserted:

```bash
card-tools/card-manifest.sh
```
```
=== CA card of this directory (ca-card.manifest) ===
  CA             CN=Example Root CA,O=Example
  card           Gemalto ID Prime MD
  card serial    1178F12543E0C897
  key            mini-pki-ca (ID 01, rsa:4096)

No card inserted - insert card serial 1178F12543E0C897 to use this CA.
```

With a manifest, the pre-flight check also compares the card serial
(*"wrong card: this CA belongs to card ..., card ... is inserted"*). For a CA
created before manifests existed: `card-tools/card-manifest.sh --write`.
For revocation and CRLs see [Certificate Revocation](#certificate-revocation).

### Step 7 - Inspect the card

```bash
card-tools/.venv/bin/python card-tools/card-tree.py --login
```

```
└── Objects (3)  all objects
    └── ID 01
        ├── Private key  RSA 4096 "mini-pki-ca"
        │   ├── usage     sign, decrypt, unwrap
        │   └── access    private, sensitive, always-sensitive, never-extractable, generated-on-card
        ├── Public key  RSA 4096 "mini-pki-ca"
        └── Certificate  X.509 "mini-pki-ca"
            ├── subject   CN=Example Root CA,O=Example
            ├── valid     2026-10-04 .. 2036-10-01
            └── CA        yes
```

`never-extractable` and `generated-on-card` confirm the key was created on
the card and can never leave it.

Which PIN protects which key, the IDPrime *Digital Signature PIN*, and how a
CA signature differs from an eIDAS qualified signature:
[docs/PIN_USAGE.md](docs/PIN_USAGE.md).

### Card tools

| Tool | Purpose |
|---|---|
| `card-tools/setup.sh [--rebuild]` | One-shot setup of card mode: checks system parts, builds provider and venv, runs `card-status.sh`. Safe to run again |
| `card-tools/build-pkcs11-provider.sh` | Builds the OpenSSL pkcs11 provider into `card-tools/pkcs11-provider/` (portable, no system install) |
| `card-tools/card-status.sh` | Read-only health check of the whole card setup (no PIN) |
| `card-tools/card-manifest.sh [--write]` | Shows which card holds this CA's key (works without the card); `--write` records the inserted card |
| `card-tools/card-tree.py [--login] [--slot N] [--mechanisms] [--module M]` | Tree view of the token: info, PIN status, memory, objects grouped by ID with key type/size, usage, access flags and decoded certificates. `--login` logs in to **one** slot only |
| `card-tools/card-set-expired-pin.py` | Changes an expired factory PIN via `C_SetPIN` without login |
| `card-tools/card-wipe.py --objects \| --factory [--dry-run]` | Erases the card. `--objects` deletes all keys and certificates with the user PIN (admin key untouched); `--factory` re-initializes the token with the admin key and sets a new user PIN. Shows the card first, warns if it holds this directory's CA key, and only proceeds after you **type the card serial**. Refuses `--factory` if the card reports earlier wrong admin key attempts |

The Python tools need `card-tools/.venv` (created by `setup.sh`) and use `$PKCS11_MODULE`
(default: SAC). Pass `--module /usr/lib/x86_64-linux-gnu/opensc-pkcs11.so`
to `card-tree.py` to see the card through OpenSC instead.

**Erasing a card for reuse:**

```bash
card-tools/.venv/bin/python card-tools/card-wipe.py --objects --dry-run   # look first
card-tools/.venv/bin/python card-tools/card-wipe.py --factory             # full reset
```

`--factory` uses the admin key exactly once and never retries - a locked admin
key makes an IDPrime 940 permanently unusable. It never changes the admin key.
In SAC's default unlinked mode the Digital Signature PIN/PUK stay as they are.

Sources behind the card mode (Thales manuals, product briefs, OpenSC code,
PKCS#11 and eIDAS) and what was measured on a real card:
[card-tools/REFERENCE.md](card-tools/REFERENCE.md).

### Card troubleshooting

| Symptom | Cause / fix |
|---|---|
| `Card absent or mute` in the pcscd log, no ATR | Card inserted the wrong way round, or dirty contacts |
| `CKR_PIN_EXPIRED` | Factory PIN still active - step 3 |
| `CKR_ATTRIBUTE_VALUE_INVALID` on key generation | Curve not enabled on the card, e.g. `EC:secp384r1` - use `EC:prime256v1` or RSA |
| `CKR_DEVICE_MEMORY` on key generation, card not full | Key size not enabled on the card, e.g. `rsa:3072` - use `rsa:2048` or `rsa:4096` |
| `pkcs11 provider not found` | Run `card-tools/build-pkcs11-provider.sh` (or `apt install pkcs11-provider`, or set `PKCS11_PROVIDER_DIR`) |
| `certs/ca-cert.pem does not belong to key ...` | Wrong card, or `CARD_KEY_LABEL` differs from the one the CA was created with - keep the settings in `pki.conf` |
| `wrong card: this CA belongs to card ...` | Insert the card named in `ca-card.manifest` (`card-tools/card-manifest.sh`) |
| `CA key '...' is not on this card` / `card '...' not found` | Another card is inserted, or `CARD_KEY_LABEL` / `CARD_TOKEN` in `pki.conf` is wrong |
| A second PIN slot shows up (OpenSC) | The IDPrime 940 *Digital Signature PIN* - not used by mini-pki. Logging in to it with the user PIN costs a try; `card-tree.py --login` only uses one slot |

Card mode is meant for the host: the Docker image has no PC/SC access unless
you pass the host's `pcscd` socket through.

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
