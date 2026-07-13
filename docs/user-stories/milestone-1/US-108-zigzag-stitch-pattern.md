# US-108 — Zigzag stitch pattern

**Epic**: E2 Engine | **Estimate**: ~3 h | **Depends on**: US-107

**Story**: As a program, I want a zigzag stitch pattern with configurable length and width, so that designs can use dense decorative lines (satin-like columns).

## Acceptance criteria
- [ ] `ZigzagStitchPattern(length:width:start:)` conforming to the `StitchPattern` protocol from US-107. *(Amended from `(length:width:)`: the engine is platform-independent and cannot read a sprite's position, so the anchor is passed explicitly — same rationale as US-107's `RunningStitchPattern(length:start:)`.)*
- [ ] Stitches alternate perpendicular to the **needle's heading from the `NeedleUpdate`** (not the path delta — Catroid samples the sprite's motion direction, which differs under goto/glide), offset ±width/2, spaced `length` apart along the path. Perpendicular via sin/cos per the ADR-007 angle convention (0° = up).
- [ ] The heading is sampled **once per update call** — Catroid does *not* re-orient within a single update; a new heading takes effect on the next update.

## Test-first plan
1. Horizontal-line test: exact expected alternating coordinates (port cases from `ZigZagRunningStitchTest` / `ZigZagParametrizedTest`, documenting the angle-convention mapping used — the classic silent-flip bug source).
2. Vertical and diagonal line tests (perpendicular math via heading).
3. Corner test: heading change takes effect on the *next* update, matching Catroid.

## References
- `Catroid/.../embroidery/ZigZagRunningStitch.java`, `ZigZagRunningStitchTest.java`, `ZigZagParametrizedTest.java`
- `Catty/src/Catty/Embroidery/Pattern/ZigzagStitchPattern.swift`
