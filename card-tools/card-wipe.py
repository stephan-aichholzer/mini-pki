#!/usr/bin/env python3
"""Erase a PKCS#11 smartcard (tested with Thales IDPrime 940 + SAC).

Two modes:

  --objects   delete every key, certificate and data object visible with the
              user PIN. The admin key is not used. Objects protected by the
              IDPrime Digital Signature PIN are not visible and stay.

  --factory   re-initialize the token with the admin key (C_InitToken) and set
              a new user PIN (C_InitPIN). Everything under the user PIN is gone.
              In SAC's default "unlinked" mode the Digital Signature PIN/PUK
              are left as they are. The admin key itself is never changed.

Safety:
  - the card is shown first; nothing happens before you type its serial number
  - --dry-run stops before any change
  - --factory refuses to run if the card reports earlier wrong admin key
    attempts: on an IDPrime 940 a LOCKED ADMIN KEY MAKES THE CARD UNUSABLE
    FOREVER, so the admin key is checked locally and tried exactly once
  - PINs and the admin key are read from hidden prompts, never from argv
    (except --new-pin / --factory-admin-key for training cards)

Usage (from the repository root, after setting up card-tools/.venv):
    card-tools/.venv/bin/python card-tools/card-wipe.py --objects --dry-run
    card-tools/.venv/bin/python card-tools/card-wipe.py --factory

The PKCS#11 module defaults to $PKCS11_MODULE, else SAC (/usr/lib/libeTPkcs11.so).
"""
import argparse
import getpass
import os
import re
import sys

import PyKCS11

DEFAULT_MODULE = "/usr/lib/libeTPkcs11.so"
FACTORY_ADMIN_KEY = "0" * 48
MANIFEST = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "ca-card.manifest")

CLASS_NAMES = {
    PyKCS11.CKO_PRIVATE_KEY: "private key",
    PyKCS11.CKO_PUBLIC_KEY: "public key",
    PyKCS11.CKO_CERTIFICATE: "certificate",
    PyKCS11.CKO_SECRET_KEY: "secret key",
    PyKCS11.CKO_DATA: "data",
}
SO_DANGER_FLAGS = ("CKF_SO_PIN_COUNT_LOW", "CKF_SO_PIN_FINAL_TRY", "CKF_SO_PIN_LOCKED")


def fail(msg, code=1):
    print(f"✗ {msg}", file=sys.stderr)
    sys.exit(code)


def find_slot(lib):
    """The token named $CARD_TOKEN, or the only/first token present."""
    want = os.environ.get("CARD_TOKEN", "")
    slots = lib.getSlotList(tokenPresent=True)
    for slot in slots:
        if not want or lib.getTokenInfo(slot).label.strip() == want:
            return slot
    if want:
        fail(f"card '{want}' (CARD_TOKEN) not found")
    fail("no card found - is it inserted? (card-tools/card-status.sh)")


def describe_objects(session):
    out = []
    for obj in session.findObjects():
        cls, label = session.getAttributeValue(obj, [PyKCS11.CKA_CLASS, PyKCS11.CKA_LABEL])
        obj_id = session.getAttributeValue(obj, [PyKCS11.CKA_ID], allAsBinary=True)[0]
        if isinstance(label, (bytes, bytearray, list, tuple)):
            label = bytes(label).decode("utf-8", "replace")
        label = (label or "").strip("\x00 ")
        obj_id = bytes(obj_id).hex() if obj_id else "-"
        out.append((obj, CLASS_NAMES.get(cls, f"class {cls}"), label, obj_id))
    return out


def manifest_serial():
    try:
        with open(MANIFEST) as f:
            for line in f:
                if line.startswith("token_serial="):
                    return line.split("=", 1)[1].strip()
    except OSError:
        pass
    return None


def show_card(info, objects, scope):
    print("=== Card ===")
    print(f"  label         {info.label.strip()}")
    print(f"  serial        {info.serialNumber.strip()}")
    print(f"  model         {info.manufacturerID.strip()} {info.model.strip()}")
    print(f"  flags         {', '.join(f.replace('CKF_', '').lower() for f in info.flags2text())}")
    print(f"  objects       {len(objects)} {scope}")
    for _, cls, label, obj_id in objects:
        print(f"      ID {obj_id:<6} {cls:<12} {label}")


def warn_if_ca_card(serial):
    ca_serial = manifest_serial()
    if ca_serial and ca_serial == serial:
        print("")
        print("  !!! This card holds the CA key of this mini-pki directory (ca-card.manifest).")
        print("  !!! After erasing it the CA can never sign again - not even to revoke")
        print("  !!! certificates. There is no backup of a key that was generated on the card.")


def confirm(serial, action):
    print("")
    print(f"This will {action}. It cannot be undone.")
    typed = input(f"Type the card serial ({serial}) to continue, anything else aborts: ").strip()
    if typed != serial:
        fail("serial does not match - aborted, nothing was changed", 3)


def read_secret(prompt, env=None):
    value = os.environ.get(env) if env else None
    return value or getpass.getpass(prompt)


def new_user_pin(args, info):
    if args.new_pin:
        pin = args.new_pin
    else:
        pin = getpass.getpass("New user PIN: ")
        if pin != getpass.getpass("Repeat new user PIN: "):
            fail("PINs do not match - aborted, nothing was changed", 3)
    if not info.ulMinPinLen <= len(pin) <= info.ulMaxPinLen:
        fail(f"user PIN must have {info.ulMinPinLen}-{info.ulMaxPinLen} characters - nothing was changed", 3)
    return pin


