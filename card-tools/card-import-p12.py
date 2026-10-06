#!/usr/bin/env python3
"""Load a private key and its certificate from a PKCS#12 file onto a card.

The key is stored as sensitive and not extractable; the public key and the
certificate are stored next to it under the same label and CKA_ID. (SAC
gives the key the usages decrypt, sign and unwrap, like a key generated on
the card.) One test signature, checked against the
certificate, proves the imported key works.

Typical uses:
  - put a key made on an offline machine onto a card - and the same file
    onto a second card, so the key exists twice (backup card)
  - restore a backup onto a replacement card

Tested with a Thales IDPrime 940 + SAC: RSA-2048 and RSA-4096 keys import;
EC keys are refused by the card (generate them on the card instead).

Safety:
  - --dry-run reads the file and the card and stops before logging in
  - refuses a label or ID that is already used on the card
  - shows what will be stored and asks before writing
  - if any step fails, the objects created so far are removed again
  - the PIN and the file passphrase come from hidden prompts (or the
    CARD_PIN / P12_PASSPHRASE environment variables - training cards only)

Usage (from the repository root, after setting up card-tools/.venv):
    card-tools/.venv/bin/python card-tools/card-import-p12.py key.p12 --dry-run
    card-tools/.venv/bin/python card-tools/card-import-p12.py key.p12 --label my-key

The PKCS#11 module defaults to $PKCS11_MODULE, else SAC (/usr/lib/libeTPkcs11.so).
The PKCS#12 file is left untouched - keep or destroy it as your process requires.
"""
import argparse
import getpass
import os
import re
import sys

import PyKCS11
from cryptography import x509
from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, padding, rsa, utils
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.x509.oid import NameOID

DEFAULT_MODULE = "/usr/lib/libeTPkcs11.so"
# DER of the named-curve OID, the CKA_EC_PARAMS value
CURVE_PARAMS = {
    "secp256r1": bytes.fromhex("06082a8648ce3d030107"),
    "secp384r1": bytes.fromhex("06052b81040022"),
    "secp521r1": bytes.fromhex("06052b81040023"),
}
CLASS_NAMES = {
    PyKCS11.CKO_PRIVATE_KEY: "private key",
    PyKCS11.CKO_PUBLIC_KEY: "public key",
    PyKCS11.CKO_CERTIFICATE: "certificate",
    PyKCS11.CKO_SECRET_KEY: "secret key",
    PyKCS11.CKO_DATA: "data",
}
# Used in pkcs11: URIs by mini-pki, so keep it to characters that need no escaping
LABEL_RE = re.compile(r"[A-Za-z0-9._-]{1,64}")


def fail(msg, code=1):
    print(f"✗ {msg}", file=sys.stderr)
    sys.exit(code)


def read_secret(prompt, env=None):
    value = os.environ.get(env) if env else None
    return value if value is not None else getpass.getpass(prompt)


def find_slot(lib):
    """The token named $CARD_TOKEN, or the only/first token present."""
    want = os.environ.get("CARD_TOKEN", "")
    for slot in lib.getSlotList(tokenPresent=True):
        if not want or lib.getTokenInfo(slot).label.strip() == want:
            return slot
    if want:
        fail(f"card '{want}' (CARD_TOKEN) not found")
    fail("no card found - is it inserted? (card-tools/card-status.sh)")


def load_p12(path):
    try:
        data = open(path, "rb").read()
    except OSError as e:
        fail(f"cannot read {path}: {e}")
    passphrase = read_secret(f"Passphrase of {os.path.basename(path)}: ", "P12_PASSPHRASE")
    try:
        key, cert, chain = pkcs12.load_key_and_certificates(
            data, passphrase.encode() if passphrase else None)
    except ValueError as e:
        fail(f"cannot open {path} - wrong passphrase or not a PKCS#12 file ({e})")
    if key is None or cert is None:
        fail(f"{path} must contain a private key and its certificate")
    if key.public_key().public_bytes(serialization.Encoding.DER,
                                     serialization.PublicFormat.SubjectPublicKeyInfo) != \
            cert.public_key().public_bytes(serialization.Encoding.DER,
                                           serialization.PublicFormat.SubjectPublicKeyInfo):
        fail(f"the private key in {path} does not belong to its certificate")
    if not isinstance(key, (rsa.RSAPrivateKey, ec.EllipticCurvePrivateKey)):
        fail(f"unsupported key type {type(key).__name__} - RSA and EC only")
    if isinstance(key, ec.EllipticCurvePrivateKey) and key.curve.name not in CURVE_PARAMS:
        fail(f"unsupported curve {key.curve.name}")
    friendly = None
    try:
        p12 = pkcs12.load_pkcs12(data, passphrase.encode() if passphrase else None)
        if p12.key and p12.cert and p12.cert.friendly_name:
            friendly = p12.cert.friendly_name.decode("utf-8", "replace")
    except (ValueError, AttributeError):
        pass
    return key, cert, chain or [], friendly


