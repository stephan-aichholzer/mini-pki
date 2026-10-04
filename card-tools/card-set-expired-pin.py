#!/usr/bin/env python3
"""Change an expired user PIN (C_Login -> CKR_PIN_EXPIRED).

IDPrime cards ship with a transport PIN (0000) flagged "user PIN to be
changed". `pkcs11-tool --change-pin` logs in first and therefore fails.
PKCS#11 allows C_SetPIN in an R/W *public* session (no login), which is
what this script does.

Usage (from the repository root, after setting up card-tools/.venv):
    card-tools/.venv/bin/python card-tools/card-set-expired-pin.py   # prompts for old/new PIN

The PKCS#11 module defaults to $PKCS11_MODULE, else SAC (/usr/lib/libeTPkcs11.so).
"""
import argparse
import getpass
import os
import sys

import PyKCS11

DEFAULT_MODULE = "/usr/lib/libeTPkcs11.so"


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--module", default=os.environ.get("PKCS11_MODULE", DEFAULT_MODULE),
                    help="PKCS#11 module (default: $PKCS11_MODULE or SAC)")
    ap.add_argument("--slot", type=int, default=0, help="index into slots with a token")
    ap.add_argument("--old", help="current PIN (prompted if omitted)")
    ap.add_argument("--new", help="new PIN (prompted if omitted)")
    args = ap.parse_args()

    lib = PyKCS11.PyKCS11Lib()
    lib.load(args.module)
    slots = lib.getSlotList(tokenPresent=True)
    if not slots:
        sys.exit("no token present")
    slot = slots[args.slot]
    info = lib.getTokenInfo(slot)
    print(f"token: {info.label.strip()}  flags: {', '.join(info.flags2text())}")

    old = args.old or getpass.getpass("current PIN: ")
    new = args.new
    if not new:
        new = getpass.getpass("new PIN: ")
        if new != getpass.getpass("repeat new PIN: "):
            sys.exit("PINs do not match")

    session = lib.openSession(slot, PyKCS11.CKF_SERIAL_SESSION | PyKCS11.CKF_RW_SESSION)
    try:
        session.setPin(old, new)
    except PyKCS11.PyKCS11Error as e:
        sys.exit(f"C_SetPIN failed: {e}")
    finally:
        session.closeSession()

    info = lib.getTokenInfo(slot)
    print(f"PIN changed. flags now: {', '.join(info.flags2text())}")


if __name__ == "__main__":
    main()
