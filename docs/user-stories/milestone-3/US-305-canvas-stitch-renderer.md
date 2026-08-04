# US-305 — Canvas stitch renderer, fit-to-screen, empty state

**Epic**: E4 Stage & preview | **Estimate**: ~5 h | **Depends on**: US-302, US-303

**Status**: Not started

**Story**: As a user, I want to see the design drawn on a stage that fits the screen, so the preview is legible before I ever press play.

This is where ADR-009 becomes code. Both references get the rendering wrong in instructive ways: Catty creates **two** `SKShapeNode`s per stitch as direct scene children with no batching and no removal path, and Catroid batches its draw calls well but rebuilds the entire export model every frame. We take Catroid's per-primitive geometry, Catty's nothing, and ADR-009's cached-raster strategy — which Catroid itself already validates for pen drawing in `PenActor`'s `FrameBuffer`.

## Acceptance criteria
- [ ] `StagePreviewRenderer` protocol with `associatedtype Body: View`, taking `(display, transform, needle, viewport)`; `StageView` is generic over it. **No `GraphicsContext` in the protocol signature** — a context there *is* the Canvas leaking into the abstraction and would defeat ADR-009's Metal escape hatch. `CanvasStitchRenderer` returns a `Canvas`; a future `MetalStitchRenderer` returns something else.
- [ ] `CanvasStitchRenderer` draws **one stroked `Path` per colour run** for threads and one per colour run for penetration dots. Never one shape per stitch — that is the Catty anti-goal ADR-009 exists to forbid.
- [ ] Dot radius and thread width use the same value, ported from Catroid's `BrickValues.STITCH_SIZE = 3.15`, scaled by the transform. **Not** by device diagonal: Catty derives width from device-diagonal ÷ project-diagonal once at stream init and never recomputes it on rotation.
- [ ] No dot on jump or colour-change points (Catroid parity: `isConnectingPoint == !jumpPoint && !colorChangePoint`).
- [ ] **Jump traversals are drawn distinctly from thread** — via `EmbroideryStream.requiresTraversal` from US-302, so the app asks the engine rather than re-deriving ADR-020. This is a deliberate deviation from *both* references, which draw machine travel as solid thread indistinguishable from stitching. Documented fallback if the predicate runs hot or proves unreliable: draw every segment as thread, matching both references, recorded as a known limitation — `PreviewStitch.Segment` already accommodates adding it later.
- [ ] The 500×500 stage is drawn as a **hoop outline and is not clipped to**; the fit target is `union(stageRect, contentBounds)`, so a design that leaves the hoop is visible rather than silently cropped. Nothing bounds a `StagePoint` (US-302's `StageGeometry` doc comment says so), and showing the overflow is how the user learns before export tells them.
- [ ] The settled/live split is wired from the start: stitches below `settledCount` render from a cached raster, the live tail per frame. The baking threshold is a named constant with a comment; US-309 tunes it by measurement.
- [ ] **Empty state**: with no stitches, a localised "press play" state rather than a blank canvas. The loading state is unreachable and stated as such.
- [ ] **Thread colours must not adapt to dark mode** — they are design data. Only stage chrome (hoop, background, grid) is semantic-coloured; contrast checked in both appearances.
- [ ] **Story-specific definition of done**: screenshots at compact and regular, light and dark, with a sample loaded; the canvas's accessibility summary is deferred to US-307 and the canvas is not left as an unlabelled element in the meantime.
- [ ] Close-out pins **ADR-024**: the renderer's deviations from both references (distinct jumps, greenfield needle, dot/thread geometry, dark-mode rule).

## Test-first plan
1. Renderer *inputs*, not rendering: a recording renderer double asserts it is handed the expected display list and transform for a given viewport.
2. Colour-run grouping: a two-colour sample yields exactly two thread paths — asserted via the US-302 run partition, so no `Canvas` is needed.
3. Fit-to-screen: a design exceeding the stage produces a transform whose fitted content bounds include the out-of-stage extreme (i.e. it is not clipped away).
4. Settled/live split: after `markSettled(upTo: k)`, the per-frame drawn set is exactly `stitches[k...]`.
5. Segment classification: a > 121-unit op gap classifies `.traversal`, below it `.thread`, matching the engine predicate.
6. Empty display list produces the empty state, not a zero-stitch canvas.
7. Screenshot review across the four appearance/size-class combinations.

## References
- `Catroid/catroid/src/main/java/org/catrobat/catroid/stage/EmbroideryActor.kt` — the whole 99-line renderer: circle + `rectLine` geometry, the colour-change line suppression latch, and the `getEmbroideryPatternList()` per-frame rebuild trap
- `Catroid/.../stage/PenActor.java:46-77` — the `FrameBuffer` stamp: ADR-009's rasterisation strategy, already validated in the reference for a sibling feature
- `Catty/src/Catty/Extension&Delegate&Protocol/Extensions/SpriteNode/CBSpriteNodeEmbroideryExtension.swift:32-77` — two nodes per stitch, the confirmed anti-goal; `CattyTests/Stage/CBSpriteNodeStitchExtensionTests.swift` — the tests that institutionalise it
- ADR-007 (stage space, no y-flip in the engine), ADR-009 (Canvas with batched paths), ADR-020 (the traversal trigger), ADR-024 (this story's close-out)
