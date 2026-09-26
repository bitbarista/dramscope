#!/usr/bin/env bash
# Build DRAMscope and its fault-injected variants.
#   bash build.sh
#
# ⚠ The fault builds are not optional extras. A diagnostic that cannot report a
# fault proves nothing, and test/run.sh asserts both directions. See SPEC.md §8.
set -e
cd "$(dirname "$0")"
mkdir -p build

# ⚠ An EasyFlash image is 1 MB: 64 banks of ROML(8K) + ROMH(8K). cartconv
# rejects anything shorter, so bank 0 is ours and the other 63 are $FF.
pack() {  # $1 = roml bin, $2 = romh bin, $3 = output bin
  python3 -c "
import sys
roml, romh, out = sys.argv[1:4]
l = open(roml,'rb').read(); h = open(romh,'rb').read()
assert len(l) == 8192 and len(h) == 8192, 'each half must be exactly 8 KiB'
open(out,'wb').write(l + h + b'\xff' * (1024*1024 - 16384))" "$1" "$2" "$3"
}

# ⚠ EVERY VARIANT GETS ITS OWN SYMBOL FILE. Injected instructions shift every
# address after them, so the clean build's `halt` is NOT the fault build's
# `halt` -- and a harness that breakpoints the wrong address simply hangs,
# which is how this was found.
acme src/dramscope_romh.asm

mk() {   # $1 = -D flag or empty, $2 = output stem, $3 = cart name
  if [ -z "$1" ]; then
    acme -l "build/$2.labels" src/dramscope.asm
  else
    acme "$1" -l "build/$2.labels" -o "build/$2_roml.bin" src/dramscope.asm
  fi
  pack "build/$2_roml.bin" build/dramscope_romh.bin "build/$2.bin"
  cartconv -t easy -i "build/$2.bin" -o "build/$2.crt" -n "$3" >/dev/null
  printf "  %-22s %6s bytes\n" "$2.crt" "$(stat -c%s "build/$2.crt")"
}

mk ""              dramscope       "DRAMSCOPE"
mk "-DINJECT_DB=1" dramscope_fdb   "DS FAULT DB"
mk "-DINJECT_AB=1" dramscope_fab   "DS FAULT AB"
mk "-DINJECT_NOEF=1" dramscope_fef "DS NO EASYFLASH"
mk "-DINJECT_MEM=1"  dramscope_fmem "DS FAULT MEM"
mk "-DINJECT_ALL=1"  dramscope_fall "DS FAULT ALLBITS"

# --- gate G1 probe: EasyFlash $DE02 mode switching on real hardware ---------
acme -l build/g1.labels src/g1probe_roml.asm
acme src/g1probe_romh.asm
pack build/g1probe_roml.bin build/g1probe_romh.bin build/g1probe.bin
cartconv -t easy -i build/g1probe.bin -o build/g1probe.crt -n "G1 EASYFLASH PROBE" >/dev/null
printf "  %-22s %6s bytes  (gate G1)\n" "g1probe.crt" "$(stat -c%s build/g1probe.crt)"
