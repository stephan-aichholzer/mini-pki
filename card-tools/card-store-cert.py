#!/usr/bin/env python3
"""Store a certificate on a card - public, without a key.

For the certificates above a card's own key: an intermediate CA card can then
carry its whole chain, so whoever inserts it can read the chain from the card.
Only the public certificate is written; no key is created or changed.

Safety:
  - the card and its objects are shown first; --dry-run stops there
  - refuses a label or ID that is already in use - unless --replace: then the
    certificate with that label is replaced (same ID; a key is never touched)
  - does nothing if the identical certificate is already on the card
  - reads the certificate back after writing and compares it byte for byte
  - the user PIN is read from a hidden prompt (or CARD_PIN - test cards only)

Usage (from the repository root, after setting up card-tools/.venv):
    card-tools/.venv/bin/python card-tools/card-store-cert.py ISSUER.pem --label issuing-ca --dry-run
    card-tools/.venv/bin/python card-tools/card-store-cert.py ISSUER.pem --label issuing-ca
    card-tools/.venv/bin/python card-tools/card-store-cert.py NEW.pem --label my-key --replace
    card-tools/.venv/bin/python card-tools/card-store-cert.py KEY-CERT.pem --label my-key --for-key

--for-key: the certificate OF a key on the card (e.g. one just generated with
card-gen-key.sh) - stored next to that key, with its label and ID, only if the
certificate's public key is that key's and the key has no certificate yet.

The card is $CARD_TOKEN, or the only/first inserted one. The PKCS#11 module
defaults to $PKCS11_MODULE, else SAC (/usr/lib/libeTPkcs11.so).
"""
import argparse
import getpass
import os
import re
import sys

import PyKCS11
from cryptography import x509
from cryptography.hazmat.primitives import serialization

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from importlib import import_module  # noqa: E402

find_key = import_module("card-find-key")   # card_public_keys(), cert_key()

DEFAULT_MODULE = "/usr/lib/libeTPkcs11.so"
CLASS_NAMES = {
    PyKCS11.CKO_PRIVATE_KEY: "private key",
    PyKCS11.CKO_PUBLIC_KEY: "public key",
    PyKCS11.CKO_CERTIFICATE: "certificate",
    PyKCS11.CKO_SECRET_KEY: "secret key",
    PyKCS11.CKO_DATA: "data",
}


def fail(msg, code=1):
    print(f"✗ {msg}", file=sys.stderr)
    sys.exit(code)


def load_cert(path):
    data = open(path, "rb").read()
    try:
        return x509.load_pem_x509_certificate(data)
    except ValueError:
        return x509.load_der_x509_certificate(data)


def find_slot(lib):
    want = os.environ.get("CARD_TOKEN", "")
    for slot in lib.getSlotList(tokenPresent=True):
        if not want or lib.getTokenInfo(slot).label.strip() == want:
            return slot
    fail(f"card '{want}' (CARD_TOKEN) not found" if want else "no card found - is it inserted?")


def objects(session):
    """(class name, label, ID hex, DER value or None) of every visible object."""
    out = []
    for obj in session.findObjects():
        cls, label = session.getAttributeValue(obj, [PyKCS11.CKA_CLASS, PyKCS11.CKA_LABEL])
        obj_id = session.getAttributeValue(obj, [PyKCS11.CKA_ID], allAsBinary=True)[0]
        value = None
        if cls == PyKCS11.CKO_CERTIFICATE:
            value = bytes(session.getAttributeValue(obj, [PyKCS11.CKA_VALUE], allAsBinary=True)[0])
        if isinstance(label, (bytes, bytearray, list, tuple)):
            label = bytes(label).decode("utf-8", "replace")
        out.append((CLASS_NAMES.get(cls, f"class {cls}"), (label or "").strip("\x00 "),
                    bytes(obj_id).hex() if obj_id else "", value))
    return out


