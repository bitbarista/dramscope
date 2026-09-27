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
VERSION = "1.5"
PAGES = 2          # ⚠ 1 = the chart, 2 = the advisory. Overflow must fail, not slide.

CSS = """
@page { size: A4 portrait; margin: 10mm 14mm 8mm 14mm; }
* { box-sizing: border-box; }
html, body { margin: 0; padding: 0; }
body {
  font-family: "DejaVu Sans", Arial, Helvetica, sans-serif;
  font-size: 9.0pt; line-height: 1.23; color: #000; background: #fff;
  -webkit-print-color-adjust: exact; print-color-adjust: exact;
}
h1 { font-size: 17pt; margin: 0; letter-spacing: -0.2pt; }
.sub { font-size: 8.6pt; color: #444; margin: 1mm 0 0 0; }
.head { border-bottom: 2.2pt solid #000; padding-bottom: 2.2mm; margin-bottom: 2.8mm;
        display: flex; align-items: flex-end; justify-content: space-between; gap: 6mm; }
.ver { font-family: "DejaVu Sans Mono", monospace; font-size: 8pt; color: #444;
       white-space: nowrap; text-align: right; }
h2 { font-size: 9.4pt; text-transform: uppercase; letter-spacing: 0.7pt;
     margin: 2.2mm 0 1.0mm 0; padding-bottom: 0.6mm; border-bottom: 0.6pt solid #999; }
p { margin: 0 0 1.3mm 0; }
.lead { font-size: 9.6pt; }
b, strong { font-weight: 700; }

table.chips { width: 100%; border-collapse: collapse; margin-top: 1mm;
              font-family: "DejaVu Sans Mono", monospace; }
table.chips th, table.chips td { border: 0.6pt solid #666; padding: 1.0mm 0.6mm;
                                 text-align: center; font-size: 9.6pt; }
table.chips thead th { background: #000; color: #fff; font-size: 8.4pt;
                       letter-spacing: 0.4pt; padding: 1.7mm 0.6mm; }
table.chips td.assy { font-weight: 700; font-size: 10.4pt; letter-spacing: 0.3pt; }
table.chips td.meta { font-size: 8.2pt; color: #333; }
table.chips td.chip { font-weight: 700; }
table.chips td.span { font-weight: 700; background: #e8e8e8; }
.dag { font-weight: 700; vertical-align: 0.9mm; font-size: 8pt; }
.srcnote { font-size: 7.8pt; margin: 1.1mm 0 0 0; }
table.chips tbody tr:nth-child(4) td { border-top: 1.6pt solid #000; }
.divider td { padding: 0 !important; border: 0 !important; height: 0; }

.box { border: 1.1pt solid #000; padding: 1.8mm 2.4mm; margin: 1.7mm 0; }
.box.warn { border-left: 3.4pt solid #000; background: #f2f2f2; }
.box h3 { margin: 0 0 1.2mm 0; font-size: 9pt; text-transform: uppercase;
          letter-spacing: 0.5pt; }
.cols { display: flex; gap: 5mm; }
.cols > div { flex: 1; }
ol { margin: 1mm 0 0 4.6mm; padding: 0; }
ol li { margin-bottom: 0.6mm; }
code, .mono { font-family: "DejaVu Sans Mono", monospace; }
pre.screen { font-family: "DejaVu Sans Mono", monospace; font-size: 8.4pt;
             background: #000; color: #fff; padding: 2.2mm 2.6mm; margin: 1.4mm 0 0 0;
             line-height: 1.3; white-space: pre; }
.page2 { page-break-before: always; }
.advisory { border: 1.6pt solid #000; padding: 2.4mm 3mm; margin: 0 0 3mm 0; background: #ececec; }
.advisory h2 { margin: 0 0 1.2mm 0; border: 0; padding: 0; font-size: 10pt; }
.tag { font-family: "DejaVu Sans Mono", monospace; font-size: 6.8pt; letter-spacing: 0.5pt;
       text-transform: uppercase; background: #000; color: #fff; padding: 0.2mm 1mm;
       border-radius: 0.6mm; vertical-align: 0.4mm; }
h2 .tag { vertical-align: 0.8mm; }
table.parts { width: 100%; border-collapse: collapse; margin: 1mm 0 2mm 0; }
table.parts th, table.parts td { border: 0.6pt solid #666; padding: 1.3mm 1.8mm;
                                 text-align: left; vertical-align: top; font-size: 8.8pt; }
table.parts thead th { background: #000; color: #fff; font-size: 8pt; letter-spacing: 0.4pt; }
table.parts td.pn { font-family: "DejaVu Sans Mono", monospace; font-weight: 700;
                    white-space: nowrap; }
.foot { margin-top: 2.6mm; padding-top: 1.4mm; border-top: 0.6pt solid #999;
        font-size: 7.6pt; color: #444; display: flex; justify-content: space-between;
        gap: 4mm; }
"""


