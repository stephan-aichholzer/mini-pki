#!/usr/bin/env python3
"""Find the CA on the inserted card and verify its chain against a trusted root.

The card must hold a CA key together with its certificate, and the
certificates above it (see card-store-cert.py). This tool reads them from the
card - no PIN, nothing changed - writes them to --out, and verifies the chain
against the root the caller trusts, given from outside: either --root FILE, or
--root-sha256 FINGERPRINT - then the root certificate stored on the card is
used only if its SHA-256 fingerprint matches. --pathlen N demands the CA's path length constraint, e.g. 0 for
a CA that may only sign end entities (a line CA, not an issuing CA).
--leaf looks for a key that is NOT a CA instead (e.g. a code signing key),
with the same chain check; --eku codeSigning additionally demands that
extended key usage in its certificate.

On success prints shell assignments and exits 0:
    CARD_TOKEN, CARD_SERIAL, CARD_KEY_LABEL, CARD_KEY_ID  - card and key
    CA_CERT   - OUT/ca-cert.pem  (the CA whose key is on the card)
    CA_CHAIN  - OUT/ca-chain.pem (CA_CERT, its issuers from the card, the root)
    ROOT_CERT - the trusted root certificate (--root, or OUT/root.pem)
    CA_SUBJECT, CHAIN_SUBJECTS, ROOT_SHA256
Exit 1: the inserted card holds no such CA (stderr says why).
Exit 2: no card inserted, or --root cannot be read.

Usage (from the repository root, after setting up card-tools/.venv):
    card-tools/.venv/bin/python card-tools/card-find-ca.py --root ROOT.pem --pathlen 0 --out DIR
    card-tools/.venv/bin/python card-tools/card-find-ca.py --root-sha256 7D:3F:...:58:99 --pathlen 0 --out DIR

The PKCS#11 module defaults to $PKCS11_MODULE, else SAC (/usr/lib/libeTPkcs11.so).
"""
import argparse
import os
import shlex
import subprocess
import sys

import PyKCS11
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from importlib import import_module  # noqa: E402

find_key = import_module("card-find-key")   # card_public_keys(), cert_key()

DEFAULT_MODULE = "/usr/lib/libeTPkcs11.so"


def err(msg, code):
    print(f"✗ {msg}", file=sys.stderr)
    sys.exit(code)


def pem(cert):
    return cert.public_bytes(serialization.Encoding.PEM).decode()


def name(cert):
    cns = cert.subject.get_attributes_for_oid(x509.NameOID.COMMON_NAME)
    return cns[0].value if cns else cert.subject.rfc4514_string()


