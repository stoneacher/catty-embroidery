# US-315 — The canvas and the hoop come apart while the keyboard animates

**Epic**: E4 Stage & preview | **Estimate**: ~3 h ⏱ **timebox, not an estimate** | **Depends on**: US-409 (sequencing only)
**Discovered**: 2026-09-17, US-313b device session (Sebastian, on the phone). **Scheduled into M4**: 2026-09-19.

**Story**: As a user, I want the design and the hoop to stay locked together while the keyboard appears, so the design does not appear to jump outside the hoop.

⏱ **The diagnosis *is* the story.** Three hours buys the device recording and a verdict. If the verdict is "reproduced and understood, but the fix is large", the fix becomes a new story and this one closes on the diagnosis. That is the deliverable; a fix is the hoped-for bonus.

## Problem

Focusing the design-name field glitches the drawn canvas while the keyboard animates in or out — the **design and the hoop field are briefly drawn at different transforms**, so the design sits off-centre and spills outside the hoop onto the mat. Visible in the session's screen recording at 3.01 s with the keyboard mid-dismiss. Every *committed* state before and after is correct; this is a transient, the class ADR-028 records as invisible to stills, and it has now produced **four** defects across M3 and M4's inheritance.

## Already ruled out — written down so the next attempt does not spend the same hour

Two mechanical explanations were built and **refuted by reading the code**:

1. *A stale cached raster composited into the new size.* `CanvasStitchLayers.BakeKey` includes `width` and `height`, so a resize changes the key, `baked?.key != bakeKey`, and `compositingRaster` returns false — the frame takes the full-stroke path at `transform.current`.
2. *An explicit `settled` transform that does not follow the viewport.* True of `settled` itself, but the hoop field is drawn by `StageFieldView(transform: render.current)` — the **same** value the renderer strokes with, so the two cannot disagree by that route.

**Not reproducible on the simulator**, tried three ways: focusing the field from a fresh fit (the export row hides, so the canvas resizes with no keyboard at all); with the software keyboard enabled; and at 200 % zoom with `settled` non-`nil`. All settle correctly, and no intermediate frame showed the mismatch when sampled at 20 ms from a 60 fps `simctl recordVideo`.

**Not US-313b's.** Nothing that story changed is on this path: the catcher is an overlay that draws nothing, and the renderer, the bake key and the field are untouched by it. The interaction is US-308's name field against US-305's canvas.

## Why it is scheduled here, after US-409

US-409's palette is a **detented sheet that resizes the stage area** — the same transient class, a view whose frame is animating while the canvas draws. Two consequences, and both argue for this position:

- The palette may hand this story a **simulator-reproducible** instance of the bug, which is precisely what two device sessions have failed to produce. A sheet detent drag is a slower, more controllable frame animation than a keyboard.
- Doing this story *first* would risk US-409 shipping a second instance of the defect it had just fixed.

## The next step is a question, not a fix

The missing variable is the **interaction state before focusing**: had the stage been zoomed or panned, and does it reproduce from a fresh fit? A device recording of both discriminates.

After that, the two remaining suspects:

1. **SwiftUI snapshotting and scaling a view whose frame is animating** — the canvas would be a *rendered* layer being interpolated rather than re-stroked, which would explain why the bake key argument does not save us.
2. **The `SettlingProgress` shim's captured closure holding a stale value from the previous layout pass.** `StageCanvas.swift:92-104` documents the staleness and is worth reading before starting, **because the backlog entry described its reasoning wrongly and this story inherited that**. The comment does **not** argue "a manipulation and a fit animation cannot coexist" — it explicitly says that argument **is false** and was already retracted (`swift-code-reviewer`, Q3). Its live argument is narrower: every mutation of `manipulation` goes through the `@State` setter, so the outer body is re-evaluated and the closure rebuilt before the next render, and `baseline(fitting:settlingAt:)` ignores progress once the phase is not `.settling`.

 So the hypothesis has to be restated rather than inherited: **does a keyboard-driven layout change rebuild that closure?** It is not a `manipulation` mutation, so the stated mechanism does not obviously cover it. That is a real question — and it must be asked against the comment's *current* argument, not the retracted one.

## Acceptance criteria

- [ ] **A device recording of both conditions** — focus the name field from a fresh fit, and after a zoom/pan. Owner: Sebastian; this cannot be done from here.
- [ ] **An explicit outcome even if neither recording reproduces it.** "Not reproduced" is a permitted and useful result, and it ends the timebox: record the two conditions tried, the sampling rate, and a recommendation (close as not-reproducible, or keep open with the next condition named). Requiring a mismatch frame unconditionally would be unsatisfiable when the transient does not appear.
- [ ] **A verdict on each of the two remaining suspects** — confirmed with evidence, refuted with a reason, or **explicitly recorded as not examined and why**. Those three are the permitted outcomes; "unexamined" is an outcome, not a gap, provided the timebox is what stopped it.
- [ ] **If the palette reproduces it**, a simulator-reproducible case is captured — the artefact worth more than the fix, because it turns a device-only transient into something a test or a repeatable capture can watch.
- [ ] If the cause is found **and** the fix is small, it ships with a test at whatever level the cause permits. If the fix is large, a new story is written with the diagnosis and this one closes.
- [ ] Either way, ADR-028's transient-class note gains a dated line recording what this class has now cost: four defects, none visible to a still.

## Test-first plan

Deliberately thin, and honestly so: **this story's first deliverable is evidence, not a test.** Writing tests before the mechanism is known would be writing tests against a guess — and ADR-032 invariant 2 says a test that cannot fail is worse than none.

1. *(Only once the mechanism is known)* A test at the level the cause permits — a transform-equality assertion across a simulated resize if the cause is in `StagePreview`; a capture-based check if it is in the view layer.
2. If the cause turns out to be the `SettlingProgress` staleness, a test that drives a **layout change** while a fit animation is in flight — the combination the comment's live argument (rebuild-on-`@State`-mutation) does not obviously cover, since a layout change is not a `manipulation` mutation.

## References

- ADR-028 (the transient class, invisible to stills), ADR-029/ADR-030 (the frame instrumentation available for captures)
- `StageCanvas.swift:92-104` — the `SettlingProgress` staleness comment. Read the *current* text: its "manipulation and animation cannot coexist" argument is explicitly retracted there, and the backlog entry that seeded this story cited the retracted version.
- US-313b device session, 2026-09-17 — the recording at 3.01 s
- `docs/user-stories/backlog.md` — the original entry
