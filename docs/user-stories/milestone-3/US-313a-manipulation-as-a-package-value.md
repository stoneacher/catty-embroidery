# US-313a — The manipulation is a package value: centroid pan, latched pinch, one commit

**Status**: **Planned — 2026-09-14.** Split out of backlog entry US-313 at planning time, which
came in at 7–9 h against its own ~5 h estimate. Planned with `swift-architect` and
`swift-ui-design`; **the planning pass corrected nine things in the backlog specification**,
marked **planning correction** inline, and the central one inverts the story: the backlog names
two separable causes and **only the first is real**. Sebastian took four scope decisions,
recorded under "Scope decisions". This half is entirely headless — package types under
`swift test`, no simulator — and is independently mergeable, because the tracker can be built
and fully tested before anything consumes it. US-313b puts fingers on it.

**Epic**: E4 Stage & preview | **Estimate**: ~4 h | **Depends on**: US-307, US-310 |
**Discovered**: 2026-09-02, US-309 device session (Sebastian, iPhone 17 Pro)

## Story

As a user inspecting a design, I want two fingers to zoom **and** move the stage at once, about
the point between them, the way every iOS app does — so the preview feels like a thing I am
holding rather than a control I am operating.

In the user's own words, from the device session: *"pinching really only zooms in/out of the
canvas and does not register side-to-side movements in parallel."*

## Problem, restated correctly — the backlog's diagnosis is half wrong

The backlog names two causes. **Cause 1 is the entire bug. Cause 2 is not a defect, and
implementing it as written would introduce the drift it means to remove.** This is the story's
first planning correction and it is load-bearing, so it is derived here rather than asserted.

`StageInteraction.moved(by:from:fitting:in:)` composes

```
baseline.pinched(by: m, about: a, within: bounds).dragged(by: p)
```

`pinched(by:about:)` sets the translation so that the stage point under view point `a` stays at
`a` (`StageTransform.swift`: `translated = anchor − anchoredStagePoint × zoomed`). `dragged(by:)`
adds `p` uniformly. So a point sitting at view position `x₀` under the baseline lands at

```
v(x₀) = m·(x₀ − a) + a + p
```

Native two-finger manipulation is uniquely determined by two requirements: the scale is the
ratio of the fingers' separation, and **each finger keeps the stage point it grabbed**. Take
fingers at view points with centroid `c₀` and separation `d₀` at the start, `c₁` and `d₁` now.
Substituting `m = d₁/d₀`, `a = c₀`, `p = c₁ − c₀`:

```
v(x₀) = m·(x₀ − c₀) + c₁
```

which is exactly where each finger now is. **The package math is already native.** The three
inputs it needs are the cumulative separation ratio, **the start centroid as anchor**, and
**the centroid delta as pan**. Only the last is missing: `StageGesture.pan` is fed from
`DragGesture`, a single-touch recogniser with no concept of a centroid, so lateral movement
during a pinch is largely dropped — precisely the symptom reported.

**Planning correction 1 — cause 2 is wrong, not merely unnecessary.** A *live* anchor `a = c₁`
alongside the correct pan gives `m·x₀ − m·c₁ + 2c₁ − c₀`, which differs from the correct result
by `(1 − m)(c₁ − c₀)`. The frozen start anchor is not a shortcut that causes drift; it is the
correct formulation. Any criterion asking for a "live anchor" is struck.

**Planning correction 2 — the backlog's named mechanism is the wrong input.** It proposes
"reading `location(in:)` for the live centroid", which produces exactly the anchor above. The
correct inputs are `UIPinchGestureRecognizer.scale`, `UIPanGestureRecognizer.translation(in:)`
— which UIKit re-bases across touch-count changes, so it is jump-free when a finger lands or
lifts — and `location(in:)` read **once**, at pinch begin, corrected into the baseline frame.

**Planning correction 3 — the `minimumDistance` claim is overstated.** The backlog says the
10 pt threshold "compounds both". It produces a one-off start offset (ADR-028 measured 101
committed against 91 shown, then removed the compensation); it does not compound a centroid
error. Its only live role is protecting the double tap, and that role ends when the tap moves
into the same recogniser set (US-313b).

## The ADR-028 tension dissolves — this is an amendment, not a revision

