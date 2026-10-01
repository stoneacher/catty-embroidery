# US-315 — the keyboard transient, captured

Every image here is a sheet of **consecutive frames from one keyboard animation**, on the iPhone 17
simulator with the 50 001-stitch `Synthetic 50k` fixture run to the end. Each frame is cropped to the
stage, its caption and the name field. None of these states can be seen in a still.

| File | Build | What it shows |
|---|---|---|
| `01-shipped-dismiss-design-spills-past-mat.jpg` | `main` (plus a logging probe) | Keyboard dismiss. The mat and the hoop animate with the stage's frame, while the design is already drawn at its final size. It spills past the mat over "Hoop 100 mm × 100 mm" and "Design name". |
| `02-h1-no-bake-off-centre-and-spills.jpg` | baking disabled | The same dismiss, with the raster's re-bake taken out. The design is also **off-centre**, which is the symptom first seen on the device. |
| `03-variants-none-nobake-drawinggroup-merged.jpg` | one build, variant switched at runtime | One row per variant, three frames each: shipped, no bake, `.drawingGroup()` on the pair, field drawn in the stitch `Canvas`. Only the last row stays locked. |
| `04-fix-fresh-fit-locked.jpg` | this branch | Dismiss and focus with the fix. The hoop and the design agree in every frame. |

## Reproducing it

`capture/` holds the tools that produced these sheets. They are not part of the app.

1. Build `capture/frames.swift` (AVFoundation, no ffmpeg needed) and `capture/tile.swift` with `swiftc -O`.
2. On the simulator, open the stage for `Synthetic 50k`, play it to the end, and focus the name field.
3. Raise the software keyboard with **⌘⌥K** in Simulator. A relaunch hides it again.
4. Run `SIM=<udid> OUT=<dir> bash capture/capture.sh <name>`. It records dismiss → focus → dismiss and
   extracts every frame.
5. `simctl` writes a frame only when the screen changes, so a burst of closely spaced timestamps marks
   an animation. Tile that burst with `tile`.

**The zoomed condition was not captured on the simulator.** A scripted double tap did not land, so
it is covered only by the device recording.
