# US-102 — Stitch domain model and embroidery stream

**Epic**: E2 Engine | **Estimate**: ~3 h | **Depends on**: US-101

**Story**: As the engine, I need a stitch domain model and an ordered stitch stream, so that all pattern generators and the DST writer operate on one shared representation.

## Acceptance criteria
- [ ] `Stitch`: position (embroidery coordinates), thread color, flags `isJump` and `isColorChange` — a `Sendable`, `Equatable` value type (strict concurrency is on; domain types must cross isolation boundaries freely).
- [ ] Coordinate conversion: stage points → embroidery units with factor 2.0 (`STITCH_POINT_UNIT_FACTOR`), rounding = `floor(x + 0.5)` matching Java `Math.round` (differs from Swift `.rounded()` on negative halves — ADR-012). **No y-flip**: stage y-up maps straight to DST +Y in both references; flipping for screen display is M3's rendering concern. Stage space per ADR-007 (center origin, 500×500 pt).
- [ ] `EmbroideryStream`: append stitches, append jump, append color change; exposes stitch count, color-change count (header `CO` = count + 1, see US-104), bounding box (min/max X/Y), and **first and last stitch positions** (the header's AX/AY need them).
- [ ] `EmbroideryStream` is a plain `Sendable` struct with `mutating` appends — do not port Catty's class + `SynchronizedArray` + draw-queue design; M3's preview only needs "stitches since index i", which an array gives for free.
- [ ] No UIKit/SwiftUI/SpriteKit imports — pure Foundation.

## Test-first plan
1. Coordinate conversion and rounding tests, including negative halves: stage point (10.5, −3) → (21, −6); **−3.25 → −6, not −7** (`floor(−6.5 + 0.5) = −6`, where Swift `.rounded()` would give −7).
2. Stream accumulation: appending N stitches yields count N, correct ordering, correct bounding box including negative coordinates.
3. Color change: appending a color change increments the color-change count and flags the next stitch, mirroring `DSTStream` semantics.

## References
- `Catty/src/Catty/Embroidery/Stitch.swift`, `EmbroideryStream.swift`
- `Catroid/.../embroidery/DSTStream.java`, `DSTWorkSpace.java`, `DSTFileConstants.java`
