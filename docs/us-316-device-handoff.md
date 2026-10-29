# US-316 device hand-off — where does the mid-gesture tail live?

The protocol for slice 5 of [Stage 60 fps tail](features/stage-60fps-tail.md). It reuses
[`us309-device-handoff.md`](us309-device-handoff.md) for the bar and the `xctrace` friction, and
replaces its build and capture steps: captures are now **unattended**, launched from the Mac and
read off the console (D4, D5). The decision rule (D6) and the calibration (D7) are fixed in the
brief and are not restated here; this file is how to run them.

## What needs Sebastian, and what does not

| Step | Who | Why |
|---|---|---|
| Make the iPhone visible to `xctrace` | **Sebastian**, once | It listed the phone under *Devices Offline* (2026-10-29). No access prompt appeared; opening **Window → Devices and Simulators** and letting Xcode prepare the phone moved it to *Devices*, over Wi-Fi. |
| Auto-lock off on the iPhone (Settings → Display & Brightness) | **Sebastian**, once | The app disables its own idle timer while capturing, but the phone must be unlocked when a launch arrives. |
| Calibration: 3 hand runs of A0, alternating with 3 driver runs | **Sebastian** gestures; the agent launches and records | D7. |
| The D6 matrix (A0, B, C, D, E, mixed A0), every run traced | agent | Unattended. |
| Acceptance of any fix: 1 hand run ≥ 10 s with its Hitches trace | **Sebastian** gestures | D8 "fixed". |
| Looking at any fix that changes the live image | **Sebastian** | D7. |

The phone is paired over the local network (`devicectl`: `Transport Type: localNetwork`), so no
cable is needed for `devicectl`. Whether `xctrace` reaches it wirelessly is untested.

## Build — Release, `DEBUG` defined, **coverage off**

```
xcodebuild -project catrobat_embroidery_ios/catrobat_embroidery_ios.xcodeproj \
  -scheme catrobat_embroidery_ios -configuration Release \
  -destination 'platform=iOS,id=00008150-001525401181401C' \
  -derivedDataPath build/us316 \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) DEBUG' \
  ENABLE_CODE_COVERAGE=NO CLANG_COVERAGE_MAPPING=NO \
  DEVELOPMENT_TEAM=6M2HZFQZ6L PRODUCT_BUNDLE_IDENTIFIER=org.superrandom.embroiderydesigner \
  -allowProvisioningUpdates build
```

**`ENABLE_CODE_COVERAGE=NO` is new and load-bearing.** Xcode's effective Release settings for this
scheme include `ENABLE_CODE_COVERAGE = YES` and `CLANG_COVERAGE_MAPPING = YES` (the project does not
set them; they are defaults), so US-309's command produces a binary with 7 `__llvm_prf` sections —
coverage-instrumented — and the app logs `LLVM Profile Error: Failed to write file
"default.profraw"` on device. With the two overrides the binary has none (`otool -l … | grep -c
__llvm_prf` → 0). **US-309's and US-310's device numbers may have been taken on an instrumented
binary**: their command has no override, but the Xcode that built them cannot be re-checked, so
this is an open question about those records, noted here and in the journal, not a reason to edit
them.

Install: `xcrun devicectl device install app --device 00008150-001525401181401C
build/us316/Build/Products/Release-iphoneos/catrobat_embroidery_ios.app`.

## One driver run

```
xcrun devicectl device process launch --device 00008150-001525401181401C --console \
  --terminate-existing org.superrandom.embroiderydesigner -- -US316Capture <A0|B|C|D|E|A0-mixed>
```

The `--` matters: without it `devicectl` reads `-US316Capture` as its own option. The app selects the
fixture, plays it through, settles 2 s (C also zooms to 0.3 of the fit and settles 2 s more),
starts recording, begins the scripted gesture 0.1 s later, holds it 12 s, holds it still 0.1 s,
stops recording, ends the gesture, prints one `US316 …` line and exits (~35 s per run).

Under `xctrace` — **the form every D6 run uses**:

```
xcrun xctrace record --template 'Animation Hitches' --instrument 'Points of Interest' \
  --device 00008150-001525401181401C \
  --output build/instruments/us316-<condition>-<n>.trace --time-limit 60s --no-prompt \
  --launch -- org.superrandom.embroiderydesigner -US316Capture <condition>
```

- `--instrument 'Points of Interest'` is required: the Hitches template does not record app
  signposts (probe 1 had none of ours among its 326 signpost rows).
- The run's result line travels **inside the trace**, as a `result` Points-of-Interest event: the
  template records no unified log (its `os-log` table came back empty), and `--target-stdout -`
  printed nothing.
- The `capture` interval marks the recorded window. `plan`, `segmentPath`, `stroke`, `dotPath` and
  `fill` intervals attribute CPU work per frame (D9).
- Read a run with `python3 -I scripts/us316_trace_summary.py <run>.trace`: the result line, the
  window length, and the hitches **inside the window** (count, over 33.3 ms, worst), with the
  signpost totals. It resolves the export's `id`/`ref` compression (us-309 note 4).

## One hand run (calibration and acceptance)

Launch under `xctrace` exactly as above, with `-US316Capture <condition> -US316Hand` (and
`--time-limit 120s`): the hand flag applies the condition's live control but starts no session.
Then by hand: pick the condition's design (**Synthetic 50k**, or **Compact 50k** for B), Play,
wait for it to finish and 2 s more, tap **Record**, pan in slow circles with one finger
**without lifting it** for at least 12 s, tap **Stop** with another finger while still holding,
then lift. Record and Stop mark the same `capture` window and `result` event a driver run does
(marked `hand`), so the summary script reads both alike.

## Pilot runs (2026-10-29) — not data

Taken while building the instrument, **without Hitches traces**, so D6 does not count them. They
are recorded because they changed the instrument and because one of them is worth having in mind
before the calibration.

| # | build | condition | drawn / n | med | p99 | worst | verdict | what it showed |
|---|---|---|---|---|---|---|---|---|
| p1 | coverage on | A0 | 718 / 718 | 16.669 | 16.670 | 16.670 | DRAWS NOT MEASURED (2) | recording and the gesture began in one tick |
| p2 | coverage off | A0 | 719 / 719 | 16.669 | 16.670 | 16.670 | DRAWS NOT MEASURED (1) | one tick apart was not enough |
| p3 | coverage off | B | 719 / 719 | 16.669 | 16.670 | 16.702 | DRAWS NOT MEASURED (1) | |
| p4 | coverage off | A0 | 718 / 728 | 16.669 | 16.702 | 29.181 | FAIL (p99 clause only) | every draw timed; no frame > 33.3 ms |
| p5 | traced, one display link | A0 | 720 / 731 | 16.669 | 16.670 | 16.670 | PASS | 0 hitches inside the 12.2 s window (128 before it, in the pre-roll); `plan` 2.9 ms mean, 4.5 ms worst per frame |

Read with care: under the driver, A0's capsule showed **no frame over 33.3 ms in any pilot**, where
every hand capture since US-310 did (worst 38–50 ms). If the traced runs agree, A0 does not tail
under the surrogate, and D7's calibration decides whether that means the tail lives above the
coordinator (touch delivery) or that the driver is not a valid surrogate.

## Results

*(Filled in by the device session: calibration, then the matrix, one row per run with the capsule
line's fields and the trace's hitch count, hitches > 33.3 ms and worst hitch inside the window.)*
