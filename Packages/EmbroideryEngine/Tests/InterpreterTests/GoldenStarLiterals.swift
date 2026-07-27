import EmbroideryEngine

// US-208's **independent** golden half, the counterpart of `GoldenSquareLiterals`
// for the star: values derived by hand from closed-form pentagram geometry plus
// the engine's documented rounding order, owing nothing to
// `replayGoldenProgram`. Kept in its own file for the same reason as the
// square's — a later "simplification" that computed these from the replay would
// collapse the two golden halves into one, and the zigzag makes that collapse
// costly. What these literals uniquely caught, measured by mutation rather than
// asserted (two earlier drafts overstated this — Codex US-208 rounds 2–3), are
// the four errors *inside* the pattern that the differential half mirrors and so
// cannot see: the anchor emitted raw instead of offset, `direction` reset per
// update, interior midpoints not `javaRound`ed, and the final clamp rounded
// instead of raw. Each takes this table red while every differential assertion
// stays green. A length/width transposition is *not* in that set — it is caught
// by the differential half and by the structural counts as well.
//
// # The derivation, once
//
// Geometry (ADR-007: degrees, 0° = up, x via sin, y via cos; `turnRight` adds).
// Five moves of 20 stage units — the square's side, so only the turn, the
// pattern and the colour differ between the two goldens — at headings 0°, 144°,
// 288°, 72°, 216°: the five 5th-roots of unity, whose vector sum is zero, which
// is *why* the path closes. Writing c36 = cos36° = (1+√5)/4 = 0.809017,
// s36 = sin36° = 0.587785, c18 = cos18° = 0.951057, s18 = sin18° = 0.309017,
// the vertices are
//
//   V0 (0, 0) → V1 (0, 20) → V2 (20·s36, 20−20·c36) = (11.755705, 3.819660)
//   → V3 (−7.265425, 10) → V4 (11.755705, 16.180340) → V5 (0, 0).
//
// Emission (`ZigzagStitchPattern`): 20 units at length 5 is 4 whole intervals, so
// each update emits interior points at f = 1/4, 2/4, 3/4 — `javaRound`ed to
// integers **in stage space, before the offset** — then the final point at the
// **raw** clamp. The first update additionally emits the anchor, itself offset
// (unlike running/triple, which emit it raw). Turns move nothing, so their
// zero-distance updates emit nothing. That is 5 + 4 + 4 + 4 + 4 = 21 path points.
//
// Offsets: each point is `base − (width/2)·(sin(h+90°), cos(h+90°))·direction`
// with width 4, and `direction` flips once per emitted point and is never reset
// — so a point's sign is fixed by its **global** index: + on even, − on odd.
// Only three offset magnitude pairs occur across the five headings, in stage
// units:
//
//   h = 0°   → (h+90) = 90° → (2, 0)
//   h = 144° → 234°         → (−1.618034, −1.175570)
//   h = 288° → 18°          → (0.618034, 1.902113)
//   h = 72°  → 162°         → (0.618034, −1.902113)
//   h = 216° → 306°         → (−1.618034, 1.175570)
//
// Conversion is ADR-012's ×2-then-`javaRound`. Every value below clears its
// nearest rounding boundary by at least 0.148 embroidery units — some 10¹⁴× the
// transcendental dust — so this table cannot disagree with the engine by a
// rounding flip. That margin is a property of the chosen side/length/width and
// nothing more general: `theGoldenDependsOnLibmRoundingOfHypot` pins the one
// measured distance this table's structure turns on, and shows a neighbouring
// side length falling the other way. Note what that test does and does not do —
// it measures distances only; the emission structure they imply is pinned by
// `eachSideCarriesItsOwnStitchesAndEachTurnNone` through the real pattern, and
// nothing constructs the neighbouring design to check its records (Codex US-208).

