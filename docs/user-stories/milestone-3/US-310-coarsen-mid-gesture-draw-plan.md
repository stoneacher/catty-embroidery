# US-310 — Coarsen the mid-gesture draw plan

**Status**: **In progress** — planned 2026-09-03 with `swift-architect`. The story's own premise
check (AC1) ran **before** any code change and answered **go**; the numbers are in "Premise"
below. **The planning pass corrected nineteen things**, marked **planning correction** inline —
including two in ADR-029's own rung-2 wording and one that made AC1 unexecutable as first
written.

**Epic**: E4 Stage & preview | **Estimate**: ~5 h | **Depends on**: US-305, US-306, US-307,
US-309 | **Rung**: ADR-029 fallback ladder, **rung 2**

## Story

As a user inspecting a large design, I want pinch and pan to stay responsive at 50 000
stitches, so the stage is usable at the scale ADR-009 promised.

## Problem

US-309 turned ADR-009's rendering bet into evidence and the answer was **half no**. On an iPhone
17 Pro (A19, iOS 26.6, Release with `DEBUG`, 60 Hz link confirmed), quantiles over **drawn
frames only**:

| capture | drawn | med | p95 | p99 | worst | verdict |
|---|---|---|---|---|---|---|
| animating to 50 000 | 251 | 16.669 | 16.670 | 16.670 | 16.703 @13.5 s | **PASS** |
| **50 000, mid-gesture** | 312 | **69.1** | **118.8** | **136.2** | **166.2 @13.8 s** | **FAIL** |
| 50 000 settled, still | **0** | 16.669 | 16.669 | 16.669 | 16.725 @12.8 s | NO DRAWS |

ADR-028 removed the mid-gesture blit deliberately — a `Canvas` rasterises only its own bounds,
so moving an already-rendered layer cannot *reveal* content that was off-screen. The cost of
that decision is that while an interaction is live `StageRenderTransform.canUseRaster` is
`false` and `CanvasStitchLayers.body` takes its `else` branch: `StitchDrawPlan.entire(of:)` over
the whole design, **every frame**. About 14 fps.

