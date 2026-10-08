#!/usr/bin/env python3
"""Find the inserted card that holds the private key for a certificate.

Compares the public keys stored on every inserted card with the public key in
CERT - no PIN needed, nothing is changed. A match identifies the card and the
key by what they are, not by a serial number: a backup card with the same
imported key matches too, a wrong card never does.

On a match prints shell assignments and exits 0:
    CARD_TOKEN='<token label>'  CARD_SERIAL='<serial>'
    CARD_KEY_LABEL='<key label>'  CARD_KEY_ID='<hex id>'
Exit 1: no inserted card holds the key (stderr names what is in the reader).
Exit 2: no card inserted, or the certificate cannot be read.

Usage (from the repository root, after setting up card-tools/.venv):
    card-tools/.venv/bin/python card-tools/card-find-key.py CERT.pem
    eval "$(card-tools/.venv/bin/python card-tools/card-find-key.py CERT.pem)"

RSA and EC (P-256) keys. The PKCS#11 module defaults to $PKCS11_MODULE, else
SAC (/usr/lib/libeTPkcs11.so).
"""
import argparse
import os
import shlex
import sys

import PyKCS11
from cryptography import x509
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec, rsa

DEFAULT_MODULE = "/usr/lib/libeTPkcs11.so"


def load_cert(path):
    data = open(path, "rb").read()
    try:
        return x509.load_pem_x509_certificate(data)
    except ValueError:
        return x509.load_der_x509_certificate(data)


def text(value):
    if isinstance(value, (bytes, bytearray, list, tuple)):
        value = bytes(value).decode("utf-8", "replace")
    return (value or "").strip("\x00 ")


def card_public_keys(session):
    """(label, id hex, matcher data) for every public key object on the card."""
    out = []
    for obj in session.findObjects([(PyKCS11.CKA_CLASS, PyKCS11.CKO_PUBLIC_KEY)]):
        key_type, label = session.getAttributeValue(obj, [PyKCS11.CKA_KEY_TYPE, PyKCS11.CKA_LABEL])
        key_id = session.getAttributeValue(obj, [PyKCS11.CKA_ID], allAsBinary=True)[0]
        key_id = bytes(key_id).hex() if key_id else ""
        if key_type == PyKCS11.CKK_RSA:
            n, e = session.getAttributeValue(obj, [PyKCS11.CKA_MODULUS, PyKCS11.CKA_PUBLIC_EXPONENT], allAsBinary=True)
            data = ("rsa", int.from_bytes(bytes(n), "big"), int.from_bytes(bytes(e), "big"))
        elif key_type == PyKCS11.CKK_EC:
            point = bytes(session.getAttributeValue(obj, [PyKCS11.CKA_EC_POINT], allAsBinary=True)[0])
            # CKA_EC_POINT is the X9.62 point, usually wrapped in a DER OCTET STRING
            if point[:1] == b"\x04" and len(point) > 2 and point[1] == len(point) - 2:
                point = point[2:]
            elif point[:1] == b"\x04" and point[1:2] == b"\x81":
                point = point[3:]
            data = ("ec", point)
        else:
            continue
        out.append((text(label), key_id, data))
    return out


def cert_key(cert):
    pub = cert.public_key()
    if isinstance(pub, rsa.RSAPublicKey):
        nums = pub.public_numbers()
        return ("rsa", nums.n, nums.e)
    if isinstance(pub, ec.EllipticCurvePublicKey):
        return ("ec", pub.public_bytes(serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint))
    sys.exit("✗ unsupported key type in the certificate (RSA or EC only)")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cert", help="certificate (PEM or DER) whose private key is wanted")
    ap.add_argument("--module", default=os.environ.get("PKCS11_MODULE", DEFAULT_MODULE),
                    help="PKCS#11 module (default: $PKCS11_MODULE or SAC)")
    args = ap.parse_args()

    try:
        want = cert_key(load_cert(args.cert))
    except (OSError, ValueError) as e:
        print(f"✗ cannot read certificate {args.cert}: {e}", file=sys.stderr)
        sys.exit(2)

    lib = PyKCS11.PyKCS11Lib()
    try:
        lib.load(args.module)
        slots = lib.getSlotList(tokenPresent=True)
    except PyKCS11.PyKCS11Error as e:
        print(f"✗ PKCS#11 module {args.module}: {e}", file=sys.stderr)
        sys.exit(2)
    if not slots:
        print("✗ no card in the reader", file=sys.stderr)
        sys.exit(2)

    seen = []
    for slot in slots:
        info = lib.getTokenInfo(slot)
        session = lib.openSession(slot)
        try:
            keys = card_public_keys(session)
        finally:
            session.closeSession()
        for label, key_id, data in keys:
            if data == want:
                for name, value in (("CARD_TOKEN", info.label.strip()), ("CARD_SERIAL", info.serialNumber.strip()),
                                    ("CARD_KEY_LABEL", label), ("CARD_KEY_ID", key_id)):
                    print(f"{name}={shlex.quote(value)}")
                return
        seen.append(f"{info.serialNumber.strip()} (keys: {', '.join(k[0] or k[1] for k in keys) or 'none'})")
    print(f"✗ no inserted card holds the key for {args.cert} - in the reader: {'; '.join(seen)}", file=sys.stderr)
    sys.exit(1)


if __name__ == "__main__":
    main()
