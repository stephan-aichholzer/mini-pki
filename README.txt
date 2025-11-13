X.509 Certificate Authority Setup
==================================

This directory contains an OpenSSL configuration and helper scripts for managing
a self-signed Certificate Authority (CA) and generating various types of certificates.

Directory Structure:
-------------------
  certs/          - Generated certificates
  private/        - Private keys (keep secure!)
  newcerts/       - Copies of issued certificates (managed by OpenSSL CA)
  crl/            - Certificate Revocation Lists
  index.txt       - CA database of issued certificates
  serial          - Next serial number for certificates
  crlnumber       - Next CRL number
  openssl.cnf     - OpenSSL configuration file

Getting Started:
---------------

1. CREATE ROOT CA (Do this first!)
   ./create-root-ca.sh

   This will:
   - Generate a 4096-bit RSA private key (password protected)
   - Create a self-signed root CA certificate valid for 10 years

   Files created:
   - private/ca-key.pem (KEEP THIS SECURE!)
   - certs/ca-cert.pem (distribute to clients/servers)

2. CREATE SERVER CERTIFICATE (for TLS/HTTPS)
   ./create-server-cert.sh <hostname> [additional-dns-names...]

   Examples:
   ./create-server-cert.sh server.example.com
   ./create-server-cert.sh api.example.com www.example.com cdn.example.com

   Use for:
   - HTTPS web servers
   - TLS-enabled services
   - Mutual TLS (server side)

   Key Usage: digitalSignature, keyEncipherment
   Extended Key Usage: serverAuth

3. CREATE CLIENT CERTIFICATE (for mutual TLS authentication)
   ./create-client-cert.sh <client-name>

   Examples:
   ./create-client-cert.sh client1.example.com
   ./create-client-cert.sh user@example.com

   Use for:
   - Mutual TLS authentication
   - Client authentication
   - Email protection

   Key Usage: digitalSignature, keyEncipherment, nonRepudiation
   Extended Key Usage: clientAuth, emailProtection

4. CREATE CODE SIGNING CERTIFICATE
   ./create-code-signing-cert.sh <signer-name>

   Examples:
   ./create-code-signing-cert.sh "John Doe"
   ./create-code-signing-cert.sh developer@example.com

   Use for:
   - Signing software
   - Signing scripts
   - Signing documents

   Key Usage: digitalSignature
   Extended Key Usage: codeSigning

Viewing Certificates:
--------------------
# View certificate details
openssl x509 -noout -text -in certs/<cert-name>.pem

# View certificate subject and issuer
openssl x509 -noout -subject -issuer -in certs/<cert-name>.pem

# View certificate dates
openssl x509 -noout -dates -in certs/<cert-name>.pem

# View certificate in human-readable format
openssl x509 -in certs/<cert-name>.pem -noout -text | less

Verifying Certificates:
----------------------
# Verify a certificate against the CA
openssl verify -CAfile certs/ca-cert.pem certs/<cert-name>.pem

# Verify certificate chain
openssl verify -CAfile certs/ca-cert.pem -untrusted certs/intermediate.pem certs/server-cert.pem

Testing TLS:
-----------
# Test TLS server
openssl s_server -accept 4433 -cert certs/server-cert.pem -key private/server-key.pem -CAfile certs/ca-cert.pem

# Test TLS client connection
openssl s_client -connect localhost:4433 -CAfile certs/ca-cert.pem

# Test with client certificate (mutual TLS)
openssl s_client -connect localhost:4433 -CAfile certs/ca-cert.pem \
    -cert certs/client-cert.pem -key private/client-key.pem

Creating PKCS#12 Bundles:
------------------------
# Create .p12 file (contains private key + certificate + CA cert)
openssl pkcs12 -export -out certs/bundle.p12 \
    -inkey private/server-key.pem \
    -in certs/server-cert.pem \
    -certfile certs/ca-cert.pem

# Extract certificate from .p12
openssl pkcs12 -in certs/bundle.p12 -nokeys -out extracted-cert.pem

# Extract private key from .p12
openssl pkcs12 -in certs/bundle.p12 -nocerts -out extracted-key.pem

Certificate Revocation:
----------------------
# Revoke a certificate
openssl ca -config openssl.cnf -revoke certs/<cert-name>.pem

# Generate Certificate Revocation List (CRL)
openssl ca -config openssl.cnf -gencrl -out crl/ca-crl.pem

# View CRL
openssl crl -in crl/ca-crl.pem -noout -text

Manual Certificate Creation:
---------------------------
If you need more control, you can create certificates manually:

# 1. Generate private key
openssl genrsa -out private/custom-key.pem 2048

# 2. Create CSR
openssl req -config openssl.cnf -key private/custom-key.pem \
    -new -sha256 -out certs/custom.csr

# 3. Sign with CA (choose appropriate extension)
openssl ca -config openssl.cnf -extensions v3_server \
    -days 375 -notext -md sha256 \
    -in certs/custom.csr \
    -out certs/custom-cert.pem

Available Extensions in openssl.cnf:
----------------------------------
- v3_ca                  - Root CA certificates
- v3_intermediate_ca     - Intermediate CA certificates
- v3_server              - Server certificates (TLS/HTTPS)
- v3_client              - Client certificates (mutual TLS)
- v3_user                - User certificates (signing + encryption)
- v3_code_signing        - Code signing certificates
- v3_ocsp                - OCSP responder certificates
- v3_timestamp           - Time stamping certificates
- v3_custom              - Custom capabilities (modify as needed)

Security Best Practices:
-----------------------
1. Keep private/ca-key.pem extremely secure (offline storage recommended)
2. Use strong passphrases for CA and code signing keys
3. Set appropriate file permissions (done automatically by scripts)
4. Back up the entire directory (especially private/ and index.txt)
5. Monitor issued certificates and revoke compromised ones
6. Use separate intermediate CAs for different purposes in production
7. Regularly rotate certificates before expiration

Troubleshooting:
---------------
# If "failed to update database" error occurs:
# Make sure index.txt exists and has proper format
touch index.txt

# If serial number issues:
echo 1000 > serial

# If you need to start fresh:
rm index.txt* serial* crlnumber*
touch index.txt
echo 1000 > serial
echo 1000 > crlnumber

# View all issued certificates:
cat index.txt

# The index.txt format:
# Status  Expiry  Revocation  Serial  Filename  Subject

For More Information:
--------------------
OpenSSL documentation: https://www.openssl.org/docs/
Man pages: man openssl, man x509, man ca, man req
