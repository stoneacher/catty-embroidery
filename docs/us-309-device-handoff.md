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
- **Controlled refresh conditions, and this is not optional.** iOS may drop a display link to
  30, 20 or 15 Hz under **Low Power Mode**, a **critical thermal state**, or Accessibility →
  Motion → **Limit Frame Rate**. At 30 Hz every interval is ~33.3 ms, so a renderer doing
  essentially no work fails *both* halves of the bar — an unforced FAIL that looks exactly
  like the real thing. So before each capture: Low Power Mode **off**, Limit Frame Rate
  **off**, device not hot and not charging hard, and screen brightness fixed. The readout
  prints the link's own nominal rate (`60Hz`, `30Hz`, …); **record it with every row**, and
  discard any capture that does not say `60Hz`.
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
  -derivedDataPath build/us309 \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) DEBUG' \
  build
```

**`$(inherited)` is not decoration.** A command-line build setting *replaces* the target's own
value rather than appending to it. The app target's is `"DEBUG $(inherited)"`, so nothing is
lost there — but the SwiftPM targets lose `SWIFT_PACKAGE`, which is safe today only because no
first-party source tests `#if SWIFT_PACKAGE` (grepped: zero hits) and would stop being safe
without warning. The bare `SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG'` spelling was verified
to build with zero warnings on 2026-09-01; `$(inherited)` is the same build with the failure
mode removed, and the failure it prevents would land on the device session rather than in CI.

**`build` neither installs nor launches** — it only produces the `.app`. Do one of:

- **Xcode**: select the device, set the scheme's Run configuration to Release, add `DEBUG` to
  *Swift Compiler → Custom Flags → Active Compilation Conditions* for Release, then Run. This
  is the least error-prone route and gives Instruments the same build.
- **Command line**: after the `build` above, install and launch with `devicectl`:

  ```
  xcrun devicectl device install app --device <udid> <path-to>/catrobat_embroidery_ios.app
  xcrun devicectl device process launch --device <udid> org.catrobat.embroiderydesigner
  ```

  `<path-to>` is `build/us309/Build/Products/Release-iphoneos/` — the `-derivedDataPath` above,
  which the build command has to pass explicitly or the products land in a hashed directory
  under `~/Library/Developer/Xcode/DerivedData` that this instruction cannot name. `xcrun
  devicectl list devices` gives the udid.

Record the exact commands used in the results table. Prefer the XcodeBuildMCP device tools over
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

**The capsule does not exist on a fresh launch.** It is rendered only in the `.drawn` state,
which needs `hasStitches || isRunning` — so after launch → select the fixture the canvas is
empty and there is no Record button. Press **Play once** before looking for it. This matters
only for capture 5, which asks you to record *before* pressing Play: do a first run, let it
finish (the stitches stay on the canvas, so the capsule stays), then press **Record** and
press **Play** again to re-run. The second run replaces the first, and recording is already
armed when it starts.

For each capture: press **Record**, hold the stated condition for the stated window, press
**Stop**, photograph or screenshot the readout.

**The readout shows a constant `capturing… hold ≥ 10 s, then Stop` while a capture runs** — it
deliberately does not count frames on screen, because doing so re-rendered a blurred capsule
over the canvas under measurement sixty times a second and put the instrument inside its own
distribution. Time the window yourself; the result line prints the capture's length in seconds
and marks anything under ten with `(short)`, so a mistimed hold is caught rather than quoted.
If the app loses the foreground mid-capture the result reads
**`INTERRUPTED — discard and re-capture`**. The recorder *excludes* the background gap rather
than measuring it, so the numbers are not corrupt — but the capture is short by however long
the app was away and its window is no longer the one you timed, so discard it. Either way it
must not be read as a `FAIL` or taken to the fallback ladder.

| # | Condition | What to do | Window |
|---|---|---|---|
| 1 | 5 000 settled | run, stop early at ~5k, hold still | ≥ 10 s |
| 2 | 20 000 settled | as above at ~20k | ≥ 10 s |
| 3 | **50 000 settled** | run to completion, hold still | ≥ 10 s |
| 4 | 50 000, **mid-gesture** | continuous slow pinch and pan for the whole window | ≥ 10 s |
| 5 | 50 000, **animating** | run once so the capsule appears, then Record → Play → Stop at the end | whole run |

**Read this before quoting any of these numbers as "60 fps at 50 000 stitches".**

A `CADisplayLink` callback fires once per display refresh **whether or not the app drew
anything**, and SwiftUI redraws a `Canvas` only when something invalidates it. On a settled
50 000-stitch stage nothing does — no run is advancing, no gesture is live — so **captures 1–3
can return a flawless `p99 16.7 · PASS` while the renderer produced zero frames.** That is the
*expected* behaviour of a static stage, not a fault, and it means those captures measure the
display's cadence rather than ADR-009's claim.

The readout therefore prints **`draws=`** beside `n=`: the number of canvas draw passes during
the capture. A capture whose draw count is near zero is labelled **`NO DRAWS — measures the
display, not the renderer`** instead of `PASS`/`FAIL`. Expect exactly that on captures 1–3, and
**do not report it as the criterion being met.**

Measured on the simulator before the hand-off, as the illustration:

| | readout |
|---|---|
| 50k settled, static | `n=988 draws=0 60Hz med 16.7 p95 16.7 p99 16.7 max 16.7@0.0s · 16.5 s · NO DRAWS` |
| 50k animating | `n=1932 draws=251 60Hz med 16.7 p95 16.7 p99 49.7 max 72.8@22.4s · 33.7 s · FAIL` |

Same fixture, same device, `PASS`-shaped numbers against a `FAIL`, and a p99 of 16.7 against
49.7 ms. Non-authoritative for the bar (a host GPU is not an A15) but the difference is
structural. **If your capture 3 comes back `NO DRAWS`, that is correct behaviour, not a bug.**