def wipe_objects(lib, slot, info, args):
    pin = read_secret("User PIN: ", "CARD_PIN")
    session = lib.openSession(slot, PyKCS11.CKF_SERIAL_SESSION | PyKCS11.CKF_RW_SESSION)
    try:
        session.login(pin)
    except PyKCS11.PyKCS11Error as e:
        fail(f"login failed: {e} - nothing was changed")
    try:
        objects = describe_objects(session)
        show_card(info, objects, "(user PIN scope)")
        warn_if_ca_card(info.serialNumber.strip())
        if not objects:
            print("\nNothing to delete.")
            return
        if args.dry_run:
            print("\n--dry-run: stopping here, nothing was changed.")
            return
        confirm(info.serialNumber.strip(), f"delete all {len(objects)} objects listed above")
        # Certificates and public keys first, private keys last
        order = {"certificate": 0, "data": 1, "public key": 2, "secret key": 3, "private key": 4}
        deleted = 0
        for obj, cls, label, obj_id in sorted(objects, key=lambda o: order.get(o[1], 9)):
            try:
                session.destroyObject(obj)
                deleted += 1
                print(f"  ✓ deleted {cls} ID {obj_id} {label}")
            except PyKCS11.PyKCS11Error as e:
                print(f"  ✗ {cls} ID {obj_id} {label}: {e}")
        print(f"\n{deleted} of {len(objects)} objects deleted.")
    finally:
        session.logout()
        session.closeSession()


def wipe_factory(lib, slot, info, args):
    serial = info.serialNumber.strip()
    flags = info.flags2text()

    session = lib.openSession(slot)
    objects = describe_objects(session)  # public objects, no login
    session.closeSession()
    show_card(info, objects, "public (private keys are listed after login only)")
    warn_if_ca_card(serial)

    danger = [f for f in flags if f in SO_DANGER_FLAGS]
    if danger:
        fail("the card reports earlier wrong admin key attempts ("
             + ", ".join(f.replace("CKF_", "").lower() for f in danger) + ").\n"
             "  Refusing: another wrong attempt could lock the admin key, which makes\n"
             "  an IDPrime 940 permanently unusable.")

    if args.factory_admin_key:
        admin_key = FACTORY_ADMIN_KEY
        print("\nUsing the factory admin key (48 zeros).")
    else:
        admin_key = getpass.getpass("Admin key (48 hex characters): ").strip()
    if not re.fullmatch(r"[0-9a-fA-F]{48}", admin_key):
        fail("the admin key must be exactly 48 hex characters - not sent to the card", 3)

    label = args.label or info.label.strip()
    if len(label) > 32:
        fail("the token label may have at most 32 characters", 3)
    pin = new_user_pin(args, info)

    if args.dry_run:
        print(f"\n--dry-run: would re-initialize card {serial} as '{label}' and set a new user PIN.")
        print("Stopping here, nothing was sent to the card.")
        return
    confirm(serial, f"re-initialize card {serial} with the admin key and erase all its user keys")

    # Exactly one admin authentication; never retried.
    try:
        lib.initToken(slot, admin_key, label)
    except PyKCS11.PyKCS11Error as e:
        after = ", ".join(f.replace("CKF_", "").lower() for f in lib.getTokenInfo(slot).flags2text())
        fail(f"C_InitToken failed: {e}\n  Card flags now: {after}\n"
             "  Do NOT retry with a guessed admin key.")
    print(f"  ✓ token re-initialized as '{label}'")

    session = lib.openSession(slot, PyKCS11.CKF_SERIAL_SESSION | PyKCS11.CKF_RW_SESSION)
    try:
        session.login(admin_key, user_type=PyKCS11.CKU_SO)
        session.initPin(pin)
        print("  ✓ new user PIN set")
    except PyKCS11.PyKCS11Error as e:
        fail(f"setting the user PIN failed: {e}\n"
             "  The card is erased but has no usable user PIN yet. Set one with:\n"
             f"  pkcs11-tool --module {args.module} --login --login-type so --init-pin")
    finally:
        try:
            session.logout()
        except PyKCS11.PyKCS11Error:
            pass
        session.closeSession()

    info = lib.getTokenInfo(slot)
    print(f"\nDone. Card flags: {', '.join(f.replace('CKF_', '').lower() for f in info.flags2text())}")
    if os.path.exists(MANIFEST) and manifest_serial() == serial:
        print("ca-card.manifest still names this card, but its CA key is gone - "
              "remove the manifest or create a new CA.")


def main():
    # Keep stdout and stderr in the order things happen (prompts, errors)
    sys.stdout.reconfigure(line_buffering=True)
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--objects", action="store_true", help="delete all objects visible with the user PIN")
    mode.add_argument("--factory", action="store_true", help="re-initialize the token with the admin key")
    ap.add_argument("--dry-run", action="store_true", help="show what would happen, change nothing")
    ap.add_argument("--module", default=os.environ.get("PKCS11_MODULE", DEFAULT_MODULE),
                    help="PKCS#11 module (default: $PKCS11_MODULE or SAC)")
    ap.add_argument("--label", help="--factory: new token label (default: keep the current one)")
    ap.add_argument("--new-pin", help="--factory: new user PIN (default: prompted) - training cards only")
    ap.add_argument("--factory-admin-key", action="store_true",
                    help="--factory: use the factory admin key (48 zeros) instead of prompting")
    args = ap.parse_args()

    lib = PyKCS11.PyKCS11Lib()
    try:
        lib.load(args.module)
    except PyKCS11.PyKCS11Error as e:
        fail(f"cannot load {args.module}: {e}")
    slot = find_slot(lib)
    info = lib.getTokenInfo(slot)

    if args.objects:
        wipe_objects(lib, slot, info, args)
    else:
        wipe_factory(lib, slot, info, args)


if __name__ == "__main__":
    main()