def card_certs(session):
    out = []
    for obj in session.findObjects([(PyKCS11.CKA_CLASS, PyKCS11.CKO_CERTIFICATE)]):
        value = bytes(session.getAttributeValue(obj, [PyKCS11.CKA_VALUE], allAsBinary=True)[0])
        try:
            out.append(x509.load_der_x509_certificate(value))
        except ValueError:
            pass
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    trust = ap.add_mutually_exclusive_group(required=True)
    trust.add_argument("--root", help="the trusted root certificate (PEM) - from outside, not from the card")
    trust.add_argument("--root-sha256", help="SHA-256 fingerprint of the trusted root; the card's copy is used only if it matches")
    ap.add_argument("--pathlen", type=int, help="required path length constraint of the CA, e.g. 0")
    ap.add_argument("--leaf", action="store_true", help="look for a non-CA key (e.g. code signing) instead of a CA")
    ap.add_argument("--eku", choices=["codeSigning", "serverAuth", "clientAuth"],
                    help="required extended key usage of the certificate, e.g. codeSigning")
    ap.add_argument("--out", required=True, help="folder for ca-cert.pem and ca-chain.pem")
    ap.add_argument("--module", default=os.environ.get("PKCS11_MODULE", DEFAULT_MODULE),
                    help="PKCS#11 module (default: $PKCS11_MODULE or SAC)")
    args = ap.parse_args()

    root = None
    if args.root:
        try:
            root = find_key.load_cert(args.root)
        except (OSError, ValueError) as e:
            err(f"cannot read --root {args.root}: {e}", 2)
    else:
        pin = args.root_sha256.replace(":", "").replace(" ", "").lower()
        if len(pin) != 64 or any(c not in "0123456789abcdef" for c in pin):
            err("--root-sha256 must be 64 hex digits (colons allowed)", 2)

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
        session = lib.openSession(slot)
        try:
            keys = find_key.card_public_keys(session)
            certs = card_certs(session)
        finally:
            session.closeSession()
        by_subject = {c.subject: c for c in certs}
        anchor = root
        if anchor is None:     # pinned: the card's own root copy, only if its fingerprint matches
            pinned = [c for c in certs if c.fingerprint(hashes.SHA256()).hex() == pin and c.subject == c.issuer]
            if not pinned:
                reasons.append(f"{serial}: no root certificate with the pinned fingerprint on this card")
                continue
            anchor = pinned[0]
            os.makedirs(args.out, exist_ok=True)
            root_file = os.path.join(args.out, "root.pem")
            open(root_file, "w").write(pem(anchor))
        else:
            root_file = args.root
        for cert in certs:
            match = [k for k in keys if k[2] == find_key.cert_key(cert)]
            if not match:
                continue                      # a chain certificate, not this card's key
            try:
                bc = cert.extensions.get_extension_for_class(x509.BasicConstraints).value
            except x509.ExtensionNotFound:
                bc = None
            if args.leaf:
                if bc and bc.ca:
                    reasons.append(f"{serial}: '{name(cert)}' is a CA, not the key looked for")
                    continue
            elif not bc or not bc.ca:
                reasons.append(f"{serial}: '{name(cert)}' is not a CA")
                continue
            elif args.pathlen is not None and bc.path_length != args.pathlen:
                reasons.append(f"{serial}: '{name(cert)}' has path length {bc.path_length}, needed {args.pathlen}")
                continue
            if args.eku:
                wanted = {"codeSigning": x509.ExtendedKeyUsageOID.CODE_SIGNING,
                          "serverAuth": x509.ExtendedKeyUsageOID.SERVER_AUTH,
                          "clientAuth": x509.ExtendedKeyUsageOID.CLIENT_AUTH}[args.eku]
                try:
                    ekus = cert.extensions.get_extension_for_class(x509.ExtendedKeyUsage).value
                except x509.ExtensionNotFound:
                    ekus = []
                if wanted not in ekus:
                    reasons.append(f"{serial}: '{name(cert)}' is not a {args.eku} certificate")
                    continue
            # chain from the card: follow the issuers, stop below the root
            chain, cur = [cert], cert
            while cur.issuer != cur.subject and cur.issuer in by_subject and cur.issuer != anchor.subject:
                cur = by_subject[cur.issuer]
                chain.append(cur)
            os.makedirs(args.out, exist_ok=True)
            ca_file = os.path.join(args.out, "ca-cert.pem")
            chain_file = os.path.join(args.out, "ca-chain.pem")
            open(ca_file, "w").write(pem(cert))
            open(chain_file, "w").write("".join(pem(c) for c in chain) + pem(anchor))
            # verify against the root from outside; the card's own root copy is not trusted
            untrusted = os.path.join(args.out, ".untrusted.pem")
            open(untrusted, "w").write("".join(pem(c) for c in chain[1:]) or pem(cert))
            check = subprocess.run(["openssl", "verify", "-CAfile", root_file, "-untrusted", untrusted, ca_file],
                                   capture_output=True, text=True)
            os.remove(untrusted)
            if check.returncode != 0:
                os.remove(ca_file)
                os.remove(chain_file)
                reasons.append(f"{serial}: '{name(cert)}' does not chain to the trusted root: "
                               f"{(check.stderr or check.stdout).strip().splitlines()[-1]}")
                continue
            label, key_id = match[0][0], match[0][1]
            values = (("CARD_TOKEN", info.label.strip()), ("CARD_SERIAL", serial),
                      ("CARD_KEY_LABEL", label), ("CARD_KEY_ID", key_id),
                      ("CA_CERT", ca_file), ("CA_CHAIN", chain_file), ("CA_SUBJECT", name(cert)),
                      ("CHAIN_SUBJECTS", " -> ".join([name(c) for c in chain] + [name(anchor)])),
                      ("ROOT_CERT", root_file),
                      ("ROOT_SHA256", anchor.fingerprint(hashes.SHA256()).hex(":").upper()))
            for k, v in values:
                print(f"{k}={shlex.quote(v)}")
            return
        if not any(k for k in keys if any(k[2] == find_key.cert_key(c) for c in certs)):
            reasons.append(f"{serial}: no key with its certificate on this card")
    err("; ".join(reasons) or "no suitable CA on the inserted card", 1)


if __name__ == "__main__":
    main()