def main():
    sys.stdout.reconfigure(line_buffering=True)
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cert", help="certificate to store (PEM or DER)")
    ap.add_argument("--label", required=True, help="label of the certificate object, e.g. issuing-ca or root-ca")
    ap.add_argument("--id", help="object ID in hex (default: the next free one-byte ID)")
    ap.add_argument("--replace", action="store_true",
                    help="replace the certificate that has this label (same ID) - keys are never touched")
    ap.add_argument("--for-key", action="store_true",
                    help="the certificate of a key on the card: stored next to it (its label and ID)")
    ap.add_argument("--dry-run", action="store_true", help="show the card and the plan, write nothing")
    ap.add_argument("--module", default=os.environ.get("PKCS11_MODULE", DEFAULT_MODULE),
                    help="PKCS#11 module (default: $PKCS11_MODULE or SAC)")
    args = ap.parse_args()

    if not re.fullmatch(r"[A-Za-z0-9._-]{1,64}", args.label):
        fail("label: 1-64 characters, letters, digits, . _ - only", 2)
    try:
        cert = load_cert(args.cert)
    except (OSError, ValueError) as e:
        fail(f"cannot read certificate {args.cert}: {e}", 2)
    der = cert.public_bytes(serialization.Encoding.DER)

    lib = PyKCS11.PyKCS11Lib()
    try:
        lib.load(args.module)
    except PyKCS11.PyKCS11Error as e:
        fail(f"cannot load {args.module}: {e}")
    slot = find_slot(lib)
    info = lib.getTokenInfo(slot)
    session = lib.openSession(slot, PyKCS11.CKF_SERIAL_SESSION | PyKCS11.CKF_RW_SESSION)
    try:
        objs = objects(session)
        print("=== Card ===")
        print(f"  label         {info.label.strip()}")
        print(f"  serial        {info.serialNumber.strip()}")
        print(f"  objects       {len(objs)} public")
        for cls, label, obj_id, _ in objs:
            print(f"      ID {obj_id or '-':<6} {cls:<12} {label}")
        print("=== Certificate ===")
        print(f"  subject       {cert.subject.rfc4514_string()}")
        print(f"  issuer        {cert.issuer.rfc4514_string()}")
        print(f"  file          {args.cert}")

        for cls, label, obj_id, value in objs:
            if value == der:
                print(f"\n✓ already on the card as '{label}' (ID {obj_id}) - nothing to do")
                return
        old = [o for o in objs if o[0] == "certificate" and o[1] == args.label]
        if args.for_key:
            match = [k for k in find_key.card_public_keys(session) if k[2] == find_key.cert_key(cert)]
            if not match:
                fail("--for-key: the card holds no key matching this certificate")
            key_label, cka_id = match[0][0], match[0][1].lower()
            if key_label != args.label:
                fail(f"--for-key: the matching key is labelled '{key_label}', not '{args.label}'")
            if any(o[0] == "certificate" and o[2] == cka_id for o in objs):
                fail(f"--for-key: the key '{key_label}' (ID {cka_id}) already has a certificate - use --replace")
            print(f"\nPlan: store it next to its key '{key_label}', ID {cka_id} (public)")
        elif args.replace:
            if not old:
                fail(f"--replace: no certificate labelled '{args.label}' on the card")
            cka_id = (args.id or old[0][2]).lower()
            old_subject = x509.load_der_x509_certificate(old[0][3]).subject.rfc4514_string()
            print(f"\nPlan: replace certificate '{args.label}' (ID {old[0][2]}, {old_subject})")
            print(f"      with this one, ID {cka_id} - keys are not touched")
        else:
            used_ids = {o[2] for o in objs}
            cka_id = (args.id or next(f"{n:02x}" for n in range(1, 256) if f"{n:02x}" not in used_ids)).lower()
            for cls, label, obj_id, _ in objs:
                if label == args.label:
                    fail(f"the card already has a {cls} labelled '{args.label}' - choose another --label, or --replace")
                if obj_id == cka_id:
                    fail(f"the card already has a {cls} with ID {cka_id} ('{label}') - choose another --id")
            print(f"\nPlan: store it as certificate '{args.label}', ID {cka_id} (public, no key)")
        if args.dry_run:
            print("--dry-run: stopping here, nothing was written.")
            return

        pin = os.environ.get("CARD_PIN") or getpass.getpass("User PIN: ")
        try:
            session.login(pin)
        except PyKCS11.PyKCS11Error as e:
            fail(f"login failed: {e} - nothing was written")
        template = [(PyKCS11.CKA_CLASS, PyKCS11.CKO_CERTIFICATE),
                    (PyKCS11.CKA_CERTIFICATE_TYPE, PyKCS11.CKC_X_509),
                    (PyKCS11.CKA_TOKEN, True), (PyKCS11.CKA_PRIVATE, False),
                    (PyKCS11.CKA_LABEL, args.label), (PyKCS11.CKA_ID, bytes.fromhex(cka_id)),
                    (PyKCS11.CKA_SUBJECT, list(cert.subject.public_bytes())),
                    (PyKCS11.CKA_ISSUER, list(cert.issuer.public_bytes())),
                    (PyKCS11.CKA_VALUE, list(der))]
        if args.replace:
            for obj in session.findObjects([(PyKCS11.CKA_CLASS, PyKCS11.CKO_CERTIFICATE),
                                            (PyKCS11.CKA_LABEL, args.label)]):
                try:
                    session.destroyObject(obj)
                except PyKCS11.PyKCS11Error as e:
                    fail(f"removing the old certificate failed: {e} - nothing was written")
            print(f"  ✓ old certificate '{args.label}' removed")
        try:
            session.createObject(template)
        except PyKCS11.PyKCS11Error as e:
            fail(f"writing the certificate failed: {e}")
        stored = [o for o in objects(session) if o[1] == args.label and o[3] == der]
        if not stored:
            fail("the certificate was written but does not read back identically - check the card")
        print(f"  ✓ stored as '{args.label}' (ID {cka_id}) and read back identically")
    finally:
        try:
            session.logout()
        except PyKCS11.PyKCS11Error:
            pass
        session.closeSession()


if __name__ == "__main__":
    main()
