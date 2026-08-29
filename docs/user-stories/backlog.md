# Backlog — specified but not yet scheduled

Stories that are fully analysed but have no milestone yet. They live here rather than in a
milestone folder so a closed milestone's "all N stories merged" claim stays true, and so the
analysis is captured while it is fresh instead of being re-derived at the next planning
session. Precedent for why that matters: the ±121 coordinate trap sat as a journal
carry-forward from 2026-07-09 to M2 planning, and was then mis-scoped twice by review before
it became US-210.

Milestone planning picks these up and assigns them a place; the ID stays stable so existing
ADR and journal references keep resolving.

---

## US-312 — Thread colours do not survive export, and nothing tells the user

**Epic**: E7 Export & sharing | **Estimate**: ~3 h | **Discovered**: 2026-08-29, US-308 manual Ink/Stitch verification

**Problem**: the app shows the design in the thread colours the program set, and the exported
`.dst` cannot carry them. **Tajima DST stores no colour at all** — only stitch coordinates and
colour-*change* commands — so every viewer and every machine assigns its own palette per block.
Verified two ways rather than assumed: this repo's writer emits no RGB anywhere
(`DSTFile`/`DSTHeader`/`DSTStitchRecord` contain no colour bytes), and Catroid's reference
writer likewise tracks only `colorChangeCount`.

Measured on the first file exported through the app path (`squareCoil`, named "SquareCoilexp"):
the design sets `#1d4ed8` for the inner half and `#f59e0b` for the outer; Ink/Stitch drew the
inner half **pink** and the outer **green**. The *structure* round-tripped exactly — `CO:2`, one
colour change at record 1489 of 2976 (50.0%), extents 53.40 × 52.80 mm matching the app's own
summary to the millimetre — so this is a **fidelity-of-expectation** problem, not a byte
problem. Nothing on screen prepares the user for it, which makes a correct export look broken.

**Why it is a story rather than a note**: US-308's whole value proposition is that what you name
is what the machine displays. The colour half of that promise is one a user will reasonably
assume and the format cannot keep, and they will meet it the first time they open their own
file.

**Options to weigh at planning** (none decided — that is the story's job):
- Say so in the app: a line near the share control, or in the share sheet's preview, that thread
  colours are chosen on the machine. Cheapest, and honest.
- Ship a **companion colour file** beside the `.dst`. Several toolchains read a sidecar for
  per-block colours; which formats are actually read by Ink/Stitch and by common machines is the
  research this story owes, and it interacts with the exported UTType (ADR-026) and with sharing
  two files instead of one.
- Write the colours into a format that does carry them. Out of scope for M3's DST-only promise
  (ROADMAP E7) and a much larger change.

**Not** a defect in US-308: ADR-012 pins the byte semantics, ADR-015 pins when a colour change is
emitted, and both are met. ADR-026 records the finding.

---

**Otherwise empty.** The mechanism worked as designed and is worth recording:

- **US-211 — DST serialization field-width chokepoint.** Specified here at discovery time on
  2026-07-31, scheduled into M3 on 2026-08-04 →
  [`milestone-3/US-211-dst-field-width-chokepoint.md`](milestone-3/US-211-dst-field-width-chokepoint.md).
  Its status line said "Candidate for M3, where the export path forces the decision this
  story needs", and that is exactly what happened: the three-way choice (clamp / throwing
  init / bound at the app layer) was resolved during M3 planning once the export path existed
  to be the caller, and two facts that only surfaced then changed the answer — ADR-007's stage
  bounds do not exist as code, and `DSTHeader.init` is a second public trapping entry point
  this file never listed. Deciding it in isolation would have picked the wrong option.

Also settled by M3 planning, though they were ADR-020 consequences rather than backlog
entries: the `hasValidPattern`-vs-replay export-gating divergence and the adversarial-coordinate
question are now placed in
[`milestone-3/US-308`](milestone-3/US-308-design-name-and-dst-export.md) and
[`milestone-3/US-211`](milestone-3/US-211-dst-field-width-chokepoint.md) respectively.
