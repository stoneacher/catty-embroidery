# US-313b — Two fingers reach the stage: the recogniser pair, the a11y gap, the tail discriminator

**Status**: **Planned — 2026-09-14.** The second half of backlog entry US-313, split at planning
time. Everything here either needs a simulator or needs a human with two fingers on a device —
which is the whole reason for the split: US-313a's red phase can be shown for all of its
criteria without either. Planned with `swift-architect` and `swift-ui-design`. Sebastian took
four scope decisions, recorded in [US-313a](US-313a-manipulation-as-a-package-value.md).

**Epic**: E4 Stage & preview | **Estimate**: ~4 h | **Depends on**: **US-313a** (the tracker it
feeds), US-310 (the instrument and the protocol)

## Story

As a user inspecting a design, I want the two-finger manipulation US-313a made correct to
actually reach the stage — and, if I use VoiceOver, I want to be able to reach the corners of my
own design.

## What this story is

US-313a proves the manipulation math against synthetic fingers under `swift test`. Nothing
consumes it. This story replaces the SwiftUI gesture composition with a UIKit recogniser pair,
takes the two accessibility items that became due, and runs the device session — including the
**tail discriminator**, folded in from M3's final-verification list.

## Design

### 1. The catcher

`StageManipulationCatcher.swift` — a `UIViewRepresentable` plus a
`Coordinator: NSObject, UIGestureRecognizerDelegate` installing three recognisers:

- `UIPinchGestureRecognizer` — `scale`, and `location(in:)` read **once** at `.began`.
- `UIPanGestureRecognizer`, `minimumNumberOfTouches = 1`, `maximumNumberOfTouches = 2`. Its
  `translation(in:)` is the **centroid** translation of its touches and stays continuous when a
  finger is added or removed. That is the single missing input, and it is why the pair beats a
  hand-rolled `UIGestureRecognizer` subclass: rolling your own means re-implementing the
  centroid re-basing, which is the thing that visibly jumps when it is wrong.
- `UITapGestureRecognizer(numberOfTapsRequired: 2)` — the double tap moves in here so all
  hit-testing lives in one place, and so ADR-028's `minimumDistance` trade can be retired.

`shouldRecognizeSimultaneouslyWith` returns `true` for the pinch/pan pair. The view is
`accessibilityElementsHidden = true` and is not itself an accessibility element.

**No arithmetic in the coordinator.** Each action method reads the recogniser's plain numbers
and calls the US-313a tracker. That is what makes the interesting half testable, and it is
ADR-028's own rewrite lesson applied one level further out: the area with the worst defect
history in this repo had zero automated cover, and six review rounds found the same conceptual
mistake in four spellings.

**Three lifecycle rules the ADR must pin**, because two recognisers make "one gesture"
ambiguous:

