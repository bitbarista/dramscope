#!/usr/bin/env python3
"""Fail if the README screenshots no longer match the shipping binary.

⚠ Generated images drift. Every other generated artefact in this project has,
at least once. This compares the md5 recorded by tools/make-screenshots.py
against the current build/dramscope.crt -- milliseconds, no emulator -- so a
stale screenshot on the landing page is a build failure rather than something
a reader notices before we do.
"""
import hashlib
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
STAMP = ROOT / "docs" / "img" / ".built-from"
CRT = ROOT / "build" / "dramscope.crt"

print("README screenshots")
if not CRT.exists():
    print("  (no build yet -- nothing to compare)")
    sys.exit(0)
if not STAMP.exists():
    sys.exit("  *** docs/img/.built-from missing -- run tools/make-screenshots.py")
want = hashlib.md5(CRT.read_bytes()).hexdigest()
got = STAMP.read_text().strip()
missing = [n for n in ("healthy", "fault", "colour-ram")
           if not (ROOT / "docs" / "img" / f"{n}.png").exists()]
if missing:
    sys.exit(f"  *** missing: {', '.join(missing)} -- run tools/make-screenshots.py")
if got != want:
    sys.exit(f"  *** stale: rendered from {got[:8]}, the build is now {want[:8]}\n"
             f"      run tools/make-screenshots.py")
print(f"  3 images, current with dramscope.crt {want[:8]}")
