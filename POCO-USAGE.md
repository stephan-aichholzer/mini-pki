# Using Certificates with POCO C++ SSL/TLS

## Common Error: X509_check_private_key: key values mismatch

This error in POCO C++ typically occurs due to:
1. Loading certificate and key in wrong order
2. Using separate files incorrectly
3. Missing passphrase for encrypted keys
4. Incorrect file format

## Solution 1: Use Combined PEM File (Recommended)

### Create Combined PEM:
```bash
./create-combined-pem.sh private/server-key.pem certs/server-cert.pem certs/ca-cert.pem
```

### POCO Code (Combined PEM):
```cpp
#include "Poco/Net/SecureServerSocket.h"
#include "Poco/Net/Context.h"

// For unencrypted key
Poco::Net::Context::Ptr pContext = new Poco::Net::Context(
    Poco::Net::Context::SERVER_USE,
    "certs/server-combined.pem",  // Combined: key + cert + CA
    Poco::Net::Context::VERIFY_RELAXED,
    9,
    true,
    "ALL:!ADH:!LOW:!EXP:!MD5:@STRENGTH"
);

Poco::Net::SecureServerSocket serverSocket(8443, 64, pContext);
```

### POCO Code (Combined PEM with Encrypted Key):
```cpp
// For encrypted key, you need a passphrase callback
class MyPassphraseHandler : public Poco::Net::PrivateKeyPassphraseHandler
{
public:
    void onPrivateKeyRequested(const void* pSender, std::string& privateKey)
    {
        privateKey = "your-passphrase-here";
    }
};

// Create context with passphrase handler
Poco::SharedPtr<Poco::Net::InvalidCertificateHandler> pCertHandler =
    new Poco::Net::AcceptCertificateHandler(false);

Poco::SharedPtr<MyPassphraseHandler> pPassphraseHandler =
    new MyPassphraseHandler();

Poco::Net::Context::Ptr pContext = new Poco::Net::Context(
    Poco::Net::Context::SERVER_USE,
    "certs/server-combined.pem",
    Poco::Net::Context::VERIFY_RELAXED,
    9,
    true,
    "ALL:!ADH:!LOW:!EXP:!MD5:@STRENGTH"
);

Poco::Net::SSLManager::instance().initializeServer(
    pPassphraseHandler,
    pCertHandler,
    pContext
);
```

## Solution 2: Use Separate Files

### POCO Code (Separate Files - Unencrypted Key):
```cpp
Poco::Net::Context::Ptr pContext = new Poco::Net::Context(
    Poco::Net::Context::SERVER_USE,
    "",  // Empty for separate files
    "",
    "",
    Poco::Net::Context::VERIFY_RELAXED,
    9,
    true,
    "ALL:!ADH:!LOW:!EXP:!MD5:@STRENGTH"
);

// Load private key first
pContext->usePrivateKey(
    Poco::Net::PrivateKey("", "private/server-key.pem")
);

// Then load certificate
pContext->useCertificate(
    Poco::Net::X509Certificate("certs/server-cert.pem")
);

// Optionally add CA certificate
pContext->addCertificateAuthority(
    Poco::Net::X509Certificate("certs/ca-cert.pem")
);

// Create server socket
Poco::Net::SecureServerSocket serverSocket(8443, 64, pContext);
```

### POCO Code (Separate Files - Encrypted Key):
```cpp
Poco::Net::Context::Ptr pContext = new Poco::Net::Context(
    Poco::Net::Context::SERVER_USE,
    "",
    "",
    "",
    Poco::Net::Context::VERIFY_RELAXED,
    9,
    true
);

// Load encrypted private key with passphrase
pContext->usePrivateKey(
    Poco::Net::PrivateKey(
        "RSA",                          // Algorithm
        "private/server-key.pem",       // Key file
        "your-passphrase-here"          // Passphrase
    )
);

// Load certificate
pContext->useCertificate(
    Poco::Net::X509Certificate("certs/server-cert.pem")
);

// Add CA
pContext->addCertificateAuthority(
    Poco::Net::X509Certificate("certs/ca-cert.pem")
);
```