ADR-029 re-orders its own fallback ladder on this data — rung 1 tunes `settleChunk`, which
governs *baking*, and the gesture path never bakes — and names **rung 2** as the target:
coarsen the mid-gesture path. This is the work the milestone's exit criterion is waiting on
([README](README.md#exit-criteria)); the A15 confirmation of the *fix* is already a
milestone-level final-verification item and is **not** this story's to close.

## Premise — checked first, with a stated decision rule, before the type change

The story's premise is that the 69.1 ms is **proportional to the primitive count**. That was a
hypothesis, not a measurement, and ADR-029 contains evidence against it: the bake schedule
strokes the same ~50 000 stitches into `Image(size:renderer:)` up to fifty times per run, yet
the animating capture's *worst* frame over 251 drawn frames was 16.703 ms. If a full 50 000-stitch
re-stroke cost 69 ms of main-thread time, some of those frames should have shown it. ADR-029
never reconciles the two. So the check came first, and coarsening was **not** to be implemented
if the cost turned out to be a fixed per-frame overhead.

**Decision rule, fixed before measuring**: capture the mid-gesture drawn-frame median at two
stitch counts on one instrument. A count-independent overhead predicts **equal** medians; a
per-primitive cost predicts **growth** with the count.

Measured 2026-09-03 on the **simulator** (iPhone 17, Release with `DEBUG`, 60 Hz), a held
single-finger pan — three 4-second drags of 80 steps each — over a finished run:

| capture | drawn | med | p95 | p99 | worst | screenshot |
|---|---|---|---|---|---|---|
| 3 194 stitches (Octagon Rosette) | 231 | **16.667** | 16.667 | 37.175 | 43.710 @2.5 s | [01](../../screenshots/us-310/01-sim-3194-mid-gesture-premise.jpg) |
| 50 001 stitches (Synthetic 50k) | 230 | **36.129** | 49.177 | 56.292 | 86.858 @2.4 s | [02](../../screenshots/us-310/02-sim-50k-mid-gesture-premise.jpg) |

**`drawn` is 231 against 230**, which is the control that makes the comparison mean something:
the redraw count is set by the touch-move rate (3 × 80 steps), not by the refresh rate, so both
captures drew essentially the same number of frames and the median difference is **per-frame
cost** rather than a different number of frames. Two independent counts, one instrument, same
draw count.

**Result: growth, so the premise holds.** A fixed per-frame overhead is refuted outright —
it predicts equal medians and the medians differ by 19.5 ms. Decomposing as `C + p·n`, with the
3 194 frame fitting inside one period (the instrument reports display-link *intervals*, so
16.667 ms is a floor, not a reading) and the 50 001 frame at 36.129 ms:

- `p · 46 807 ≥ 36.129 − 16.667 = 19.462 ms` → **`p ≥ 0.416 µs` per stitch**, so **at least
  57 %** (≥ 20.8 of 36.1 ms) of the mid-gesture frame at 50 000 scales with the stitch count.
- `C ≤ 15.4 ms` — an upper bound on whatever is count-independent.

At `k = 13` (the default budget below) the per-primitive share falls by ~13/14, predicting
**36.1 → ≲ 17.3 ms** on this simulator: under the 33.3 ms dropped-frame half of the bar. The
residual `C` is the honest uncertainty and it is bounded, not unknown.

**What this measurement is not.** Simulator absolute milliseconds are not authoritative for
ADR-029's bar — a host GPU is not an A19, let alone an A15, and the device read 69.1 ms where
this reads 36.1. What carries is the **structure**: same instrument, same draw count, two
counts, cost grows. That is the same reasoning ADR-029 uses for its draw counts, which agreed
at `drawn=251` across simulator and device.

**The instrument had to be widened to take this measurement at all** — see planning correction
P19; the change is a launch argument, and it is part of this story.

## Design decisions

### 1. Coarsen, do not dash — and the representation becomes index *pairs*

ADR-029's rung-2 wording, "draw every k-th segment", is **dashing**: it leaves k−1 stitch
lengths of blank fabric between every drawn segment, and it does nothing at all for the dots.
Rejected (**planning correction P3**).

A coarse thread segment instead spans stitch `a → b` with `b − a ≤ k`, so the thread stays
continuous through subsampled vertices. `StitchDrawPlan.Stroke.segmentStarts: [Int]`, whose
contract pins "segment `i` spans stitch `i → i + 1`", becomes `segments: [Segment]` where
`Segment` carries `from` and `to`.

- `Segment` is a **sibling** of `Stroke` and `DotRun`, not nested inside `Stroke`: SwiftLint's
  one-level nesting limit is already load-bearing in this repo and CI runs `--strict` (P12).
- `segmentStarts` is **deleted rather than kept as a shim**, so the single non-test consumer
  (`CanvasStitchRenderer.segmentPath`) fails to compile. A shim would leave the old contract
  alive in the renderer.
- Memory: 16 bytes per segment against 8. At 50 000 that is 800 KB against 400 KB, and only in
  the *un-coarsened* paths. Plans are per-frame temporaries; stated rather than hidden.

A **polyline** representation (vertices, not pairs) was considered and rejected *now*: it is the
more natural expression of continuity, but `segmentPath`'s per-subpath
`guard from.isDrawable, to.isDrawable` (ADR-021 divergence #5, where a rejected coordinate may
legitimately be non-finite) currently loses exactly **one** segment, and a polyline would let one
bad coordinate delete a whole colour run's thread. Recorded as the natural shape for **rung 3**
(`Path` reuse), with that hardening as its price.

### 2. The coarse-span rule

**A coarse segment is thread only if every stitch it spans is joined to the next by thread, and
both endpoints lie in one colour run.**

The planner keeps walking `colorRuns` and each run's owned window, classifying every unit
segment with `StitchSegmentStyle.classifying` exactly as today, while maintaining one open span
anchored at vertex `a`:

- `.thread` → extend the span; on reaching k units emit `(a, i+1)` and re-anchor `a = i+1`.
- `.traversal` → close the open span as `(a, i)`, emit the traversal **verbatim** as `(i, i+1)`
  into the traversal stroke, re-anchor `a = i+1`.
- `.suppressed` → unreachable inside a run, unchanged.
- At the run's last owned segment, close any open span at the run's last stitch.

Consequences, each of which is a test below: **no thread is drawn across a jump** — ADR-024's
named defect of *both* references, which we do not reproduce and must not start reproducing
under decimation; **no span crosses a colour change**, enforced by the iteration as today; and
the coarse route is the fine route with interior vertices skipped, so no run's thread falls
short of its end.

**Traversals are never coarsened**, because merging two jumps would erase a real needle
penetration between them. The budget therefore bounds *thread*, not travel (AC8).

Classification stays O(n): the planner must look at every unit segment to know whether a span
may be joined. **The saving is entirely in the renderer**, which is why no headless timing test
is written (P9).

### 3. Dots are strided per run, not suppressed

`DotRun.indices: Range<Int>` stays and gains `stride: Int`, plus `dottedIndices` and `count` so
the stride semantics live in the package and the renderer cannot get them wrong.

- `[Int]` was rejected: it would allocate up to 50 000 `Int`s per plan in the **un-coarsened**
  paths — every settled bake — turning a fix for the live path into a regression for the settled
  one (P11).
- A stored `StrideTo<Int>` was rejected because `StitchDrawPlan` must stay `Equatable`;
  `StitchDrawPlanWindowTests` compares whole plans.
- **The stride is anchored at each run's own `lowerBound`**, never globally. A global
  `index % k == 0` rule would skip an entire run shorter than k — a thread colour silently
  vanishing mid-gesture. Per-run anchoring gives the assertable rule "every colour run keeps at
  least one dot".
- **Striding, not suppressing**: dot radius equals thread width (`StitchDrawMetrics.dotRadius`),
  so the dots are the beading that makes penetration points read as points. Suppressing them
  makes the design visibly *thinner* the instant a finger lands — a larger visual delta than
  sparser beading, for one further constant factor.

`DotRun`'s current justification for being a `Range` ("**every** entry in the window is dotted —
there is nothing to filter") becomes false and is **rewritten, not extended**. ADR-029 records
precisely this failure mode for `settleChunk`: stale prose sitting directly above the line a
future reader would edit (P15).

### 4. Choosing k — a stitch budget, and why it is not ADR-029's `settleChunk` trap

`coarseningStride(forStitchCount:budget:)` = `count <= budget ? 1 : (count - 1) / budget + 1`.
Spelled that way and not `(count + budget - 1) / budget`, which **overflows** at
`budget == Int.max` — a case the tests exercise (P16).

**Public, pure, and a function rather than a sentence**, which is the direct application of
US-309's most useful result: a test that *restated* the settle rule instead of observing it
passed the mutant, which is why `PreviewRunState.settleWatermark(for:)` exists. The stride rule
gets the same treatment on day one.

`k == 1` at or below the budget, so both shipping samples (3 194 and 2 976) plan **identically**
to `.entire` — asserted by plan equality, not by inspection.

**Is this the negative result ADR-029 records for the proportional `settleChunk`?** No.
`settleChunk` failed because a threshold tracking a continuously growing count moved a
*watermark with a side effect* on nearly every batch — 176 rasterisations instead of fifty. `k`
parameterises a **pure per-frame function whose result is thrown away**: nothing is cached on
it, nothing is triggered by its changing, and at budget 4 000 it changes 12 times across a
50 000-stitch run rather than per batch. The coupling that *would* recreate the trap is rung 3 —
a `Path` cache keyed on the plan is invalidated by k — so rung 3 must key on the plan including
k and expect ~12 invalidations per run. Recorded so it is not rediscovered.

**Starting budget: `liveStitchBudget = 4_000`**, and it is arithmetic rather than measurement:
12.5× below 50 000, above both shipping samples, above the app's `bakingThreshold` of 2 000, and
at k = 13 the premise decomposition predicts ~17.3 ms from 36.1 on the simulator. **It is the
device session's knob**, the same status ADR-029 gives `settleChunk`.

### 5. The switch is a package function keyed on `canUseRaster`

`StitchDrawPlan.forFrame(of:at:compositingRaster:budget:)`, with a documented precedence and all
four cases asserted:

| `transform` | `compositingRaster` | result |
|---|---|---|
| `.live` | `false` | `.coarse(of:budget:)` |
| `.live` | `true` | `.coarse` — a live transform can never composite; the guard comes first |
| `.settled` | `false` | `.entire` — **no valid raster is not a gesture** |
| `.settled` | `true` | `.live` |

The app supplies `compositingRaster` as its existing
`canUseRaster && baked?.key == bakeKey && matches(size, viewport)` conjunction, so no new
plumbing, and the app keeps **zero** window-choice logic — all of it on the fast gate under
`swift test` (ADR-023). Keying on "the renderer took the `else` branch" would have been wrong:
that branch is also taken when there is simply no valid raster (below `bakingThreshold`, key
mismatch, viewport mismatch), which is not a gesture (P7).

**`canUseRaster == false` is a gesture *or* the fit animation** — `StageInteraction.rendering`
returns `.live` when `gesture != nil || isSettling` — so the coarse plan is also drawn during
the double-tap / Fit-to-Hoop spring. That is correct (it is equally a per-frame full re-stroke)
and it is the only *deterministic* way to put the coarse plan on screen for a screenshot. This
story must not call the path "gesture-only" (**planning correction P2**).

### 6. The seam, precisely

There is **no spatial seam**: `coarse` is selected only when `canUseRaster == false`, and in
that state no raster is composited — the coarse plan covers the whole list and is drawn alone.
Two seams do exist and both are stated rather than asserted:

- **A temporal one.** Frame N (fine) → frame N+1 (coarse) at interaction start, and the reverse
  at commit: a visible fidelity pop. The same class of trade ADR-028 already took when it
  accepted that content is revealed only as frames re-stroke.
- **Run boundaries.** A coarse span never crosses one and the fine plan suppresses the boundary
  segment, so the two agree exactly about where thread stops.

`StitchDrawPlan+Planning.swift`'s argument — "one planner parameterised by two windows, rather
than three implementations", because settled and live pixels must be produced by identical rules
or the seam differs in a way no unit test would notice — **survives verbatim and gets stronger**:
`coarse` is not a third implementation but the same `planning` function with a stride parameter,
and `.entire` / `.settled` / `.live` are its stride-1 callers. The identity
`coarse(of: l, budget: .max) == entire(of: l)` is what keeps that true under refactoring.

### 7. What US-313 inherits

Nothing here breaks: the choice keys on `canUseRaster`, not on how a gesture value is produced,
so a `UIPinchGestureRecognizer` pair reaching `StageGesture` changes nothing. The **inherited
invariant is the converse**, and it is why this belongs in the ADR: if US-313 satisfies "live
two-finger centroid" by committing the transform *continuously*, `canUseRaster` becomes `true`
mid-gesture — every frame then takes `.entire` **uncoarsened** *and* `BakeKey.transform` changes
per frame, re-rasterising the settled prefix on every frame, which is **worse than today**.
ADR-028's one-commit-per-gesture rule is what makes this rung effective, and US-313 must not
trade it away unknowingly.

## Acceptance criteria

1. **The premise is measured before the type change, with a decision rule fixed in advance.**
   Two stitch counts, one instrument, mid-gesture drawn-frame medians; growth means implement,
   equal medians mean stop and attribute the cost instead. — **Discharged 2026-09-03: go.** See
   "Premise".
2. A drawn segment is an explicit index **pair**, and in `.entire`, `.settled` and `.live` every
   segment satisfies `to == from + 1`, so no existing window's meaning changes.
3. `coarse(of:budget:)` draws **continuous** thread: for each maximal chain of thread the fine
   plan draws, the coarse plan draws a chain with the same first and last vertex and no gaps
   between consecutive segments. It is not "every k-th segment".
4. No coarse thread segment spans a traversal or a colour change: every constituent unit segment
   of an emitted thread segment classifies `.thread`, and both endpoints lie in one colour run.
5. Traversals are never coarsened: each traversal unit segment appears verbatim as `(i, i+1)` in
   its run's traversal stroke.
6. Dots are strided from each colour run's own lower bound, so every colour run keeps at least
   one dot and no thread colour can disappear mid-gesture.
7. The stride is a **public pure function** of (stitch count, budget) with `k == 1` at or below
   the budget; at the default budget **every** sample in `SampleLibrary.all` plans identically
   to `.entire`, asserted by plan equality.
8. The bound is stated as what it is, not as "≤ N": thread segments
   `≤ ceil(count/k) + colorRuns + traversalCount`, dots `≤ ceil(count/k) + colorRuns`. **The
   colour-run axis is not bounded by this rung** — ADR-029's colour-change-per-stitch design is
   unhelped by it (P6).
9. Coarsening is selected exactly when `canUseRaster == false` (a gesture **or** the fit
   animation), by a package function whose four cases are asserted on the fast gate; the app
   contains no window-choice branch.
10. ADR-009's batching claim holds in the coarse plan too — at most two strokes plus one dot
    path per colour run — asserted on a design **above** the budget, since below it the
    assertion is vacuous (P14).
11. The default budget is documented as a knob with the arithmetic behind it, and the device
    session's job is named. It is not presented as measured.
12. **Device**: the 50 000 mid-gesture capture is re-taken and reported as
    median/p95/p99/worst over drawn frames, at ≥ 2 budget values. ADR-029's bar is quoted
    **unchanged** — US-309's AC8 forbids rewording a criterion in response to a measurement, and
    nothing here rewords it.
13. The fidelity cost is stated: the coarse route may deviate from the true path by up to the
    largest excursion within k consecutive stitches, and the image changes at interaction start
    and at commit. Accepted, reviewed on a screenshot, not asserted.

## Test-first plan

All package tests in `Packages/EmbroideryEngine/Tests/StagePreviewTests/`. **Every red here is a
compile failure** — there is no `coarse`, no `Segment`, no `stride`, no `forFrame` — which is
this repo's norm, so each item names the **mutation** that proves the assertion discriminates.

### New file: `StitchDrawPlanCoarseningTests.swift`

| # | Asserts | Red? | Mutation |
|---|---|---|---|
| T1 | `coarse(of: l, budget: .max) == entire(of: l)` over a fixture family: empty, single stitch, `twoShortRuns`, `firstRunWithALongGap`, an all-traversal run. | Yes (compile). **Vacuous alone** — an implementation ignoring the budget passes; non-vacuous only paired with T3/T10, and the file says so. | Stride hard-wired to 2 → fails. |
| T2 | `coarseningStride(forStitchCount:budget:)`: 1 at `count <= budget`; 1 at `count == budget`; 2 at `budget+1`; 13 at (50 000, 4 000); 1 at count 0; no overflow at `budget == .max`. The rule **observed**, not restated. | Yes (compile). | `<` for `<=` → the `count == budget` case fails. `(count + budget - 1)/budget` → the `.max` case traps. |
| T3 | At `SyntheticDesign.displayList(count: 50_000, colorRuns: 5)`, budget 4 000: thread segments `≤ ceil(50_000/13) + 5 + fineTraversalCount` and dots `≤ ceil(50_000/13) + 5`, **and both ≥ 3 000** — two-sided, because a `coarse` returning nothing sails through an upper bound. `fineTraversalCount` is computed from `entire(of:)` in the test. | Yes (compile). | k forced to 1 → far over the bound. `strokes(for:)` returning `[]` → the lower bound fails. |
| T4 | **Continuity** on a 200-stitch single-colour list of short moves at budget 10: `segments.first!.from == 0`, `segments.last!.to == count-1`, and `segments[i].to == segments[i+1].from` throughout. | Yes (compile). Encodes decision 1. | ADR-029's literal wording — emit `(i, i+1)` for `i % k == 0` — leaves gaps and fails contiguity. |
| T5 | **No thread across travel.** One colour run, short moves with a hop in the middle longer than the budget: for every emitted thread segment `(a,b)`, all unit segments in `[a,b)` classify `.thread`; and the hop appears verbatim as `(t, t+1)` in the traversal stroke. | Yes (compile). | Coarsen without breaking at traversals → fails. Classify a coarse span by its *endpoints* → the whole run becomes travel and both halves fail. |
| T6 | **No coarse segment crosses a colour run.** Multi-run fixture above the budget: every segment's `from` and `to` lie in the same `colorRuns` element, and the stroke's `color` is that run's. | Yes (compile) — the *fine* analogue is covered, this is the coarse one. | Walk the whole list ignoring runs → fails. |
| T7 | **Every colour run keeps a dot.** `displayList(count: 50_000, colorRuns: 1_000)` (run length 50) and `colorRuns: 50_000` (run length 1) at budget 4 000: `plan.dots.count == list.colorRuns.count`, each `dottedIndices` non-empty, each first dotted index `== run.range.lowerBound`, all dotted indices inside their run. | Yes (compile). Encodes the per-run anchoring. | Global stride (`index % k == 0`) → runs shorter than k lose their dot; fails at `colorRuns: 50_000`. |
| T8 | **Exact dot count** on a traversal-free hatch: `dots == Σ ceil(runLength / k)`, computed from `list.colorRuns` in the test. Structural, no clock. | Yes (compile). | Stride applied to the range's *upper* bound, or a k±1 off-by-one → fails. |
| T9 | **`forFrame` picks the window** — all four rows of decision 5, each compared against the window it should equal. **On a list above the budget**, or `.coarse == .entire` and three of the four expectations collapse to one value (P14). | Yes (compile). | Swap the precedence so `compositingRaster` wins → row 2 fails. Drop the coarse branch → row 1. Coarsen on `.settled` → row 3. |
| T10 | **ADR-009's batching bound in the coarse plan**: `strokes.count <= 2 * colorRuns.count` and `dots.count == colorRuns.count`, on the 50 000/5-run fixture. | Yes (compile). **Already green if written against a shipping sample** — the existing suite asserts it for `.entire`, and `coarse == entire` there — so only non-vacuous above the budget. | Emit leftover short spans as a third stroke per run → fails. |
| T11 | **Shipping samples unaffected**: for **every** sample in `SampleLibrary.all` (not `.first` — the existing suite uses `.first` and covers only the rosette, P13), build the list through the interpreter and assert `coarse(of: l, budget: liveStitchBudget) == entire(of: l)` **and** `l.count < liveStitchBudget`. | Yes (compile). | Lower `liveStitchBudget` to 2 000 → both 2 976 and 3 194 stride, fails. This is what makes the constant part of the contract. |

### Edits to existing files

| # | File / change | Red? |
|---|---|---|
| T12 | `StitchDrawPlanTests.swift` — the member-index assertions become the pair form; the `reduce`/`allSatisfy` counts move to `\.segments`. **Churn: no new assertion**, and labelled as such. | Compile-red, proves nothing new. |
| T13 | `StitchDrawPlanWindowTests.swift` — the `segmentStarts` helper becomes `segments(_:)` mapping `\.from`, preserving the partition assertions. **Plus a genuine new assertion**: in `.settled`, `.live` and `.entire` every segment has `to == from + 1` (AC2). | Compile-red; the new half is non-vacuous — mutation: make `.live` coarse → fails. |
| T14 | `StitchDrawPlanScalingTests.swift` — the `settled + tail - 2` bound, justified in-comment by "the renderer reads `start + 1`", becomes a bound on `to <= count - 1`: the bound the *reader of the index* actually needs, now that it is `points[segment.to]`. The comment's reasoning is rewritten with it. | Compile-red; the mutation the old bound exists to catch (a plan whose last segment indexes `points[N]`) still fails under the new one. |

### Test items deliberately **not** written, with reasons

- **A wall-clock ratio for `coarse` against `entire`.** The planner still classifies every unit
  segment (decision 2), so headless *planning* time falls only marginally — the win is entirely
  in the renderer (P9). A ratio here would measure the wrong half at a ~0.045 ms denominator,
  the exact fragile magnitude of the **five** wall-clock ratios this project has already had
  refuted by CI. T3's structural bound is the honest instrument.
- **An assertion of AC13's deviation bound.** It needs a geometric comparison of two polylines;
  unassertable at proportionate cost. Device and screenshot only, and labelled so.
- **An app-level test that the renderer calls `forFrame`.** `CanvasStitchLayers` is `private` and
  its `Canvas` closure runs only when hosted *and* drawn; `StageViewWiringTests` sees only
  `StageView`'s inputs. The app-side change is verified by the UI definition of done and by the
  device capture, not by a unit test. That is the price of decision 5, and it is the right price:
  the *logic* moved to where a test can see it.

### Visual definition of done

Host `StageView` with `StageInteraction` driven into settling (`commit` → `beginSettling` →
`settlingProgressed(to: 0.5)`, all public) at 50 000 stitches: `canUseRaster` is false in that
phase, so the screenshot is of the coarse plan, reproducibly and with no pinch tooling. The
premise captures above already show the instrument path works on the simulator via a scripted
drag, which is the fallback.

## File-by-file change list

**Package** — `Packages/EmbroideryEngine/Sources/StagePreview/`

1. `StitchDrawPlan.swift` — add `Segment`; `Stroke.segmentStarts` → `segments: [Segment]`;
   `DotRun` gains `stride`, `dottedIndices`, `count`; **rewrite** the `DotRun` `Range`
   justification and the `Stroke` segment contract. The "indices, never geometry" and "no public
   initializer" arguments are unchanged and stay.
2. `StitchDrawPlan+Planning.swift` — `planning(…, stride:)` and the span walker;
   `.entire`/`.settled`/`.live` become unchanged stride-1 callers.
3. **`StitchDrawPlan+Coarsening.swift` (new)** — `liveStitchBudget`,
   `coarseningStride(forStitchCount:budget:)`, `coarse(of:budget:)`,
   `forFrame(of:at:compositingRaster:budget:)`. A separate file so `+Planning.swift` stays under
   SwiftLint's `file_length` and so the rung has a name on disk.

No `Package.swift` change, no new target, no dependency change.

**Package tests** — 4. `StitchDrawPlanCoarseningTests.swift` (new, T1–T11); 5.
`StitchDrawPlanTests.swift` (T12); 6. `StitchDrawPlanWindowTests.swift` (T13); 7.
`StitchDrawPlanScalingTests.swift` (T14).

**App** — `catrobat_embroidery_ios/catrobat_embroidery_ios/`

8. `CanvasStitchRenderer.swift` — three edits: the `body` branch becomes `compositingRaster`
   plus one `forFrame` call; `segmentPath` reads `segment.from`/`segment.to`; the dot loop
   iterates `run.dottedIndices`. No new app file, **no `*.pbxproj` edit**, no human Xcode
   session.
9. `FrameTimeReadout.swift` + `StageView.swift` — the `-US310FrameTimes` launch argument
   (already done, for AC1; see P19).

**Docs** — 10. this file; 11. `docs/us-310-device-handoff.md` (new), mirroring US-309's protocol
with the budget sweep and the mid-gesture re-capture; 12. at close-out `docs/DECISIONS.md` (new
ADR-030 plus ADR-029 corrections), `README.md`, `docs/workflow-journal.md` (append-only).

**Descope lever** if the 5 h runs out: drop `forFrame` and leave a three-line branch in
`CanvasStitchLayers` (T9 goes with it). It keeps the fidelity work intact and loses only the
fast-gate coverage of the window choice — the wrong half to lose, but the cheapest.

## What cannot be proven headlessly

1. The **mid-gesture 50 000 re-capture** on device, drawn frames only, against ADR-029's
   unchanged bar.
2. The **budget sweep** — at least two of {2 000, 4 000, 8 000}. 4 000 is arithmetic.
3. **Which half of the residual is thread and which is dots** — only an Instruments trace can
   attribute `Path` construction against ellipse scan-conversion. Already an ADR-029 requirement
   and a milestone final-verification item.
4. The **visual acceptance** of the coarse image and of the pop at interaction start and commit
   (AC13).
5. The **A15 confirmation** — already a milestone final-verification item, explicitly gated on
   "once ADR-029's rung 2 lands". **Not this story's to close.**

**No Ink/Stitch verification is needed**: this story changes no exported byte. The display list,
the export model and `DSTFile` are untouched — it changes only which subset of the display list
a *frame* draws.

## ADR consequence

**A new ADR-030, plus corrections inside ADR-029.** New because it pins semantics a future story
could silently get wrong, where ADR-029 is a measurement record. It would pin, and only pin:
coarsening over dashing and why; the coarse-span rule of decision 2 verbatim, as the guarantee
that ADR-024's "we never draw thread where the machine travels" survives decimation; index pairs
as the representation, `to == from + 1` as the fine-window invariant, and why polylines were
rejected now and are rung 3's natural shape; per-run dot anchoring and the rule it exists for;
the budget as a **stitch** budget with the `k == 1` floor, and why it is not ADR-029's
proportional-`settleChunk` trap — including the warning that rung 3 *would* create that
coupling; the honest bound and the colour-run axis being out of reach; that the choice is one
package function on `canUseRaster == false`, which is a gesture **or** the fit animation; that
the coarse plan is never composited with a raster, so the pop is temporal and there is no
spatial seam; and **US-313's inherited invariant** (decision 7).

ADR-009 needs **no** change — the batching claim is preserved, and ADR-030 should say so
explicitly so nobody thinks it moved. ADR-021 and ADR-024 need no change; ADR-030 records that
both are *preserved by construction*.

## Planning corrections

Each verified against the named source by reading or executing it, not taken on report.

- **P1 — ADR-029's `0.0013 ms` and `350×` are stale, refuted by ADR-029's own correction.** Its
  per-frame-independence paragraph records that "0.0013 ms" was corrected for naming no fixture
  and gives `0.041 ms` (50 000 settled, 100-stitch tail, one colour run) — but two later
  paragraphs still say "0.0013 ms" and "**350×**", as do `README.md` and US-309's AC5. The
  correct mid-gesture-to-settled *planning* ratio is ~11× (0.45 / 0.041).
- **P2 — `canUseRaster == false` is not "gesture-only".** `StageInteraction.rendering` returns
  `.live` when `gesture != nil || isSettling`, so the coarse plan also draws during the
  double-tap / Fit-to-Hoop spring. Desirable — it is the only deterministic screenshot path —
  but the story must not say "gesture".
- **P3 — ADR-029's rung-2 wording is wrong twice.** "Draw every k-th segment" is dashing, and it
  says nothing about dots, which are plausibly the larger half of the cost; a literal
  implementation could leave most of the 69 ms in place.
- **P4 — "50 000 filled ellipses" is right in count, misleading in implication.** The renderer
  builds **one `Path` per colour run** and issues **one `fill` per run** — five for the five-band
  fixture, not 50 000 draw calls. The cost is path construction plus scan-conversion of
  ~200 000 cubic curves (four per `addEllipse`) against ~50 000 line segments for thread. That
  asymmetry is the quantitative reason to expect dots to dominate — still a hypothesis until the
  Instruments trace.
- **P5 — the renderer does not draw a polyline today, so "coarsening needs a polyline" is
  false.** `segmentPath` emits `move`/`addLine` per segment: 50 000 *disjoint* subpaths, visually
  joined only by `.round` caps. Continuity is a property of shared endpoints, and index pairs
  deliver it with the per-subpath non-finite skip intact.
- **P6 — a stitch budget does not bound the plan by the budget.** Every colour run must
  contribute its own dot and close its own span, so the counts are `ceil(n/k) + r` and
  `ceil(n/k) + r + traversals`. At `r = 50 000` — ADR-029's colour-change-per-stitch case, the
  one axis it identifies as genuinely growing — coarsening saves **nothing**. A bare "≤ N"
  criterion would be a false claim.
- **P7 — the `k == 1` floor is the second line of defence, not the first.** With the choice keyed
  on `canUseRaster`, the `.entire` path taken for *lack of a raster* (below `bakingThreshold`,
  key mismatch, viewport mismatch) is never coarsened at all.
- **P8 — the ripple is smaller than it looks.** `.entire(of:)` has exactly **one** non-test call
  site and `segmentStarts` exactly **one** non-test consumer; the rest is ~17 lines across three
  test files. Verified by grep over the whole repo.
- **P9 — rung 2's "on the fast gate" is about the *plan*, not the *saving*.** The planner must
  still classify every unit segment or it draws thread across jumps, so headless planning time
  falls only marginally. `swift test` proves the plan's shape; every millisecond is in the
  renderer. Hence no timing test.
- **P10 — the premise was not established, and two device facts did not obviously reconcile.**
  The bake schedule strokes the same ~50 000 stitches up to fifty times per run, yet the
  animating capture's worst frame over 251 drawn frames was 16.703 ms. ADR-029 lists "the last
  and largest bake" only as a *candidate* for the simulator capture's worst frame and never
  reconciles the two. **Discharged by the premise measurement above** — the cost does grow with
  the count — but the reconciliation itself is still open and belongs in the device session: a
  bake's rasterisation is not necessarily paid inside a display-link interval that the recorder
  tags as drawn.
- **P11 — `Range<Int>` is still right for `DotRun`, and `[Int]` would be a regression.** An array
  of selected indices allocates up to 50 000 `Int`s per plan in the un-coarsened paths — every
  settled bake — trading a live-path fix for a settled-path cost. A stored `StrideTo<Int>` is not
  `Equatable` and would break `StitchDrawPlan: Equatable`, which the window tests compare whole.
- **P12 — `Segment` must be one nesting level, not nested on `Stroke`.** SwiftLint's one-level
  nesting limit is already load-bearing here (`StageViewWiringTests.Invocation` is a sibling
  purely to stay within it) and CI runs `--strict`.
- **P13 — the two shipping samples, correctly attributed.** `SampleLibrary.all.first` is the
  Octagon Rosette at **3 194**; Square Coil is **2 976**. The existing plan suite uses `.first`
  and therefore covers only the rosette, so T11 must iterate `SampleLibrary.all` — which excludes
  the `#if DEBUG` synthetic by ADR-029's `SampleID.shipping` split.
- **P14 — two test items are vacuous unless the fixture is above the budget.** T9 and T10 compare
  values that are *equal* at k = 1, so on a shipping sample they assert nothing. T1 and T11 are
  likewise non-discriminating alone; only paired with T3/T10 do they mean "the budget is
  respected *and* small designs are untouched".
- **P15 — the `DotRun` doc comment must be rewritten, not extended.** Its stated reason for being
  a `Range` becomes false under a stride, and it sits directly above the line a future reader
  would edit. ADR-029 records exactly this failure for `settleChunk`'s comment.
- **P16 — `(count + budget - 1) / budget` overflows at `budget == Int.max`**, which T1/T2
  exercise. Use `count <= budget ? 1 : (count - 1) / budget + 1`.
- **P17 — a renderer-only alternative exists and is deliberately not this story.** Replacing
  `addEllipse` with `addRect` while live turns four cubics per dot into four lines, with no plan
  change at all. It cannot be tested headlessly, which is why ADR-029 named a plan change — but
  it is a legitimate device-session knob if the trace says the ellipses dominate, and it is
  recorded so it is not rediscovered.
- **P18 — "the only work blocking the exit criterion" is nearly right.** Rung 2 is the blocking
  *work*; the criterion additionally needs the A15 capture, which the **milestone** owns, not
  this story.
- **P19 — AC1 was unexecutable as first written, and fixing it is part of this story.** The
  premise check was specified as "hold a gesture on sample 1 and read the drawn-frame median",
  but `FrameTimeReadout` is shown only for `sample?.id == .us309Synthetic`, and that fixture is
  fixed at `us309SyntheticStitchCount` (50 001) with **no smaller variant** — so there was no
  instrumented small design to take the second reading on, and one reading cannot separate a
  per-primitive cost from a fixed per-frame one. The readout is now shown for every design when
  the process is launched with **`-US310FrameTimes`**: an argument rather than a widened
  condition, so US-309's reason for the narrow gate survives (an ordinary debug run does not
  pass it, so no shipping design's *screenshot* gains a diagnostic overlay). A first attempt put
  the flag as a `static let` on `StageView`, which does not compile — `StageView` is generic over
  its renderer, and Swift forbids static stored properties in generic types; it lives on the
  non-generic `FrameTimeReadout` instead.
