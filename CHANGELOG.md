# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added
- Automatic key/certificate verification in all creation scripts
- POCO C++ SSL/TLS usage guide with complete examples
- Verification and combined PEM tools for OpenSSL applications
- Optional passphrase protection for server certificates
- Interactive X.509 certificate detail prompts
- CA database initialization script
- Docker containerization support (Alpine Linux 3.19)
- Comprehensive documentation (README.md, DOCKER.md, POCO-USAGE.md)
- Test scripts for CI/CD automation
- Helper scripts: `verify-key-cert-match.sh`, `create-combined-pem.sh`, `test-server-cert-openssl.sh`

### Changed
- Email address is now optional in certificates (press Enter to skip)
- All production scripts now use interactive prompts instead of hardcoded values
- README converted from .txt to .md with improved formatting
- OpenSSL config updated to use correct paths for CA files

### Fixed
- Certificate creation scripts now verify key/cert match before completion
- Prevents "X509_check_private_key: key values mismatch" errors
- Fixed CA database file paths in openssl.cnf

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
