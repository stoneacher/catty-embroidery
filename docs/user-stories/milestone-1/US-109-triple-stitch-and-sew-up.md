# US-109 — Triple stitch pattern and sew-up

**Epic**: E2 Engine | **Estimate**: ~3 h | **Depends on**: US-107

**Status**: Done — 2026-07-14, PR #13

**Story**: As a program, I want a reinforced triple stitch pattern and a sew-up primitive, so that seams are durable and thread ends are secured.

## Acceptance criteria
- [x] `TripleStitchPattern(steps:)` conforming to the `StitchPattern` protocol: forward–back–forward at each interval, matching `TripleRunningStitch` semantics (each segment stitched three times). *(Amended to `(length:start:)`: `length` keeps the label shared by `RunningStitchPattern`/`ZigzagStitchPattern` — Catroid's `steps` is the same quantity — and the anchor is passed explicitly per the US-107/108 rationale.)*
- [x] `SewUp` primitive: Catroid's **5-point** sequence center/ahead/center/behind/center (STEPS = 3 px along the heading) — not Catty's 4-point variant (ADR-012).
- [x] Both compose with the stream and lifecycle exactly like the other patterns (pause/resume interplay on the US-107 lifecycle wrapper: running stitch is paused around a sew-up, as in Catroid).
- [x] Known interaction with US-110's dedup rule, made explicit in a test: if the needle just stitched at the sew-up's center, the dedup drops the first center point and 4 records are emitted — this matches Catroid. *(The single-actor slice of the dedup rule landed here in `EmbroideryStream.addStitch` to make this test executable; US-110 keeps the actor/layer/color dimensions.)*

## Test-first plan
1. Triple stitch on a straight line: expected stitch sequence (positions visited 3× per step) ported from `TripleRunningStitchTest`.
2. Sew-up: exact 5-stitch sequence at a point, ported from `SewUpTest`.
3. Interplay test: sew-up during active running stitch pauses and resumes it without positional drift.

## References
- `Catroid/.../embroidery/TripleRunningStitch.java`, `TripleRunningStitchTest.java`
- `Catroid/.../content/actions/SewUpAction.java`, `SewUpTest.java`
- `Catty/src/Catty/Embroidery/Pattern/TripleStitchPattern.swift`
