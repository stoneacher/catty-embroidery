# Android reference exports — provenance

**External goldens**, not our engine's output. Each file was exported on 2026-10-17 by Sebastian from the Android **Embroidery Designer** (Catroid `embroideryDesigner` flavour) on a physical phone. Each comes from a project holding one object with one script. They are byte-identical copies of `docs/android_refs/2nd_run/`, whose README records each program, its screenshot and the export quirks.

They are the only external check of the Arc/GoThrough feed rule (brief `docs/features/brick-backend.md`, D5). Comparisons are per stitch, on absolute positions, within ±1 DST unit: Android computes positions in `float`, we compute them in `Double` (ADR-014). The stitch count must match exactly.

| File | Program (object starts at (0, 0), facing 90°) |
|---|---|
| `arc_run.dst` | Start running stitch 10 · Arc left r 50, 360° · Arc right r 30, 90° · Move 40 steps |
| `arc_zigzag.dst` | Start zigzag stitch length 2, width 10 · Arc right r 50, 180° · Move 50 steps |
| `go_through.dst` | Start running stitch 10 · Go through (50, 100) then to (100, 0) · Go through (0, 0) then to (−100, 0) |

Set transparency and Pen down bricks preceded each program on the phone and do not affect stitches. The degenerate program (arcs of radius 0 and of 0°) drew nothing and could not be exported. That absence is its reference result.
