#!/usr/bin/env python3
"""Generate the printable chip chart as a one-page A4 PDF.

⚠ THE TABLE IS NOT WRITTEN HERE. It is imported from test/chart.py, which is the
single source every other copy is checked against. A hand-written PDF would be a
fifth copy of a table that tells someone which part to desolder, and this
project has already had one figure wrong in four places at once.

⚠ PRINTS IN BLACK AND WHITE. A bench chart goes through a mono laser printer and
gets pinned to a wall under bad light, so nothing may depend on colour: emphasis
is carried by weight, rules and boxes. The one accent is a mid grey that still
reads as a distinct tone in greyscale.

Usage:  python3 tools/make-chip-chart.py  ->  build/CHIP-CHART.pdf
"""
import html
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "test"))
from chart import CHART, BOARDS          # noqa: E402  -- the single source

OUT_HTML = ROOT / "build" / "chip-chart.html"
OUT_PDF = ROOT / "build" / "CHIP-CHART.pdf"
VERSION = "1.4"

CSS = """
@page { size: A4 portrait; margin: 10mm 14mm 8mm 14mm; }
* { box-sizing: border-box; }
html, body { margin: 0; padding: 0; }
body {
  font-family: "DejaVu Sans", Arial, Helvetica, sans-serif;
  font-size: 9.2pt; line-height: 1.34; color: #000; background: #fff;
  -webkit-print-color-adjust: exact; print-color-adjust: exact;
}
h1 { font-size: 17pt; margin: 0; letter-spacing: -0.2pt; }
.sub { font-size: 8.6pt; color: #444; margin: 1mm 0 0 0; }
.head { border-bottom: 2.2pt solid #000; padding-bottom: 2.2mm; margin-bottom: 2.8mm;
        display: flex; align-items: flex-end; justify-content: space-between; gap: 6mm; }
.ver { font-family: "DejaVu Sans Mono", monospace; font-size: 8pt; color: #444;
       white-space: nowrap; text-align: right; }
h2 { font-size: 9.4pt; text-transform: uppercase; letter-spacing: 0.7pt;
     margin: 3.1mm 0 1.4mm 0; padding-bottom: 0.8mm; border-bottom: 0.6pt solid #999; }
p { margin: 0 0 1.6mm 0; }
.lead { font-size: 9.6pt; }
b, strong { font-weight: 700; }

table.chips { width: 100%; border-collapse: collapse; margin-top: 1mm;
              font-family: "DejaVu Sans Mono", monospace; }
table.chips th, table.chips td { border: 0.6pt solid #666; padding: 1.45mm 0.6mm;
                                 text-align: center; font-size: 9.6pt; }
table.chips thead th { background: #000; color: #fff; font-size: 8.4pt;
                       letter-spacing: 0.4pt; padding: 1.7mm 0.6mm; }
table.chips td.assy { font-weight: 700; font-size: 10.4pt; letter-spacing: 0.3pt; }
table.chips td.meta { font-size: 8.2pt; color: #333; }
table.chips td.chip { font-weight: 700; }
table.chips td.span { font-weight: 700; background: #e8e8e8; }
table.chips tbody tr:nth-child(4) td { border-top: 1.6pt solid #000; }
.divider td { padding: 0 !important; border: 0 !important; height: 0; }

.box { border: 1.1pt solid #000; padding: 2.0mm 2.6mm; margin: 2.0mm 0; }
.box.warn { border-left: 3.4pt solid #000; background: #f2f2f2; }
.box h3 { margin: 0 0 1.2mm 0; font-size: 9pt; text-transform: uppercase;
          letter-spacing: 0.5pt; }
.cols { display: flex; gap: 5mm; }
.cols > div { flex: 1; }
ol { margin: 1mm 0 0 4.6mm; padding: 0; }
ol li { margin-bottom: 0.9mm; }
code, .mono { font-family: "DejaVu Sans Mono", monospace; }
pre.screen { font-family: "DejaVu Sans Mono", monospace; font-size: 8.4pt;
             background: #000; color: #fff; padding: 2.2mm 2.6mm; margin: 1.4mm 0 0 0;
             line-height: 1.3; white-space: pre; }
.foot { margin-top: 2.6mm; padding-top: 1.4mm; border-top: 0.6pt solid #999;
        font-size: 7.6pt; color: #444; display: flex; justify-content: space-between;
        gap: 4mm; }
"""


def row(assy: str) -> str:
    board, ram = BOARDS[assy]
    cells = CHART[assy]
    head = (f'<td class="assy">{assy}</td>'
            f'<td class="meta">{board}</td><td class="meta">{ram}</td>')
    if len(set(cells)) == 2:            # a 4-bit part: one chip spans a nibble
        lo, hi = cells[0], cells[4]
        body = (f'<td class="span" colspan="4">{lo}</td>'
                f'<td class="span" colspan="4">{hi}</td>')
    else:
        body = "".join(f'<td class="chip">{c}</td>' for c in cells)
    return f"<tr>{head}{body}</tr>"


def build_html() -> str:
    rows = "\n".join(row(a) for a in CHART)
    bits = "".join(f"<th>D{i}</th>" for i in range(8))
    screen = html.escape(
        " MEMORY FAULT, FIRST BAD BYTE AT $4037\n"
        " BITS                               D0\n"
        " LIKELY                             U21\n"
        " 8X4164 ASSUMED. 41464? D0-D3=1 CHIP.")
    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<title>DRAMscope chip chart</title><style>{CSS}</style></head><body>