1. **Liveness is the union of the two recognisers' `state`s**, asked of the recognisers, never
   inferred from values (ADR-028's own lesson, verbatim).
2. **The commit fires when the *last* active recogniser ends**, not when either does. Otherwise
   lifting one finger mid-manipulation commits the pinch while the pan continues — two `settled`
   writes, and therefore two full re-bakes of a 50 000-stitch prefix back to back at finger-lift,
   exactly where ADR-030 says the tail already lives.
3. **`.cancelled` and `.failed` are handled explicitly.** `@GestureState` clears itself for a
   system-cancelled gesture; a coordinator does not. Miss it and an incoming call leaves the
   stage permanently live, `canUseRaster` false forever, the design coarse forever. This is the
   most likely defect of the approach and it has a named test in both halves.

### 2. The `StageCanvas` surgery

`@GestureState private var gesture: StageGesture?` becomes `@State private var manipulation =
StageManipulation()`; `inspectGesture(...)` and `static reading(_:)` are deleted; `.gesture(...)`
and `.onTapGesture(count: 2)` are replaced by an `.overlay { StageManipulationCatcher(...) }`
**inside the `SettlingProgress` shim**, so the closures still capture `animated`. ADR-028's
Codex-round-8 fix must survive verbatim — a catcher constructed outside the shim reintroduces
the snap-to-destination bug.

`AppModel` is unchanged: the tracker stays view-local, because touch delivery is per-view and a
size-class change that destroys the view also cancels the recogniser. Same lifetime as today's
`@GestureState`; ADR-028's "two call sites" argument applies to `interaction`, which stays where
it is.

### 3. The two accessibility items that became due

**Directional pan actions.** `StageInteraction.adjust` anchors on `viewport.center`, so zoom is
reachable without gestures but **pan is not**: an assistive user can zoom to 3× and then only
ever see the middle of their design. Four named actions — Pan Left / Right / Up / Down by ~25 %
of the viewport — over US-313a's pure `panned(by:)`. Six rotor actions total is acceptable;
check the catalog names read as speakable Voice Control commands. This is the honest completion
of what ADR-028 calls "the one feature added for users who cannot pinch".

**The deferred string caching.** ADR-028 handed it to US-309 and US-309 did not take it. On a
finished design every body evaluation rebuilds label, hint and value, and the value runs
`Measurement.FormatStyle` twice with a wide unit style — tens of microseconds a call, per frame,
on precisely the path US-310 ground down to a 16.667 ms median. Memoise on
`(summary, state, roundedPercent)`. This story is what makes the path hotter, so this story
takes it.

**Not at risk, stated so nobody re-litigates it**: the ADR-028 criterion that the stage summary
is written only on run-state transitions. A gesture is not a run-state transition. Separately,
the spoken zoom percentage *does* change per frame mid-pinch — benign, because VoiceOver
intercepts direct touches so a VoiceOver user never drives that path, but named here rather than
discovered later.

### 4. What is deliberately not built

- **Momentum / deceleration.** Not an omission — derived. Momentum frames are *live* frames,
  each a coarse full re-stroke at 50 000 stitches, and they defer the commit and its re-bake to
  the end of deceleration, holding the stage coarse for ~1 s after release, at the moment the
  user has stopped acting and started looking. It is also the one Maps behaviour that is wrong
  for bounded content: a 100 mm hoop at 1–3× is a couple of viewport widths and a fling has
  nowhere to go.
- **Rubber-banding**, and therefore **pan clamping**, its prerequisite. Clamping is the valuable
  half and it is a real gap — ADR-028 ships the pan unclamped and says so, and a better gesture
  means users fling further and hit it more often. It needs package math ADR-028 did not budget.
  **Its own story**, named here so it is not smuggled in.
- **Rotation.** `StageTransform` is uniform scale plus translation; hoop orientation is
  meaningful and a rotatable preview would misrepresent it.
- **Refine-on-pause** (re-plan fine when the transform has been still for ~150 ms). Recorded
  with its cost attached: it puts a timer back into a decision ADR-028 deliberately made a pure
  function of the phase, and going fine currently means flipping `canUseRaster`, which would
  *bake* mid-gesture — the exact hazard ADR-030 exists to prevent.
- **Viewport-culled planning.** At 10× only a fraction of the design is on screen; a culled plan
  would draw every stitch of what is visible for the same budget, solving fidelity and cost
  together. `StitchDrawPlan`'s type doc forbids it ("keeps the plan transform-free"), so it needs
  a transform-aware layer above the plan. ADR-level, beside rungs 3 and 4.
- **The compact-width `NavigationStack` interactive-pop conflict.** A two-finger pan never
  conflicts with the single-finger screen-edge pan, so the two-finger path escapes it for free;
  a one-finger pan keeps the existing conflict, which is the shipped state and not a regression.
  A UIKit delegate could now address it — recorded, not fixed. **The fix improves the case it
  improves and does not claim the other.**

## Acceptance criteria

1. **The catcher installs a pinch, a pan and a double-tap recogniser** with the stated
   parameters and a delegate.
2. **The pinch and the pan recognise simultaneously.**
3. **The double tap is not gated on the pan failing** — panning is not delayed by the
   double-tap interval.
4. **A recogniser action sequence drives the tracker and commits exactly once**:
   `began → changed → changed → ended` changes the bound `StageInteraction.settled` once.
5. **A cancelled recogniser leaves no live state** — the app-level companion to US-313a's AC8.
6. **The double-tap toggles fit ↔ ~2× about the tapped point**, with fit always one tap away.
7. **The catcher is not an accessibility element**, asserted on its own flags. **Deliberately
   not a tree walk**: US-307 records a hosted accessibility-tree test that passed locally and
   failed unreproducibly on CI, and was deleted.
8. **The stage is still exactly one accessibility element** after the representable lands —
   verified with the Accessibility Inspector, not by a test, because of 7.
9. **Four directional pan actions exist, are reachable, and move the stage** by ~25 % of the
   viewport.
10. **The accessibility strings are computed once per `(summary, state, roundedPercent)`**, not
    once per body evaluation.
11. **The renderer sees live-then-settled across a manipulation**: extend `StageViewWiringTests`'
    `RecordingRenderer` — `bake` constant while live, one change at the end.
12. **The four device captures below**, with `drawn/n` recorded on each.
13. **`liveSegmentTarget = 2000` is re-verified on device under the new gesture**, since a
    better gesture may raise the touch-move rate and therefore the draw rate. US-313a changes
    the constant on simulator evidence; this criterion is what makes it a measured decision.
14. **ADR-031 is written and ADR-028 takes its five dated corrections** — the ADR work belongs
    to US-313a, but correction 3 (the `minimumDistance` trade) is **re-measured here**, under
    UIKit, rather than reasoned about.

## The device protocol, and the tail discriminator folded in

Same instrument as US-310 (`-US310FrameTimes`, Release with `DEBUG`, 60 Hz confirmed, quantiles
over **drawn frames only**, `drawn/n` recorded and compared like-for-like — a capture reading the
animating signature is discarded, which is the error ADR-030's session made and corrected).

| # | Capture | Bar |
|---|---|---|
| 1 | 50 001, sustained two-finger pinch **and** pan, never released, ≥ 10 s | median and p95 stay at one refresh period (ADR-030's clean row: `med 16.670 p95 16.670`); `drawn/n` ≥ 0.6 |
| 2 | 50 001, several short two-finger drags, same duration, **gesture-ends counted** | tail against #1: if p99/worst scale with the number of ends rather than with `drawn`, the commit hypothesis is confirmed and the residual is rung 1's |
| 3 | 3 194 (Octagon Rosette) mid-gesture control | unchanged from ADR-030 capture 10 — floor throughout |
| 4 | 50 001 animating | unchanged from ADR-030 capture 09 (`drawn=251`, p99 16.670). A regression here means the new liveness source is leaking into the animating path |

**Why the discriminator belongs here rather than in M3's final verification**, which is where it
was parked:

1. This story changes the variable it measures — gesture-ends per unit of user activity. A
   before/after is only interpretable if it is run on both sides.
2. It gets *cheaper and cleaner*: "one gesture that is never released" becomes a single sustained
   two-finger manipulation with a high, steady draw rate, instead of an alternating pinch/pan
   sequence that ADR-030 had to discard once for carrying the animating signature.
3. **It makes US-310's hand-off capture 1 performable as originally written** — "pinch *and*
   pan, since a pinch redraws on every touch move" — the instruction the 2026-09-14 session had
   to correct in place because the shipped app could not honour it. Re-running it as specified is
   a dated closure of that correction.

**One piece of new code makes #2 an observation instead of an inference**, and ADR-029 already
names it as the cheapest thing to add: a `#if DEBUG` `StageCommitCounter`, mirroring
`StageDrawCounter` exactly (main-actor enum, non-observable, `record()` at the commit call site),
printed as `commits=` beside `drawn=` in `FrameTimeReadout`. ~20 lines, one app test:
`theCommitCounterCountsManipulationsNotFrames`.

## Test-first plan

New file `catrobat_embroidery_ios/catrobat_embroidery_iosTests/StageManipulationCatcherTests.swift`,
following `StageViewWiringTests`' hosting idiom (`UIWindow`, explicit frame, forced layout).

1. `theCatcherInstallsAPinchAPanAndADoubleTapRecognizer` (AC1)
2. `thePinchAndThePanRecognizeSimultaneously` (AC2) — call the delegate method directly
3. `theDoubleTapIsNotGatedOnThePanFailing` (AC3)
4. `aRecognizerActionSequenceDrivesTheTrackerAndCommitsOnce` (AC4) — stub recogniser subclasses
   with a settable `state` via `import UIKit.UIGestureRecognizerSubclass`
5. `aCancelledRecognizerLeavesNoLiveState` (AC5)
6. `theDoubleTapTogglesFitAndTwoTimesAboutTheTappedPoint` (AC6)
7. `theCatcherIsNotAnAccessibilityElement` (AC7)
8. `theStageOffersFourDirectionalPanActions` (AC9)
9. `theAccessibilityStringsAreComputedOncePerDistinctState` (AC10)
10. `theRendererSeesLiveThenSettledAcrossAManipulation` (AC11) — extend `StageViewWiringTests`
11. `theCommitCounterCountsManipulationsNotFrames`

**Flagged for the red phase, not to be taken from the plan**: that a settable `state` on a
recogniser stub works at all. If it does not, item 4 degrades to driving the coordinator's action
method through a hand-rolled protocol seam — which is arguably the better design anyway and would
push more of item 4 into the package.

## Visual definition of done

Screenshots at two zoom levels **plus a mid-manipulation frame**. ADR-028's process lesson
applies directly: stills of the committed state cannot show a defect that exists only *during* a
gesture, and both of the defects Sebastian found in US-307 were of exactly that kind. Sample the
simulator continuously through a scripted drag.

## Human-only checks

The UI automation available here is single-finger (`npx xcodebuildmcp ui-automation tap`), so a
pinch cannot be synthesised at all. On device:

1. Two-finger centroid tracking 1:1 — content stays under both fingers through a long combined
   pinch-and-drag, and does not drift over a long pinch.
2. Translation continuity when a second finger lands or lifts mid-gesture — **verify the
   `UIPanGestureRecognizer` re-basing claim, do not trust the plan**.
3. That the pan's slop still lets the double tap through under UIKit — **re-measure** ADR-028's
   finding rather than assuming it transfers.
4. Compact-width leading-edge behaviour: two-finger pan versus the interactive pop.
5. iPad with a Magic Keyboard trackpad: does the recogniser pair receive a trackpad pinch as
   `MagnifyGesture` did?
6. The three in-the-hand judgement questions ADR-030 still owes — the coarse image at two zoom
   levels, the pop at gesture start and commit, the stride discontinuity at
   `liveCoarseningThreshold` — now answerable under a gesture worth judging.
7. Accessibility Inspector: one element, the new actions reachable, the names speakable.

## Relationship to M3's final verification

This story **supplies** two of the milestone's open items — the tail discriminator, and US-310's
hand-off capture 1 as originally written — and it makes a third (the A15 re-run) cheaper by
sharing a session. The bundled manual accessibility pass must run **after** this story, and its
checklist gains AC8 and AC9 explicitly.

## Manual Ink/Stitch verification

**Not needed.** No byte path is touched.
