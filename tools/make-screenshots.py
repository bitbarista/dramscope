#!/usr/bin/env python3
"""Render the README screenshots from real runs, through the real character ROM.

⚠ THESE ARE GENERATED, SO THEY CAN GO STALE. Every other generated artefact in
this project has drifted from its source at least once. So each render records
the md5 of the .crt it came from in docs/img/.built-from, and
tools/check-screenshots.py fails if that no longer matches the current build --
a check that costs milliseconds and needs no emulator.

⚠ NOT A VICE SCREENSHOT. The screen matrix, colour RAM and VIC registers are
dumped by the monitor at the observation point and rendered here, so the image
is tied to the bytes the test suite already asserts rather than to whatever
frame the emulator happened to exit on.

Usage:  python3 tools/make-screenshots.py
"""
import hashlib
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
OUT = ROOT / "docs" / "img"
KERNAL = pathlib.Path.home() / ".local/share/vice/C64/kernal-901227-03.bin"
CHARROM = pathlib.Path.home() / ".local/share/vice/C64/chargen-901225-01.bin"

# Colodore palette -- the measured-from-hardware C64 palette VICE ships.
PAL = [(0, 0, 0), (255, 255, 255), (129, 51, 43), (112, 190, 203),
       (129, 55, 143), (86, 158, 59), (49, 40, 133), (202, 214, 121),
       (132, 79, 29), (85, 56, 0), (180, 98, 89), (67, 67, 67),
       (108, 108, 108), (154, 226, 127), (110, 101, 192), (149, 149, 149)]

# stem, output name, what it shows
SHOTS = [
    ("dramscope",      "healthy",    "a clean machine"),
    ("dramscope_fmem", "fault",      "one bad bit, chip named"),
    ("dramscope_fcol", "colour-ram", "colour RAM, not a DRAM"),
]


def sym(stem: str, name: str) -> str:
    for line in (BUILD / f"{stem}.labels").read_text().splitlines():
        m = re.match(rf"\s*{name}\s*=\s*\$([0-9a-fA-F]+)", line)
        if m:
            return "0x" + m.group(1)
    sys.exit(f"no {name!r} in {stem}.labels")


def grab(stem: str):
    for f in ("s_scr.bin", "s_col.bin", "s_vic.bin"):
        (BUILD / f).unlink(missing_ok=True)
    (BUILD / "s_mon.txt").write_text(
        'bank ram\nsave "build/s_scr.bin" 0 0400 07ff\n'
        'bank io\nsave "build/s_col.bin" 0 d800 dbff\n'
        'save "build/s_vic.bin" 0 d011 d02f\nquit\n')
    subprocess.run(
        ["x64sc", "-console", "-warp", "-kernal", str(KERNAL),
         "-initbreak", sym(stem, "pass_obs"), "-moncommands", "build/s_mon.txt",
         "-cartcrt", str(BUILD / f"{stem}.crt")],
        cwd=ROOT, timeout=400, check=False,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        return ((BUILD / "s_scr.bin").read_bytes()[2:],
                (BUILD / "s_col.bin").read_bytes()[2:],
                (BUILD / "s_vic.bin").read_bytes()[2:])
    except (FileNotFoundError, IndexError):
        sys.exit(f"{stem}: never reached pass_obs")


def render(dump, path: pathlib.Path, scale: int = 3) -> None:
    from PIL import Image
    scr, col, vic = dump
    border, bg = vic[0x20 - 0x11] & 15, vic[0x21 - 0x11] & 15
    rom = CHARROM.read_bytes()
    BW, BH = 32, 35
    W, H = 320 + 2 * BW, 200 + 2 * BH
    img = Image.new("RGB", (W, H), PAL[border])
    px = img.load()
    if vic[0] & 0x10:                       # DEN -- display enabled
        for cy in range(25):
            for cx in range(40):
                glyph = rom[scr[cy * 40 + cx] * 8:][:8]
                fg = PAL[col[cy * 40 + cx] & 15]
                for row in range(8):
                    bits = glyph[row]
                    for bit in range(8):
                        px[BW + cx * 8 + bit, BH + cy * 8 + row] = (
                            fg if bits & (0x80 >> bit) else PAL[bg])
    img.resize((W * scale, H * scale), Image.NEAREST).save(path)


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    for stem, name, what in SHOTS:
        render(grab(stem), OUT / f"{name}.png")
        print(f"  docs/img/{name}.png  {what}")
    # ⚠ The staleness anchor. The screenshots are only honest while they came
    # from the binary that is shipping.
    digest = hashlib.md5((BUILD / "dramscope.crt").read_bytes()).hexdigest()
    (OUT / ".built-from").write_text(digest + "\n")
    print(f"  rendered from dramscope.crt {digest}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
