#!/usr/bin/env bash
# Run DRAMscope on every C64 variant VICE can emulate.
#   bash test/models.sh
#
# ⚠ Slower than test/run.sh (about twenty full passes) and complementary to it:
# run.sh proves the tool reports faults correctly on ONE machine, this proves
# it behaves identically on EVERY machine. Neither substitutes for the other.
set -e
cd "$(dirname "$0")/.."
echo "  rebuilding first (a stale binary would give a false PASS)"
bash build.sh >/dev/null
exec python3 test/models.py
