# Card mode: CA key on a smartcard (PKCS#11)

Run every command from the repository root, as in the [README](../README.md).
On WSL2, first follow [card-mode-wsl2.md](card-mode-wsl2.md).

Instead of `private/ca-key.pem`, the CA private key can be generated on and
used from a PKCS#11 smartcard. Signing happens on the card; the key is
created *non-extractable* and cannot be copied. Tested with a
**Thales IDPrime 940** using the SafeNet Authentication Client (SAC) on Linux.

Only the CA key moves to the card. Server, client and code signing keys stay
software keys, and everything else (database, profiles, verification) works
as in file mode.

## Step 1 - Install

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

**On WSL2** the reader must first be passed from Windows to WSL with
usbipd-win, and pcscd must be allowed to serve your WSL shell (polkit) - see
[card-mode-wsl2.md](card-mode-wsl2.md), including the PowerShell part.

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

## Step 2 - Check the card

```bash
card-tools/card-status.sh
```

Read-only - it never logs in. It checks pcscd, reader, card, PKCS#11
module, OpenSSL provider, PIN state and remaining tries, and whether the CA
key from `pki.conf` is already on the card. Without the script:
`pkcs11-tool --module /usr/lib/libeTPkcs11.so -T`.

## Step 3 - Change the factory PIN (new cards)

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

## Step 4 - Configure `pki.conf`

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

## Step 5 - Create the root CA

```bash
./init-ca-database.sh
./create-root-ca.sh
```

The key is generated on the card (or reused if a key with `CARD_KEY_LABEL`
already exists), the CA certificate is self-signed **by the card** and then
stored on the card next to its key. You are asked for the **card PIN**
wherever file mode asks for the CA passphrase.

