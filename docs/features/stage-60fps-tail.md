# Stage 60 fps tail

**Status**: Planned — 2026-10-29 | **Epic**: E4 | **Branch**: `feature/stage-60fps-tail`

**Goal**: settle where M3's last unmet exit criterion goes. At 50 001 stitches (`makeUS309SyntheticProgram`) the mid-gesture median and p95 sit at one refresh period, but the worst frame is 38–50 ms against the bar's 33.3 ms (ADR-043 "Where it stands"). Coarsening is exhausted and the commit is excluded (the tail shows up in a single gesture that is never released). This feature runs ladder rung 3's discriminating experiment: does the tail follow **covered pixels** or **geometry**? It builds the instrument that makes the experiment repeatable and agent-runnable, records the verdict, and then either ships a fix that meets the bar on device or names the next rung with evidence. **The outcome is unknown at planning, so "done" is defined independently of it (D8).**

**In scope**
- A DEBUG fixture with the synthetic's geometry over a small area (D1–D2), and a zoomed-out condition on the existing fixture (D3).
- A DEBUG scripted-gesture driver, launched by argument, that drives the real coordinator (D4), and a console report (D5).
- Attribution: DEBUG signposts, an Animation Hitches trace and a Time Profiler trace per condition (D9).
- The device session, a decision rule fixed before measuring (D6), and the verdict as an ADR-043 amendment.
- The conditional fix half (slice 7), capped at two candidates.
- **US-322** (raster never composited at a fractional viewport): measured in PR 1 by the report's canvas, viewport and raster fields, and fixed in PR 2 as a slice that does not depend on the verdict (D10; accepted 2026-10-29).

