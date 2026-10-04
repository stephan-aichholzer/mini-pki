# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added
- PKCS#12 bundle script (`create-pkcs12-bundle.sh`) for cross-platform
  certificate distribution

### Added
- `create-root-ca.sh` refuses to replace an existing CA unless confirmed;
  overwriting the key invalidates every certificate already issued from it

### Fixed
- Key/certificate comparisons no longer pipe the modulus through `openssl md5`.
  If both openssl calls failed they each hashed empty input to the same digest
  and the scripts reported a MATCH; the raw moduli are now compared directly
- Passphrase prompts during verification are no longer swallowed by
  `2>/dev/null`, so an encrypted key no longer looks like a silent hang
- Password-protection prompts read a whole line instead of a single character.
  The Enter keystroke after "y" stayed in the input buffer and was consumed by
  openssl's next passphrase prompt as an empty passphrase, aborting the script
- `create-root-ca.sh` now verifies the CA certificate against the key that
  signed it, which the other creation scripts already did
- Creation scripts no longer claim the Common Name is filled in automatically;
  it has always been entered at the interactive prompt
- `create-client-cert.sh` now asks whether to protect the key, matching
  `create-server-cert.sh`, instead of relying on a hidden prompt and a fallback
- `create-server-cert.sh` removes `temp_server.cnf` via a trap, so it is not
  left behind when the script fails partway
- `create-pkcs12-bundle.sh` and `verify-key-cert-match.sh` no longer contain
  `if [ $? -ne 0 ]` branches that `set -e` made unreachable
- `test-server-cert-openssl.sh` detects a busy port with bash's `/dev/tcp`
  instead of `lsof`, which is not installed in the Docker image
- `create-combined-pem.sh` usage hints: Node.js `pfx` expects PKCS#12, not a
  combined PEM, and the Apache example was missing `SSLCertificateKeyFile`

### Changed
- Private keys and bundles are created `600` instead of `400`, and
  certificates `644` instead of `444`. The read-only modes made every re-run
  fail with a bare "Permission denied"; this is a toolkit for generating
  certificates, not for holding them in production, so the owner keeps write
  access. Tighten a key to `400` when you move it into service
- `init-ca-database.sh` writes `index.txt.attr` with `unique_subject = no`.
  openssl otherwise refuses to issue a second certificate for a name already
  in the database, so re-running a script failed with "There is already a
  certificate for /CN=..." — and only after the private key had been
  overwritten
- Docker base image bumped from Alpine 3.19 to 3.24. Alpine 3.19 reached end of
  support in November 2025 and shipped OpenSSL 3.1.x, a branch that is no
  longer maintained; 3.24 ships OpenSSL 3.5.x

### Removed
- Duplicate `[ ocsp ]` section in `openssl.cnf`, identical to `[ v3_ocsp ]`

### Fixed (documentation)
- DOCKER.md no longer references the test scripts removed in 1.1.0; the
  "Automated Testing" and CI/CD sections now reflect that the creation scripts
  are interactive
- DOCKER.md bind-mount example no longer mounts over `/ca`, which hid the
  scripts and `openssl.cnf` baked into the image
- DOCKER.md now documents the single `/ca` volume the image actually declares,
  instead of four per-directory volumes
- Corrected documented image size (~82 MB) and the stale `README.txt` reference
- README examples now use the filenames the scripts actually generate
  (`<common-name>-key.pem` / `<common-name>-cert.pem`)
- README License section now matches the MIT badge and LICENSE file

### Documentation
- Noted that scripts must be run from the repository root (`dir = .` in
  `openssl.cnf`)
- Noted that server certificates always get `localhost`, `127.0.0.1`, and `::1`
  in the SAN
- Noted the leftover `.csr` files in `certs/`

## [1.1.0] - 2025-11-14

### Added
- Automatic key/certificate verification in all creation scripts
- Verification and combined PEM tools for OpenSSL applications
- Optional passphrase protection for server certificates
- Interactive X.509 certificate detail prompts (no hardcoded values)
- CA database initialization script (`init-ca-database.sh`)
- Docker containerization support (Alpine Linux 3.19, 57MB image)
- Interactive welcome message in Docker container
- Helper scripts: `verify-key-cert-match.sh`, `create-combined-pem.sh`, `test-server-cert-openssl.sh`
- Comprehensive Markdown documentation (README.md, DOCKER.md, CHANGELOG.md)

### Changed
- Email address is now optional in certificates (press Enter to skip)
- All production scripts use interactive prompts instead of hardcoded `-subj` values
- README converted from .txt to .md with improved formatting, badges, and tables
- OpenSSL config updated to use correct paths for CA files (`private/`, `certs/`)
- Docker now uses single volume mount (`/ca`) for better persistence
- Docker COPY strategy updated to explicitly list required scripts

### Removed
- Test scripts for CI/CD (not essential, users can use interactive scripts)

### Fixed
- Certificate creation scripts now verify key/cert match before completion
- Prevents "X509_check_private_key: key values mismatch" errors
- Fixed CA database file paths in openssl.cnf
- Docker container now includes all helper scripts and documentation

## [1.0.0] - 2025-11-13

### Initial Release

- OpenSSL configuration with multiple certificate profiles
- Scripts for creating CA, server, client, and code signing certificates
- Directory structure with .gitkeep files
- Comprehensive .gitignore for certificate artifacts
- AES-256 encryption for password-protected keys
- Support for multiple certificate types:
  - Root CA (4096-bit)
  - Server certificates (TLS/HTTPS with SAN)
  - Client certificates (mutual TLS)
  - Code signing certificates
- Basic documentation and usage examples