<div class="head">
  <div>
    <h1>Which chip carries which bit</h1>
    <p class="sub">Commodore 64 DRAM reference &middot; for use with DRAMscope</p>
  </div>
  <div class="ver">DRAMscope {VERSION}<br>github.com/bitbarista/dramscope</div>
</div>

<p class="lead"><b>DRAMscope names the failing data bit, D0 to D7.</b> That bit number is
true on every C64 ever made. This chart turns it into a chip &mdash; which is not.</p>

<h2>1 &nbsp; Find your assembly number</h2>
<p>It is printed on the board itself, usually along the front edge near the keyboard
connector, as <span class="mono">ASSY 250469</span> or similar. Do not guess from the case or
the badge &mdash; the same case was used for several boards.</p>

<h2>2 &nbsp; Read across</h2>
<table class="chips">
  <thead><tr><th>Assembly</th><th>Board</th><th>RAM</th>{bits}</tr></thead>
  <tbody>
{rows}
  </tbody>
</table>

<div class="cols">
  <div class="box warn">
    <h3>The two 41464 boards are reversed</h3>
    <p>On the <b>250469</b> the lower designator carries the lower bits. On the
    <b>250466</b> it is the other way round. <b>There is no rule to work this out
    from</b> &mdash; check the assembly number.</p>
  </div>
  <div class="box warn">
    <h3>Counting chips is not the board type</h3>
    <p><b>250466 is a long board with two RAM chips.</b> &ldquo;Two chips means short
    board&rdquo; is wrong, and so is &ldquo;long board means eight chips&rdquo;.</p>
  </div>
</div>

<h2>3 &nbsp; Before you desolder anything</h2>
<div class="box">
  <p><b>The bit is measured. The chip is a suggestion</b> &mdash; which is why the screen says
  <span class="mono">LIKELY</span> rather than naming the part as a fact. A failing bit means
  the fault is somewhere <b>on that data line</b>. The RAM is the likeliest part on it, but a
  dry or cracked joint, a corroded or spread socket contact, a broken track, the PLA, or the
  CPU end of the same line are <b>indistinguishable to any software test</b>.</p>
  <ol>
    <li><b>Reseat the chip.</b> Socketed RAM that has sat for forty years is a common fault by
        itself.</li>
    <li><b>Inspect and reflow</b> the joints on that chip and its socket.</li>
    <li><b>Check continuity</b> along the data line, RAM pin to CPU pin.</li>
    <li><b>Only then swap the chip</b> &mdash; and keep the old one until the repair is
        confirmed, because it may well be good.</li>
  </ol>
  <p style="margin-top:1.6mm">If you replace a chip and the same bit still fails, the chip was
  never the fault. That is information, not a wasted part: it points at the line.</p>
</div>

<div class="cols">
  <div>
    <h2>What the screen shows</h2>
    <pre class="screen">{screen}</pre>
  </div>
  <div>
    <h2>Two it will not name</h2>
    <p><b>Every bit failing</b> &mdash; it names no chip and says <span class="mono">SEE
    PLA</span>. Eight dead RAMs is not the likely reading: suspect the PLA, the address
    multiplexers at U13/U25, or their resistor packs RP1/RP2.</p>
    <p><b>Colour RAM</b> &mdash; a separate 1K&nbsp;&times;&nbsp;4 static chip. It causes wrong
    colours rather than a crash, which is why it gets blamed on the VIC. It is never counted
    against the DRAMs.</p>
  </div>
</div>

<div class="foot">
  <div><b>Sources:</b> schematic 251138, cross-checked against the opencbm Hardware Reference
  and Repair Guide; the 250466 row from myoldcomputer.nl. Full evidence in PROVENANCE.md.</div>
  <div style="text-align:right; white-space:nowrap">MIT licensed &middot; <b>no warranty</b><br>
  ko-fi.com/bitbarista</div>
</div>

</body></html>"""


def main() -> int:
    OUT_HTML.parent.mkdir(parents=True, exist_ok=True)
    OUT_HTML.write_text(build_html(), encoding="utf-8")

    chrome = shutil.which("google-chrome") or shutil.which("chromium")
    if not chrome:
        sys.exit("no chrome/chromium found; cannot render the PDF")
    subprocess.run(
        [chrome, "--headless", "--disable-gpu", "--no-sandbox",
         "--no-pdf-header-footer", f"--print-to-pdf={OUT_PDF}",
         OUT_HTML.as_uri()],
        check=True, capture_output=True, timeout=180)
    if not OUT_PDF.exists():
        sys.exit("chrome ran but produced no PDF")

    # ⚠ ONE PAGE, ASSERTED. The whole point is a single sheet that gets pinned to
    # a wall; spilling a footer onto page 2 is the failure mode, and it happened
    # on the first render. Content grows, so this has to be checked, not hoped.
    import re
    pages = len(re.findall(rb"/Type\s*/Page[^s]", OUT_PDF.read_bytes()))
    if pages != 1:
        sys.exit(f"CHIP-CHART.pdf is {pages} pages -- it must be exactly 1. "
                 f"Tighten the CSS or cut copy.")
    print(f"  {OUT_PDF.relative_to(ROOT)}  {OUT_PDF.stat().st_size:,} bytes")
    print(f"  {len(CHART)} assemblies, taken from test/chart.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
