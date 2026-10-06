# References - smartcard / PKCS#11 card mode

Sources behind the card mode, the card tools and the statements in
[card-mode.md](card-mode.md) and [card-pins.md](card-pins.md). For each source: what
it was used for. Links checked 2026-10-04.

## Thales / SafeNet documentation

| Source | Used for |
|---|---|
| [SafeNet Authentication Client 10.8 R6 - Windows Release Notes](https://www.posta.ba/wp-content/uploads/2023/12/safenet-authentication-client-108-r6-windows-post-ga-2-release-notes-rev-m-1.pdf) (PDF, third-party mirror) | Factory credentials: user PIN `0000`, admin key 48 hex zeros, Digital Signature PIN/PUK `000000`. Known issue **ASAC-11163**: a locked admin key makes an IDPrime 940/3940 permanently unusable. Digital Signature PIN = role #3, PUK = role #4 |
| [SafeNet Authentication Client 10.8 R6 - Windows Administrator Guide](https://www.posta.ba/wp-content/uploads/2023/12/safenet-authentication-client-108-r6-windows-ga-administrator-guide-rev-h-1.pdf) (PDF, third-party mirror) | Chapter "Common Criteria": `C_InitToken` needs the current SO (admin) password; linked vs. unlinked mode; in unlinked mode `C_InitToken` ignores the Digital Signature PIN/PUK; linked-mode `C_SetPIN`/`C_InitPIN` behaviour. Basis of `card-wipe.py --factory` |
| [SafeNet IDPrime 940 and 940B - Product Brief](https://www.thalestct.com/wp-content/uploads/2024/08/SafeNet-IDPrime-940-TCT-pb-11.14.23.pdf) (PDF) | *"P-256 bits ECDSA, ECDH. P-384 & P-521bits ECDSA, ECDH are available via a custom configuration"*; RSA up to 4096; on-card key generation; CC EAL5+ / QSCD; 400 KB (940) / 500 KB (940B) flash |
| [SafeNet IDPrime 940C/3940C - Product Brief](https://cpl.thalesgroup.com/sites/default/files/content/product_briefs/safenet-idprime-940C-3940C-smart-cards-pb.pdf) (PDF) | Same curve statement for the 940C/3940C |
| [SAC 10.9 for Linux - release announcement](https://data-protection-updates.gemalto.com/2025/01/13/safenet-authentication-client-sac-10-9-for-linux-and-safenet-authentication-client-sac-10-8-for-sdk-release-announcement/) | SAC 10.9 for Linux exists and supports the IDPrime 940 family (the version tested here) |

The official Thales support portal (supportportal.thalesgroup.com) holds the
current SAC manuals but needs a customer login; SAC itself comes from Thales
or the card supplier.

## Third-party documentation

| Source | Used for |
|---|---|
| [Nexus: Encoding using Gemalto/SafeNet/Thales middleware](https://doc.nexusgroup.com/pub/encoding-using-gemalto-safenet-thales-middleware-i) | *"The factory default for the signature PIN and PUK is 000000"*; the IDPrime 940 has a secondary signature slot with its own credentials |
| [Chilkat: IDPrime MD - import certificate](https://example-code.com/tcl/idprime_md_import_certificate_smart_card.asp) | The four PIN roles: `user`, `admin`, `3` (Digital Signature PIN), `4` (PUK) |
| [QSCD.eu: Thales IDPrime 940](https://www.qscd.eu/eidas-smart-cards/smart-card-thales-gemalto-idprime-md-940/) | IDPrime 940 is an eIDAS qualified signature creation device (QSCD) |

## Open-source software

| Source | Used for |
|---|---|
| [OpenSC `card-idprime.c`](https://github.com/OpenSC/OpenSC/blob/master/src/libopensc/card-idprime.c) | Curves P-256/384/521 are **hardcoded** for every IDPrime 940 (not read from the card); signature-PIN keys use PIN id `83`, normal keys `11` |
| [OpenSC `pkcs15-idprime.c`](https://github.com/OpenSC/OpenSC/blob/master/src/libopensc/pkcs15-idprime.c) | PIN references `0x11` (user PIN) and `0x83` (Digital Signature PIN); keys under the signature PIN are marked *user consent* (PIN for every signature) |
| [OpenSC PR #2666](https://github.com/OpenSC/OpenSC/pull/2666) | IDPrime 830/930/940 support in OpenSC (0.24+) |
| [OpenSC wiki](https://github.com/OpenSC/OpenSC/wiki) | `pkcs11-tool`, `pkcs15-tool`, `opensc-tool` usage |
| [pkcs11-provider](https://github.com/openssl-projects/pkcs11-provider), [release v1.3.0](https://github.com/openssl-projects/pkcs11-provider/releases/tag/v1.3.0) | OpenSSL 3 provider built by `build-pkcs11-provider.sh`; the release publishes no checksum file, so the tarball SHA-256 is pinned in the script |
| [PyKCS11](https://github.com/LudovicRousseau/PyKCS11) | Python PKCS#11 binding used by `card-tree.py`, `card-set-expired-pin.py`, `card-wipe.py` |
| [pcsc-lite](https://pcsclite.apdu.fr/) | PC/SC daemon (`pcscd`), `pcsc_scan`; `pcsc-spy` for APDU traces |

## Standards and regulation (background)

| Source | Used for |
|---|---|
| [OASIS PKCS #11 Specification v3.1](https://docs.oasis-open.org/pkcs11/pkcs11-spec/v3.1/os/pkcs11-spec-v3.1-os.html) | Semantics of `C_InitToken`, `C_InitPIN`, `C_SetPIN` (allowed in an R/W public session - basis of `card-set-expired-pin.py`), `CKR_PIN_EXPIRED`, token flags such as `CKF_USER_PIN_TO_BE_CHANGED` and `CKF_SO_PIN_*` |
| [Regulation (EU) No 910/2014 (eIDAS)](https://eur-lex.europa.eu/eli/reg/2014/910/oj) | Simple / advanced / qualified electronic signatures; Art. 25(2): a qualified signature has the effect of a handwritten one |
| [EU Trust Services List browser](https://eidas.ec.europa.eu/efda/trust-services/browse/eidas/tls) | Qualified trust service providers - where qualified certificates come from |

## Own measurements (IDPrime 940, SAC 10.9, OpenSC 0.25, 2026-10-04)

Verified on a real card, not taken from documentation:

- Factory user PIN is flagged *"to be changed"*; login returns `CKR_PIN_EXPIRED`
  (correct but expired); `pkcs11-tool --change-pin` cannot change it, a
  `C_SetPIN` in an R/W public session can. The Digital Signature PIN was
  **not** flagged as expired.
- Retry counters (`pkcs15-tool --list-pins`): user PIN 5, Digital Signature PIN 3.
- Unlinked mode confirmed: after changing the user PIN, the Digital Signature
  PIN still accepted its factory value `000000`.
- Key generation: RSA-2048, RSA-4096, EC P-256 work; EC P-384/P-521 fail with
  `CKR_ATTRIBUTE_VALUE_INVALID`, RSA-3072 with `CKR_DEVICE_MEMORY` (card far
  from full). P-256 key generation ~4 s, RSA-4096 ~2 min, a signature ~0.6 s.
- Private key **import** (2026-10-06, SAC 10.9 R1, user PIN, throwaway keys):
  RSA-2048 and RSA-4096 import with `C_CreateObject` and with `C_UnwrapKey`
  (PKCS#8, wrapped with an AES-CBC-PAD session key); the imported key is
  `sensitive`, not extractable, `local=false`, no PIN per signature, and its
  signatures verify against the original certificate. **EC P-256 import is
  refused** on both paths: `C_CreateObject` → `CKR_USER_NOT_LOGGED_IN` (also
  with `pkcs11-tool --write-object --type privkey`), `C_UnwrapKey` →
  `CKR_TEMPLATE_INCONSISTENT` with `CKA_EC_PARAMS`, `CKR_WRAPPED_KEY_INVALID`
  without, for raw scalar, SEC1 and PKCS#8 encodings alike. P-384 →
  `CKR_ATTRIBUTE_VALUE_INVALID`, RSA-3072 → `CKR_DEVICE_MEMORY`, as for key
  generation. So an EC key can only be generated on the card - one card, no
  backup copy.
- Memory: ~73 KB in total; one RSA-4096 key pair plus certificate uses ~3 KB.
- The public key read from the card (`pkcs11-tool --read-object --type pubkey`)
  is byte-identical to the certificate's SubjectPublicKeyInfo - basis of the
  pre-flight key/certificate check.
- Wipe (`card-wipe.py`): `--objects` deleted all 6 objects with the user PIN,
  counters unchanged. `--factory` with the factory admin key re-initialized
  the token: no objects left, free memory back to 74,704 of 74,752 bytes
  (deleting objects alone leaves ~3 KB in use), new user PIN set and **not**
  flagged as expired, no admin warning flags. The Digital Signature PIN kept
  its value `000000` and its 3 tries (unlinked mode).
- After the factory reset, mini-pki card mode worked unchanged: RSA-4096
  generated on the empty card (~1 min this time - RSA key generation time
  varies), root CA, server and client certificates verified.
- OpenSC exposes the Digital Signature PIN as a second slot: logging in to all
  slots with the user PIN costs a try on the Digital Signature PIN.