## Solution 3: Check Certificate Format

The certificates must be in PEM format (not DER or PKCS12).

### Verify Format:
```bash
# Should show "-----BEGIN CERTIFICATE-----"
head -1 certs/server-cert.pem

# Should show "-----BEGIN PRIVATE KEY-----" or "-----BEGIN ENCRYPTED PRIVATE KEY-----"
head -1 private/server-key.pem

# Should show "-----BEGIN RSA PRIVATE KEY-----" or "-----BEGIN ENCRYPTED PRIVATE KEY-----"
head -1 private/server-key.pem
```

## Troubleshooting Steps

### 1. Verify Key and Certificate Match
```bash
./verify-key-cert-match.sh private/server-key.pem certs/server-cert.pem
```

### 2. Test with OpenSSL Directly
```bash
./test-server-cert-openssl.sh private/server-key.pem certs/server-cert.pem
```

If OpenSSL can use the certificate, POCO should be able to as well.

### 3. Check File Permissions
```bash
ls -la private/server-key.pem certs/server-cert.pem

# Key should be readable
# Private key should be 400 or 600
chmod 400 private/server-key.pem
chmod 444 certs/server-cert.pem
```

### 4. Verify Certificate Chain
```bash
openssl verify -CAfile certs/ca-cert.pem certs/server-cert.pem
```

### 5. Inspect Certificate Extensions
```bash
openssl x509 -in certs/server-cert.pem -noout -text | grep -A5 "X509v3 extensions"
```

Should show:
- `Key Usage: Digital Signature, Key Encipherment`
- `Extended Key Usage: TLS Web Server Authentication`

## Common Mistakes

### ❌ Wrong Order (This causes the error!)
```cpp
// WRONG: Loading certificate before key
pContext->useCertificate(cert);
pContext->usePrivateKey(key);  // Error here!
```

### ✓ Correct Order
```cpp
// CORRECT: Load private key first, then certificate
pContext->usePrivateKey(key);
pContext->useCertificate(cert);  // Works!
```

### ❌ Missing Passphrase for Encrypted Key
```cpp
// WRONG: Encrypted key without passphrase
Poco::Net::PrivateKey("", "private/server-key.pem")  // Fails if key is encrypted
```

### ✓ With Passphrase
```cpp
// CORRECT: Provide passphrase for encrypted key
Poco::Net::PrivateKey("RSA", "private/server-key.pem", "passphrase")
```

## Complete Working Example

```cpp
#include "Poco/Net/HTTPSServerParams.h"
#include "Poco/Net/SecureServerSocket.h"
#include "Poco/Net/HTTPServer.h"
#include "Poco/Net/Context.h"
#include "Poco/Net/PrivateKeyPassphraseHandler.h"

int main()
{
    try
    {
        // Use combined PEM (easiest approach)
        Poco::Net::Context::Ptr pContext = new Poco::Net::Context(
            Poco::Net::Context::SERVER_USE,
            "certs/server-combined.pem",
            Poco::Net::Context::VERIFY_RELAXED,
            9,
            true,
            "ALL:!ADH:!LOW:!EXP:!MD5:@STRENGTH"
        );

        Poco::Net::SecureServerSocket serverSocket(8443, 64, pContext);

        Poco::Net::HTTPServerParams* pParams = new Poco::Net::HTTPServerParams;
        pParams->setMaxThreads(16);

        Poco::Net::HTTPServer server(
            new MyRequestHandlerFactory,
            serverSocket,
            pParams
        );

        server.start();

        // Wait for termination
        waitForTerminationRequest();

        server.stop();
    }
    catch (Poco::Exception& e)
    {
        std::cerr << "POCO Exception: " << e.displayText() << std::endl;
        return 1;
    }

    return 0;
}
```

## Still Not Working?

If you still get the "key values mismatch" error after trying these solutions:

1. Create a new certificate from scratch with our scripts
2. Use the `create-combined-pem.sh` script
3. Verify with `test-server-cert-openssl.sh`
4. Share your exact POCO code for review

The issue is almost always in how POCO is loading the files, not the certificates themselves.
