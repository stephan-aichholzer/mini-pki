#!/usr/bin/env python3
"""Dump the content of a PKCS#11 token as a tree.

Objects are grouped by CKA_ID, so a private key, its public key and its
certificate show up together, the way the card pairs them.

Usage (from the repository root, after setting up card-tools/.venv):
    card-tools/.venv/bin/python card-tools/card-tree.py            # public objects, no PIN
    card-tools/.venv/bin/python card-tools/card-tree.py --login    # prompts for the user PIN
    card-tools/.venv/bin/python card-tools/card-tree.py --login --mechanisms

The PKCS#11 module defaults to $PKCS11_MODULE, else SAC (/usr/lib/libeTPkcs11.so).
"""
import argparse
import getpass
import hashlib
import os
import sys
from collections import OrderedDict

import PyKCS11
from PyKCS11.LowLevel import CK_UNAVAILABLE_INFORMATION
from cryptography import x509
from cryptography.x509.oid import ExtensionOID

DEFAULT_MODULE = "/usr/lib/libeTPkcs11.so"

EC_CURVES = {
    "06082a8648ce3d030107": "P-256",
    "06052b81040022": "P-384",
    "06052b81040023": "P-521",
    "06052b8104000a": "secp256k1",
}

CLASS_ORDER = {
    PyKCS11.CKO_PRIVATE_KEY: 0,
    PyKCS11.CKO_PUBLIC_KEY: 1,
    PyKCS11.CKO_CERTIFICATE: 2,
    PyKCS11.CKO_SECRET_KEY: 3,
    PyKCS11.CKO_DATA: 4,
}

USAGE_ATTRS = [
    (PyKCS11.CKA_SIGN, "sign"), (PyKCS11.CKA_VERIFY, "verify"),
    (PyKCS11.CKA_DECRYPT, "decrypt"), (PyKCS11.CKA_ENCRYPT, "encrypt"),
    (PyKCS11.CKA_UNWRAP, "unwrap"), (PyKCS11.CKA_WRAP, "wrap"),
    (PyKCS11.CKA_DERIVE, "derive"),
]

ACCESS_ATTRS = [
    (PyKCS11.CKA_PRIVATE, "private"),
    (PyKCS11.CKA_SENSITIVE, "sensitive"),
    (PyKCS11.CKA_ALWAYS_SENSITIVE, "always-sensitive"),
    (PyKCS11.CKA_EXTRACTABLE, "EXTRACTABLE"),
    (PyKCS11.CKA_NEVER_EXTRACTABLE, "never-extractable"),
    (PyKCS11.CKA_LOCAL, "generated-on-card"),
    (PyKCS11.CKA_ALWAYS_AUTHENTICATE, "PIN-per-use"),
    (PyKCS11.CKA_MODIFIABLE, "modifiable"),
]


class Style:
    def __init__(self, enabled):
        self.enabled = enabled

    def _c(self, code, text):
        return f"\033[{code}m{text}\033[0m" if self.enabled else text

    def bold(self, t): return self._c("1", t)
    def dim(self, t): return self._c("2", t)
    def green(self, t): return self._c("32", t)
    def yellow(self, t): return self._c("33", t)
    def red(self, t): return self._c("31", t)
    def cyan(self, t): return self._c("36", t)


class Tree:
    """Prints nested nodes with box-drawing branches."""

    def __init__(self):
        self.lines = []

    def render(self, node, prefix="", last=True, root=True):
        text, children = node
        if root:
            self.lines.append(text)
            child_prefix = ""
        else:
            self.lines.append(prefix + ("└── " if last else "├── ") + text)
            child_prefix = prefix + ("    " if last else "│   ")
        for i, child in enumerate(children):
            self.render(child, child_prefix, i == len(children) - 1, root=False)
        return self.lines


def node(text, children=None):
    return (text, children or [])


def attr(session, obj, attribute):
    """One attribute, or None if the token does not have/allow it."""
    try:
        value = session.getAttributeValue(obj, [attribute], allAsBinary=False)[0]
    except PyKCS11.PyKCS11Error:
        return None
    return value


def raw(session, obj, attribute):
    try:
        value = session.getAttributeValue(obj, [attribute], allAsBinary=True)[0]
    except PyKCS11.PyKCS11Error:
        return None
    return bytes(value) if value else None


def text(value):
    if value is None:
        return None
    if isinstance(value, (bytes, bytearray, list, tuple)):
        value = bytes(value).decode("utf-8", "replace")
    return value.strip("\x00 ")


def key_description(session, obj):
    key_type = attr(session, obj, PyKCS11.CKA_KEY_TYPE)
    if key_type == PyKCS11.CKK_RSA:
        modulus = raw(session, obj, PyKCS11.CKA_MODULUS)
        return f"RSA {len(modulus) * 8}" if modulus else "RSA"
    if key_type == PyKCS11.CKK_EC:
        params = raw(session, obj, PyKCS11.CKA_EC_PARAMS)
        curve = EC_CURVES.get(params.hex(), params.hex()) if params else "?"
        return f"EC {curve}"
    if key_type in (PyKCS11.CKK_AES, PyKCS11.CKK_DES3, PyKCS11.CKK_GENERIC_SECRET):
        length = attr(session, obj, PyKCS11.CKA_VALUE_LEN)
        name = PyKCS11.CKK[key_type].replace("CKK_", "")
        return f"{name} {length * 8}" if length else name
    return PyKCS11.CKK.get(key_type, f"key type {key_type}")


