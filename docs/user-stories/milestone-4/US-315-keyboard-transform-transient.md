# US-315 — The canvas and the hoop come apart while the keyboard animates

**Epic**: E4 Stage & preview | **Estimate**: ~3 h ⏱ **timebox, not an estimate** | **Depends on**: US-409 (sequencing only)
**Discovered**: 2026-09-17, US-313b device session (Sebastian, on the phone). **Scheduled into M4**: 2026-09-19.

**Status**: In review — 2026-10-01, [PR #65](https://github.com/stoneacher/catty-embroidery/pull/65). **Reproduced on the simulator for the first time, diagnosed, and fixed within the timebox.** Cause: the hoop field and the design were two sibling `Canvas` views, and while the keyboard resized the stage SwiftUI presented them under different geometry. The fix draws the field in the stitch `Canvas`'s own pass. The device recordings (criterion 1) are still owed by Sebastian, before and after the fix. A second, unrelated defect found on the way became [US-322](../backlog.md).

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

- [ ] **A device recording of both conditions** — focus the name field from a fresh fit, and after a zoom/pan. Owner: Sebastian; this cannot be done from here. *Open. The simulator now reproduces the defect from a fresh fit (see the Outcome), so this recording confirms the fix on hardware rather than finding the bug. The zoomed condition rests on it entirely, because a scripted double tap did not land on the simulator.*
- [x] **An explicit outcome even if neither recording reproduces it.** *Reproduced, so the "not reproduced" branch does not apply. The outcome is recorded below.*
- [x] **A verdict on each of the two remaining suspects.** *Suspect 1 is confirmed, in a narrower form than stated. Suspect 2 is refuted, by reading and by measurement. See the Outcome.*
- [x] **If the palette reproduces it**, a simulator-reproducible case is captured. *The premise was wrong: the palette never resizes the stage. The palette is presented from the script list's Add button, and on compact the stage is a separate pushed screen, so the two are never on screen together. `RootView.swift:43-45` also closes the palette on the one size-class swap that would put the stage on top. On iPad the palette is a popover over the script column. The **keyboard** reproduces it on the simulator instead, once the software keyboard is raised (⌘⌥K). The repeatable capture is in [`docs/screenshots/us-315/`](../../screenshots/us-315/), and the tools are in its `capture/` folder.*
- [x] If the cause is found **and** the fix is small, it ships with a test at whatever level the cause permits. *Small (one pass instead of two views), so it ships. It has a unit test of the field geometry the merged pass draws (`StageFieldTests`, red first on behaviour) and the frame capture as evidence for the merge itself, which no unit test can see.*
- [x] Either way, ADR-028's transient-class note gains a dated line. *Added 2026-10-01.*

## Test-first plan

Deliberately thin, and honestly so: **this story's first deliverable is evidence, not a test.** Writing tests before the mechanism is known would be writing tests against a guess — and ADR-032 invariant 2 says a test that cannot fail is worse than none.

1. *(Only once the mechanism is known)* A test at the level the cause permits — a transform-equality assertion across a simulated resize if the cause is in `StagePreview`; a capture-based check if it is in the view layer.
2. If the cause turns out to be the `SettlingProgress` staleness, a test that drives a **layout change** while a fit animation is in flight — the combination the comment's live argument (rebuild-on-`@State`-mutation) does not obviously cover, since a layout change is not a `manipulation` mutation.

## Outcome — 2026-10-01

**How it was reproduced.** The 50k fixture was run to the end on the iPhone 17 simulator, the software keyboard was raised, and the name field was dismissed, focused and dismissed again. `simctl io recordVideo` writes a frame only when the screen changes. Frames were extracted with AVFoundation and the bursts tiled. An uncommitted DEBUG probe logged every `Canvas` draw, with its `size`, transform and raster decision, plus each re-bake and each focus change. The two earlier simulator attempts missed it because the software keyboard was never raised: focusing with a hardware keyboard only hides the export row, and this design is width-bound, so the canvas never resizes.

**What the probe showed.**
- **Each `Canvas` is drawn once per layout change, not once per animation frame.** Over a whole keyboard animation there were one or two draws per `Canvas`, jumping straight between sizes: focus 309 → 172 pt, dismiss 172 → 309 → 257 pt. Everything on screen in between is SwiftUI presenting views that were already drawn.
- **Dismiss is two layout changes about 50 ms apart**: the keyboard leaving, then the export row returning (`StageView`'s `!isNameFocused` branch).
- **After every layout change the stitch `Canvas` alone gets a second draw.** The resize changes `BakeKey`, so `rebakeIfWorthwhile` writes `@State baked` 20–40 ms later, while the keyboard is still animating. The field `Canvas` is never redrawn.

**What the frames showed** ([`docs/screenshots/us-315/`](../../screenshots/us-315/)). Mid-dismiss, the mat and the hoop field follow the stage's animating frame, while the design is already drawn at its final size. It spills past the mat, over the caption and the name label. With baking off it is also **off-centre**, which is the symptom first seen on the device.

**Verdicts on the suspects.**
1. **SwiftUI snapshotting and scaling a view whose frame is animating — confirmed, in a narrower form.** The `Canvas` views are not re-stroked during the animation, and the two **sibling** `Canvas` views are not presented under the same geometry while the frame animates. Discriminated with one build, switching variants at runtime:
   - **Baking off:** still comes apart, in a different shape. So the mid-animation re-bake affects the separation but is not its cause.
   - **`.drawingGroup()` on the pair:** still comes apart. So flattening them into one offscreen pass is not enough.
   - **Field drawn inside the stitch `Canvas`:** locked in every sampled frame.

   **What is not established** is *why* SwiftUI treats the two siblings differently. The fix does not depend on the answer: one pass cannot disagree with itself, whatever SwiftUI does with an animating frame.
2. **The `SettlingProgress` shim's closure holding a stale value — refuted.**
   - *By reading:* a layout change resizes the `GeometryReader`, which re-runs its content and rebuilds `viewport`, `fitted` and the shim's closure. `render` is computed once per evaluation (`StageCanvas.swift:106`), and every layer is handed that one value.
   - *By measurement:* the probe shows the field and the stitches drawn with identical transforms, at identical sizes, in every logged draw.
   - So "does a keyboard-driven layout change rebuild that closure?" — yes, through the `GeometryReader`, not through the `@State` setter the comment names.
   - One staleness does exist and is not this bug: a fit animation in flight during a resize keeps its old endpoints, and snaps to the new fit at the end. All layers agree while it does.

**Review (`swift-code-reviewer`, in a worktree, with mutations).** The fix is sound: one closure, one `transform.current`, an unchanged `BakeKey`, a transparent baked image (`Image(size:)` is not opaque), and nothing lost for VoiceOver, because a `Canvas` exposes no children. Findings and what was done about them:
- **Three comments were wrong.**
  - The `Color.clear` claim: corrected, see below.
  - "Today they are equal" in `CanvasStitchRenderer`, which US-322's measurement contradicts: corrected, with a pointer.
  - "whenever the keyboard resized": reworded.
  The reviewer's call to retract "can differ by a fraction of a point" was **rejected**, because the probe measured exactly that. The comment now cites the numbers.
- **Mutants of the merged pass survived the geometry tests.** The survivors were the deleted `StageField.draw` call, the field drawn after the strokes, and the field drawn at `bake`. `StageFieldRenderingTests` (`ImageRenderer`, three pixels) now kills all three, each applied and measured. Its mat probe was written to also catch `bake`, and measured, it does not; its title says so.
- **The needle is still a sibling layer**, so it is exposed to the same class. This is documented at the call site rather than fixed. Keeping it out of the bake key was ADR-024's reason for making it a separate layer.
- **The renderer contract is not enforced**: a renderer that skips the field shows the mat and no hoop. Stated in `StagePreviewRenderer`.

**The fix.** `StageField` (geometry as a value, plus a draw function) is drawn first in `CanvasStitchLayers`' own `Canvas` pass, at `transform.current` and at the `Canvas`'s own `size`. `StageFieldView` is gone. Consequences, recorded rather than hidden:
- **The field is now the renderer's job.** `StagePreviewRenderer` says so: a future renderer must draw it, through `StageField.geometry`.
- **`StageCanvas` keeps a `ZStack { Color.clear; renderer }` around the renderer.** With the field view gone, hanging the modifiers straight on the renderer's body failed the hosted wiring tests (six in the first run, five in the reviewer's mutant). Their renderer double returns `EmptyView`, and the catcher never reached the hierarchy. **It is the `ZStack` that fixes that, not `Color.clear`.** An earlier version of this note and of the code comment said otherwise; `swift-code-reviewer` measured it. `Color.clear` keeps the other half of what the field view gave, a view that fills the slot whatever the renderer returns. No test pins it, and that mutant survives.
- **The field is not baked.** It is three fills, and keeping it out of the raster leaves `BakeKey` unchanged.
- **The needle is still a sibling layer**, as ADR-024 intends. It could in principle drift the same way, but it was not visible in any capture, because the needle is absent once a run has finished. That is recorded as unexamined.

**Found on the way, and not this story's: [US-322](../backlog.md).** On iPhone 17 the stage's default layout measures a viewport of 370 × **256.83** pt, while the `Canvas` gets 370 × **257.0**. `compositingRaster`'s exact size comparison therefore never passes there. One full 50k run drew 251 of 251 frames on the full-stroke path and baked 51 times, discarding every bake.

## References

- ADR-028 (the transient class, invisible to stills), ADR-029/ADR-030 (the frame instrumentation available for captures)
- `StageCanvas.swift:92-104` — the `SettlingProgress` staleness comment. Read the *current* text: its "manipulation and animation cannot coexist" argument is explicitly retracted there, and the backlog entry that seeded this story cited the retracted version.
- US-313b device session, 2026-09-17 — the recording at 3.01 s
- `docs/user-stories/backlog.md` — the original entry