The backlog parks the story on a conflict: the idiomatic fix "conflicts with ADR-028's
load-bearing decision that the transform is written once, in `onEnded`, and never during the
gesture". **Planning correction 4: it conflicts with the wording, not the substance.**

ADR-028's single commit justifies three things, and only the third is load-bearing for
performance: the settled raster re-bakes exactly once per gesture, *structurally*, because
`BakeKey` reads the transform. That does not depend on `onEnded`. It depends on
`StageInteraction.settled` not being written mid-gesture. ADR-028's own 2026-08-18 correction
already split presentation from commit — `StageRenderTransform.live(bake:current:)` gives a
continuous presentation transform against a frozen bake transform. **The architecture the
backlog asks for already exists and ships.** What is single-touch is only the input that
produces `current`.

So `settled` is still written exactly once per manipulation, `bake` is still frozen for its
duration, `canUseRaster` still stays `false` while the transform differs from the committed
one, and **ADR-030 §7's inherited invariant is satisfied rather than traded**. That paragraph
warned US-313 not to commit continuously; this story does not.

**Planning correction 5 — `UIScrollView` is not a live option, and the rejection is recorded so
it is not re-proposed.** Two ways to host a `Canvas` in one, both bad: at viewport size, UIKit
scaling its layer mid-gesture reproduces exactly the defect ADR-028's 2026-08-18 correction
reversed (a `Canvas` rasterises only its own bounds, so content dragged back into frame stays
missing until the gesture ends — found in the running app during US-307); at content size, the
canvas rasterises the whole design at every zoom level, which is strictly worse than today at
50 000 stitches and undoes US-310. It also writes the transform continuously, which flips
`canUseRaster` true mid-gesture — ADR-030's warned-of case. The scroll view's real answer is
tiled re-rendering (`CATiledLayer`), which is ADR-029 rung 4 territory: a milestone, not a
story. Secondary: it would own the geometry, making `StageTransform` derived from
`contentOffset`/`zoomScale` — two representations of one fact, the failure mode this repo has
now paid for three times — and `StageZoomBounds`' fit-aware floor is viewport-dependent where
`minimumZoomScale` is a scalar, with no scroll-view equivalent of `settled == nil`.

**Planning correction 6 — the modern bridge is unavailable at this deployment target.**
`UIGestureRecognizerRepresentable` is iOS 18.0 and `SpatialEventGesture` (the only pure-SwiftUI
API exposing per-touch locations, and therefore a computable centroid) is iOS 18.0; the project
is `IPHONEOS_DEPLOYMENT_TARGET = 17.0` and `.iOS(.v17)`. Verified against the installed SDK
interface, not from memory. `MagnifyGesture.Value` exposes `startAnchor` and `startLocation`
only — both *start* values — so there is no live centroid in SwiftUI at any version below 18.
`UIViewRepresentable` it is, and **ADR-004's iOS 17 floor is not amended for one story's
convenience**.

**Planning correction 7 — ADR-028 partially retracts.** It claims the single commit means
`StageZoom.commit` "needs no captured baseline, no rebasing and no per-channel end bookkeeping
— a state machine … which the single commit deletes entirely". **That state machine comes
back**, because two UIKit recognisers have independent lifecycles: a pinch begins only at two
touches and ends when a finger lifts, while a pan with `maximumNumberOfTouches = 2` continues
on one. The improvement over ADR-028's situation is that it now lives in a `Sendable` value
type in `StagePreview` under `swift test`, rather than as four pieces of `@State` in a view —
which is ADR-028's own rewrite argument applied one level further out, and which makes
`onlyTheFinalCumulativeValueIsApplied` assertable for the first time (ADR-028 records it
collapsing to `once == once` because "applied exactly once" was a fact about the view).

## Scope decisions (Sebastian, 2026-09-14)

1. **Split into US-313a / US-313b.** 7–9 h realistically against the backlog's ~5 h, on the file
   with the worst defect history in the repo (ADR-028's interaction layer took 6 and 8 review
   rounds across two stories). The split is not cosmetic: this half has the derived-not-asserted
   content and no simulator dependency; the other half's definition of done is a human with two
   fingers on a device.
