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

/// The residue US-209's hand-built stream puts on the tack's leading centre.
///
/// It exists only to be **distinct from zero**, not to model a magnitude:
/// `EmbroideryStream.addStitch` dedups by comparing raw stage `Double`s, so a
/// clean `(0, 0)` fed straight after the path's closing `(0, 0)` is dropped and
/// the hand-built design would carry 21 records where the real one carries 22.
/// The admissible class is every ε with `ε != 0` and `|2ε| < 0.5` — non-zero so
/// it survives dedup, inside half an embroidery unit so it still `javaRound`s to
/// unit 0 — and `residueClassProducesTheGoldenBytes` walks that class instead of
/// asserting this one value works.
///
/// Deliberately **not** the interpreter's own residue (~3.55e-15 in x,
/// ~−3.67e-15 in y; `tackCentreIsNotTheLastPathPoint` has the arithmetic). That
/// value is a Darwin `sin`/`cos` product, and importing it would put a libm
/// dependency into the half that is supposed to owe nothing to the platform
/// (ADR-019), while crediting these bytes with a sensitivity they do not have.
/// `1e-12` is unmistakably hand-picked: three orders above the real dust,
/// eleven below the conversion boundary.
let goldenSquareNominalTackResidue = 1e-12

/// The square's path in **stage** units, as US-209's hand-built stream feeds it:
/// `goldenSquareRecords` halved (the ADR-012 ×2 conversion inverted), exact for
/// every value here — 0, 5, 10, 15, 20 and the tack's ±3 (`SewUp.steps`).
///
/// This is the one place the design's *pre-conversion* geometry is stated:
/// `goldenSquareRecords` are already-converted units, so US-207's independent
/// half never says what the stage path was. Feeding it forward pins ×2 +
/// `javaRound` from the other direction.
///
/// Only index 17 carries the residue — it is the design's one consecutive stage
/// duplicate, since the path closes on `(0, 0)` and the tack centres there. The
/// tack's later centres each follow an `ahead` or `behind` point and survive
/// dedup unaided. `ahead`/`behind` are fed clean, because the bytes see only
/// rounded values and the interpreter's dust-bearing ±3 (5.999999999999993,
/// −6.000000000000007) `javaRound` to the same ±6 an exact ±3 does.
func goldenSquareStagePath(tackCentreResidue: Double = goldenSquareNominalTackResidue) -> [StagePoint] {
    [
        // Side 1 — the lazy anchor, then up +y.
        StagePoint(x: 0, y: 0), StagePoint(x: 0, y: 5),
        StagePoint(x: 0, y: 10), StagePoint(x: 0, y: 15), StagePoint(x: 0, y: 20),
        // Side 2 — right, +x.
        StagePoint(x: 5, y: 20), StagePoint(x: 10, y: 20),
        StagePoint(x: 15, y: 20), StagePoint(x: 20, y: 20),
        // Side 3 — down, −y.
        StagePoint(x: 20, y: 15), StagePoint(x: 20, y: 10),
        StagePoint(x: 20, y: 5), StagePoint(x: 20, y: 0),
        // Side 4 — left, −x, closing on the origin.
        StagePoint(x: 15, y: 0), StagePoint(x: 10, y: 0),
        StagePoint(x: 5, y: 0), StagePoint(x: 0, y: 0),
        // Sew-up bar tack: centre / ahead / centre / behind / centre, heading 0.
        // The residue is on both axes, mirroring the over-determination US-207
        // documents (either channel alone defeats clause A).
        StagePoint(x: tackCentreResidue, y: tackCentreResidue), StagePoint(x: 0, y: 3),
        StagePoint(x: 0, y: 0), StagePoint(x: 0, y: -3), StagePoint(x: 0, y: 0)
    ]
}

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
