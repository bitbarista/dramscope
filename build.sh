#!/usr/bin/env bash
# Build DRAMscope and its fault-injected variants.
#   bash build.sh
#
# ⚠ The fault builds are not optional extras. A diagnostic that cannot report a
# fault proves nothing, and test/run.sh asserts both directions. See SPEC.md §8.
set -e
cd "$(dirname "$0")"
mkdir -p build

# ⚠ EVERY VARIANT GETS ITS OWN SYMBOL FILE. The injected instructions shift
# every address after them, so the clean build's `halt` is NOT the fault
# build's `halt` -- and a harness that breakpoints the wrong address simply
# hangs, which is how this was found.
mk() {   # $1 = -D flag or empty, $2 = output stem, $3 = cart name
  if [ -z "$1" ]; then
    acme -l "build/$2.labels" src/dramscope.asm
  else
    acme "$1" -l "build/$2.labels" -o "build/$2.bin" src/dramscope.asm
  fi
  cartconv -t normal -i "build/$2.bin" -o "build/$2.crt" -n "$3" >/dev/null
  printf "  %-22s %6s bytes\n" "$2.crt" "$(stat -c%s "build/$2.crt")"
}

mk ""              dramscope       "DRAMSCOPE"
mk "-DINJECT_DB=1" dramscope_fdb   "DS FAULT DB"
mk "-DINJECT_AB=1" dramscope_fab   "DS FAULT AB"
