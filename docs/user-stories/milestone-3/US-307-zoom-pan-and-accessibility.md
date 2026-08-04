# US-307 — Pinch-zoom / pan and the stage VoiceOver summary

**Epic**: E4 Stage & preview | **Estimate**: ~3 h | **Depends on**: US-302, US-305, **US-306**

**Status**: Not started

**Story**: As a user, I want to pinch and drag the stage to inspect stitches closely; and as a VoiceOver user, I want one spoken summary of what the stage holds rather than tens of thousands of elements.

The roadmap gates zoom/pan on "only if the ADR-009 transform work makes it nearly free". US-302 delivers the math and its tests, so it is — the view only composes gestures and calls pure methods. The accessibility summary lands here rather than in US-305 because its content (stitch count, colours, size in mm) is only meaningful once a run can produce it.

## Acceptance criteria
- [ ] `MagnifyGesture` and `DragGesture` composed simultaneously, writing `StageTransform` through the US-302 pure methods. **No transform math in the view.**
- [ ] Pinch is anchored: the stage point under the user's fingers stays fixed. Zoom clamped to documented min/max; double-tap resets to fit.
- [ ] During a gesture the settled raster is blitted *through* the transform (a GPU scale) and re-rasterised on gesture end. The mid-gesture crispness loss is an accepted, **stated** trade-off rather than a surprise.
- [ ] Gestures work during a run without dropping batches.
- [ ] **The canvas is a single accessibility element** with a summary value: design name, stitch count, colour count, and size in millimetres (embroidery units × 0.1 from the export model when present, else display bounds × 0.2 per ADR-007's 1 pt = 0.2 mm). The hint describes the run state and the available adjust actions.
- [ ] **The summary updates on run-state transitions only, never per batch.** A value changing 60×/s makes VoiceOver unusable. This is the story's headline definition-of-done item and it is asserted by call count, not by inspection.
- [ ] Zoom is reachable **without gestures**: `.accessibilityAdjustableAction` (increment/decrement) on the canvas element, so VoiceOver and Switch Control users can zoom at all.
- [ ] Reduce Motion: the double-tap-to-fit transition is instant (the transform spring is decoration; the stitch animation from US-306 is not).
- [ ] **Story-specific definition of done**: a real VoiceOver pass on simulator or device, plus screenshots at two zoom levels; the mm figure verified against a known sample (sample 1 is ~98.6 × 98.6 mm).
- [ ] Close-out records the zoom min/max, the adjustable-action step, and the mid-gesture raster policy.

## Test-first plan
1. Anchor invariance: pinching by 2× about a given view point leaves that point's stage coordinate unchanged (pure, runs under `swift test`).
2. Clamping holds at both ends; double-tap-to-fit reproduces `StageTransform.fitting(...)` exactly.
3. Summary builder: for sample 1 it reads "3194 stitches, 1 colour, 98.6 by 98.6 millimetres" — localised and plural-aware through the String Catalog, not string-concatenated.
4. The summary builder's call count across a multi-batch run equals the number of state transitions, not the number of batches.
5. The adjustable action changes scale by the documented step and respects the clamps.
6. Size-in-mm uses the export model when present and display bounds otherwise, and both agree for a sample with no rejected coordinates.

## References
- ADR-007 (1 pt = 2 embroidery units = 0.2 mm — the mm conversion), ADR-009 (the transform is `CGAffineTransform` applied to the context; unit-testable math), ADR-010
- ROADMAP.md M3 in-scope note: "pinch-zoom/pan only if the ADR-009 transform work makes it nearly free"; ROADMAP.md:14 — "the stage canvas gets a summarizing label: stitch count, colors, size in mm"
- `Catty/src/Catty/Embroidery/EmbroideryStream.swift:54-65` — device-diagonal-derived stitch size that never recomputes: why the transform, not the device, owns scale
