# Intermediate CAs - a CA hierarchy

A root CA can sign further CAs below it, which in turn issue certificates -
for example `Root → Issuing CA → Line CA → server certificates`. The root
key is then only needed when a new CA below it is created; day-to-day
certificates come from a lower CA. Every CA can keep its key in a file or
on a smartcard ([card-mode.md](card-mode.md)), independently of the others.

## One directory per CA

Each CA lives in a directory of its own: its `openssl.cnf`, database
(`index.txt`, `serial`), `certs/`, `private/` and, in card mode,
`ca-card.manifest`. The mini-pki scripts work on the directory they are
**run from**; the code stays in the repository.

```bash
mkdir -p ~/pki/root ~/pki/issuing
cd ~/pki/root && ~/mini-pki/init-ca-database.sh      # creates folders, copies openssl.cnf
```

The repository itself remains the default CA directory - nothing changes
for a single CA.

**Settings per CA:** a `pki.conf` in a CA directory is read after the
repository's `pki.conf` and overrides it for that CA - typically the card
and the key on it:

```bash
# ~/pki/issuing/pki.conf
CA_BACKEND=card
CARD_TOKEN=23F86AB4720B353F      # token label of this CA's card
CARD_KEY_LABEL=issuing-ca
CARD_KEY_ID=01
CARD_KEY_TYPE=rsa:4096
```

Use `CARD_PIN=${CARD_PIN:-}`-style lines if the environment should still be
able to override a value.

## Creating an intermediate CA - three steps

```bash
# 1. In the new CA's directory: key pair + certificate request
cd ~/pki/issuing && ~/mini-pki/init-ca-database.sh
~/mini-pki/create-intermediate-ca.sh request

# 2. In the parent CA's directory: issue the certificate
cd ~/pki/root
~/mini-pki/sign-intermediate-ca.sh ~/pki/issuing/certs/ca-csr.pem --pathlen 1

# 3. Back in the new CA's directory: check and install it
cd ~/pki/issuing
~/mini-pki/create-intermediate-ca.sh install ~/pki/root/certs/<name>-ca-chain.pem
```

| Step | Script | Result |
|---|---|---|
| 1 | `create-intermediate-ca.sh request` | key (file, or generated on the card) and `certs/ca-csr.pem` |
| 2 | `sign-intermediate-ca.sh CSR` | `certs/<name>-ca-cert.pem` and `certs/<name>-ca-chain.pem` in the parent's directory; the parent's `index.txt` records it |
| 3 | `create-intermediate-ca.sh install CHAIN` | `certs/ca-cert.pem` and `certs/ca-chain.pem`; in card mode the certificate is also stored on the card and `ca-card.manifest` written |

**With the keys on different cards**, swap cards between the steps: step 2
needs the parent's card, steps 1 and 3 the new CA's card. Each step checks
that the right card is inserted (by `CARD_TOKEN` and, once it exists, the
manifest) before it asks for a PIN.

### Checks

- **Path length** (`--pathlen N`): how many CA levels may follow below the
  new CA. Default: one less than the parent allows, or 0 below a root
  without limit. A CA with path length 0 may only issue end-entity
  certificates; asking it to sign a CA is refused, and so is a path length
  the parent does not allow.
- **Validity** (`--days N`, default 1825 = 5 years): refused if the new
  certificate would outlive its parent - the message names the maximum.
- **Install** refuses a certificate that does not belong to this CA's key,
  is not a CA certificate, or does not verify up to a self-signed root.

`--subject "/C=../O=../CN=.."` on `create-root-ca.sh` and
`create-intermediate-ca.sh request` replaces the interactive DN prompts;
`--yes` on `sign-intermediate-ca.sh` skips openssl's confirmation.

## Issuing from an intermediate CA

Run the issuing scripts (`create-server-cert.sh`, `create-client-cert.sh`,
`create-code-signing-cert.sh`) in the intermediate CA's directory, as for a
root. Relying parties trust **only the root**; they need the chain to get
there:

- `certs/ca-chain.pem` holds this CA and every CA above it, up to the root.
- A server must send its certificate **plus** the chain (e.g. nginx
  `ssl_certificate` = server certificate followed by `ca-chain.pem` without
  the root). `test-server-cert-openssl.sh` does this automatically.
- Checking a certificate the way a client does:

```bash
openssl verify -CAfile root-ca-cert.pem -untrusted certs/ca-chain.pem certs/server-cert.pem
```

## Certificates for keys without a request

Some keys cannot sign a certificate request - a TPM's endorsement key only
decrypts, a restricted attestation key only signs the TPM's own data. For
those, `sign-pubkey.sh` issues a certificate from the bare public key:

```bash
cd ~/pki/line
~/mini-pki/sign-pubkey.sh device-key.pub.pem \
    --subject "/O=Example/serialNumber=1234/CN=device 1234" \
    --profile v3_device --extfile device-profiles.cnf --days 365
```

The certificate goes into this CA's register (`index.txt`, `newcerts/`) with
the next serial, like one issued by `openssl ca`, and can be revoked the
same way.

## Example: three CAs on three cards

Verified on Thales IDPrime 940 cards (SAC 10.9): root (RSA-4096, card 1) →
issuing CA (RSA-4096, card 2, `pathlen:1`) → line CA (EC P-256, card 3,
`pathlen:0`) → server certificate signed by the line CA's card key
(ECDSA), verified by a client that trusts only the root. Mixed key types
along a chain are fine.
