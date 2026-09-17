# US-313b — Two fingers reach the stage: the recogniser pair, the a11y gap, the tail discriminator

**Status**: **Implemented 2026-09-16, reviewed 2026-09-17, device session 2026-09-17 —
AC8, AC9, AC12 and AC13 are met, and ADR-028 correction 3 is measured. Only capture 3's floor
check is outstanding.**
**236 app tests** (up from 200) and **810 engine tests** (up from 804), SwiftLint `--strict`
clean, CI green on all three checks, [PR #47](https://github.com/stoneacher/catty-embroidery/pull/47).
Five simulator captures including a mid-drag frame. Planned with `swift-architect` and
`swift-ui-design`; Sebastian took three further scope decisions on 2026-09-16 (below), alongside
the four recorded in [US-313a](US-313a-manipulation-as-a-package-value.md).

**Two review layers, 32 findings, none rejected.** `swift-code-reviewer` found 1 critical
(a system cancel left the coordinator suppressed, swallowing the next whole touch sequence) and
6 important, four of which were mutations that survived the suite — including the pan translation
this story exists to deliver. `/codex-review` then ran **3 rounds, 12 findings, severity
High → Medium → Low**, closing on **both** stop conditions: no code change in the last round, and
two consecutive decreases. Its High was the one defect reading the diff could not surface —
`UIView.isMultipleTouchEnabled` defaults to `false`, so the touch-counting view saw one finger
while its recognisers saw two, and the stage committed with a finger still down. **Thirteen of the
32 findings were "this assertion cannot fail"**, on a branch both reviewers agreed behaved
correctly.

**The story's own design shipped a defect, and the planning pass found it.** Its three lifecycle
rules are individually right and jointly incomplete: with the pan still `.possible` — two fingers
pinching without passing its slop — the pinch's `.ended` correctly declines to commit while
touches remain, and then the **last finger lifts with no recogniser left to send an action**.
Nothing asks again, the manipulation stays live forever, `canUseRaster` stays false and the design
stays coarse for the rest of the session: rule 3's catastrophe reached through rule 2's door. A
touch-counting view supplies the missing terminal signal.

**Three of the eleven test items were not buildable as written**, and the red phase refuted a
fourth premise by executing it. AC3 asks a question UIKit has no getter for; AC9's is the
accessibility-tree walk US-307 deleted for CI flakiness; the commit-counter test asserted on
process-wide state from a parallel suite. And the proposed stub recogniser with a settable
`state` **compiles and is silently ignored** — measured on a booted iPhone 17 — so the stubs
override instead. Four tests the story did not have were added; the ADR records why.

**Scope decisions (Sebastian, 2026-09-16)**

1. **The directional pan actions are camera-relative** — "Pan Left" moves the viewport left, so
   the design's left-hand side comes into view and the design itself slides right. A named
   action is a word, and every spoken or typed direction uses the camera convention.
2. **Both VoiceOver hints are rewritten** (~75 Crowdin re-translations each). Neither mentioned
   panning, and the *running* hint named no recovery at all — and the pan is deliberately
   unclamped, so a user who pushes a running design off the canvas had nothing telling them the
   way back.
3. **ADR-031 and ADR-028's five corrections land here.** US-313a specified both and wrote
   neither, while `docs/ROADMAP.md` already claimed "ADR-031 pins it"; journalled as a
   close-out miss.

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
8. **Begin a manipulation *during* a fit animation** — double-tap to start the toggle, then put
   two fingers down while it is still moving — and say whether the stage takes over smoothly from
   where it visibly is, or snaps to where the animation was heading. Added after `/codex-review`
   round 2: the automated guard for this (that `updateUIView` keeps handing the coordinator the
   shim's current progress) could not be made deterministic, so this step is what covers it, and
   check 6's "pop at gesture start" does **not** — it judges a gesture begun from rest.

## Relationship to M3's final verification

This story **supplies** two of the milestone's open items — the tail discriminator, and US-310's
hand-off capture 1 as originally written — and it makes a third (the A15 re-run) cheaper by
sharing a session. The bundled manual accessibility pass must run **after** this story, and its
checklist gains AC8 and AC9 explicitly.

## Device session, 2026-09-17

**In the hand**: every item verified, "intuitive and very smooth" (Sebastian). That covers centroid
tracking, the add/remove-finger continuity the plan took on trust, the double tap under UIKit
(**ADR-028 correction 3 measured, not reasoned about**), the compact-width edge, the trackpad, and
ADR-030's three outstanding judgements.

**AC12 — the discriminator is conclusive.** Capture 2 has a third of capture 1's drawn frames and
13× its commits, and its tail is *worse* (p99 48.936 → 76.683). ADR-030's unclaimed tail is the
gesture-end commit and its re-bake. Rows are in ADR-030.

**A second sustained capture** (screenshot 07) reads `n=545 drawn=487 commits=1 med 35.854 p95
48.677 p99 51.303 max 57.149@12.8s · 18.4 s`. It reproduces capture 1 (34.281 → 35.854) and
reinforces the discriminator from the other side: one commit, a high draw ratio, and a tail
*well below* capture 2's thirteen-commit one (p99 51.303 against 76.683).

**AC13 passes, settled by an A/B rather than by argument.** Both gesture captures sit at a ~34 ms
median against ADR-030's 16.670, and three variables had moved at once — the constant, the device,
and a gesture now driving `drawn/n` to 0.94 against 0.6. Flipping `liveSegmentTarget` back to 1 000
and re-running capture 1 on the same phone in the same session isolated it: **35.769 at 1 000
against 34.281 and 35.854 at 2 000** (screenshot 11). Halving the drawn segments changed nothing
measurable, so the raise is confirmed free on real hardware under the gesture that was supposed to
threaten it — and, more usefully, **the mid-gesture frame is not dominated by the segment count in
this range**, which re-points ADR-029's remaining rungs away from drawing less. The engine's own
stride assertion caught the flip within seconds, which is what it was written for.

Capture 3 (the 3 194 control) still needs a re-run with `-US310FrameTimes` — a scheme argument
applies only to a launch from Xcode. It is the floor check, not a claim this story rests on.

**AC8 passes.** Accessibility Inspector, on device: one `SwiftUI.AccessibilityNode`, traits exactly
`Image` + `Adjustable`, the label, the zoomed value and the rewritten hint all correct.

**AC9 passes on content, *failed on order*, and is now fixed and re-verified.** All five custom
actions were present (the Inspector lists eight: those five plus `Activate`, `Increment` and
`Decrement`, which the traits imply), but they appeared in **reverse declaration order**, putting
Fit to Hoop last — behind the four pans a user would need it to recover from. The planning pass
called this out as unassumable, which is the only reason it was looked for. Reversing the modifiers
on one observation is itself an inference, so it was **re-read on device** rather than assumed
(screenshot 06): the list now reads Fit to Hoop, Pan Left, Pan Right, Pan Up, Pan Down. That shot
incidentally confirms two more things live — the value carries no zoom phrase at the fit, and the
rewritten hint reads in full.

**Audit findings, triaged**: one contrast warning (`#0091FF` on `#FFFFFF`, 3.23 at 14 pt) — Apple's
own tint on the share row, real against WCAG AA for normal text, recorded for the milestone
accessibility pass rather than fixed here. Four "Dynamic Type font sizes are unsupported" — **false
positives**: every font in the app is a semantic text style, and `DesignNameField` already reflows
at AX1 (US-308). The flagged nodes are the stage, which contains no text at all, and SwiftUI's own
`UIKitTextField`. The behavioural check — AX1 on device — is the milestone pass's, not the audit's.

**Found during the session, and not this story's**: focusing the design-name field glitches the
drawn canvas during the keyboard's resize — the design and the hoop field are briefly drawn at
different transforms. Reproduced from Sebastian's recording, **not** reproducible on the simulator
(fresh fit, keyboard up, or at 200 % zoom), and both mechanical explanations were refuted by reading
the code: `CanvasStitchLayers.BakeKey` includes the viewport, so a resize does invalidate the cached
raster, and the field and the design are drawn through the same `transform.current`. Filed as its
own story rather than widening this one; it lives in the US-308 name-field ↔ canvas interaction and
nothing links it to this story's changes.

## What this story leaves open, named so it is not rediscovered

- **A directional pan gives an assistive user no feedback.** VoiceOver announces nothing after a
  *custom* action and a pan does not change the spoken value, so four activations are four silent
  events — and the pan is unclamped, so they can put the design off the canvas entirely. Recorded
  in ADR-031 and handed to the deferred **pan-clamping story**, which owns both halves.
- **The `minimumDistance` trade (ADR-028 correction 3) still needs its device measurement.** Under
  UIKit it is inherited and non-configurable rather than retired — which is what this story's own
  text got wrong — so human check 3 is what closes it.
- **Pre-existing, unchanged by this story**: `StageInteraction.magnification(gesture:fitting:in:)`
  takes no `settlingAt:`, so the *spoken* zoom percentage jumps to a fit animation's destination
  the instant `withAnimation` runs — ADR-028's Codex-round-8 class of bug, in the accessibility
  value rather than in the render. Identical on `main`; recorded because this story moved the call
  site and doubled the ways to start that animation (`swift-code-reviewer`, S13).

## Manual Ink/Stitch verification

**Not needed.** No byte path is touched.
