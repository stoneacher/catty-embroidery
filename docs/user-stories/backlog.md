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

**Placement, decided 2026-09-14**: **not** taken into M3. It changes no bytes and no gesture, and
its sidecar option is better decided once M5's file handling exists to decide it against.
Candidate for **M4 or M5**.

---

## US-314 — The stage is not frozen under the fingers while the design is still growing

**Epic**: E4 Stage & preview | **Estimate**: ~3 h | **Discovered**: 2026-09-14, `/codex-review`
round 2 on US-313a

**Problem**: ADR-028's baseline is `settled ?? fit`, and `fit` is a *per-frame parameter* the view
recomputes from the display list's bounds. While the user has never zoomed — `settled == nil`,
"following the fit", the state a fresh stage is in — a run whose design grows beyond the hoop
changes `StageGeometry.fitTarget(including:)`, and therefore changes the fit, the bake key and the
drawn transform **mid-manipulation**. The stage shifts under the fingers, and the point a finger
grabbed is no longer under it.

**Reproduction** (Codex's, at viewport 100 × 100): a fresh interaction, `panBegan`, `pinchBegan` at
(20, 20), `pinchChanged(to: 2)`, then render once with `fit.scale == 1` and once with
`fit.scale == 0.5` without ending the manipulation. The grabbed stage point maps to x = 20 in the
first frame and x = 0 in the second, and `bake` changes between them.

**Why it is not US-313a's**: it is pre-existing — US-307 shipped this and US-313a changes nothing
about it. What US-313a did was *claim* the invariant more loudly (its AC10 said "`bake` is
identical across every frame of a manipulation"), so that criterion is narrowed to "at a constant
fit" rather than left overstating what the code does. The fix is a design decision this story
should not take in passing: a manipulation needs a **frozen baseline** distinct from `settled`,
because pinning `settled` at gesture start instead would take the stage permanently off the fit
and contradict ADR-028's rule that an identity gesture must not do that.

**Scope when scheduled**: a `manipulationBaseline` captured at the first channel's begin and
cleared at commit or cancel, read by `baseline`, `rendering`, `transform` and `commit` while a
manipulation is live; an ADR-028 amendment recording that "the baseline cannot move while fingers
are down" is now enforced rather than assumed; and a test that drives two different fits through
one manipulation, which is the shape every existing test misses by passing the same `Self.fit`
every frame.

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

- **US-313 — Zoom and pan do not feel native: no live two-finger centroid.** Specified here on
  2026-09-02 from the US-309 device session, scheduled into M3 on 2026-09-14 and **split in
  two** at planning →
  [`milestone-3/US-313a`](milestone-3/US-313a-manipulation-as-a-package-value.md) (the headless
  manipulation value) and
  [`milestone-3/US-313b`](milestone-3/US-313b-two-fingers-reach-the-stage.md) (the recogniser
  pair, the accessibility gap, the device session). **The mechanism paid for itself twice
  over**, and in the opposite direction to US-211: this entry's analysis was not merely
  incomplete, it was **wrong in a way that would have produced a defect**. It named two
  separable causes; the second — "`startAnchor` is captured once … content drifts away from
  under the touch" — is not a defect at all, and the fix it implies (a live anchor) is off by
  `(1 − m)(c₁ − c₀)`, so building it as specified would have *introduced* the drift the entry
  wanted removed. The frozen start anchor is the correct formulation and the single-touch pan
  channel was the whole bug. The entry's central premise — that the fix "conflicts with
  ADR-028's load-bearing decision" and therefore "carries an ADR revision" — was also wrong:
  it conflicts with ADR-028's *wording*, not its substance, so the outcome is a dated
  amendment plus ADR-031, and ADR-030 §7's inherited invariant is **satisfied rather than
  traded**. The entry's own suggested mechanism (`location(in:)` per frame) is the wrong input,
  and the bridge it implies (`UIGestureRecognizerRepresentable`) is iOS 18 against an iOS 17
  floor. Nine corrections in all. **What the entry got right is what mattered**: the user's own
  words, the sequencing against rung 2, and the instruction to weigh the single-commit
  invariant at a planning session rather than in a hurry.

Also settled by M3 planning, though they were ADR-020 consequences rather than backlog
entries: the `hasValidPattern`-vs-replay export-gating divergence and the adversarial-coordinate
question are now placed in
[`milestone-3/US-308`](milestone-3/US-308-design-name-and-dst-export.md) and
[`milestone-3/US-211`](milestone-3/US-211-dst-field-width-chokepoint.md) respectively.

## US-315 — The canvas and the hoop come apart while the keyboard animates

**Epic**: E4 Stage & preview | **Estimate**: unknown until reproduced — the diagnosis *is* the
story | **Discovered**: 2026-09-17, US-313b device session (Sebastian, on the phone)

**Problem**: focusing the design-name field glitches the drawn canvas while the keyboard animates
in or out — the **design and the hoop field are briefly drawn at different transforms**, so the
design sits off-centre and spills outside the hoop onto the mat. Visible in the session's screen
recording at 3.01 s with the keyboard mid-dismiss. Every *committed* state before and after is
correct; this is a transient, which is the class ADR-028 records as invisible to stills and which
has now produced three defects in this milestone.

**Already ruled out, written down so the next attempt does not spend the same hour.** Two
mechanical explanations were built and **refuted by reading the code**:

1. *A stale cached raster composited into the new size.* `CanvasStitchLayers.BakeKey` includes
   `width` and `height`, so a resize changes the key, `baked?.key != bakeKey`, and
   `compositingRaster` returns false — the frame takes the full-stroke path at `transform.current`.
2. *An explicit `settled` transform that does not follow the viewport.* True of `settled` itself,
   but the hoop field is drawn by `StageFieldView(transform: render.current)` — the **same** value
   the renderer strokes with, so the two cannot disagree by that route.

**Not reproducible on the simulator**, tried three ways: focusing the field from a fresh fit (the
export row hides, so the canvas resizes with no keyboard at all); with the software keyboard
enabled; and at 200 % zoom with `settled` non-`nil`. All settle correctly, and no intermediate
frame showed the mismatch when sampled at 20 ms from a 60 fps `simctl recordVideo`.

**Next step, and it is a question rather than a fix**: the missing variable is the interaction
state before focusing — had the stage been zoomed or panned, and does it reproduce from a fresh
fit? A device recording of both discriminates. After that, the two remaining suspects are SwiftUI
snapshotting and scaling a view whose frame is animating (the canvas would be a *rendered* layer
being interpolated rather than re-stroked), and the `SettlingProgress` shim's captured closure
holding a `fitted` from the previous layout pass — `StageCanvas` documents that staleness and
argues it is safe because a manipulation and a fit animation cannot coexist. **A keyboard resize
is neither**, so that argument does not cover this case.

**Not US-313b's.** Nothing that story changed is on this path: the catcher is an overlay that draws
nothing, and the renderer, the bake key and the field are untouched by it. The interaction is
US-308's name field against US-305's canvas.

---

## US-316 — The mid-gesture tail survives both rungs of the ladder, and the next experiment is named

**Epic**: E4 Stage & preview | **Estimate**: unknown until the fixture exists — the measurement
*is* the story | **Discovered**: 2026-09-17, US-313b's AC12/AC13 controls; carried out of M3 at
its close on 2026-09-19 as the one thing standing between the milestone and its own 60 fps exit
criterion.

**Problem**: every mid-gesture capture at 50 001 stitches still reads FAIL on the bar, and on the
tail alone — worst frame **50.008 ms** in US-310's device session and **38.076 ms** in the cleanest
capture to date (2026-09-18), against a bar of 33.3 ms. Median and p95 are both at one refresh
period, so this is a tail, not a throughput problem.

**Both standing explanations are refuted by measurement, which is what makes this a story rather
than a rung.** ADR-029's ladder has now been re-pointed twice. Rung 1 (the bake schedule) cannot
touch a path that never bakes — US-309's device session. Rung 2 (draw fewer segments) landed in
US-310, moved the median from 69.1 ms to 16.670 ms on device, and **did not move the tail at any of
four stride values**; doubling the target left the worst frame *identical* at 50.008 ms. US-313b's
two control criteria then closed the door from the other side: a 3 194-stitch design drawing *more*
uncoarsened segments than the coarsened 50 001-stitch one runs at exactly one refresh period, while
halving the coarsened count changes nothing. **The mid-gesture frame cost is not the number of
segments drawn**, and the gesture-end commit — the suspect ADR-030 named — is not it either, since
the tail is present in a capture holding a single gesture that is never released.

**The named experiment, recorded in ADR-029 as a hypothesis rather than acted on**: the two designs
differ in *area covered* far more than in geometry, so fill rate and overdraw are the candidate. A
**50 000-stitch fixture covering a small area** discriminates — if it sits at the floor, area is the
variable and the tail is a rasterisation cost rather than a planning one. This repo has no such
fixture, and building it is the story's first half.

**Open at planning, nothing decided**: whether the discriminator is a new `Samples` design or a
test-only synthetic (they answer different questions — only a sample can be captured on device with
the shipping instrument); whether a positive result implicates `Canvas` blending or the dot
ellipses specifically; and whether the answer touches **ADR-009's bet itself** rather than its
constants, which is the outcome that would matter most and the one no evidence yet supports.

**Blocks** the A15-class capture M3 carried out alongside it: confirming a fix on A15 requires
there to be a fix. Read ADR-029's 2026-09-18 amendment before taking any capture for this story — a
capsule `PASS` is not on its own sufficient evidence for the bar's dropped-frame clause.