def key_description(key):
    if isinstance(key, rsa.RSAPrivateKey):
        return f"RSA-{key.key_size}"
    return {"secp256r1": "EC P-256", "secp384r1": "EC P-384", "secp521r1": "EC P-521"}[key.curve.name]


def default_label(cert, friendly):
    if friendly:
        name = friendly
    else:
        cns = cert.subject.get_attributes_for_oid(NameOID.COMMON_NAME)
        name = cns[0].value if cns else "imported-key"
    return re.sub(r"[^A-Za-z0-9._-]+", "-", name).strip("-")[:64] or "imported-key"


def card_objects(session):
    """(class name, label, ID hex) of every object visible in this session."""
    out = []
    for obj in session.findObjects():
        cls, label = session.getAttributeValue(obj, [PyKCS11.CKA_CLASS, PyKCS11.CKA_LABEL])
        obj_id = session.getAttributeValue(obj, [PyKCS11.CKA_ID], allAsBinary=True)[0]
        if isinstance(label, (bytes, bytearray, list, tuple)):
            label = bytes(label).decode("utf-8", "replace")
        out.append((CLASS_NAMES.get(cls, f"class {cls}"), (label or "").strip("\x00 "),
                    bytes(obj_id).hex() if obj_id else ""))
    return out


def next_free_id(objects):
    used = {o[2] for o in objects}
    for n in range(1, 256):
        if f"{n:02x}" not in used:
            return f"{n:02x}"
    fail("no free one-byte ID left - choose one with --id")


def check_free(objects, label, cka_id):
    for cls, obj_label, obj_id in objects:
        if obj_label == label:
            fail(f"the card already has a {cls} labelled '{label}' - choose another --label")
        if obj_id == cka_id:
            fail(f"the card already has a {cls} with ID {cka_id} ('{obj_label}') - choose another --id")


def show_card(info, objects, scope):
    print("=== Card ===")
    print(f"  label         {info.label.strip()}")
    print(f"  serial        {info.serialNumber.strip()}")
    print(f"  model         {info.manufacturerID.strip()} {info.model.strip()}")
    print(f"  objects       {len(objects)} {scope}")
    for cls, label, obj_id in objects:
        print(f"      ID {obj_id or '-':<6} {cls:<12} {label}")


def show_file(path, key, cert, chain):
    print(f"=== {os.path.basename(path)} ===")
    print(f"  key           {key_description(key)}")
    print(f"  subject       {cert.subject.rfc4514_string()}")
    print(f"  issuer        {cert.issuer.rfc4514_string()}")
    print(f"  valid         {cert.not_valid_before_utc:%Y-%m-%d} .. {cert.not_valid_after_utc:%Y-%m-%d}")
    print(f"  sha256        {cert.fingerprint(hashes.SHA256()).hex()}")
    if chain:
        print(f"  chain         {len(chain)} more certificate(s) in the file - not stored on the card")