def flags_of(session, obj, table):
    return [name for a, name in table if attr(session, obj, a) is True]


def access_text(style, names):
    out = []
    for n in names:
        if n == "EXTRACTABLE":
            out.append(style.red("extractable"))
        elif n in ("never-extractable", "always-sensitive", "generated-on-card"):
            out.append(style.green(n))
        else:
            out.append(n)
    return ", ".join(out)


def certificate_children(style, der):
    try:
        cert = x509.load_der_x509_certificate(der)
    except ValueError as e:
        return [node(style.red(f"cannot parse certificate: {e}"))]
    children = [
        node(f"subject   {cert.subject.rfc4514_string()}"),
        node(f"issuer    {cert.issuer.rfc4514_string()}"),
        node(f"serial    {cert.serial_number:x}"),
        node(f"valid     {cert.not_valid_before_utc:%Y-%m-%d} .. {cert.not_valid_after_utc:%Y-%m-%d}"),
    ]
    try:
        bc = cert.extensions.get_extension_for_oid(ExtensionOID.BASIC_CONSTRAINTS).value
        children.append(node("CA        " + (style.yellow("yes") if bc.ca else "no")))
    except x509.ExtensionNotFound:
        pass
    if cert.subject == cert.issuer:
        children.append(node(style.dim("self-signed")))
    children.append(node(style.dim("sha256    " + hashlib.sha256(der).hexdigest())))
    return children


def object_node(style, session, obj):
    cls = attr(session, obj, PyKCS11.CKA_CLASS)
    label = text(attr(session, obj, PyKCS11.CKA_LABEL)) or ""
    label = f' "{label}"' if label else ""

    if cls in (PyKCS11.CKO_PRIVATE_KEY, PyKCS11.CKO_PUBLIC_KEY, PyKCS11.CKO_SECRET_KEY):
        kind = {PyKCS11.CKO_PRIVATE_KEY: "Private key",
                PyKCS11.CKO_PUBLIC_KEY: "Public key",
                PyKCS11.CKO_SECRET_KEY: "Secret key"}[cls]
        head = f"{style.bold(kind)}  {key_description(session, obj)}{label}"
        children = []
        usage = flags_of(session, obj, USAGE_ATTRS)
        if usage:
            children.append(node("usage     " + ", ".join(usage)))
        access = flags_of(session, obj, ACCESS_ATTRS)
        if access:
            children.append(node("access    " + access_text(style, access)))
        return node(head, children)

    if cls == PyKCS11.CKO_CERTIFICATE:
        head = f"{style.bold('Certificate')}  X.509{label}"
        der = raw(session, obj, PyKCS11.CKA_VALUE)
        return node(head, certificate_children(style, der) if der else [])

    if cls == PyKCS11.CKO_DATA:
        app = text(attr(session, obj, PyKCS11.CKA_APPLICATION))
        value = raw(session, obj, PyKCS11.CKA_VALUE)
        size = f"{len(value)} bytes" if value is not None else "not readable"
        head = f"{style.bold('Data')}{label}"
        return node(head, [node(f"application  {app or '-'}"), node(f"size         {size}")])

    name = PyKCS11.CKO.get(cls, f"class {cls}")
    return node(f"{style.bold(name)}{label}")


def number(value):
    """Token info counters are often CK_UNAVAILABLE_INFORMATION."""
    if value is None or value == CK_UNAVAILABLE_INFORMATION or value < 0:
        return None
    return value


def token_children(style, lib, slot, info):
    flags = info.flags2text()
    children = [
        node(f"manufacturer  {info.manufacturerID.strip()}"),
        node(f"model         {info.model.strip()}"),
        node(f"serial        {info.serialNumber.strip()}"),
        node(f"PIN length    {info.ulMinPinLen}..{info.ulMaxPinLen}"),
    ]

    pin_state = []
    warn = {
        "CKF_USER_PIN_TO_BE_CHANGED": "user PIN must be changed",
        "CKF_USER_PIN_COUNT_LOW": "user PIN: wrong tries made",
        "CKF_USER_PIN_FINAL_TRY": "user PIN: LAST TRY",
        "CKF_USER_PIN_LOCKED": "user PIN LOCKED",
        "CKF_SO_PIN_COUNT_LOW": "admin: wrong tries made",
        "CKF_SO_PIN_FINAL_TRY": "admin: LAST TRY",
        "CKF_SO_PIN_LOCKED": "admin LOCKED",
    }
    for flag, msg in warn.items():
        if flag in flags:
            pin_state.append(style.red(msg))
    children.append(node("PIN status    " + (", ".join(pin_state) or style.green("ok"))))

    mem = [(number(info.ulFreePublicMemory), number(info.ulTotalPublicMemory), "public"),
           (number(info.ulFreePrivateMemory), number(info.ulTotalPrivateMemory), "private")]
    mem_txt = [f"{name} {free}/{total} bytes free" for free, total, name in mem
               if free is not None and total is not None]
    if mem_txt:
        children.append(node("memory        " + ", ".join(mem_txt)))

    pretty = [f.replace("CKF_", "").lower() for f in flags]
    children.append(node(style.dim("flags         " + ", ".join(pretty))))
    return children