So:

- **Captures 4 and 5 are the authoritative ones for the 60 fps claim**, because only they force
  a redraw every frame. The thesis sentence about ADR-009 rests on these two.
- **Captures 1–3 prove something narrower** and should be reported as such: a settled stage
  introduces no background stutter, and per-frame cost does not grow with the settled count.
  (The *independence* claim itself is already proved headlessly and structurally —
  `StitchDrawPlanScalingTests` — which is where it belongs; see ADR-029.)
- **The Instruments trace is not an optional cross-check on 4 and 5, it is required**: it is the
  only mechanism here that observes the rendering pipeline directly rather than inferring it.

**Capture 4 is the one at risk** — ADR-028 removed the mid-gesture blit, so every frame
re-strokes the entire design (0.45 ms of *main-thread* planning alone at 50k, 350× the settled
frame, before the `Path` build and 50 000 ellipses). **Capture 5 is where the bake spikes
live**: the readout prints the worst frame's position as `max <ms>@<seconds>s`, seconds from
the start of the capture, so the spike can be located without an Instruments timeline. Start
the capture immediately before pressing Play and stop it immediately after the run ends —
`draws=` and the total window let you check afterwards how much idle time crept in at either
end, but keep it small so the animation dominates.

### Tuning (AC5's actual requirement)

**One factor at a time, not a factorial** — the earlier wording said "four extra captures"
while describing a 2 × 2 × 2 grid, which is eight, and left the second `bakingThreshold` value
as "one other value", so two testers would produce incomparable tables. Fixed:

| Run | `settleChunk` | `bakingThreshold` | Captures |
|---|---|---|---|
| baseline | 1 000 | 2 000 | 4, 5 |
| chunk | **5 000** | 2 000 | 4, 5 |
| threshold | 1 000 | **8 000** | 4, 5 |

Six extra captures, three rows, each changing exactly one constant from the baseline.
`bakingThreshold = 8000` is chosen so the 50k design still crosses it comfortably while the
shipping samples (2 976 / 3 194) do not — i.e. it tests the threshold rather than disabling
the raster path. If a row wins, re-run the *other* factor from that winner before concluding.

The chosen constants go into ADR-029 **with the table that chose them** — a bare number would
fail the criterion, which asks for the measurement that justified it.

Note that `settleChunk = 5000` stops the shipping samples (2 976 and 3 194 stitches) settling
at all, so it is a *measurement* value, not a shippable one. If the device says a larger chunk
is worth it, the shippable form is a floor plus a proportional term — see ADR-029 for why the
naive proportional version measured *worse* (176 bakes instead of 50).

## Also record, once

- An Instruments **Animation Hitches** trace of **captures 4 and 5** — the two the 60 fps claim
  rests on. (This said "3 and 4", which contradicted the section above: capture 3 is a settled
  stage that draws nothing, so a trace of it shows an idle app, while capture 5 is where the
  bake and export spikes live and had no required trace at all.) It is the only artefact here
  that observes the rendering pipeline directly rather than inferring it from callback timing,
  so it is required rather than a cross-check. Say in the thesis whether it and the in-app
  recorder agreed.
- The device's own `assembled()` timing at 1 k / 10 k / 50 k, so **ADR-021's Mac figure finally
  gets its device counterpart**. **There is no UI for this**, so use the debugger: run the app
  on the device from Xcode, pause on the stage with the fixture settled, and in the LLDB
  console time the call directly, e.g.

  **`assembled()` is on `EmbroideryPatternManager`, not on `StitchDisplayList`** — an earlier
  version of this recipe named the display list, which has no such method, so it could not
  have been run at all. The stage does not retain a pattern manager either: the interpreter
  builds one internally and the app only ever sees `assembledStream()`'s result. So build the
  input in the debugger rather than fishing for it:

  ```
  (lldb) e -l Swift -- import Foundation
  (lldb) e -l Swift -- import EmbroideryEngine
  (lldb) e -l Swift -- 
  let m = EmbroideryPatternManager()
  for i in 0 ..< 50_000 { m.addStitch(...) }        // 1_000 / 10_000 / 50_000 in turn
  let t = Date(); for _ in 0 ..< 20 { _ = m.assembled() }
  print(-t.timeIntervalSinceNow / 20 * 1000)
  ```

  filling the manager through the same public `addStitch` the synthetic fixture uses, 20
  iterations to average, repeated at each of the three counts. **Take the pause in the
  Release-with-`DEBUG` build**, or the number is a debug build's and not comparable with
  ADR-021's. A `signpost` + Instruments interval would be tidier and is worth adding if this
  measurement is ever repeated; today this is the procedure. That ADR claimed 0.64 ms was "roughly 10% of a frame on
  A15-class hardware"; it is 3.8% of a frame on the Mac it was measured on, and the A15 number
  has never existed. The correction is already recorded; this is what closes it.

## Screenshots still owed

- `docs/screenshots/us-309/03-device-50k-fitted.jpg`
- `docs/screenshots/us-309/04-device-50k-zoomed.jpg`

The two already committed are the simulator pair, kept because the contrast between them is
the point: `01-sim-50k-settled-no-draws.jpg` is the flawless capture of nothing, and
`02-sim-50k-animating-fail.jpg` is the same fixture actually rendering.

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

**Eleven statistic rows** — the five numbered captures, then six more from the three tuning
rows above (2 captures × 3 rows). The earlier "5 (then 9)" was arithmetic for the old
four-capture tuning grid and no longer matches the table. The two `.trace` bundles, the device `assembled()` numbers, and
the two screenshots. Everything else — the headless guards, the simulator rehearsal, the tuning
*shape* — is already done and does not need the device.
