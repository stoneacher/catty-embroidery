# US-302 — Preview core: colour-resolved stitch events, display list, transform math

**Epic**: E4 Stage & preview | **Estimate**: ~5 h | **Depends on**: US-301

**Status**: Not started

**Story**: As the app layer, I want stitches to arrive already carrying their colour and to accumulate in an append-only display list with unit-tested zoom/pan math, so the preview never re-implements engine semantics and never re-assembles the stream per frame.

This story implements ADR-021 and ADR-022. It is the milestone's load-bearing story: everything render-side depends on it, and because `StagePreview` is Foundation-only, the exit criterion "zoom/pan transform math is unit-tested" is met here under `swift test` with no simulator.

`InterpreterEvent`'s embroidery payloads are documented as **provisional** — "chosen to carry what US-206's producers will need so the enum need not be reshaped then". M3 is the first real *consumer*, so reshaping now is what that comment invited.

## Acceptance criteria
- [ ] `InterpreterEvent.stitch` carries `color: ThreadColor`, supplied by a new public read-only `EmbroideryPatternManager.threadColor(for actor: ActorID) -> ThreadColor`. No new dependency edge: `InterpreterEvent` already imports `EmbroideryEngine` and already carries `ActorID`, `StagePoint` and `NeedleUpdate`, so ADR-016 is unaffected.
- [ ] Reading `threadColor(for:)` before or after `addStitch` yields the same value — `addStitch` captures `let color = colorState.current` up front and only clears `pendingChange`. Asserted, because this invariant is what makes the change two lines in the producer rather than a refactor.
- [ ] `.colorArmed` is unchanged and **no preview code path consumes it**. The app performs no ADR-015 reasoning: not the silent start, not the invalid-hex no-op, not clause-B black, not the `==121` tie-off.
- [ ] New `StagePreview` target and product (depends on `Interpreter` + `EmbroideryEngine`), **Foundation-only** — no SwiftUI, no CoreGraphics. Transform math is `Double`-based; the app adds a small `CGAffineTransform` adapter in US-305.
- [ ] `StitchDisplayList` is append-only, never reordered, with incrementally maintained `colorRuns` (a gapless partition of `stitches.indices`), `bounds`, and a `settledCount` rasterisation watermark. Appending N stitches is O(N) regardless of how many are already held — no rescan.
- [ ] `StageTransform` is pure `Double` math: fit-to-content, pinch about an anchor, drag, zoom clamping, and both directions of the stage↔view mapping. **The y-flip exists in exactly one function.** Stage space is y-up and the engine applies no y-flip (ADR-007), so the flip is purely the renderer's; confining it makes a future "why is my design mirrored?" a one-line diff.
- [ ] `StageGeometry` puts ADR-007's 500×500 stage into code for the first time, with a doc comment stating explicitly that it does **not** bound engine input — nothing bounds a `StagePoint` and a design can legitimately leave the stage.
- [ ] `RunBatch.reducing(_:from:)` folds `[InterpreterEvent]` into stitches + last needle pose + terminal marker as a **pure function**, so US-306's batching is tested here rather than behind an actor.
- [ ] `EmbroideryStream.requiresTraversal(from:to:)` is public and agrees with whether `append` actually interpolated, proven differentially. Note the shape risk: ADR-020's dual trigger currently reads `stitches.last` for the encoded-delta half, so as a static it must use `EmbroideryPoint(converting: previous)` instead. Those are believed to agree in a real stream but that is **not proven** — hence the differential test, not an assertion.
- [ ] **Display model ≠ export model, deliberately.** A test pins that the display list's colour sequence matches the assembled stream's for a single-object sample. Clause C/D re-emits and interpolation intermediates differ only in record sequence (duplicates and on-segment points, so the drawn path is identical). **Clause B differs in colour and must have its own multi-actor test**: when an actor changes on a layer, the replay emits transition point(s) at the previous actor's workspace position in explicit black, which the display list never contains — so a two-actor design's export and preview genuinely disagree about colour there. M3's samples are single-object so it is not user-visible in this milestone, but the test must exist and the difference must be asserted rather than assumed away. Catroid needed `EmbroideryExportIsolationTest` for the same separation.

## Test-first plan
1. A one-brick colour program: the `.stitch` event's colour is the armed colour; setting an invalid hex leaves it unchanged — proving the app inherits ADR-015 without implementing it.
2. Order-insensitivity of `threadColor(for:)` across an `addStitch` call.
3. Sample 2 from US-301: the display list's colour-run boundary lands on the same stitch index as the assembled stream's colour change.
4. `StitchDisplayList`: appends preserve order; `colorRuns` partition `stitches.indices` with no gaps or overlaps; `bounds` equals a from-scratch min/max; `markSettled` moves `liveTail` and nothing else; `reset` empties everything.
5. `StageTransform` round-trip: `stagePoint(of: viewPoint(of: p)) ≈ p` across a spread of points and scales.
6. y-flip direction: stage `(0, +250)` maps to a *smaller* view y than `(0, −250)`. Fit-to-content centres and preserves aspect for a non-square viewport.
7. Pinch about an anchor leaves the anchor's stage point fixed; clamping bounds scale at both ends; drags compose additively.
8. `requiresTraversal` differential, on **both** of ADR-020's triggers — random pairs alone are not enough, because the difference trigger dominates them and a predicate that checks only that trigger would pass while being wrong exactly at the crash boundary (Codex round 1). Required explicit cases: the journal's rounding seam `previous (0.125, 0) → target (60.75, 0)`, where the *difference* distance is 121 but the *encoded delta* is 122, plus its mirror; then random pairs as breadth. And the oracle must compare **records added by that one call**, not the stream's total count — `(0,0) → (1,0)` already leaves more than one record in the stream and would be a false positive.
9. Multi-actor clause-B case: two actors on one layer, and the assembled stream's black transition point(s) are absent from the display list. Asserts the divergence rather than the agreement.
10. `RunBatch.reducing`: concatenating the reductions of every `step()` batch equals the reduction of `run(maxTicks:)`'s events — ADR-018's structural invariant, one layer up.

## References
- `Packages/EmbroideryEngine/Sources/EmbroideryEngine/EmbroideryPatternManager.swift` — `addStitch` clauses A–E, `assembled()` (the `layerOps.keys.sorted()` replay that ADR-021 rejects for per-frame use)
- `Packages/EmbroideryEngine/Sources/Interpreter/InterpreterEvent.swift` — the "provisional payload" comments this story acts on
- `Packages/EmbroideryEngine/Sources/EmbroideryEngine/Geometry.swift` — `StagePoint`, `EmbroideryPoint(converting:)`, `stitchPointUnitFactor`
- ADR-009 (batched paths, rasterised settled prefix), ADR-015 (colour semantics the app must not duplicate), ADR-016, ADR-020 (the traversal trigger), ADR-021, ADR-022
- `Catroid/.../test/embroidery/EmbroideryExportIsolationTest.kt` — display/export separation, same concern
- `Catty/src/Catty/Embroidery/EmbroideryStream.swift:161-169` — the producer→renderer seam worth porting, with the cursor as an index rather than a second mutated array
