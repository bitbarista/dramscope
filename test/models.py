#!/usr/bin/env python3
"""Run DRAMscope across every C64 variant VICE can emulate.

⚠ WHY THIS EXISTS. Until now the tool had been exercised on exactly two
machines: VICE's default PAL C64, and Carl's own Ultimate II+ / Kung Fu Flash.
It is meant for anyone's C64, and several things it relies on are not constant
across the family:

  * raster geometry      P7 waits on raster line $80 -- PAL has 312 lines,
                         NTSC 262 or 263, PAL-N its own count
  * phi2 frequency       sets the flash rate and the length of the dwell
  * CIA revision         6526 vs 8521 -- and the flash rate is now a CIA timer
  * KERNAL revision      ⚠ should be irrelevant, because the cartridge boots
                         in Ultimax and supplies its own reset vector. That is
                         a CLAIM, so it is tested -- not by swapping revisions
                         but by booting with a KERNAL of all $FF, which is a
                         far stronger demonstration and needs no ROM we lack.

⚠ WHAT SIMULATION CANNOT COVER, and the docs must not pretend otherwise:
VICE models the machine, not the DRAM arrangement. A short board's two 41464s
and a long board's eight 4164s look identical to the emulator, so the chip
naming can only ever be verified on real hardware.
"""
import re
import subprocess
import sys
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"

# Every model x64sc accepts. `ultimax` is the MAX Machine, not a C64 -- it is
# here deliberately, to prove the cartridge reports a fatal code instead of
# hanging on a machine whose memory it cannot use.
C64_MODELS = ["c64", "c64c", "c64old", "ntsc", "newntsc", "oldntsc",
              "drean", "c64gs", "pet64"]
# ⚠ Several models name a KERNAL image this machine does not have, and VICE
# refuses to initialise without one. The stock ROM is substituted so the run
# can proceed: the cartridge never executes a byte of it, and what these
# models actually change -- the VIC-II and CIA revisions -- is unaffected.
# Substituting it is what makes the comparison about the chips rather than
# about which ROM files happen to be installed.
STOCK_KERNAL = pathlib.Path.home() / ".local/share/vice/C64/kernal-901227-03.bin"

BORDER = {1: "WHITE", 2: "RED", 3: "CYAN", 4: "PURPLE", 5: "GREEN",
          6: "BLUE", 7: "YELLOW", 8: "ORANGE", 10: "LTRED", 12: "GREY"}
GLYPH = {0x20: " ", 0x2E: ".", 0x2A: "*", 0xA0: "#", 0x18: "X", 0x2B: "+"}


def sym(stem: str, name: str) -> str:
    for line in (BUILD / f"{stem}.labels").read_text().splitlines():
        m = re.match(rf"\s*{name}\s*=\s*\$([0-9a-fA-F]+)", line)
        if m:
            return "0x" + m.group(1)
    sys.exit(f"no {name!r} in {stem}.labels")


def vice_starts(extra_args) -> bool:
    """⚠ A machine VICE cannot initialise is a MISSING ROM, not a defect in
    the cartridge, and reporting it as a failure would be a lie."""
    r = subprocess.run(
        ["x64sc", "-console", "-warp", "-limitcycles", "100000"] + extra_args,
        cwd=ROOT, capture_output=True, text=True, timeout=90)
    return "Machine initialization failed" not in (r.stdout + r.stderr)