2. **The double-tap becomes a toggle** — fit ↔ ~2× about the tapped point — rather than the
   shipped reset-to-fit. More native, and fit stays one tap away, so the recovery path assistive
   users rely on is preserved. The *math* is this story; the recogniser is US-313b.
3. **`liveSegmentTarget` rises from 1 000 to 2 000.** ADR-030's device session measured it free
   (median, p95 and worst identical at both values) and explicitly left it to the author. It
   halves the coarse-image pop, which matters more once gestures are held longer. **Re-verified
   on device in US-313b under the new gesture**, since a better gesture may raise the touch-move
   rate and therefore the draw rate.
4. **Directional pan accessibility actions.** `StageInteraction.adjust` anchors on
   `viewport.center`, so an assistive user can zoom to 3× and never reach their design's
   corners — a live gap in the shipped app. The pure `panned(by:)` math is this story; the four
   named actions are US-313b.

## The `.live` gating, where the two planning passes disagreed — and where the plan was wrong

`swift-ui-design` proposed gating `.live` on `!gesture.isIdentity`, because
`StageInteraction.rendering` goes `.live` the instant `gesture != nil` — so the image degrades
on touch-down, while nothing has moved, which is a pop on a *stationary* frame and the most
visible kind. `swift-architect` proposed asserting `canUseRaster == false` for **every** frame
of a manipulation. Both cannot stand.

