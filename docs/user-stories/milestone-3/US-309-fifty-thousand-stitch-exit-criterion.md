# US-309 — Exit criterion: 50k synthetic design at 60 fps

**Epic**: E4 Stage & preview | **Estimate**: ~4 h | **Depends on**: US-305, US-306, US-307

**Status**: Not started

**Story**: As the milestone, I want a measured 60 fps at 50 000 stitches on an A15-class device, so ADR-009's rendering bet is evidence rather than a claim.

ADR-009 was decided on reference analysis (Catty's node-per-stitch collapse, Catroid's batched renderer) and has never been measured on our code. This story closes that. `EmbroideryStream.addStitch/addJump/addColorChange` are all public, so a synthetic design can be built directly without running an interpreter.

## Acceptance criteria
- [ ] `SyntheticDesign` in `StagePreview` builds a 50 000-stitch display list directly, **and** — separately — a program that animates up to 50k, so both the steady state and the production path are measured.
- [ ] Frame times measured **on device** (A15-class) in a **Release** build, with before/after numbers recorded for the thesis. Simulator numbers are noted as non-authoritative.
- [ ] **Per-frame work is shown to be independent of total stitch count**: frame time at 50k settled + a 100-stitch live tail ≈ frame time at 5k settled + the same tail. This is the actual claim ADR-009 makes; a single 50k number would not test it.
- [ ] The rasterisation threshold and the re-rasterisation policy (including the mid-gesture blit from US-307) are tuned by measurement, and the chosen constants are documented **with the measurement that justified them** — not as bare magic numbers.
- [ ] Headless throughput guard under `swift test`: appending 50 000 stitches in 1 000 batches to a `StitchDisplayList` stays within a documented time bound. This catches an accidental O(n²) in `colorRuns`/`bounds` maintenance, which is the realistic regression — and it runs on the existing pre-commit gate, unlike the device measurement.
- [ ] The planning-session baseline is recorded for the record: **`assembled()` costs 0.64 ms/call at 50k stitches, 0.17 ms at 10k, 0.023 ms at 1k** (release, M-series Mac). This is the number that shows option B was *affordable* and was rejected on prefix stability, not on speed — the interesting part for the thesis, and the correction to the intuition that both references' per-frame rebuild was simply "too slow".
- [ ] Pan/zoom at 50k stays within budget, with the mid-gesture path measured separately from the settled path.
- [ ] If measurement misses 60 fps, the **fallback is stated** — coarser colour-run batching, `Path` reuse, or the Metal renderer behind US-305's existing protocol — rather than the criterion being quietly reworded. ADR-009 kept that escape hatch open precisely for this.
- [ ] **Story-specific definition of done**: screenshots at 50k both fitted and zoomed in; the VoiceOver summary from US-307 still reads correctly at 50 000 stitches (a plural-form and number-formatting check at scale).

## Test-first plan
1. Headless throughput/complexity guard, written first and shown **red against a deliberately O(n²) append** — a passing performance test that was never seen failing proves nothing.
2. Frame-time capture on device at 5k / 20k / 50k settled, tabulated.
3. Per-frame independence assertion across those three points.
4. An animated run to 50k with no dropped batch: display list count equals the interpreter's stitch-event count.
5. Pan and zoom at 50k measured, settled path and mid-gesture path separately.
6. Screenshots at 50k, fitted and zoomed.

## References
- ADR-009 (the rendering decision this story tests, including the Metal escape hatch and the 50k/60fps criterion it names), ADR-021 (why the display list is append-only with a settled watermark)
- `Catroid/.../stage/PenActor.java:46-77` — the `FrameBuffer` precedent for rasterising a settled prefix
- `Catroid/.../embroidery/DSTPatternManager.java` — `getEmbroideryPatternList()`, the per-frame full rebuild whose cost this story quantifies for our own code
- ROADMAP M3 exit criteria