def mechanisms_node(style, lib, slot):
    items = []
    for mech in lib.getMechanismList(slot):
        try:
            mi = lib.getMechanismInfo(slot, mech)
            ops = [f.replace("CKF_", "").lower() for f in mi.flags2text()
                   if f not in ("CKF_HW", "CKF_EC_F_P", "CKF_EC_NAMEDCURVE",
                                "CKF_EC_UNCOMPRESS", "CKF_EC_OID")]
            size = f"{mi.ulMinKeySize}-{mi.ulMaxKeySize}"
            items.append(node(f"{mech:<28} {style.dim(size):<12} {', '.join(ops)}"))
        except PyKCS11.PyKCS11Error:
            items.append(node(str(mech)))
    return node(style.bold(f"Mechanisms ({len(items)})"), items)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--module", default=os.environ.get("PKCS11_MODULE", DEFAULT_MODULE),
                    help="PKCS#11 module (default: SAC; try opensc-pkcs11.so to compare)")
    ap.add_argument("--login", action="store_true",
                    help="log in to show private objects (PIN from CARD_PIN or prompt). "
                         "Only ONE slot is logged in - see --slot")
    ap.add_argument("--slot", type=int,
                    help="slot id to show and log in to (default: all slots shown, "
                         "login only on the first). A card can expose several PINs as "
                         "separate slots; a wrong PIN costs a try on each one")
    ap.add_argument("--mechanisms", action="store_true", help="also list supported mechanisms")
    ap.add_argument("--no-color", action="store_true", help="plain output")
    args = ap.parse_args()
    style = Style(sys.stdout.isatty() and not args.no_color)

    lib = PyKCS11.PyKCS11Lib()
    lib.load(args.module)
    lib_info = lib.getInfo()
    root = node(f"{style.bold('PKCS#11 module')} {args.module}  "
                + style.dim(f"({lib_info.manufacturerID.strip()}, "
                            f"{lib_info.libraryDescription.strip()} "
                            f"{lib_info.libraryVersion[0]}.{lib_info.libraryVersion[1]})"))

    slots = lib.getSlotList(tokenPresent=True)
    if args.slot is not None:
        if args.slot not in slots:
            sys.exit(f"slot {args.slot} has no token (slots with a token: {list(slots)})")
        slots = [args.slot]
    login_slot = slots[0] if slots else None
    if not slots:
        root[1].append(node(style.red("no token present")))

    pin = None
    if args.login:
        pin = os.environ.get("CARD_PIN") or getpass.getpass("User PIN: ")

    for slot in slots:
        slot_info = lib.getSlotInfo(slot)
        info = lib.getTokenInfo(slot)
        token = node(f"{style.cyan('Token')} {style.bold(info.label.strip())}",
                     token_children(style, lib, slot, info))
        root[1].append(node(f"Slot {slot}  {slot_info.slotDescription.strip()}", [token]))

        session = lib.openSession(slot)
        logged_in = False
        if pin and slot == login_slot:
            try:
                session.login(pin)
                logged_in = True
            except PyKCS11.PyKCS11Error as e:
                token[1].append(node(style.red(f"login failed: {e}")))
        try:
            groups = OrderedDict()
            for obj in session.findObjects():
                obj_id = raw(session, obj, PyKCS11.CKA_ID)
                groups.setdefault(obj_id.hex() if obj_id else None, []).append(obj)

            obj_count = sum(len(v) for v in groups.values())
            if logged_in:
                scope = "all objects"
            elif pin:
                scope = f"public objects - not logged in (login only on slot {login_slot})"
            else:
                scope = "public objects - use --login for private keys"
            objects = node(style.bold(f"Objects ({obj_count})") + style.dim(f"  {scope}"))
            for obj_id in sorted(groups, key=lambda k: (k is None, k or "")):
                members = sorted(groups[obj_id],
                                 key=lambda o: CLASS_ORDER.get(attr(session, o, PyKCS11.CKA_CLASS), 9))
                title = f"ID {obj_id}" if obj_id else "(no ID)"
                objects[1].append(node(style.yellow(title),
                                       [object_node(style, session, o) for o in members]))
            if not groups:
                objects[1].append(node(style.dim("empty")))
            token[1].append(objects)

            if args.mechanisms:
                token[1].append(mechanisms_node(style, lib, slot))
        finally:
            if logged_in:
                session.logout()
            session.closeSession()

    print("\n".join(Tree().render(root)))


if __name__ == "__main__":
    main()