**Out of scope**
- Rung 5 (`MetalStitchRenderer`): a milestone of its own (ADR-029). If the verdict points there, it is named and gets a backlog item, not built here.
- **The A15-class capture**: blocked until a fix exists. If slice 7 ships one, the capture is *unblocked* and stays a milestone item that needs an A15 device in hand; not taken here unless one is paired (D11).
- The animating path's GPU-side hitches (ADR-029's 2026-09-18 amendment): recorded, not this feature's bar. They are re-captured only as a no-regression check after US-322.
- Viewport-culled planning (ADR-044's "deliberately not built" list) and momentum.

## Decisions (D1–D11, accepted by Sebastian 2026-10-29 as planned by `swift-architect`)

- **D1 What the discriminator holds and varies.** A `Canvas` stroke or fill is a *single* path, and its coverage is computed once, so overlap *inside* a path is not blend overdraw. Only about 15 layers blend (two strokes and one dot path for each of 5 colour runs). Two quantities can therefore be "the pixels", and two conditions separate them:
  - **B: compact fixture at fit.** Holds constant the stitch count, the colour runs and their lengths, the coarsening stride, the coarse segment and dot counts, the corners, travel (none), the transform (the fit is constant for any design inside the hoop, `StageGeometry.fitTarget`), the stroke widths, and every segment's view-space length and orientation. So **the total primitive area and the number of edge crossings per scanline are invariant**. It varies only the **covered area** (the union) by ≥ 10×.
  - **C: original fixture zoomed out.** Same plan and the same `Path` element count, with the thread width scaling with zoom (`StitchDrawMetrics.threadWidth`). It shrinks **both** the covered area and the per-primitive area.
  - B clean and C clean: covered area. B tailing and C clean: per-primitive fill or scan-conversion. Both tailing: not pixels. B clean and C tailing: contradictory, so re-run (D6).
- **D2 The compact fixture: `makeUS316CompactProgram`, only `rowSpacing` changes.** The integer stitch length rules out shrinking by length (ADR-017 truncates through `interpretInteger`, and 1 would only halve the size while changing segment lengths). A narrower row changes the stitches per row and with them the count and the corners. Spacing is the only free knob: it must stay shorter than the stitch length, so the spacing move emits nothing and every row stays worth 200 stitches. Slice 1 picks the value (try 0.1, then 0.25) that keeps the count at exactly 50 001 under ADR-019's floor-boundary argument (the synthetic's file explains it). It lives in `Samples` under `#if DEBUG`, as `SampleID.us316Compact` with `resourceName` "US316Compact". It is not in `SampleLibrary.all` or `SampleID.shipping`, it is listed after `us309Synthetic`, and it shows the frame-time capsule. A test-only synthetic was rejected: only a sample can be captured on device.
- **D3 The zoom condition: zoom below fit is allowed and changes what "area" means.** `StageZoomBounds(fitting:)` allows zooming down to `min(fit, 0.05)`. Width scales until the 0.75 pt floor (scale ≈ 0.238). Below the floor, dots stop shrinking and segments shrink only in length. C is taken at the scale where the covered view area is ≤ 1/10 of A0's. The driver reaches it with a real pinch and a release (one commit), waits 2 s for the bake, then pans only. The console line prints the scale and the widths, so the real reduction is recorded rather than assumed.
- **D4 The driver drives the real coordinator, not the value types beside it.** DEBUG only, active only with `-US316Capture …` (the parser is pure and takes `[String]`). When the argument is present, `StageManipulationCatcher.makeUIView` registers its `Coordinator` with the driver. The driver calls the coordinator's own `panned(_:)`/`pinched(_:)` with scripted `UIPanGestureRecognizer`/`UIPinchGestureRecognizer` subclasses that override `state`, `translation(in:)` and `location(in:)`. That is the pattern `StageManipulationDoubles` already measured to work; assignment is silently swallowed. A `CADisplayLink` steps it, and the position is a pure function of `targetTimestamp`, so a stall makes the next step jump the way a moving finger does. Without the argument nothing registers, so the parallel suites never touch it.
  - **Reproduced exactly, from the action methods down**: the suppression gate, `beginManipulating` (ADR-044's frozen fit), the `StageManipulation` channels, the binding writes that invalidate SwiftUI, `gesture(in:)` → `rendering` → `isLive` and `canUseRaster == false`, `StitchDrawPlan.forFrame`'s coarse plan, the `Canvas`, `StageDrawCounter`, and at the end `settleIfFinished` → one commit → `onCommitted` → the re-bake.
  - **Not reproduced**:
    - UIKit's touch delivery: hit-testing, `UITouch`/`UIEvent`, the recognisers' state machines and simultaneous arbitration, `StageTouchTrackingView`'s counting, and the stage's `simultaneousGesture(tapOutOfName)`. All of this is main-thread work, and the tail is a main-thread stall (D9), so the driver can *under*-report input cost.
    - Cadence: one update per refresh (drawn/n ≈ 1.0), against 0.6–0.97 by hand, so the driver draws *at least* as many frames as a finger.
    - Human jitter.
    - Any system policy keyed on real touches, such as performance-controller boosting (undocumented; treated as unknown).
  - **Hence the calibration** (D7): the driver is trusted only once it reproduces a hand capture's tail class in the same session.
- **D5 The console report is the capsule's line, plus fields.** The caption formatting moves from `FrameTimeReadout` into a pure `FrameCaptureReport`, so the capsule and the console print the *same* `n= drawn= commits= Hz med p95 p99 max@ · s · verdict` text. The console line adds the tag `US316`, the condition, every drawn interval > 33.3 ms with its offset, `ProcessInfo.thermalState` at the start and end (captures at `.serious` or worse are discarded), and the scale and widths. For US-322 it also prints the viewport, the `Canvas` size and whether the raster composited on the last settled frame, recorded by `StageDrawCounter` in DEBUG.
  - The driver owns its own `FrameTimeRecorder`, so the capsule stays untouched and on screen for parity.
  - `stdout` is flushed per line (it is block-buffered when not a TTY).
  - The idle timer is disabled while capturing, and the app calls `exit(0)` after the last repeat, so `devicectl device process launch --console` and `xctrace --launch` both return unattended.
- **D6 The decision rule, fixed before the first capture** (ADR-030's practice). Each condition gets 5 captures of 12 s, pan-only, never released, after a full pre-roll run and 2 s of settling. Launches are interleaved A0, B, C, A0, … so that thermal drift and time spread across conditions. A condition **tails** if ≥ 3 of 5 captures hold a drawn frame > 33.3 ms, and is **clean** if ≤ 1 of 5 does *and* its paired Hitches trace has no hitch > 33.3 ms (read as ADR-029's 2026-09-18 amendment reads it).
  - A0 must tail under the driver; otherwise see D7.
  - The verdict comes from D1's table. Anything that is neither tailing nor clean (2 of 5) gets 5 more captures, once.
  - If pan-only A0 is clean but the mixed pinch-and-pan script tails, the scale change is implicated, and the matrix is re-run on the mixed script about each condition's base scale.
- **D7 Which captures need the human.**
  - Once per machine: Xcode opened and its device-access prompt approved, which `xctrace` needs (the us-309 handoff, item 1), and auto-lock disabled.
  - **Calibration**: one hand capture of A0 (sustained pinch and pan), in the same session as the driver's A0. If the driver is clean and the hand tails, the tail lives in the input path. That is a verdict in itself: the matrix is re-taken by hand (3 captures each of A0 and B), and slice 7 is skipped.
  - **Acceptance of a fix**: one hand capture ≥ 10 s, paired with an Animation Hitches trace (`xctrace --launch`, the human gesturing). A driver PASS alone never claims the bar.
  - **Judgement**: any fix that changes the live image is looked at by eye on the device.
  - Everything else (the matrix, every Hitches and Time Profiler trace, the US-322 re-capture) is agent-run with `devicectl --console` and `xctrace --launch`.
- **D8 Done, whatever the result.** (1) Instrument and fixture built and green. (2) Calibration plus the D6 matrix captured. (3) The verdict recorded as an **ADR-043 amendment** with the raw lines, in `docs/us-316-device-handoff.md`, and in the journal. (4) Then **either** a fix that meets the bar on device, supported by driver captures and confirmed by the hand capture and its Hitches trace, with "Where it stands" amended to met, **or** the next rung named, with the evidence that names it and the criterion recorded **unmet**. The bar is quoted verbatim and never reworded (ADR-032 invariant 1): *"Over a capture of at least 10 s: p99 ≤ 16.67 ms and no frame > 33.3 ms, over drawn frames only."* At most two fix candidates are tried. A candidate that misses is recorded and does not open a third.
- **D9 Attribution travels with every condition.** A display-link interval widens only for main-thread stalls (journal, 2026-09-18), so the capsule's 38 ms is CPU on the main thread. A fill-rate cost may also sit on the GPU, where only the Hitches trace sees it.
  - DEBUG `OSSignposter` intervals (Points of Interest) around `forFrame`, `segmentPath`, `dotPath` and the stroke and fill calls.
  - One Time Profiler trace of A0 and of each clean condition. These settle the long-open split between building the `Path` and scan-converting the dot ellipses, and with it ADR-030's recorded `addRect` alternative.
  - ADR-043's per-frame display-list copy is excluded: no append happens while settled.
- **D10 US-322 comes in.** The backlog pulls items into features that touch the same code, and this one does (`CanvasStitchRenderer`, `compositingRaster`). It cannot change a mid-gesture frame, since `canUseRaster` is false while live. But it governs the frames before and after the gesture, and it confounds every settled or animating device number. PR 1 measures it for free (D5); PR 2 fixes it first, so the fix captures run on a correct raster gate.
- **D11 Risk and the A15.** The fixture (engine package) and every renderer change are **risky**. The driver, the report and the scenario are DEBUG-only app code with no shipping path, so they are not risky, but the reviewer checks D4's fidelity claim against the coordinator. `release-build.yml` proves that nothing leaks into a build without `DEBUG`.

## Acceptance criteria

- [ ] `us316Compact` matches `us309Synthetic` on every property D1 holds constant, pinned as literals, and covers ≤ 1/10 of its area. Both are DEBUG-only, outside the library, and listed last.
- [ ] One launch argument runs a capture end to end, with no touch on the device. It prints a line whose statistics are byte-identical to the capsule's for the same recorder state, then exits.
- [ ] Driving the coordinator through scripted recognisers produces the same binding writes as the existing stub-driven tests: live throughout, `canUseRaster == false`, and exactly one commit, at the end.
- [ ] The calibration and the D6 matrix were captured on the iPhone 17 Pro. The verdict, per D6's rule, is recorded as an ADR-043 amendment, with Hitches and Time Profiler findings.
- [ ] US-322: a fractional viewport no longer refuses the raster (red first), and the animating 50k capture plus its Hitches trace are re-taken with no regression.
- [ ] Either the bar is met on device (driver captures, hand capture and Hitches trace, no hitch > 33.3 ms), or the next rung is named with evidence and the criterion stays recorded unmet. The bar's wording is unchanged in every document.

## Slices and test-first outline

Each slice goes red → green and is mutation-checked. Before any test, the brief gets **one Codex round**, aimed at D1's reasoning, D4's fidelity claim and D6's rule: they are new and not pinned by any ADR (ADR-041).

**PR 1 — the instrument and the verdict** (~650 lines of non-test code; the shipping render path untouched)

1. **Compact fixture** (risky: yes, engine) — red, in `StagePreviewTests`/`SamplesTests`: stitch count `== us309SyntheticStitchCount`; 5 runs, with per-run lengths equal to the original's; the live plan's segment and dot counts (via `forFrame` at a live transform) equal the original's, as literals; corners and traversals equal; a bounding-box literal with height ≤ original/10; not in `SampleLibrary.all` or `shipping`; `resourceName` valid for DST `LA`. App: `SyntheticHarnessTests` asserts both fixtures are last, in order, and that the capsule shows for both. Mutations: spacing on a floor boundary (count drifts), spacing ≥ stitch length (+250 stitches), 4 bands, row width ±1, added to `SampleLibrary.all`.
2. **Scenario, script and report** (risky: no) — red: the parser (absent → nil; each fixture, zoom, gesture, hold and repeats; unknown → nil; hold below 10 s rejected); `GestureScript` (starts at a zero translation like the recogniser; continuous, with a bounded per-frame step at 60 Hz; a pan-only script never changes scale; it keeps the design on screen; it is time-based, so a skipped tick jumps); `FrameCaptureReport` (the capsule caption is unchanged, which `FrameTimeReadout` is switched to; the console line carries the over-bar list, the thermal state and the scale, canvas, viewport and raster fields). Mutations: the over-bar list taken from all frames rather than drawn ones, a frame-count-based script, scale drift in the pan script, a 5 s minimum hold.
3. **Driver wiring** (risky: no; reviewer checks D4) — red, beside `StageManipulationWiringTests`: the scripted pan and pinch through the real `Coordinator` give live renders, no commit mid-script and exactly one at the end; the zoom pre-step commits once and lands at the requested scale; the sequence (select → play → finished → settle → [zoom] → record → gesture → stop → report → repeat → exit) is a pure state machine; nothing registers without the argument. Simulator dry run with `simctl launch --console`. Mutations: committing every step, skipping `beginManipulating`, registering unconditionally, never ending the gesture.
4. **Signposts and the draw record** (risky: yes, renderer file, DEBUG-only) — red: the draw record reports the `Canvas`'s `size` and not the viewport, and whether the raster composited; `CanvasStitchStrokeTests` stays green. Mutations: `size` recorded from the viewport, composited recorded from `canUseRaster` alone.
5. **Device session: the measurement** (no code) — the build is the us-309 handoff's Release-with-`DEBUG` command; install and `launch --console` on device 00008150-001525401181401C. Order: calibration (D7), then the D6 matrix, the Hitches traces, and the Time Profiler traces (D9). Outputs: `docs/us-316-device-handoff.md` (protocol and raw lines), the ADR-043 amendment with the verdict, and a journal entry. **PR 1 is ready for review here**, with its Codex loop.

**PR 2 — US-322 and the fix** (branch `feature/stage-60fps-fix`; size depends on the verdict)

6. **US-322** (risky: yes) — red: `compositingRaster` with a 370 × 256.833 viewport against a 370 × 257.0 `size`. The keying choice is taken from the backlog's three options at the red phase, and recorded as an ADR-043 amendment because it touches "never stretched". Re-capture the 50k animating run and its Hitches trace (agent-run). Mutations: an exact-equality comparison restored, a tolerance ≥ 1 device pixel.
7. **The fix, conditional on the verdict** (risky: yes; at most two candidates; each one captured with the driver, 5×, before the next):
   - *Covered area or per-primitive fill* → (i) `addRect` for `addEllipse` while live (ADR-030's renderer-only alternative). Red: `dotPath` in live mode emits rectangles of the same centres and extent. (ii) The live frame drawn at a reduced backing scale. Both change the live image, so each needs an ADR-043 "accepted fidelity costs" entry and the human's look (D7).
   - *Not pixels, and the Time Profiler names the `Path` build* → rung 4: `Path` reuse keyed on plan and stride, built in stage space and drawn under a transform, with the width divided by the scale and the 0.75 pt floor kept. **First** harden the engine polyline against non-finite and unconvertible vertices. Red: it drops exactly the vertices the fine plan's `isDrawable` skips. Then a cache key test: a pan re-uses the cached path, and a stride, reset or run change invalidates it.
   - *Not pixels, and not the `Path` either* (layout, diffing, input) → no fix. The amendment names the cost and the next rung.
   - The winner gets the hand capture and its Hitches trace. Mutations per candidate: the live gate inverted (rectangles drawn when settled), the cache key missing the stride, a width not divided by the scale.
8. **Close** — ADR-043 "Where it stands" amended (met, or still unmet with the next rung); US-316 removed from the backlog, or re-scoped there to the named rung; the A15 status stated (D11); `swift-documenter`; journal.

## Verification at handover

- Every slice mutation-checked and recorded; slices 1, 4, 6 and 7 reviewed (`swift-code-reviewer` in a worktree plus one Codex round when green); each PR's Codex loop (cap 5).
- Every number traced to a console line or a trace export; traces are kept at `build/instruments/` (gitignored) and their numbers go in the handoff and the ADR.
- Simulator screenshot of the compact fixture, settled; a device screenshot of a slice 7 live image if it changed.
- Ink/Stitch: not needed (no DST byte or provenance change; the fixture is DEBUG-only).
- Pre-beta accessibility: none, unless slice 7 changes the live image (Reduce Motion is unaffected).

## References

- ADR-043 (rules, bar, ladder), ADR-029 and ADR-030 (the measurement records, including the 2026-09-18 amendment), ADR-044 (one commit per manipulation, frozen fit), ADR-032 invariant 1, ADR-017/019 (the fixture's integer and floor constraints), ADR-041.
- `docs/us-309-device-handoff.md` (build, `xctrace` protocol and friction), `docs/us-310-device-handoff.md` (`-US310FrameTimes`, captures); journal 2026-09-18 ("a third instrument").
- Code: `US309SyntheticProgram.swift`, `StageZoomBounds.swift`, `StitchDrawMetrics.swift:53-72`, `StageCanvas.swift`, `StageManipulationCoordinator.swift`, `StageManipulationDoubles.swift`, `CanvasStitchRenderer.swift`, `CanvasStitchStroke.swift`, `FrameTimeRecorder.swift`, `FrameTimeReadout.swift`, `AppModel+SelectionQueries.swift`.
- Backlog: US-316, US-322.