## Step 6 - Issue certificates

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
For revocation and CRLs see
[Certificate Revocation](../README.md#certificate-revocation).

## Step 7 - Inspect the card

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
[card-pins.md](card-pins.md).

## Card tools

| Tool | Purpose |
|---|---|
| `card-tools/setup.sh [--rebuild]` | One-shot setup of card mode: checks system parts, builds provider and venv, runs `card-status.sh`. Safe to run again |
| `card-tools/build-pkcs11-provider.sh` | Builds the OpenSSL pkcs11 provider into `card-tools/pkcs11-provider/` (portable, no system install) |
| `card-tools/card-status.sh` | Read-only health check of the whole card setup (no PIN) |
| `card-tools/card-manifest.sh [--write]` | Shows which card holds this CA's key (works without the card); `--write` records the inserted card |
| `card-tools/card-tree.py [--login] [--slot N] [--mechanisms] [--module M]` | Tree view of the token: info, PIN status, memory, objects grouped by ID with key type/size, usage, access flags and decoded certificates. `--login` logs in to **one** slot only |
| `card-tools/smartcard-remote.sh [--detect \| --attach \| --detach] [NAME]` | WSL2 only: moves the USB reader between Windows and WSL2 via usbipd-win (runs `Smartcard-Remote.ps1` on the Windows side; shares/unshares with a UAC prompt). See [card-mode-wsl2.md](card-mode-wsl2.md#moving-the-reader-between-windows-and-wsl) |
| `card-tools/card-set-expired-pin.py` | Changes an expired factory PIN via `C_SetPIN` without login |
| `card-tools/card-import-p12.py FILE.p12 [--label L] [--id ID] [--dry-run] [--yes]` | Loads a private key and its certificate from a PKCS#12 file onto the card (key sensitive, not extractable), checks it with a test signature against the certificate and removes everything again if a step fails. Refuses a label or ID already in use. The same file can go onto several cards - a backup card. IDPrime 940: RSA-2048/4096 only, EC keys are refused |
| `card-tools/card-store-cert.py CERT --label L [--id ID] [--replace] [--dry-run]` | Stores a certificate on the card - public, without a key - e.g. the issuing and root CA certificates on an intermediate CA card, so the card carries its whole chain. Shows the card first, refuses a used label or ID, does nothing if the identical certificate is already there, reads it back to compare. `--replace` swaps the certificate with that label (same ID), e.g. after the key was certified by a CA - keys are never touched |
| `card-tools/card-find-ca.py (--root ROOT \| --root-sha256 FP) [--pathlen N \| --leaf] --out DIR` | Finds the CA on the inserted card (a CA key with its certificate), reads the chain above it from the card, verifies it against the root you trust - `--root FILE`, or `--root-sha256` (then the root copy on the card is used only if its fingerprint matches) - and checks the path length (e.g. 0 = a CA that may only sign end entities). `--leaf` looks for a non-CA key (e.g. code signing) with the same chain check; `--eku codeSigning` demands that key usage. Writes `ca-cert.pem` and `ca-chain.pem` to DIR, prints shell assignments. No PIN |
| `card-tools/card-ca-sign-pubkey.sh PUBKEY --ca-cert CA --subject DN --profile P --extfile F --days N --out CERT` | Issues a certificate for a bare public key with a CA whose key is on a card - without a CA directory: the card is found by matching `--ca-cert`, the serial is random (128 bits); keep the issued certificates in your own records |
| `card-tools/card-sign-file.sh FILE --cert CERT [--chain CHAIN] --out FILE.sig` | Signs a file with the key on the card that matches `--cert` - a detached CMS signature (PEM), with the chain for the verifier; checked right after signing |
| `card-tools/card-find-key.py CERT` | Finds the inserted card that holds the private key for a certificate, by comparing the public keys on the cards with the certificate's - no PIN, nothing changed. Prints `CARD_TOKEN`, `CARD_SERIAL`, `CARD_KEY_LABEL`, `CARD_KEY_ID` as shell assignments (use with `eval`). Identifies a card by what it holds, not by its serial: a backup card with the same key matches too. RSA and EC |
| `card-tools/card-change-admin-key.py [--factory-admin-key] [--generate] [--dry-run]` | Replaces the admin key (SO PIN) - the factory key is public. Keys and PINs stay. Shows the card, requires typing the card serial, validates both keys locally, tries the current one exactly once, refuses after earlier wrong admin attempts, then proves the new key with one admin login. `--generate` makes a random key and shows it **before** the change, which only runs after you confirm it is recorded |
| `card-tools/card-wipe.py --objects \| --factory [--dry-run]` | Erases the card. `--objects` deletes all keys and certificates with the user PIN (admin key untouched); `--factory` re-initializes the token with the admin key and sets a new user PIN. Shows the card first, warns if it holds this directory's CA key, and only proceeds after you **type the card serial**. Refuses `--factory` if the card reports earlier wrong admin key attempts |

The Python tools need `card-tools/.venv` (created by `setup.sh`) and use `$PKCS11_MODULE`
(default: SAC). Pass `--module /usr/lib/x86_64-linux-gnu/opensc-pkcs11.so`
to `card-tree.py` to see the card through OpenSC instead.

**Loading a key from a PKCS#12 file onto a card** (e.g. a key made on an
offline machine, or a backup for a replacement card):

```bash
card-tools/.venv/bin/python card-tools/card-import-p12.py key.p12 --dry-run   # look first, no PIN
card-tools/.venv/bin/python card-tools/card-import-p12.py key.p12 --label my-key
```

The key is then usable like a key generated on the card, e.g. via
`pkcs11:object=my-key;type=private`. The PKCS#12 file is left as it is.

**Erasing a card for reuse:**

```bash
card-tools/.venv/bin/python card-tools/card-wipe.py --objects --dry-run   # look first
card-tools/.venv/bin/python card-tools/card-wipe.py --factory             # full reset
```

`--factory` uses the admin key exactly once and never retries - a locked admin
key makes an IDPrime 940 permanently unusable. It never changes the admin key.

**Replacing the factory admin key** (before a card holds real keys - anyone
who knows the admin key can reset the user PIN):

```bash
card-tools/.venv/bin/python card-tools/card-change-admin-key.py --factory-admin-key --generate --dry-run
card-tools/.venv/bin/python card-tools/card-change-admin-key.py --factory-admin-key --generate
```

Without `--factory-admin-key` the current key is prompted; without
`--generate` the new key is entered twice. Keep the new key in custody: it
is the only way to unblock the user PIN or re-initialize the card.
In SAC's default unlinked mode the Digital Signature PIN/PUK stay as they are.

Sources behind the card mode (Thales manuals, product briefs, OpenSC code,
PKCS#11 and eIDAS) and what was measured on a real card:
[card-references.md](card-references.md).

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `pcscd refuses access - readers are hidden, not missing` | polkit only lets active local login sessions use pcscd; WSL2, IDE terminals and ssh are not. Install `card-tools/pcscd-polkit.rules` - [card-mode-wsl2.md](card-mode-wsl2.md) step 6 |
| `no reader found` on WSL2 | Reader not attached to WSL: `usbipd attach --wsl --busid <BUSID>` - [card-mode-wsl2.md](card-mode-wsl2.md) |
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
