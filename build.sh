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

# --- gate G1 probe: EasyFlash $DE02 mode switching on real hardware ---------
# ⚠ An EasyFlash image is 1 MB, 64 banks of ROML(8K)+ROMH(8K). cartconv
# rejects anything shorter, so bank 0 is ours and the remaining 63 are $FF.
acme -l build/g1.labels src/g1probe_roml.asm
acme src/g1probe_romh.asm
python3 -c "
roml = open('build/g1probe_roml.bin','rb').read()
romh = open('build/g1probe_romh.bin','rb').read()
open('build/g1probe.bin','wb').write(roml + romh + b'\xff' * (1024*1024 - 16384))"
cartconv -t easy -i build/g1probe.bin -o build/g1probe.crt -n "G1 EASYFLASH PROBE" >/dev/null
printf "  %-22s %6s bytes  (gate G1)\n" "g1probe.crt" "$(stat -c%s build/g1probe.crt)"
