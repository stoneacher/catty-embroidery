# Android reference exports (Brick backend)

External goldens for Arc and GoThrough: `.dst` files exported by Sebastian on 2026-10-17 from the Android **Embroidery Designer** (Catroid `embroideryDesigner` flavour) on a physical phone. They are the only external check of the brief's D5 feed rule (`docs/features/brick-backend.md`). Compare at ±1 DST unit (Android computes in `float`, we compute in `Double`; ADR-014).

**Canonical files: `2nd_run/`.** Each was exported from a project holding a single object with a single script.

| File | Program (one object, **When scene starts**) | Screenshot | Result |
|---|---|---|---|
| `2nd_run/arc_run.dst` | Set transparency 100 % · Pen down · Start running stitch 10 · Arc **left** r 50, 360° · Arc **right** r 30, 90° · Move 40 steps | `Screenshot_20261017-212407.png` | ST 40, ends (56, −122) units |
| `2nd_run/arc_zigzag.dst` | Set transparency 100 % · Pen down · Start zigzag stitch length 2, width 10 · Arc **right** r 50, 180° · Move 50 steps | `Screenshot_20261017-212707.png` | ST 104, ends (−98, −202) |
| `2nd_run/go_through.dst` | Set transparency 100 % · Pen down · Start running stitch 10 · Go through (50, 100) then to (100, 0) · Go through (0, 0) then to (−100, 0) | `Screenshot_20261017-213050.png` | ST 43, ends (−180, 0) |
| — (degenerate) | Set transparency 100 % · Pen down · Start running stitch 10 · Arc left r **0**, 90° · Arc left r 50, **0°** | `Screenshot_20261017-213345.png` | **Nothing drawn, so no export is possible** (Catroid refuses fewer than two points). This is the reference result: degenerate arcs add no stitches. |

Notes:

- **The programs deviate from the requested ones in two harmless ways.** The arc in `arc_zigzag` turns right rather than left, and every program starts with Set transparency and Pen down, which do not affect stitches. The object starts at (0, 0), facing 90°.
- **There is no Write embroidery to file brick.** The files were exported from the stage, so `LA` is the export file name.
- **The first DST record is the origin.** The first stitch is `S(0,0)`.
- **`go_through` stops one stitch short.** The straight run from (100, 0) to (−100, 0) stage ends at −90 stage (−180 units) and has no stitch at −100, although 200 is an exact multiple of the stitch length 10. The guess that `float` arithmetic caused it was **wrong**: slice 5's `Double` implementation stops at −90 too and matches the file exactly. The cause is geometry. The first curve's last stitch sits at (100, 1) stage, above the axis, so the running stitch measures the straight run from there, and its last full step falls short of the end.
- **Top-level files: the first run, superseded.**
  - The project held several objects and the export merges all of them. As a result, `go_through.dst` holds the GoThrough object, then a colour change, then the `arc_run` object, and `degenerate.dst` holds only the `arc_run` object's stitches.
  - `arc_run.dst` is byte-identical to `2nd_run/arc_run.dst`.
  - `arc_zigzag.dst` has the same stitches as its re-export, under the label `arc_run (1)`.
  - They are kept as the record of that mistake, not as goldens.
- **App version:** not recorded yet.
