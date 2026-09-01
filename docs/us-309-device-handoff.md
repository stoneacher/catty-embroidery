# US-309 — device measurement hand-off

Everything in US-309 except the numbers below is done and green in CI. This file is the
protocol for the one part that needs hardware: **frame times at 50 000 stitches, in a Release
build, on an A15-class device** (ADR-029, AC2/AC3/AC8).

It is written to be executed exactly as stated. The pass/fail bar is fixed **before** measuring
— that is AC3's own requirement, and without it a capture with periodic dropped frames
satisfies every other item in the story.

## Prerequisites

- iPhone with an **A15 or newer** (iPhone 13 / 13 mini / 13 Pro / SE 3 / 14 / 14 Plus are A15).
  Record which chip it actually is; anything newer beats the criterion rather than meeting it.
- iOS 17+, Developer Mode on, device trusted.
- **Signing**: the project has `CODE_SIGN_STYLE = Automatic` and **no `DEVELOPMENT_TEAM`**
  (`project.pbxproj:369`). Either set a team once in Xcode → Signing & Capabilities, or pass
  `DEVELOPMENT_TEAM=<id>` on the command line and leave the project file untouched.
- Branch `US-309-fifty-thousand-stitch-exit-criterion`.

## Build

A **Release** build — the optimiser is the thing that makes the number real — with `DEBUG`
defined so the fixture and the recorder are reachable. Command-line build settings are global
overrides, so the one flag reaches the SwiftPM targets too, which is why `SampleID`'s
`#if DEBUG` case and `FrameTimeRecorder` both survive:

```
xcodebuild -project catrobat_embroidery_ios/catrobat_embroidery_ios.xcodeproj \
  -scheme catrobat_embroidery_ios -configuration Release \
  -destination 'platform=iOS,name=<device>' \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG' \
  build
```

Record the exact command used in the results table. Prefer the XcodeBuildMCP device tools over
raw `xcodebuild` where they are available.

## The bar (state it before measuring)

Over a **≥ 10 s** capture at 50 000 settled:

- **p99 ≤ 16.67 ms**, and
- **no frame > 33.3 ms** (no dropped-frame doubling).

Report **median, p95, p99 and worst** — never an average. An average of ninety-nine 8 ms frames
and one 40 ms frame is 8.3 ms, and so is the median; the stutter a user sees lives only in the
tail. The on-screen readout prints all four plus `PASS`/`FAIL` and flags a short capture.

## Procedure

Launch, pick **Synthetic 50k** (last row in the picker), press Play. The run takes ~17 s and
settles to 50 000. The **Record / Stop** capsule sits at the bottom of the canvas.

For each capture: press **Record**, hold the stated condition for the stated window, press
**Stop**, photograph or screenshot the readout.

| # | Condition | What to do | Window |
|---|---|---|---|
| 1 | 5 000 settled | run, stop early at ~5k, hold still | ≥ 10 s |
| 2 | 20 000 settled | as above at ~20k | ≥ 10 s |
| 3 | **50 000 settled** | run to completion, hold still | ≥ 10 s |
| 4 | 50 000, **mid-gesture** | continuous slow pinch and pan for the whole window | ≥ 10 s |
| 5 | 50 000, **animating** | Record before pressing Play, Stop at the end | whole run |

Captures 1–3 are AC4's table. **Capture 4 is the one at risk** — ADR-028 removed the
mid-gesture blit, so every frame re-strokes the entire design (0.45 ms of planning alone at
50k, 350× the settled frame, before the `Path` build and 50 000 ellipses). **Capture 5 is where
the bake spikes live**: note where in the run the worst frame falls.

### Tuning (AC5's actual requirement)

Repeat captures 4 and 5 with `PreviewRunState.settleChunk` at **1 000 (baseline)** and **5 000**,
and `CanvasStitchLayers.bakingThreshold` at **2 000 (baseline)** and one other value. Four extra
captures. The chosen constants go into ADR-029 **with the table that chose them** — a bare
number would fail the criterion, which asks for the measurement that justified it.

Note that `settleChunk = 5000` stops the shipping samples (2 976 and 3 194 stitches) settling
at all, so it is a *measurement* value, not a shippable one. If the device says a larger chunk
is worth it, the shippable form is a floor plus a proportional term — see ADR-029 for why the
naive proportional version measured *worse* (176 bakes instead of 50).

## Also record, once

- An Instruments **Animation Hitches** trace of captures 3 and 4, as an independent cross-check
  that the in-app recorder is not lying. Say in the thesis whether the two agreed.
- The device's own `assembled()` timing at 1 k / 10 k / 50 k, so **ADR-021's Mac figure finally
  gets its device counterpart**. That ADR claimed 0.64 ms was "roughly 10% of a frame on
  A15-class hardware"; it is 3.8% of a frame on the Mac it was measured on, and the A15 number
  has never existed. The correction is already recorded; this is what closes it.

## Screenshots still owed

- `docs/screenshots/us-309/03-device-50k-fitted.jpg`
- `docs/screenshots/us-309/04-device-50k-zoomed.jpg`

**The zoomed one could not be produced here**: this toolchain has no pinch preset and cannot
reach the accessibility adjustable action, exactly as US-307's journal recorded. Note also that
on the *Simulator* an Option-drag mirrors its two touches about the window centre, so unless
the canvas straddles that centre one touch lands outside it and `MagnifyGesture` never
recognises — the canvas pans instead. Option+Shift-drag moves the pair onto the canvas. On a
device this does not arise.

## If the bar is missed

Do **not** reword the criterion. Take ADR-029's fallback ladder from rung 1 and re-capture:
tune `settleChunk`; then decimate the mid-gesture `.entire` plan; then reuse `Path`s across
frames; then the Metal renderer behind `StagePreviewRenderer`, which is a milestone of its own
and gets a backlog story rather than being taken here.

## Bring back

The 5 (then 9) statistic rows, the two `.trace` bundles, the device `assembled()` numbers, and
the two screenshots. Everything else — the headless guards, the simulator rehearsal, the tuning
*shape* — is already done and does not need the device.