/// The star's stream in embroidery units: 21 zigzag path points, then the
/// 5-point bar tack at the closing corner (±6 units along heading 0).
///
/// Unlike the square's, the tack's leading centre needs no dedup argument: the
/// last path point is offset to (3, −2), nowhere near the tack centre, so all 26
/// entries are distinct emissions. Repeated *values* do occur — the pentagram
/// crosses itself, so e.g. (15, 14) appears three times — but never on
/// consecutive records.
///
/// Which is more than clause A needs either way: it compares **stage** points
/// exactly, not these embroidery units, so consecutive records with equal units
/// are not deduped at all — the square's two surviving consecutive (0, 0)
/// records are exactly that case (`tackCentreIsNotTheLastPathPoint`). The star
/// happens to be free of repeats in both spaces.
let goldenStarRecords: [EmbroideryPoint] = [
    // Side 1, heading 0° — offset anchor, three interior points, the V1 clamp.
    // Offset ±(2, 0) stage = ±(4, 0) units, so x alternates while y climbs by 10.
    EmbroideryPoint(x: -4, y: 0), EmbroideryPoint(x: 4, y: 10),
    EmbroideryPoint(x: -4, y: 20), EmbroideryPoint(x: 4, y: 30),
    EmbroideryPoint(x: -4, y: 40),
    // Side 2, heading 144° — bases (3, 16), (6, 12), (9, 8) rounded, then raw V2.
    EmbroideryPoint(x: 3, y: 30), EmbroideryPoint(x: 15, y: 26),
    EmbroideryPoint(x: 15, y: 14), EmbroideryPoint(x: 27, y: 10),
    // Side 3, heading 288° — bases (7, 5), (2, 7), (−3, 8) rounded, then raw V3.
    // Its first record is the one the mid-program colour change rides.
    EmbroideryPoint(x: 15, y: 14), EmbroideryPoint(x: 3, y: 10),
    EmbroideryPoint(x: -5, y: 20), EmbroideryPoint(x: -16, y: 16),
    // Side 4, heading 72° — bases (−3, 12), (2, 13), (7, 15) rounded, then raw V4.
    EmbroideryPoint(x: -5, y: 20), EmbroideryPoint(x: 3, y: 30),
    EmbroideryPoint(x: 15, y: 26), EmbroideryPoint(x: 22, y: 36),
    // Side 5, heading 216° — bases (9, 12), (6, 8), (3, 4) rounded, then the V5
    // clamp back at the origin.
    EmbroideryPoint(x: 15, y: 26), EmbroideryPoint(x: 15, y: 14),
    EmbroideryPoint(x: 3, y: 10), EmbroideryPoint(x: 3, y: -2),
    // Sew-up bar tack: centre / ahead / centre / behind / centre, heading 0.
    EmbroideryPoint(x: 0, y: 0), EmbroideryPoint(x: 0, y: 6),
    EmbroideryPoint(x: 0, y: 0), EmbroideryPoint(x: 0, y: -6), EmbroideryPoint(x: 0, y: 0)
]

/// Index of the first record sewn in the second thread colour — side 3's first
/// stitch, the one that carries the armed change (ADR-015). Sides 1 and 2 emit
/// 5 + 4 = 9 points, so the change lands on record 9.
let goldenStarColorChangeIndex = 9

/// Events per tick: `setThreadColor`, `zigZagStitch` (action-consuming but
/// event-free), then per side a move carrying its stitches and a stitch-free
/// turn, with the mid-program `setThreadColor` between sides 2 and 3, then the
/// tack and the finalize marker.
///
/// Fifteen entries — one per *action* brick. As in US-207 that equality is the
/// observable consequence of `repeatLoop`/`loopEnd` being zero-tick (ADR-018),
/// and here it spans **two** loops: eight bookkeeping steps across two loops
/// still cost nothing.
///
/// Carrying over `goldenSquareTickProfile`'s caveat, which still applies and
/// which doubling the loops did **not** weaken: this profile pins the composed
/// shape, not ADR-018's fold-vs-yield or one-iteration-per-tick mechanisms. A
/// loop whose body starts with an action brick cannot discriminate those, and a
/// mutation making `loopEnd` consume a tick survives all fifteen of these ticks
/// — `StepperLoopTests` owns it (swift-code-reviewer US-208, mutation-proven).
let goldenStarTickProfile: [Int] = [1, 0, 6, 1, 5, 1, 1, 5, 1, 5, 1, 5, 1, 5, 1]

/// The star's event interleaving. Side 1 carries one stitch more than the rest
/// (the lazily emitted anchor), every turn carries none, and the second colour
/// intent sits between the two loops.
let goldenStarEventTags: [String] =
    ["color"]
        + ["move"] + Array(repeating: "stitch", count: 5) + ["move"] // side 1 + turn
        + ["move"] + Array(repeating: "stitch", count: 4) + ["move"] // side 2 + turn
        + ["color"] // the mid-program change, between the two loops
        + ["move"] + Array(repeating: "stitch", count: 4) + ["move"] // side 3 + turn
        + ["move"] + Array(repeating: "stitch", count: 4) + ["move"] // side 4 + turn
        + ["move"] + Array(repeating: "stitch", count: 4) + ["move"] // side 5 + turn
        + Array(repeating: "stitch", count: 5) // sew-up bar tack
        + ["finalize"]
