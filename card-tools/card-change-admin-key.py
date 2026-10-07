#!/usr/bin/env python3
"""Change the admin key (PKCS#11 SO PIN) of a smartcard (tested with Thales IDPrime + SAC).

The factory admin key of an IDPrime card is public (48 hex zeros). Whoever
knows it can reset the user PIN and re-initialize the card, so a card that
holds real keys needs its own admin key. Keys and PINs on the card are not
touched.

Safety:
  - the card is shown first; nothing happens before you type its serial number
  - --dry-run stops before anything is sent to the card
  - refuses if the card reports earlier wrong admin key attempts: on an
    IDPrime 940 a LOCKED ADMIN KEY MAKES THE CARD UNUSABLE FOREVER, so both
    keys are checked locally and the current one is tried exactly once
  - the new key is entered twice, or generated (--generate) and shown before
    the change, which only happens after you confirm it is recorded
  - keys are read from hidden prompts, never from argv
    (except --factory-admin-key for the current key of a new card)

Record the new admin key before you continue: without it the user PIN can
no longer be unblocked and the card no longer be re-initialized.

Usage (from the repository root, after setting up card-tools/.venv):
    card-tools/.venv/bin/python card-tools/card-change-admin-key.py --factory-admin-key --generate --dry-run
    card-tools/.venv/bin/python card-tools/card-change-admin-key.py --factory-admin-key --generate

The PKCS#11 module defaults to $PKCS11_MODULE, else SAC (/usr/lib/libeTPkcs11.so).
"""
import argparse
import getpass
import os
import re
import secrets
import sys

import PyKCS11

DEFAULT_MODULE = "/usr/lib/libeTPkcs11.so"
FACTORY_ADMIN_KEY = "0" * 48
SO_DANGER_FLAGS = ("CKF_SO_PIN_COUNT_LOW", "CKF_SO_PIN_FINAL_TRY", "CKF_SO_PIN_LOCKED")


def fail(msg, code=1):
    print(f"✗ {msg}", file=sys.stderr)
    sys.exit(code)


def find_slot(lib):
    """The token named $CARD_TOKEN, or the only/first token present."""
    want = os.environ.get("CARD_TOKEN", "")
    for slot in lib.getSlotList(tokenPresent=True):
        if not want or lib.getTokenInfo(slot).label.strip() == want:
            return slot
    if want:
        fail(f"card '{want}' (CARD_TOKEN) not found")
    fail("no card found - is it inserted? (card-tools/card-status.sh)")


def flags_text(info):
    return ", ".join(f.replace("CKF_", "").lower() for f in info.flags2text())


def check_key(key, what):
    if not re.fullmatch(r"[0-9a-fA-F]{48}", key):
        fail(f"the {what} must be exactly 48 hex characters - nothing was sent to the card", 3)
    return key.lower()


def new_admin_key(args, current):
    if args.generate:
        key = secrets.token_hex(24)
    else:
        key = check_key(getpass.getpass("New admin key (48 hex characters): ").strip(), "new admin key")
        if key != getpass.getpass("Repeat new admin key: ").strip().lower():
            fail("the two entries differ - nothing was sent to the card", 3)
    if key == current:
        fail("the new admin key equals the current one - nothing to do", 3)
    if key == FACTORY_ADMIN_KEY:
        print("  ! the new admin key is the public factory key - training cards only")
    return key


def main():
    sys.stdout.reconfigure(line_buffering=True)
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--factory-admin-key", action="store_true",
                    help="the current admin key is the factory key (48 zeros) instead of prompting")
    ap.add_argument("--generate", action="store_true",
                    help="generate a random new admin key and show it once (instead of entering it)")
    ap.add_argument("--dry-run", action="store_true", help="check everything, send nothing to the card")
    ap.add_argument("--module", default=os.environ.get("PKCS11_MODULE", DEFAULT_MODULE),
                    help="PKCS#11 module (default: $PKCS11_MODULE or SAC)")
    args = ap.parse_args()

    lib = PyKCS11.PyKCS11Lib()
    try:
        lib.load(args.module)
    except PyKCS11.PyKCS11Error as e:
        fail(f"cannot load {args.module}: {e}")
    slot = find_slot(lib)
    info = lib.getTokenInfo(slot)
    serial = info.serialNumber.strip()

    print("=== Card ===")
    print(f"  label         {info.label.strip()}")
    print(f"  serial        {serial}")
    print(f"  model         {info.manufacturerID.strip()} {info.model.strip()}")
    print(f"  flags         {flags_text(info)}")

    danger = [f for f in info.flags2text() if f in SO_DANGER_FLAGS]
    if danger:
        fail("the card reports earlier wrong admin key attempts ("
             + ", ".join(f.replace("CKF_", "").lower() for f in danger) + ").\n"
             "  Refusing: another wrong attempt could lock the admin key, which makes\n"
             "  an IDPrime 940 permanently unusable.")

    if args.factory_admin_key:
        current = FACTORY_ADMIN_KEY
        print("\nCurrent admin key: the factory key (48 zeros).")
    else:
        current = check_key(getpass.getpass("\nCurrent admin key (48 hex characters): ").strip(),
                            "current admin key")
    new = new_admin_key(args, current)

    if args.dry_run:
        print(f"\n--dry-run: would change the admin key of card {serial}.")
        print("Stopping here, nothing was sent to the card.")
        return

    if args.generate:
        print("\n  New admin key - record it now (safe / custody); it is not shown again:")
        print(f"\n      {new}\n")
        if input("Type RECORDED once it is written down, anything else aborts: ").strip() != "RECORDED":
            fail("not recorded - aborted, nothing was changed", 3)
    print(f"\nThis will change the admin key of card {serial}. Keys and PINs on the card stay.")
    typed = input(f"Type the card serial ({serial}) to continue, anything else aborts: ").strip()
    if typed != serial:
        fail("serial does not match - aborted, nothing was changed", 3)

    session = lib.openSession(slot, PyKCS11.CKF_SERIAL_SESSION | PyKCS11.CKF_RW_SESSION)
    try:
        # Exactly one authentication with the current key; never retried.
        try:
            session.login(current, user_type=PyKCS11.CKU_SO)
        except PyKCS11.PyKCS11Error as e:
            fail(f"admin login failed: {e}\n  Card flags now: {flags_text(lib.getTokenInfo(slot))}\n"
                 "  Nothing was changed. Do NOT retry with a guessed admin key.")
        try:
            session.setPin(current, new)
        except PyKCS11.PyKCS11Error as e:
            fail(f"C_SetPIN failed: {e} - the admin key is unchanged")
        print("  ✓ admin key changed")
    finally:
        try:
            session.logout()
        except PyKCS11.PyKCS11Error:
            pass
        session.closeSession()

    # Prove the new key works: one login with it
    session = lib.openSession(slot, PyKCS11.CKF_SERIAL_SESSION | PyKCS11.CKF_RW_SESSION)
    try:
        session.login(new, user_type=PyKCS11.CKU_SO)
        session.logout()
        print("  ✓ new admin key verified (admin login works)")
    except PyKCS11.PyKCS11Error as e:
        fail(f"login with the new admin key failed: {e}\n"
             f"  Card flags now: {flags_text(lib.getTokenInfo(slot))}\n"
             "  Do NOT retry - check which key the card holds before any further admin action.")
    finally:
        session.closeSession()

    if args.generate:
        print("Clear the terminal (Ctrl-L / clear) - the new admin key is still on screen.")
    print(f"Done. Card flags: {flags_text(lib.getTokenInfo(slot))}")


if __name__ == "__main__":
    main()
