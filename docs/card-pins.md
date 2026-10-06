# IDPrime 940 — which PIN protects which key

How PINs and keys belong together on a Thales IDPrime 940, and what that
means for the mini-pki card mode. Setup steps:
[card-mode.md](card-mode.md).

## The core idea

The card does not know *what* you sign (certificate, CSR, contract, ...).
It only knows **which PIN protects which key**. Every private key is bound
to one PIN when it is created, and that PIN must be presented before the
key can be used.

| Role | Name | Protects | Asked |
|---|---|---|---|
| #1 | User PIN | normal keys (login, encryption, our CA key) | once per session |
| #3 | Digital Signature PIN | keys for eIDAS qualified signatures | **for every signature** |
| admin | Admin key | no keys — administration only (unblock user PIN, re-init) | challenge-response |
| #4 | Signature PUK | no keys — only unblocks the Signature PIN | when blocked |

## Example: an RSA key bound to the user PIN

This is what `create-root-ca.sh` does in card mode with the default
`pki.conf` (shown here as the plain command):

```bash
pkcs11-tool --module /usr/lib/libeTPkcs11.so \
    --login \
    --keypairgen --key-type rsa:4096 \
    --id 01 --label mini-pki-ca
```

What each part does:

| Option | Meaning |
|---|---|
| `--module /usr/lib/libeTPkcs11.so` | talk to the card through SAC (OpenSC cannot create keys) |
| `--login` | log in with the **user PIN** (prompted) — the new key is bound to it |
| `--keypairgen --key-type rsa:4096` | the card generates the key pair itself (~2 min) |
| `--id 01` | `CKA_ID` — links private key, public key and certificate |
| `--label mini-pki-ca` | human-readable name, used in the `pkcs11:` URI |

Result as reported by the card:

```
Private Key Object; RSA
  label:      mini-pki-ca
  ID:         01
  Usage:      decrypt, sign, unwrap
  Access:     sensitive, always sensitive, never extractable, local
```

- `never extractable` — the private key can never leave the card
- `local` — it was generated on the card, not imported

## Checking which PIN a key is bound to

```bash
pkcs15-tool --list-keys          # read-only, no PIN needed
```

```
Private RSA Key [Private key 1]
	ModLength      : 4096
	Auth ID        : 11          <- 11 = user PIN, 83 = Digital Signature PIN
	ID             : 0001
```

The Auth ID is the PIN that protects the key: `11` is the user PIN
(card reference 0x11), `83` is the Digital Signature PIN (0x83).

## Using the key: the PIN is the only thing needed

Signing with the card - this is what `create-server-cert.sh` and the other
issuing scripts run in card mode (`lib/ca-key.sh` adds the provider options):

```bash
openssl ca -config openssl.cnf \
    -provider pkcs11 -provider default \
    -keyfile "pkcs11:object=mini-pki-ca;type=private" \
    -in request.csr -out cert.pem
# -> asks for the user PIN, the card computes the signature
```

The host sends a hash, the card signs it with the private key and returns
the signature. The key itself never crosses the reader.

## Why the Digital Signature PIN was never needed

Our CA key is bound to the **user PIN** (Auth ID 11), so the Signature PIN
plays no role. It only matters for keys that are explicitly created as
signature keys (role #3) — there are none on the card.

## Our CA signature vs. an eIDAS qualified signature

The math is identical (RSA signature on the card). The difference is
everything around it:

| | mini-pki CA signature | eIDAS qualified signature (QES) |
|---|---|---|
| Key protected by | user PIN, once per session | Signature PIN, **every** signature |
| Admin can reset that PIN | yes (admin key) | **no** — only the signer's PUK |
| Certificate from | our own root CA | qualified trust service provider (EU trust list) |
| Legal effect | none — trust inside our own PKI | equal to a handwritten signature (eIDAS Art. 25) |
| Purpose | technical: issue certificates, sign CRLs | legal: contracts, applications |

A QES needs **all three**: a qualified certificate, a certified device
(QSCD — the 940 is one) and sole control via the Signature PIN.
The card alone does not make a signature qualified.

**For a CA, the user PIN is the right choice:** a CA signs often and
sometimes automatically; a PIN prompt for every certificate would be
impractical. The Signature PIN is meant for people signing legal
declarations — not needed for this project.

## Safety rules

- Log in to **one** PIN at a time. OpenSC shows the Signature PIN as a
  second slot; logging in to "all slots" burns a try on it.
- Remaining tries: `pkcs15-tool --list-pins` (user PIN 5, Signature PIN 3).
- Never lock the admin key — a locked admin key makes the IDPrime 940
  permanently unusable (Thales known issue ASAC-11163).
