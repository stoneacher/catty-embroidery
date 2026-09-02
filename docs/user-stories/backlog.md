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

## US-313 — Zoom and pan do not feel native: no live two-finger centroid

**Epic**: E4 Stage & preview | **Estimate**: ~5 h | **Discovered**: 2026-09-02, US-309 device session (Sebastian, iPhone 17 Pro)

**Problem**, in the user's words: "pinching really only zooms in/out of the canvas and does not
register side-to-side movements in parallel", against the behaviour every iOS user has from
Maps and Photos — where two fingers zoom **and** translate at once, about the point between
them, continuously.

**This is not a missing `.simultaneously`.** `StageCanvas.inspectGesture` already composes
`MagnifyGesture().simultaneously(with: DragGesture())` and already reads `startAnchor`. Two
concrete things make it feel wrong, and they are separable:

1. **`DragGesture` is a single-touch recogniser.** Native two-finger manipulation pans by the
   *centroid* of the two touches; SwiftUI's `DragGesture` has no concept of one. With two
   fingers down its translation is not the midpoint, so lateral movement during a pinch is
   largely dropped — exactly the symptom reported.
2. **`startAnchor` is captured once, at gesture start.** Zoom is therefore anchored where the
   pinch *began* rather than following the fingers as they move, so content drifts away from
   under the touch during a long pinch.

`DragGesture`'s default 10 pt `minimumDistance` compounds both, and ADR-028 records why it
cannot simply be set to zero: `minimumDistance: 0` claims the touch and makes the double-tap
reset a byte-for-byte no-op. That trade was measured, not assumed.

**The tension to resolve first, and it is an ADR-level decision.** The idiomatic fix is UIKit
interop — either `UIScrollView` via `UIViewRepresentable` (free centroid zoom, rubber-banding,
momentum) or a `UIPinchGestureRecognizer`/`UIPanGestureRecognizer` pair with simultaneous
recognition, reading `location(in:)` for the live centroid. **Both conflict with ADR-028's
load-bearing decision that the transform is written once, in `onEnded`, and never during the
gesture.** That single commit is what makes "the settled raster re-bakes exactly once per
gesture" *structural rather than timed* (ADR-028, criterion 3), and it is what lets
`StageZoom.commit` drop a whole state machine. A scroll view writes continuously. So this
story cannot be taken as a UI change alone: it must either preserve the single-commit property
under a continuous recogniser, or ADR-028 must be revisited with its consequences re-derived.

**Sequencing against US-309.** US-309 measured the mid-gesture path on an iPhone 17 Pro at
**median 69.1 ms, p99 136.2 ms** per drawn frame at 50 000 stitches — roughly 14 fps, a
decisive miss of ADR-009's bar. A *better* gesture makes that path more prominent, not less,
because users will hold gestures longer and expect momentum. **Take ADR-029's fallback ladder
rung 2 (decimate the mid-gesture `.entire` plan) before or with this story**, or a more
responsive gesture will simply expose the rendering cost more often.

**Not scheduled**: it is a genuine usability gap rather than a defect — the gestures work, they
are merely not idiomatic — and it carries an ADR revision. It wants a planning session that can
weigh the single-commit invariant against native feel, with the M3 exit criterion already
answered.

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
