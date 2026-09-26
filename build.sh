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

# ⚠ THE FLAG STRINGS ARE SINGLE-QUOTED. They contain $ for hex constants and
# double quotes let the shell expand $40 into "$4" plus "0" -- which silently
# built a mutation aimed at page 0 instead of page $40.
mk() {   # $1 = -D flags or empty, $2 = output stem, $3 = cart name
  if [ -z "$1" ]; then
    acme -l "build/$2.labels" src/dramscope.asm
  else
    acme $1 -l "build/$2.labels" -o "build/$2_roml.bin" src/dramscope.asm
  fi
  pack "build/$2_roml.bin" build/dramscope_romh.bin "build/$2.bin"
  cartconv -t easy -i "build/$2.bin" -o "build/$2.crt" -n "$3" >/dev/null
  printf "  %-22s %6s bytes\n" "$2.crt" "$(stat -c%s "build/$2.crt")"
}

mk ""              dramscope       "DRAMSCOPE"
mk '-DINJECT_DB=1' dramscope_fdb   "DS FAULT DB"
mk '-DINJECT_AB=1' dramscope_fab   "DS FAULT AB"
mk '-DINJECT_NOEF=1' dramscope_fef "DS NO EASYFLASH"
mk '-DINJECT_MEM=1  -DINJ_PG=$40 -DINJ_OFF=$37 -DINJ_MASK=$01' dramscope_fmem "DS FAULT MEM"
mk '-DINJECT_ALL=1  -DINJ_PG=$40 -DINJ_OFF=$37 -DINJ_MASK=$ff' dramscope_fall "DS FAULT ALLBITS"
mk '-DINJECT_LR=1   -DINJ_PG=$50 -DINJ_OFF=$12 -DINJ_MASK=$80' dramscope_flr  "DS FAULT LR"
mk '-DINJECT_TOPO=1 -DINJ_PG=$60 -DINJ_OFF=$71 -DINJ_MASK=$40' dramscope_ftop "DS FAULT TOPO"
mk '-DINJECT_ZP=1'   dramscope_fzp  "DS FAULT ZP"
mk '-DINJECT_HV=1   -DINJ_PG=$05 -DINJ_OFF=$55 -DINJ_MASK=$10' dramscope_fhv  "DS FAULT HANDOVER"
mk '-DINJECT_RET=1  -DINJ_PG=$70 -DINJ_OFF=$23 -DINJ_MASK=$20' dramscope_fret "DS FAULT RETENTION"
mk '-DINJECT_COL=1  -DINJ_PG=$d9 -DINJ_OFF=$44 -DINJ_MASK=$02' dramscope_fcol "DS FAULT COLRAM"
mk '-DINJECT_ONCE=1 -DINJ_PG=$40 -DINJ_OFF=$37 -DINJ_MASK=$01 -DINJ_FIRSTPASS=1' dramscope_fonce "DS FAULT TRANSIENT"

# ⚠ The two P0a verdicts. INJECT_P0A alone = scratch bad but memory fitted, so
# the sweep must find RAM and report a STEADY red. Adding INJECT_NORAM also
# breaks the sweep, so nothing responds anywhere and it must report a FLASHING
# red. One flag apart, and they must not give the same answer.
# ⚠ Clean on run 1, faulty from run 2 -- the verdict changes from "ALL TESTS
# PASSED" to a memory fault, so row 22 goes from the coverage line to the bit
# lanes. That transition is what used to leave a tail behind.
mk '-DINJECT_MEM=1  -DINJ_PG=$52 -DINJ_OFF=$19 -DINJ_MASK=$01 -DINJ_LATERPASS=1' dramscope_fchg "DS FAULT LATE"

# ⚠ The three nibble paths, because on a 41464 board four bits are ONE chip.
# fmem ($01) is already low-nibble-only. These are the other two.
mk '-DINJECT_MEM=1  -DINJ_PG=$44 -DINJ_OFF=$21 -DINJ_MASK=$f0' dramscope_fnhi "DS FAULT NIB HI"
mk '-DINJECT_MEM=1  -DINJ_PG=$48 -DINJ_OFF=$63 -DINJ_MASK=$11' dramscope_fnbo "DS FAULT NIB BOTH"

mk '-DINJECT_P0A=1'                  dramscope_fscr  "DS FAULT SCRATCH"
mk '-DINJECT_P0A=1 -DINJECT_NORAM=1' dramscope_fnor  "DS FAULT NO RAM"

# --- gate G1 probe: EasyFlash $DE02 mode switching on real hardware ---------
acme -l build/g1.labels src/g1probe_roml.asm
acme src/g1probe_romh.asm
pack build/g1probe_roml.bin build/g1probe_romh.bin build/g1probe.bin
cartconv -t easy -i build/g1probe.bin -o build/g1probe.crt -n "G1 EASYFLASH PROBE" >/dev/null
printf "  %-22s %6s bytes  (gate G1)\n" "g1probe.crt" "$(stat -c%s build/g1probe.crt)"
