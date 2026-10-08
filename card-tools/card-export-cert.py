#!/usr/bin/env python3
"""Read a certificate from the inserted card and write it as PEM.

    card-export-cert.py --label LABEL --out FILE [--serial SERIAL]

  --label LABEL    the label of the certificate object (usually the key's label)
  --out FILE       where the certificate goes (PEM)
  --serial SERIAL  only this card (token serial), e.g. the one a script found before

The certificate is exported only if its key is on the same card (a public key
with the same key material) - so the result is the certificate of a key the
card really holds, not just a copy of someone else's. No PIN, nothing changed.

On success prints shell assignments and exits 0:
    CARD_TOKEN, CARD_SERIAL, CARD_KEY_LABEL, CARD_KEY_ID, CERT_SUBJECT, CERT_SHA256
Exit 1: no such certificate with its key on the inserted card (stderr says why).
Exit 2: no card inserted.

Usage (from the repository root, after setting up card-tools/.venv):
    card-tools/.venv/bin/python card-tools/card-export-cert.py --label my-key --out my-key.pem

The PKCS#11 module defaults to $PKCS11_MODULE, else SAC (/usr/lib/libeTPkcs11.so).
"""
import argparse
import os
import shlex
import sys

import PyKCS11
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from importlib import import_module  # noqa: E402

find_key = import_module("card-find-key")   # card_public_keys(), cert_key(), text()

DEFAULT_MODULE = "/usr/lib/libeTPkcs11.so"


def err(msg, code):
    print(f"✗ {msg}", file=sys.stderr)
    sys.exit(code)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--label", required=True, help="label of the certificate object on the card")
    ap.add_argument("--out", required=True, help="output file (PEM)")
    ap.add_argument("--serial", help="only the card with this token serial")
    ap.add_argument("--module", default=os.environ.get("PKCS11_MODULE", DEFAULT_MODULE),
                    help="PKCS#11 module (default: $PKCS11_MODULE or SAC)")
    args = ap.parse_args()

    lib = PyKCS11.PyKCS11Lib()
    try:
        lib.load(args.module)
        slots = lib.getSlotList(tokenPresent=True)
    except PyKCS11.PyKCS11Error as e:
        err(f"PKCS#11 module {args.module}: {e}", 2)
    if not slots:
        err("no card in the reader", 2)

    reasons = []
    for slot in slots:
        info = lib.getTokenInfo(slot)
        serial = info.serialNumber.strip()
        if args.serial and serial != args.serial:
            reasons.append(f"{serial}: not the card {args.serial}")
            continue
        session = lib.openSession(slot)
        try:
            keys = find_key.card_public_keys(session)
            objs = session.findObjects([(PyKCS11.CKA_CLASS, PyKCS11.CKO_CERTIFICATE),
                                        (PyKCS11.CKA_LABEL, args.label)])
            certs = [bytes(session.getAttributeValue(o, [PyKCS11.CKA_VALUE], allAsBinary=True)[0]) for o in objs]
        finally:
            session.closeSession()
        if not certs:
            reasons.append(f"{serial}: no certificate labelled '{args.label}'")
            continue
        if len(certs) > 1:
            reasons.append(f"{serial}: {len(certs)} certificates labelled '{args.label}' - ambiguous")
            continue
        cert = x509.load_der_x509_certificate(certs[0])
        match = [k for k in keys if k[2] == find_key.cert_key(cert)]
        if not match:
            reasons.append(f"{serial}: certificate '{args.label}' found, but its key is not on this card")
            continue
        out_dir = os.path.dirname(os.path.abspath(args.out))
        os.makedirs(out_dir, exist_ok=True)
        open(args.out, "w").write(cert.public_bytes(serialization.Encoding.PEM).decode())
        cns = cert.subject.get_attributes_for_oid(x509.NameOID.COMMON_NAME)
        values = (("CARD_TOKEN", info.label.strip()), ("CARD_SERIAL", serial),
                  ("CARD_KEY_LABEL", match[0][0]), ("CARD_KEY_ID", match[0][1]),
                  ("CERT_SUBJECT", cns[0].value if cns else cert.subject.rfc4514_string()),
                  ("CERT_SHA256", cert.fingerprint(hashes.SHA256()).hex(":").upper()))
        for k, v in values:
            print(f"{k}={shlex.quote(v)}")
        return
    err("; ".join(reasons), 1)


if __name__ == "__main__":
    main()