# Rows whose bit mapping rests on a SINGLE source get a mark on the printed
# chart. ⚠ Empty as of 2026-09-27: 250466 was the last one, and Commodore
# schematic 252278 settled it. Kept because the next assembly added may need it.
SINGLE_SOURCE = set()


def row(assy: str) -> str:
    board, ram = BOARDS[assy]
    cells = CHART[assy]
    mark = ' <span class="dag">*</span>' if assy in SINGLE_SOURCE else ""
    head = (f'<td class="assy">{assy}{mark}</td>'
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

<p class="lead"><b>DRAMscope names the failing data bit, D0 to D7</b>, and that bit number
holds on every C64 ever made. <b>Which chip carries it does not</b> &mdash; that depends on
which board you have, and translating one into the other is what this chart is for.</p>

<h2>1 &nbsp; Find your assembly number</h2>
<p>Look for <span class="mono">ASSY</span> followed by six digits, printed on the board itself
&mdash; <span class="mono">ASSY 250469</span> or similar. <b>Scan the whole board</b>; this
chart does not claim a position, because two published descriptions of one turned out to be
wrong. &#9888; Do not guess from the case or the badge: the same case housed several different
boards.</p>

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
 <div class="cols">
  <div>
   <p><b>The bit is measured. The chip is a suggestion</b> &mdash; which is why the screen says
   <span class="mono">LIKELY</span>. <b>What else could be at fault depends on how many bits
   failed</b>, and the <span class="mono">BITS</span> row tells you that.</p>
   <p><b>One bit.</b> The fault is on that data line; the RAM is the likeliest part on it, but a
   dry or cracked joint, a corroded or spread socket contact, or a broken track to the CPU are
   <b>indistinguishable to any software test</b>. ⚠ The address and control logic <i>cannot</i>
   do this &mdash; it is shared by all eight chips, so a fault there takes more than one bit.</p>
   <p><b>Four bits in one nibble, two-chip board.</b> Still one chip: a 41464 is four bits wide.</p>
  </div>
  <div>
   <p><b>Several bits, or all eight &mdash; probably not a RAM chip at all.</b> These are shared
   by the whole array, so one failure takes many bits at once:</p>
   <p style="margin-left:2mm"><b>U13</b>, <b>U25</b> &mdash; 74LS257 address multiplexers<br>
   <b>U14</b> (74LS258), <b>U26</b> (74LS373) &mdash; VIC/CPU address switching<br>
   <b>RP1</b>, <b>RP2</b> &mdash; 330&nbsp;&#937; series packs on those lines<br>
   <b>U17</b> &mdash; the PLA, which gates <span class="mono">/CAS</span> to the RAM<br>
   <b>VIC-II</b> &mdash; generates RAS/CAS and the refresh</p>
   <ol style="margin-top:1.4mm">
    <li><b>Reseat the chip</b> &mdash; forty-year-old socketed RAM is a fault by itself.</li>
    <li><b>Inspect and reflow</b> its joints and socket.</li>
    <li><b>Check continuity</b>, RAM pin to CPU pin.</li>
    <li><b>Only then swap it</b>, keeping the old chip until the repair is confirmed.</li>
   </ol>
   <p style="margin-top:1.3mm">If the same bit still fails with a new chip, the fault may be
   elsewhere on that line &mdash; <b>or the replacement is bad too.</b> These parts are long out
   of production, so try a second from another source before ruling the RAM out.</p>
  </div>
 </div>
</div>

<h2>Colour RAM is not a DRAM</h2>
<p>A separate 1K&nbsp;&times;&nbsp;4 static chip. It causes wrong colours rather than a crash,
which is why it gets blamed on the VIC. DRAMscope gives it its own verdict and <b>never counts
it against the DRAMs</b>. And when <b>every</b> bit fails it names no chip at all, saying
<span class="mono">SEE PLA</span> &mdash; eight dead RAMs is not the likely reading.</p>

<div class="foot">
  <div><b>Sources:</b> Commodore schematics <b>251138</b> (250407) and <b>252278</b> (250466),
  cross-checked against the opencbm Hardware Reference and Repair Guide, myoldcomputer.nl and
  open KiCad board replicas. <b>Every row is confirmed by two independent sources that agree on
  all eight bits.</b> Full evidence in PROVENANCE.md.</div>
  <div style="text-align:right; white-space:nowrap">MIT licensed &middot; <b>no warranty</b><br>
  ko-fi.com/bitbarista</div>
</div>

<div class="page2">

<div class="head">
  <div>
    <h1>If you have to replace one</h1>
    <p class="sub">Buying, substituting and proving a repair</p>
  </div>
  <div class="ver">DRAMscope {VERSION} &middot; page 2<br>github.com/bitbarista/dramscope</div>
</div>

<div class="advisory">
  <h2>&#9888; Two kinds of statement on this page, marked apart</h2>
  <p style="margin:0 0 1.2mm 0">Page 1 is derived from schematics and checked by the project's
  own tests. <b>This page is not.</b> So everything here is labelled:</p>
  <p style="margin:0"><span class="tag">FACT</span> has a named source in the footer and can
  be checked. &nbsp; <span class="tag">PRACTICE</span> is judgement &mdash; what repairers
  generally do &mdash; and is <b>not</b> a fact about your machine.
  <b>Nothing on this page is tested by DRAMscope or verified on hardware by this project.</b></p>
</div>

<h2>The parts <span class="tag">fact</span></h2>
<table class="parts">
  <thead><tr><th style="width:21%">Board</th><th style="width:25%">Part</th><th>Detail</th></tr></thead>
  <tbody>
    <tr><td>Eight RAM chips</td><td class="pn">4164</td>
        <td>64K&nbsp;&times;&nbsp;1 DRAM, 16-pin DIP. <b>On the majority of 4164-class chips
        pin&nbsp;1 is unused</b>, marked N.C.</td></tr>
    <tr><td>Two RAM chips</td><td class="pn">41464<br>also 4464</td>
        <td>64K&nbsp;&times;&nbsp;4 DRAM. Both names are used for this organisation.</td></tr>
  </tbody>
</table>
<p><b>Makers did not use a common naming standard, so the same part carries many numbers.</b>
Published cross-references list, among others:
<span class="mono">MB8264</span>, <span class="mono">HM4864</span>,
<span class="mono">M3764</span>, <span class="mono">MT4264</span>,
<span class="mono">M5K4164</span>, <span class="mono">MK4564</span>,
<span class="mono">MCM6665</span>, <span class="mono">&micro;PD4164</span>,
<span class="mono">KM4164</span>, <span class="mono">TMS4164</span>,
<span class="mono">TMM4164</span>, <span class="mono">AM9064</span>,
<span class="mono">MN4164</span>, <span class="mono">HYB4164</span>.
&#9888; Prefixes are not reliable maker badges &mdash; published lists disagree about who made
what &mdash; so match the <i>organisation</i> and the speed, not the letters.</p>
<p><b>Speed.</b> C64s shipped with parts marked <b>150&nbsp;ns</b> and <b>200&nbsp;ns</b>. A
lower number is a faster part and meets a slower requirement; a slower part than the board was
designed for does not.</p>

<h2>If you cannot find a 4164 &mdash; the 41256 substitution <span class="tag">reported</span></h2>
<p><span class="tag">fact</span> A <span class="mono">41256</span> is 256K&nbsp;&times;&nbsp;1.
<b>The only pinout difference from a 4164 is pin&nbsp;1</b>: not connected on the 4164, the
ninth address line <span class="mono">A8</span> on the 41256.</p>
<p><span class="tag">reported</span> The published method is to tie <b>pin&nbsp;1 to
pin&nbsp;16 (ground)</b> with a short wire so <span class="mono">A8</span> cannot float. The
chip then addresses only its lower 64K and, in C64-Wiki's words, &ldquo;look[s] just like a
&rsquo;64 chip to the system&rdquo;.</p>
<p>&#9888; <b>Documented, but not tested here.</b> This project has not built one and makes no
promise about current draw, timing margin or how a given board behaves. DRAMscope will tell you
whether the result works.</p>

<div class="box" style="margin-top:2.4mm">
<h3 style="margin:0 0 1.4mm 0">Practice, not fact &mdash; this is judgement, and yours may differ</h3>
<div class="cols">
 <div>
  <p><b>Treat every replacement as unproven.</b> These parts left production decades ago, so
  what is on sale is new-old-stock or desoldered pulls &mdash; and a pull may have come off a
  board <i>because it failed</i>. Buy more than you need.</p>
  <p><b>Fit a socket</b> if the RAM was soldered directly; the next swap is then minutes rather
  than a desoldering job. &#9888; The risk is in the removal &mdash; old through-plated holes
  lift pads easily.</p>
  <p><span class="tag">fact</span> <b>On socket types</b>, machined (&ldquo;turned-pin&rdquo;)
  contacts are a multi-finger collet intended for <b>round</b> pins; dual-wipe contacts bear on
  the two broad faces of a flat DIP lead. Both have failure modes &mdash; cheap dual-wipe
  contacts deform, machined collets damage more easily. <b>Which to fit is disputed among
  repairers and this page takes no side.</b></p>
 </div>
 <div>
  <p><b>A repair order</b>, cheapest and most reversible first:</p>
  <ol style="margin-top:0.8mm">
   <li><b>Reseat the chip.</b></li>
   <li><b>Inspect and reflow</b> its joints and socket.</li>
   <li><b>Check continuity</b>, RAM pin to CPU pin.</li>
   <li><b>Only then swap it</b>, keeping the old chip until the repair is confirmed.</li>
  </ol>
  <p style="margin-top:1.3mm">If the same bit still fails with a new chip, the fault may be
  elsewhere on that line &mdash; <b>or the replacement is bad too.</b></p>
  <p><b>Prove it by running it, and run it warm.</b> A single clean pass says the fault is not
  present right now, not that the machine is well. Marginal cells pass on a cold machine and
  drop bits an hour later, which is why the run counter and the burn-in exist.</p>
 </div>
</div>
</div>

<div class="foot">
  <div><b>Sources:</b> part numbers and &ldquo;pin&nbsp;1 unused on the majority of 4164-class
  chips&rdquo; &mdash; minuszerodegrees.net, pcbjunkie.net and amiga-stuff.com cross-reference
  lists. 41256 method and the 150/200&nbsp;ns markings &mdash; C64-Wiki (<i>RAM</i>),
  corroborated on 6502.org and Lemon64. Socket contact types &mdash; arcade-museum, Parallax
  and modwiggler discussions. <b>Nothing here is tested by this project.</b></div>
  <div style="text-align:right; white-space:nowrap">MIT licensed &middot; <b>no warranty</b><br>
  ko-fi.com/bitbarista</div>
</div>

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
    if pages != PAGES:
        sys.exit(f"CHIP-CHART.pdf is {pages} pages -- it must be exactly {PAGES}. "
                 f"Page 1 is the chart and page 2 the advisory; anything else means "
                 f"one of them has overflowed. Tighten the CSS or cut copy.")
    print(f"  {OUT_PDF.relative_to(ROOT)}  {OUT_PDF.stat().st_size:,} bytes")
    print(f"  {len(CHART)} assemblies, taken from test/chart.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