def run(stem, extra_args, breakpoint_sym="pass_obs", timeout=180):
    """Returns (border, screen, workspace) or None if it never got there."""
    for f in ("m_scr.bin", "m_vic.bin", "m_wrk.bin"):
        (BUILD / f).unlink(missing_ok=True)
    (BUILD / "m_mon.txt").write_text(
        'bank ram\nsave "build/m_scr.bin" 0 0400 07ff\n'
        'save "build/m_wrk.bin" 0 0300 0330\n'
        'bank io\nsave "build/m_vic.bin" 0 d020 d02f\nquit\n')
    try:
        subprocess.run(
            ["x64sc", "-console", "-warp", "-initbreak", sym(stem, breakpoint_sym),
             "-moncommands", "build/m_mon.txt",
             "-cartcrt", str(BUILD / f"{stem}.crt")] + extra_args,
            cwd=ROOT, timeout=timeout,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    except subprocess.TimeoutExpired:
        return None
    try:
        return ((BUILD / "m_vic.bin").read_bytes()[2] & 0x0F,
                (BUILD / "m_scr.bin").read_bytes()[2:],
                (BUILD / "m_wrk.bin").read_bytes()[2:])
    except (FileNotFoundError, IndexError):
        return None


def text(scr, row, c0, c1):
    out = []
    for b in scr[row * 40 + c0: row * 40 + c1]:
        if 1 <= b <= 26:
            out.append(chr(64 + b))
        elif 0x30 <= b <= 0x39:
            out.append(chr(b))
        else:
            out.append(GLYPH.get(b, "?"))
    return "".join(out)


CLEAN_ROW0 = "**#*****########"
fails = 0


def check_clean(label, args):
    """One complete pass, on a healthy machine, must look identical everywhere."""
    global fails
    if not vice_starts(args):
        print(f"  {label:34s} SKIPPED -- VICE cannot start this model here")
        return
    got = run("dramscope", args)
    if got is None:
        print(f"  {label:34s} *** NEVER COMPLETED A PASS (hang or crash)")
        fails += 1
        return
    border, scr, wrk = got
    errs = wrk[14] + 256 * wrk[15]
    row0 = text(scr, 3, 2, 18)
    passes = text(scr, 0, 33, 38)
    # ⚠ the checklist is the point: every phase must have run AND passed
    checks = "".join(text(scr, r, 32, 34).strip() or ".."
                     for r in (3, 6, 11, 12, 13, 14, 15, 16, 17))
    ok = (BORDER.get(border) == "GREEN" and errs == 0 and checks == "OK" * 9
          and row0 == CLEAN_ROW0 and passes.strip() == "0001")
    print(f"  {label:32s} {BORDER.get(border, border):6s} err={errs:<4d} "
          f"{row0} {checks} p={passes.strip()}"
          f"{'' if ok else '   <-- ***'}")
    if not ok:
        fails += 1


print("DRAMscope across every C64 variant VICE emulates")
print()
print("A clean pass must look identical on all of them:")
print(f"  GREEN, 0 errors, map {CLEAN_ROW0}, all 9 phases OK, PASSES 0001")
print()
for cia, cianame in ((0, "6526 old"), (1, "8521 new")):
    for model in C64_MODELS:
        check_clean(f"{model} + CIA {cianame}",
                    ["-model", model, "-ciamodel", str(cia),
                     "-kernal", str(STOCK_KERNAL)])
    print()

print("⚠ THE KERNAL IS NEVER EXECUTED, and here is the proof: the machine is")
print("  given a KERNAL of 8 KB of $FF and the run must be unaffected. A")
print("  normal autostart cartridge could not survive this at all -- it needs")
print("  the KERNAL's own JSR $FD02 to be handed control.")
dummy = BUILD / "dummy_kernal.bin"
dummy.write_bytes(b"\xff" * 8192)
check_clean("KERNAL replaced with $FF", ["-kernal", str(dummy)])
print()

print("⚠ A machine whose memory it cannot use must REPORT, not hang.")
print("  The MAX Machine has 2 KB and no $C000, so the engine has nowhere")
print("  to live -- that is a BLUE or PURPLE border, reached and held:")
got = run("dramscope", ["-model", "ultimax", "-kernal", str(STOCK_KERNAL)],
          breakpoint_sym="rom_halt", timeout=90)
if got is None:
    print("  ultimax                            *** HUNG -- no fatal code reported")
    fails += 1
else:
    name = BORDER.get(got[0], got[0])
    ok = name in ("BLUE", "PURPLE", "ORANGE", "RED")
    print(f"  ultimax                            {name}"
          f"{'' if ok else '   <-- *** expected a fatal code'}")
    if not ok:
        fails += 1
print()

print("A fault must be found and named the same way on PAL and on NTSC:")
for model in ("c64", "ntsc"):
    got = run("dramscope_fmem", ["-model", model, "-kernal", str(STOCK_KERNAL)])
    if got is None:
        print(f"  {model:34s} *** never completed")
        fails += 1
        continue
    border, scr, wrk = got
    bits = text(scr, 22, 0, 40).rstrip()
    chips = text(scr, 23, 0, 40).rstrip()
    ok = BORDER.get(border) == "LTRED" and bits.endswith("D0") and chips.endswith("U21")
    print(f"  {model:34s} {BORDER.get(border, border):6s} {bits.strip()} / "
          f"{chips.strip()}{'' if ok else '   <-- ***'}")
    if not ok:
        fails += 1

print()
if fails:
    print(f"  *** {fails} VARIANT(S) FAILED")
    sys.exit(1)
print("  EVERY VARIANT PASSED")