def big(n):
    return list(n.to_bytes((n.bit_length() + 7) // 8, "big"))


def templates(key, cert, label, cka_id):
    common = [(PyKCS11.CKA_TOKEN, True), (PyKCS11.CKA_LABEL, label), (PyKCS11.CKA_ID, cka_id)]
    # SAC (IDPrime) gives every user PIN key "decrypt, sign, unwrap", as for
    # keys generated on the card: CKA_UNWRAP=FALSE is ignored, and a key with
    # CKA_DECRYPT=FALSE is refused with CKR_PIN_INCORRECT (no PIN try is used)
    priv = common + [(PyKCS11.CKA_CLASS, PyKCS11.CKO_PRIVATE_KEY), (PyKCS11.CKA_PRIVATE, True),
                     (PyKCS11.CKA_SENSITIVE, True), (PyKCS11.CKA_EXTRACTABLE, False),
                     (PyKCS11.CKA_SIGN, True)]
    pub = common + [(PyKCS11.CKA_CLASS, PyKCS11.CKO_PUBLIC_KEY), (PyKCS11.CKA_PRIVATE, False),
                    (PyKCS11.CKA_VERIFY, True)]
    if isinstance(key, rsa.RSAPrivateKey):
        n = key.private_numbers()
        public = [(PyKCS11.CKA_KEY_TYPE, PyKCS11.CKK_RSA),
                  (PyKCS11.CKA_MODULUS, big(n.public_numbers.n)),
                  (PyKCS11.CKA_PUBLIC_EXPONENT, big(n.public_numbers.e))]
        priv += public + [(PyKCS11.CKA_PRIVATE_EXPONENT, big(n.d)),
                          (PyKCS11.CKA_PRIME_1, big(n.p)), (PyKCS11.CKA_PRIME_2, big(n.q)),
                          (PyKCS11.CKA_EXPONENT_1, big(n.dmp1)),
                          (PyKCS11.CKA_EXPONENT_2, big(n.dmq1)),
                          (PyKCS11.CKA_COEFFICIENT, big(n.iqmp))]
        pub += public
    else:
        params = list(CURVE_PARAMS[key.curve.name])
        size = (key.curve.key_size + 7) // 8
        point = key.public_key().public_bytes(serialization.Encoding.X962,
                                              serialization.PublicFormat.UncompressedPoint)
        value = key.private_numbers().private_value.to_bytes(size, "big")
        priv += [(PyKCS11.CKA_KEY_TYPE, PyKCS11.CKK_EC), (PyKCS11.CKA_EC_PARAMS, params),
                 (PyKCS11.CKA_VALUE, list(value))]
        # CKA_EC_POINT is the X9.62 point wrapped in a DER OCTET STRING
        octet = [0x04, len(point)] if len(point) < 128 else [0x04, 0x81, len(point)]
        pub += [(PyKCS11.CKA_KEY_TYPE, PyKCS11.CKK_EC), (PyKCS11.CKA_EC_PARAMS, params),
                (PyKCS11.CKA_EC_POINT, octet + list(point))]
    crt = common + [(PyKCS11.CKA_CLASS, PyKCS11.CKO_CERTIFICATE),
                    (PyKCS11.CKA_CERTIFICATE_TYPE, PyKCS11.CKC_X_509),
                    (PyKCS11.CKA_PRIVATE, False),
                    (PyKCS11.CKA_SUBJECT, list(cert.subject.public_bytes())),
                    (PyKCS11.CKA_ISSUER, list(cert.issuer.public_bytes())),
                    (PyKCS11.CKA_VALUE, list(cert.public_bytes(serialization.Encoding.DER)))]
    return priv, pub, crt


def test_signature(session, priv_obj, cert):
    """Sign on the card, verify with the certificate's public key."""
    data = os.urandom(32)
    digest = hashes.Hash(hashes.SHA256())
    digest.update(data)
    h = digest.finalize()
    pub = cert.public_key()
    try:
        if isinstance(pub, rsa.RSAPublicKey):
            sig = bytes(session.sign(priv_obj, data, PyKCS11.Mechanism(PyKCS11.CKM_SHA256_RSA_PKCS)))
            pub.verify(sig, data, padding.PKCS1v15(), hashes.SHA256())
        else:
            # The card signs at most 36 bytes itself, so hash here and send the digest
            sig = bytes(session.sign(priv_obj, h, PyKCS11.Mechanism(PyKCS11.CKM_ECDSA)))
            half = len(sig) // 2
            der = utils.encode_dss_signature(int.from_bytes(sig[:half], "big"),
                                             int.from_bytes(sig[half:], "big"))
            pub.verify(der, h, ec.ECDSA(utils.Prehashed(hashes.SHA256())))
    except InvalidSignature:
        return False
    return True


def main():
    sys.stdout.reconfigure(line_buffering=True)
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("p12", help="PKCS#12 file (.p12 / .pfx) with a private key and its certificate")
    ap.add_argument("--label", help="label on the card (default: the file's friendly name or the CN)")
    ap.add_argument("--id", help="CKA_ID in hex, e.g. 02 (default: the lowest free one-byte ID)")
    ap.add_argument("--dry-run", action="store_true", help="show what would happen, change nothing")
    ap.add_argument("--yes", action="store_true", help="do not ask before writing to the card")
    ap.add_argument("--module", default=os.environ.get("PKCS11_MODULE", DEFAULT_MODULE),
                    help="PKCS#11 module (default: $PKCS11_MODULE or SAC)")
    args = ap.parse_args()

    key, cert, chain, friendly = load_p12(args.p12)
    label = args.label or default_label(cert, friendly)
    if not LABEL_RE.fullmatch(label):
        fail("the label may only contain letters, digits, '.', '_' and '-' (at most 64)", 2)
    if args.id is not None and not re.fullmatch(r"(?:[0-9a-fA-F]{2}){1,20}", args.id):
        fail("--id must be 1-20 bytes in hex, e.g. 02", 2)

    lib = PyKCS11.PyKCS11Lib()
    try:
        lib.load(args.module)
    except PyKCS11.PyKCS11Error as e:
        fail(f"cannot load {args.module}: {e}")
    slot = find_slot(lib)
    info = lib.getTokenInfo(slot)

    session = lib.openSession(slot, PyKCS11.CKF_SERIAL_SESSION | PyKCS11.CKF_RW_SESSION)
    try:
        if args.dry_run:
            objects = card_objects(session)
            show_card(info, objects, "public (private keys are listed after login only)")
        else:
            try:
                session.login(read_secret("User PIN: ", "CARD_PIN"))
            except PyKCS11.PyKCS11Error as e:
                fail(f"login failed: {e} - nothing was changed")
            objects = card_objects(session)
            show_card(info, objects, "(user PIN scope)")
        cka_id = (args.id or next_free_id(objects)).lower()
        check_free(objects, label, cka_id)
        print("")
        show_file(args.p12, key, cert, chain)
        print("")
        print(f"Will store on card {info.serialNumber.strip()} under label '{label}', ID {cka_id}:")
        print(f"  private key   {key_description(key)}, sensitive, not extractable")
        print("  public key    and certificate")

        if args.dry_run:
            print("\n--dry-run: stopping here, nothing was changed (no PIN used).")
            return
        if not args.yes:
            if input("\nWrite to the card? (y/N): ").strip().lower() not in ("y", "yes"):
                fail("aborted, nothing was changed", 3)

        priv_t, pub_t, crt_t = templates(key, cert, label, list(bytes.fromhex(cka_id)))
        created = []
        try:
            step = "private key"
            priv_obj = session.createObject(priv_t)
            created.append(priv_obj)
            print("  ✓ private key stored")
            step = "public key"
            created.append(session.createObject(pub_t))
            print("  ✓ public key stored")
            step = "certificate"
            created.append(session.createObject(crt_t))
            print("  ✓ certificate stored")
            step = "test signature"
            if not test_signature(session, priv_obj, cert):
                raise RuntimeError("the card's signature does not verify with the certificate")
            print("  ✓ test signature made on the card verifies with the certificate")
        except (PyKCS11.PyKCS11Error, RuntimeError) as e:
            for obj in reversed(created):
                try:
                    session.destroyObject(obj)
                except PyKCS11.PyKCS11Error:
                    pass
            hint = ""
            if step == "private key" and isinstance(key, ec.EllipticCurvePrivateKey):
                hint = ("\n  The card refused the EC key. IDPrime 940 cards do not import EC keys -"
                        "\n  generate EC keys on the card instead.")
            elif step == "private key" and "DEVICE_MEMORY" in str(e):
                hint = "\n  The card does not support this key size (IDPrime 940: RSA-2048 and RSA-4096)."
            fail(f"{step} failed: {e}\n  Removed the {len(created)} object(s) created so far "
                 f"- the card is as before.{hint}")
    finally:
        try:
            session.logout()
        except PyKCS11.PyKCS11Error:
            pass
        session.closeSession()

    print(f"\nDone. Key URI: pkcs11:object={label};type=private")
    print(f"The file {args.p12} is unchanged - keep or destroy it as your process requires.")


if __name__ == "__main__":
    main()