**Resolved at planning in favour of the gating, and that resolution is wrong.** The argument was
that at touch-down the bake key is still the committed transform, so the settled path draws an
already-cached raster and nothing is re-baked. **The bake key is not the transform alone.**
`CanvasStitchRenderer.BakeKey` carries `settledCount` and `resetCount` as well, and the settled
watermark *advances while a run is still producing stitches*. So a resting frame reporting
`canUseRaster` mid-gesture permits a bake at a **new** watermark — a full rasterisation of the
settled prefix, during the gesture, at whatever the design has reached. That is ADR-028's Codex
round 2 defect ("a gesture returned to its baseline reported settled and let the raster rebuild
mid-gesture") arriving by a different route, and it is the expense ADR-009's cache exists to
avoid.

**Implementation correction, 2026-09-14: the architect's position stands, for a reason neither
planning pass gave.** Two existing tests — `aGestureAtItsBaselineIsStillLive` and
`presenceNotMagnitudeDecidesLiveness`, written for ADR-028's rounds 2 and 3 — went red within a
minute of the gate being implemented and are the reason this was caught rather than shipped.
Process rule 3 applies in spirit: the red test was right and the new design was wrong, so the
design changed. The gate is reverted, the rule is restated in `rendering`'s own comment with the
`settledCount` reason attached, and AC11 is inverted (below).

**The fidelity pop it was meant to fix is real and now explicitly unaddressed.** It is one frame
at touch-down only if the finger moves immediately; a finger resting on the stage holds the
coarse image for as long as it rests. Fixing it needs the *plan* to refine without the *bake key*
becoming usable — the two are currently coupled through `canUseRaster`, which is the same
coupling US-313b records against refine-on-pause. Recorded there as a candidate with its cost
attached, not smuggled in here.

## Acceptance criteria

1. **A two-finger manipulation keeps both fingers on the stage points they grabbed.** Given a
   baseline transform and two synthetic fingers moved by a known scale and translation, each
   finger's start stage point maps to that finger's current view position, within a stated
   tolerance. This is the story's reason to exist and it is red today.
2. **A pinch that begins after the pan has already moved is anchored in the baseline frame**:
   `anchor = centroidAtPinchBegin − panAtPinchBegin`. Without the correction the result is off
   by `(m − 1)·panAtPinchBegin`.
3. **Lateral centroid movement during a pinch moves the stage** by that amount — the user's
   complaint, minimally stated: constant separation, translating centroid.
4. **The magnification is cumulative, never accumulated** — 2, 2, 2 lands at 2×, preserving
   ADR-028's correctness clause across the new input path.
5. **A manipulation yields exactly one commit value**, at the last active channel's end. Ending
   one channel while the other is live yields none. This is the assertion ADR-028 records as
   unobtainable by a package test; moving the decision into the package is what obtains it.
6. **The committed value is the last live value** — ADR-028's "live and committed are the same
   number by construction", preserved.
7. **A latched magnification survives the pinch ending while the pan continues**: the derived
   transform is continuous across the channel end, with no snap toward 1×.
8. **A cancelled or failed manipulation commits nothing and clears liveness.** The failure this
   guards is worse than the bug being fixed: a stuck-live tracker means a permanently coarse
   plan that never re-bakes. Today's `@GestureState` cannot fail this way, which is why the
   backlog does not name it. **Planning correction 8** — added.
9. **Liveness is presence, not magnitude**: a pinch back to exactly 1× and a pan back to its
   origin are still live. Mirrors `StageInteractionTests.presenceNotMagnitudeDecidesLiveness`,
   which four Codex rounds paid for.
10. **`bake` is identical across every frame of a manipulation and changes exactly once**, and
    `StitchDrawPlan.forFrame` returns the coarse plan on **every** frame of a manipulation at
    50 001 stitches — moved or not, per the correction above. ADR-030 §7's inherited invariant,
    observed rather than restated. **The `bake` half was already green** and stays as a
    regression guard rather than being claimed as a red: what it pins is that the *new input
    path* cannot take the invariant away.
11. **A resting manipulation — fingers down, nothing moved — is still live**, and its bake key
    is the committed transform. **Inverted 2026-09-14 during implementation**: this criterion
    originally said the opposite (that an identity gesture renders from the settled path), and
    the section above records why that was wrong and what caught it.
12. **`panned(by:)` and the double-tap toggle exist as pure package math**, tested headlessly:
    a directional pan of ~25 % of the viewport, and fit ↔ ~2× about a given view point with the
    fit branch reachable from any state.
13. **A zero viewport anchors at the centre** — totality before layout settles, matching
    `StageTransform.fitting`'s house rule.
14. **Rotation is deliberately not recognised** and this is recorded, not left implicit:
    `StageTransform` is uniform scale plus translation, so a rotation is unrepresentable.
15. **`StagePreviewTargetIsolationTests` still compiles nothing UIKit-shaped across the
    boundary**: a `CGPoint` or a `UIGestureRecognizer.State` reaching the package stops the test
    target building.
16. **`liveSegmentTarget` is 2 000**, with the existing coarsening tests re-derived at the new
    value rather than re-blessed.

## Test-first plan

Swift Testing only, parallel-safe, no shared mutable state. **Run them and show them red before
any implementation.** Most reds here will be *compile failures* (the tracker does not exist), so
the discriminating assertions must additionally be proved by **mutation**, per US-308's and
US-309's precedent.

### New file: `Packages/EmbroideryEngine/Tests/StagePreviewTests/StageManipulationTests.swift`

Ordered; 1–3 are the ones that fail against today's behaviour.

1. `bothFingersStayUnderTheStagePointsTheyGrabbed` (AC1)
2. `aPinchThatBeginsAfterThePanHasMovedIsAnchoredInTheBaselineFrame` (AC2)
3. `lateralCentroidMovementDuringAPinchMovesTheStage` (AC3)
4. `theMagnificationIsCumulativeNeverAccumulated` (AC4)
5. `endingOneChannelWhileTheOtherIsLiveProducesNoCommitValue` (AC5)
6. `aManipulationYieldsExactlyOneCommitValue` (AC5)
7. `theCommittedValueIsTheLastLiveValue` (AC6)
8. `aLatchedMagnificationSurvivesThePinchEnding` (AC7)
9. `aCancelledManipulationCommitsNothingAndClearsLiveness` (AC8), and the same for `.failed`
10. `presenceNotMagnitudeDecidesLiveness` (AC9)
11. `aZeroViewportAnchorsAtTheCentre` (AC13)

### Edits to existing files

12. `StageInteractionTests` — `theBakeTransformIsUnchangedForEveryFrameOfAManipulation` and
    `anIdentityGestureRendersFromTheSettledPath` (AC10, AC11), driving N updates and collecting
    `rendering(gesture:fitting:in:)`.
13. `StageInteractionTests` — the directional pan and the double-tap toggle (AC12).
14. `StagePreviewTargetIsolationTests` — bind the tracker's methods to explicit function types
    (AC15).
15. `StitchDrawPlanCoarseningTests` — re-derive at `liveSegmentTarget = 2000` (AC16).

### Restating-not-observing risk

US-309's mutation survivor was a test that *restated* the settle rule instead of observing it.
The tempting-but-worthless tests here are "the anchor equals the start centroid", "the pan
equals the centroid delta" and "the stride is unchanged mid-gesture". Items 1, 2, 3 and 12 are
their observational replacements. For each discriminating test apply the standing question:
**what production code could I delete while this stays green?**

### Already green / not written, with reasons

- **ADR-029 rung 2 "before or with this story"** — already satisfied; US-310 merged 2026-09-14.
  Kept as context, dead as a dependency clause. **Planning correction 9.**
- **"The draw-plan layer keeps choosing the coarse window"** as a *change* — vacuous;
  `forFrame` keys on `canUseRaster` only and is agnostic to gesture provenance (US-310 §7). The
  useful form is the non-regression assertion in item 12.
- **"Zoom and pan feel native"** as an assertion — not assertable. UI automation here is
  single-finger, so a pinch cannot be synthesised at all. It is a named human check in US-313b.
- **`moved(by:)`, `StageTransform`, `StageZoomBounds`, `StageGesture`** — unchanged. Flagged
  explicitly: if the implementation needs to touch `moved(by:)`, the derivation above has been
  misread.

## File-by-file change list

**New**: `Packages/EmbroideryEngine/Sources/StagePreview/StageManipulation.swift` — an
`Equatable, Sendable` struct owning both channels' liveness, the baseline-frame anchor, the
latched magnification, the accumulated pan, and unit conversion against the viewport. Surface:
`panBegan(at:)`/`panChanged(to:)`/`panEnded()`, `pinchBegan(scale:centroid:)`/`pinchChanged(to:)`/
`pinchEnded()`, `cancelled()`, `var gesture: StageGesture?` (presence *is* liveness — ADR-028's
"an optional cannot be wrong the way a value comparison can"), `finish() -> StageGesture?`
(non-`nil` exactly once). Channel and phase enums as **siblings, not nested** (SwiftLint
one-level nesting under `--strict`, per ADR-030's `Segment` precedent).

**Edited**: `StageInteraction.swift` (the `!gesture.isIdentity` gate, `panned(by:)`, the toggle),
`StitchDrawPlan+Coarsening.swift` (the constant), and the four test files above.

**Unchanged, deliberately**: `StageGesture.swift` — the tracker does the `ViewPoint → unit`
conversion internally, so `anchorUnitX/Y` keeps its meaning and two green suites keep theirs.
Storing an absolute `ViewPoint` anchor is cleaner in isolation but churns them for no
behavioural gain.

## ADR consequence

**ADR-031** (new) pins the manipulation layer: the derivation above, the two-channel lifecycle,
the single commit at the last channel's end, `UIViewRepresentable` over
`UIGestureRecognizerRepresentable` with the iOS 17 reason, the `UIScrollView` rejection, and the
deliberate absence of rotation and momentum.

**ADR-028** takes five dated corrections in place (house style — ADR-030 corrected ADR-029's
rung-2 wording the same way):

1. "written once per gesture, in `onEnded`" → **"written once per manipulation, at the last
   channel's end"**. The property is unchanged; its mechanism moves into the package, where it
   becomes observable by a test.
2. The "deletes entirely" claim about the state machine is **partially retracted** (correction 7
   above).
3. The `minimumDistance: 0` / double-tap trade is **superseded, not overturned** — it was
   measured and true *of SwiftUI's `DragGesture`*. It must be **re-measured** under UIKit in
   US-313b, not reasoned about.
4. "`startAnchor` is captured once … content drifts" → **the frozen start anchor is correct**;
   record the algebra.
5. ADR-030 §7 is **satisfied, not renegotiated**.

## What cannot be proven headlessly

Everything about fingers. Carried to US-313b: that two fingers produce a live centroid at all,
that `UIPanGestureRecognizer.translation(in:)` really is jump-free across a 2→1 touch change
(the basis of AC7 — **verify at the red phase, do not take it from this plan**), the four
frame-time captures, and the human judgement of feel.

## Manual Ink/Stitch verification

**Not needed.** No byte path is touched.
