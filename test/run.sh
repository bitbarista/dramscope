#!/usr/bin/env bash
# Run every build in VICE, headless, and CHECK THE RESULT.
#
# ⚠ THE FAULT BUILDS ARE THE IMPORTANT ONES. A diagnostic that cannot report a
# fault proves nothing. SPEC.md §8 -- and an early version of the sibling
# project's own test could not test the block it ran from, found only by
# mutation testing.
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
# ⚠ THE .crt FILES MUST LEAVE THE RUN AS THEY ENTERED IT. VICE writes an
# EasyFlash image back on exit and drops its name -- the cause of the release
# assets that carried "EasyFlash" (build.sh). Every x64sc call passes
# +easyflashcrtwrite; this catches a call that does not.
crt_before=$(md5sum build/*.crt)
# ⚠ "$@" so `bash test/run.sh --bless` reaches the checker. Without it the
# flag was silently dropped and the goldens never regenerated.
rc=0
python3 test/check.py "$@" || rc=$?
if [ "$(md5sum build/*.crt)" != "$crt_before" ]; then
  echo "  *** a .crt in build/ changed during the run -- an x64sc call is writing it back"
  exit 1
fi
exit $rc
