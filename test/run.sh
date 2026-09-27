#!/usr/bin/env bash
# Run every build in VICE, headless, and CHECK THE RESULT.
#
# ⚠ THE FAULT BUILDS ARE THE IMPORTANT ONES. A diagnostic that cannot report a
# fault proves nothing. SPEC.md §8, and the sibling project's ERRATA F-16 -- a
# test that could not test the block it ran from, found only by mutation.
#
# ⚠ USES THE REAL COMMODORE ROMS, which VICE finds in its own data directory.
# They are NOT vendored here and must not be: they are copyrighted. Without
# them VICE falls back to nothing and every run fails. The upside of the real
# KERNAL is that the genuine autostart handshake runs -- JSR $FD02, which
# pushes a return address and so NEEDS THE STACK PAGE. That is this delivery
# vehicle's honest limit (SPEC.md §2.2) and a stub KERNAL cannot exercise it.
set -e
cd "$(dirname "$0")/.."
# ⚠ The chip chart first, because it takes a second and it is the check whose
# failure mode is someone desoldering the wrong part. No emulator needed.
python3 test/chart.py
# ⚠ And the landing-page screenshots, for the same reason: a generated artefact
# is only honest while it came from the binary that is shipping.
python3 tools/check-screenshots.py
echo
echo "  rebuilding first (a stale binary would give a false PASS)"
bash build.sh >/dev/null
# ⚠ "$@" so `bash test/run.sh --bless` reaches the checker. Without it the
# flag was silently dropped and the goldens never regenerated.
exec python3 test/check.py "$@"
