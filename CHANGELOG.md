# Changelog

All notable changes to this project will be documented in this file.

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
- POCO C++ usage guide (not needed for core functionality)
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
