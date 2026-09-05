# US-310 device hand-off — does coarsening reach the bar on real hardware?

US-310 coarsens the plan a live frame draws (ADR-029 fallback ladder rung 2, semantics pinned in
ADR-030). Everything that can be proved without hardware is proved: 752 engine tests, 197 app
tests, fifteen mutations, and a four-point simulator sweep. This file is the protocol for the part only a device can
answer, and it is deliberately short, because it reuses
[`us-309-device-handoff.md`](us-309-device-handoff.md) unchanged for the build, the device
conditions and the bar.

## What is already known, so the session is not re-deriving it

Simulator (iPhone 17, Release with `DEBUG`, 60 Hz), 50 001 stitches, three scripted 4-second
drags, quantiles over **drawn frames only**, `drawn = 230–231` in every capture:

| target | stride | med | p95 | p99 | worst |
|---|---|---|---|---|---|
| none (before US-310) | 1 | 36.129 | 49.177 | 56.292 | 86.858 |
| 4 000 | 13 | 33.333 | 34.943 | 46.693 | 55.316 |
| **1 000 (shipped)** | **51** | **16.667** | 33.871 | 52.857 | 56.019 |
| 250 | 201 | 16.667 | 33.465 | 49.174 | 58.974 |

Read this as: the **median** mid-gesture frame now fits one refresh period at a target of 1 000
(stride 51), a target of 250 reads no better, and **the tail does not respond to the stride at
all** — so the tail is not the coarse plan. It does **not** locate a knee: this instrument reports
only multiples of the refresh period, so 51 and 201 both read the floor and the transition lies
anywhere in (13, 51]. ADR-030 retracted that word and an earlier version of this file put it
back (`/codex-review` round 1, finding 6). The device read **69.1 ms** where this instrument reads 36.1, i.e. it is
roughly **1.9× slower on this path**, so the shipped target may well need to come down.

Two things the instrument cannot do, both of which shape what to record: a display-link interval
only reports **multiples of the refresh period** (16.667 / 33.333 / 50.0), so a frame costing
18 ms and one costing 33 ms read the same; and simulator absolute milliseconds are not
authoritative for the bar.

## Build

Exactly US-309's command (Release with `DEBUG` on the command line, `$(inherited)` included) —
see that file's **Build** section, including its warning that the Xcode UI route does **not**
reach the SwiftPM package targets and that a blanked target-level setting fails *silently* with
the fixture absent.

New in US-310: the frame-time readout is normally shown only for the `Synthetic 50k` fixture.
Launch with **`-US310FrameTimes`** to get it on *any* design, which is what makes a
small-design capture possible at all. From the command line:

```
xcrun devicectl device process launch --device <udid> org.catrobat.embroiderydesigner -US310FrameTimes
```

## The bar

**Unchanged, quoted from ADR-029**: over a ≥ 10 s capture, **p99 ≤ 16.67 ms and no frame >
33.3 ms**, reported as median / p95 / p99 / worst over drawn frames. US-309's AC8 forbids
rewording a criterion in response to a measurement, and nothing here rewords it. ADR-029's two
recorded objections to the bar itself (the p99 half has no discriminating power at 60 Hz; a
capture with no draws satisfies the numbers) are still open questions for the author and are
still not acted on.

## Captures

Each one: hold ≥ 10 s, Stop, read the row, screenshot it. Record the nominal rate the row
prints — a 30 Hz link makes every interval ~33.3 ms and fails both halves of the bar for reasons
that have nothing to do with the renderer.

1. **50 000 mid-gesture, shipped constants.** The one that matters: it is the direct successor to
   ADR-029's 69.1 ms row. Pinch *and* pan, since a pinch redraws on every touch move.
2. **50 000 mid-gesture, target sweep.** At least two of {2 000, 1 000, 500}, each needing its own
   build (the constant is `StitchDrawPlan.liveSegmentTarget`). The question is whether the median
   reaches one period on device, and how far the target can be *raised* while it still does —
   not whether it beats the simulator, and not where a "knee" is.
3. **3 194 mid-gesture (Octagon Rosette), with `-US310FrameTimes`.** The control: this design is
   below `liveCoarseningThreshold`, so US-310 changed nothing about it. If it regressed, the
   threshold is wrong or something outside the coarse path moved.
4. **50 000 animating.** ADR-029's animating capture **passed** at p99 16.670. It must still pass:
   the animating path is `.live(of:)` over the tail and should be untouched, so a regression here
   means `forFrame` is picking the wrong window.

## The question this session owns, beyond the bar

**Where is the tail?** The simulator says it is not the coarse plan. The candidates are the
gesture-end commit and the full re-bake it triggers, and ADR-029 already records that
distinguishing them needs *a run-state marker in the capture, which the recorder does not have*.
Cheapest discriminator without new code: take a capture that **holds one long gesture and never
lets go** (no commit, so no bake) and compare its tail against one with several short drags. If
the tail follows the number of gesture *ends* rather than the number of drawn frames, it is the
commit, and the fix belongs to rung 1 / the Θ(n²/chunk) bake schedule rather than to this rung.

## Judgement to bring back

- ~~The **coarse image**, in the hand, at two zoom levels~~ — **answered 2026-09-05, and the
  answer was no.** The hatch's edges frayed into comb teeth because spans were cutting the row
  turns; a corner rule now prevents that. **Re-check it**: the same pinch on the synthetic, both
  zoom levels, looking specifically at the left and right edges and at the boundary between
  colour bands. The simulator could not settle this — the screenshot that produced the original
  "indistinguishable" claim had the design's edges out of frame.
- The **pop** at gesture start and at commit: distracting, or unnoticeable?
- Whether the **discontinuity at the threshold** shows up in practice — a 4 001-stitch design
  strides by 5 while a 4 000-stitch one strides by 1.

## Still not this story's to close

The **A15-class capture** remains a milestone final-verification item
([`milestone-3/README.md`](user-stories/milestone-3/README.md#final-verification--deferred-to-milestone-close)),
as do the **Instruments (Animation Hitches) traces** — the only artefact that attributes the
residual between `Path` construction and ellipse scan-conversion, and therefore the only thing
that can decide ADR-030's recorded renderer-only alternative (`addRect` for `addEllipse` while
live).
