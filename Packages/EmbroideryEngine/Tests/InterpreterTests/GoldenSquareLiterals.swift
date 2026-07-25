import EmbroideryEngine

// US-207's **independent** golden half: values derived by hand from ADR-007
// geometry and the engine's documented rounding, owing nothing to
// `replayGoldenProgram`. Deliberately a separate file from the differential
// oracle — the whole point of these literals is that they are not computed from
// the same code the interpreter shares, and a later "simplification" that
// derived them from the replay would silently collapse the two halves into one.

/// The square's stream in embroidery units.
///
/// A 20×20 stage square at length 5 is 4 intervals per side; ×2 into embroidery
/// units gives a 40×40 square walked clockwise from the origin (heading 0 is +y
/// and `turnRight` adds): up the +y edge, right, down, back left. 17 path points
/// (the lazy anchor plus 4 sides × 4 interpolants), then the 5-point bar tack at
/// the closing corner, ±6 units along heading 0 — hence the y = −6 record.
///
/// Conversion is ADR-012's ×2-then-`javaRound`; the rule's *negative-half*
/// asymmetry is not exercised here (every value in this design rounds the same
/// under `javaRound` and `.rounded()`) — that edge is pinned by US-105/106.
///
/// The tack's leading centre is **not** deduped, so this list has 22 entries and
/// not 21: see `tackCentreIsNotTheLastPathPoint` for the arithmetic.
let goldenSquareRecords: [EmbroideryPoint] = [
    // Side 1 — the lazy anchor, then up +y.
    EmbroideryPoint(x: 0, y: 0), EmbroideryPoint(x: 0, y: 10),
    EmbroideryPoint(x: 0, y: 20), EmbroideryPoint(x: 0, y: 30), EmbroideryPoint(x: 0, y: 40),
    // Side 2 — right, +x.
    EmbroideryPoint(x: 10, y: 40), EmbroideryPoint(x: 20, y: 40),
    EmbroideryPoint(x: 30, y: 40), EmbroideryPoint(x: 40, y: 40),
    // Side 3 — down, −y.
    EmbroideryPoint(x: 40, y: 30), EmbroideryPoint(x: 40, y: 20),
    EmbroideryPoint(x: 40, y: 10), EmbroideryPoint(x: 40, y: 0),
    // Side 4 — left, −x, closing on the origin.
    EmbroideryPoint(x: 30, y: 0), EmbroideryPoint(x: 20, y: 0),
    EmbroideryPoint(x: 10, y: 0), EmbroideryPoint(x: 0, y: 0),
    // Sew-up bar tack: centre / ahead / centre / behind / centre, heading 0.
    EmbroideryPoint(x: 0, y: 0), EmbroideryPoint(x: 0, y: 6),
    EmbroideryPoint(x: 0, y: 0), EmbroideryPoint(x: 0, y: -6), EmbroideryPoint(x: 0, y: 0)
]

/// Events per tick: `setThreadColor` (one `colorArmed`), `runningStitch`
/// (action-consuming but event-free), then eight loop-body ticks alternating move
/// (one `needleMoved` + its stitches) and turn (one `needleMoved`, no stitch),
/// then `sewUp` (5 tack stitches) and `writeEmbroideryToFile` (one
/// `finalizeRequested`).
///
/// Twelve entries — one per *action* brick, which is the observable consequence
/// of `repeatLoop`/`loopEnd` being zero-tick (ADR-018): eight body bricks, not
/// eight bricks plus four loop-bookkeeping ticks. What this profile pins is that
/// composed shape and the fact that the tack does not share the last turn's tick;
/// it does **not** discriminate ADR-018's fold-vs-yield or one-iteration-per-tick
/// mechanisms, which are invisible in a loop whose body starts with an action
/// brick — `StepperLoopTests` owns those (swift-code-reviewer US-207, with a
/// mutation showing this profile survives both changes).
let goldenSquareTickProfile: [Int] = [1, 0, 6, 1, 5, 1, 5, 1, 5, 1, 5, 1]

/// The square's event interleaving: the colour intent, then per loop iteration a
/// move carrying its stitches followed by a stitch-free turn, then the bare
/// 5-stitch tack and the finalize marker. No `wait` — the program has no `wait`
/// brick, so the clock is never consumed.
///
/// This is the only assertion in the package that pins `needleMoved` *before* the
/// stitches its motion produced.
let goldenSquareEventTags: [String] =
    ["color"]
        + ["move"] + Array(repeating: "stitch", count: 5) + ["move"] // side 1 + turn
        + ["move"] + Array(repeating: "stitch", count: 4) + ["move"] // side 2 + turn
        + ["move"] + Array(repeating: "stitch", count: 4) + ["move"] // side 3 + turn
        + ["move"] + Array(repeating: "stitch", count: 4) + ["move"] // side 4 + turn
        + Array(repeating: "stitch", count: 5) // sew-up bar tack
        + ["finalize"]
