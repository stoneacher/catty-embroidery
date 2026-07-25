import EmbroideryEngine
import Interpreter
import ProgramModel
import Testing

/// US-207 items 1–2: the "stitch a square" golden. One program exercises colour,
/// pattern activation, compiled loop, motion, tie-off and the finalize marker,
/// and is pinned two independent ways — against hand-derived embroidery-unit
/// literals (`goldenSquareRecords`, owing nothing to the interpreter) and against
/// a differential replay through the engine's own pattern types
/// (`GoldenSquare.oracle`, which has no compiler, scheduler or loop counter, so a
/// miscompiled `repeatLoop` cannot be mirrored into the expectation).
///
/// Reaching this suite reaches the M2 exit criterion (ROADMAP M2).
@Suite("Golden program: square")
struct GoldenProgramSquareTests {
    private let clock = InterpreterClock(tickDelta: 0.05)

    private func run() -> (events: [InterpreterEvent], stream: EmbroideryStream) {
        var interpreter = Interpreter(program: GoldenSquare.program, clock: clock)
        let events = interpreter.run(maxTicks: 100)
        return (events, interpreter.assembledStream())
    }

    // MARK: - Item 1 — golden ordered stitch events

    @Test("the square's stitch events equal the engine oracle's points, exactly")
    func stitchEventsEqualTheEngineOracle() {
        // Exact, tolerance 0 — unlike US-206's trig comparisons. The sew-up dust
        // is real (see tackCentreCarriesDust) but the oracle issues bit-identical
        // operations in the same order, so it matches to the last bit. A 1e-9
        // tolerance would erase exactly the dust the dedup outcome depends on.
        // If this ever goes red at the 1e-16 scale, investigate the divergence —
        // do NOT loosen the comparison.
        expectApproximates(stitchPositions(run().events), GoldenSquare.oracle.points, tolerance: 0)
    }

    @Test("the event stream interleaves colour, motion, stitches and the finalize marker in order")
    func eventSequenceIsOrdered() {
        let events = run().events

        // The interleaving, not just the stitch subsequence: each move carries
        // its own stitches, each turn carries none, the tack stands alone.
        #expect(eventTags(events) == goldenSquareEventTags)
        #expect(events.count == 32)
        #expect(events.first == .colorArmed(actor: GoldenSquare.actor, hex: GoldenSquare.hex))
        #expect(events.last == .finalizeRequested(name: GoldenSquare.name))
        #expect(colorArmedHexes(events) == [GoldenSquare.hex])
        // Eight motion bricks (four moves, four turns); the clock is never waited on.
        #expect(eventTags(events).filter { $0 == "move" }.count == 8)
        #expect(!eventTags(events).contains("wait"))
    }

    @Test("the square walks 17 path points with its corners on the derived indices")
    func cornersLandOnTheDerivedIndices() {
        // Geometry only, no engine: perimeter 4 × 20 = 80 stage units at length 5
        // is 16 intervals, plus the lazy anchor → 17 path points before the tack.
        let path = stitchPositions(run().events).dropLast(5)
        #expect(path.count == 17)

        // Corners every four intervals, in embroidery units (×2, so stage dust is
        // rounded away): origin, up, right, down, back to the origin.
        let corners = [0, 4, 8, 12, 16].map { EmbroideryPoint(converting: path[$0]) }
        #expect(corners == [
            EmbroideryPoint(x: 0, y: 0), EmbroideryPoint(x: 0, y: 40), EmbroideryPoint(x: 40, y: 40),
            EmbroideryPoint(x: 40, y: 0), EmbroideryPoint(x: 0, y: 0)
        ])
    }

    @Test("the tack centre carries sin/cos dust, so clause A does not dedup it — 22 records, not 21")
    func tackCentreCarriesDust() {
        // The subtlest value in this suite. Side 4's last pattern point is
        // javaRounded to exactly (0, 0), but the *needle* the tack centres on is
        // not: turn 4 leaves heading 0 exactly (270 + 90 → 360 → 0), and the
        // fourth move added 20·cos(3π/2) = −3.674e-15 to a y of exactly 0.0,
        // which no rounding can absorb. So `EmbroideryPatternManager` clause A
        // sees two different StagePoints and records both — 22 ops, not 21.
        // Pinned explicitly so the knife edge is documented, not accidental.
        let stitches = stitchPositions(run().events)
        let lastPathPoint = stitches[16]
        let tackCentre = stitches[17]

        #expect(lastPathPoint == StagePoint(x: 0, y: 0))
        #expect(tackCentre != StagePoint(x: 0, y: 0))
        #expect(tackCentre.y != 0)
        // Both convert to the same embroidery unit, hence the duplicate record.
        #expect(EmbroideryPoint(converting: lastPathPoint) == EmbroideryPoint(converting: tackCentre))
    }

    // MARK: - Item 2 — golden assembled stream

    @Test("the assembled stream equals the hand-derived embroidery-unit golden")
    func assembledStreamEqualsTheHandDerivedGolden() throws {
        let stream = run().stream

        // Primary assertion: the independent, hand-derived golden.
        #expect(recordPositions(stream) == goldenSquareRecords)
        #expect(stream.count == 22)
        #expect(stream.firstStitchPosition == EmbroideryPoint(x: 0, y: 0))
        #expect(stream.lastStitchPosition == EmbroideryPoint(x: 0, y: 0))
        // The tack's "behind" point is the only negative coordinate.
        // (`BoundingBox.init` is engine-internal, so compare the corners.)
        let box = try #require(stream.boundingBox)
        #expect(box.min == EmbroideryPoint(x: 0, y: -6))
        #expect(box.max == EmbroideryPoint(x: 40, y: 40))
        // Every gap is 10 units, far inside ±121 — nothing interpolates, and a
        // single layer means no boundary jump either (ADR-012).
        #expect(stream.stitches.allSatisfy { !$0.isJump && !$0.isColorChange })
    }

    @Test("a single colour set before the first stitch is silent yet still colours every stitch (ADR-015)")
    func silentStartStillAppliesTheColour() {
        let stream = run().stream

        // ADR-015 silent start: no change record, so DST CO = 0 + 1 = 1 block.
        #expect(stream.colorChangeCount == 0)
        // …but the colour was applied, not dropped — the discriminating half.
        #expect(Set(stream.stitches.map(\.color)) == [GoldenSquare.color])
    }

    @Test("the assembled stream equals the differential engine replay")
    func assembledStreamEqualsTheEngineOracle() {
        // Structural half of the golden: whole-stream equality against a raw
        // manager fed the same points by the same engine primitives, covering the
        // colour, flag and layer bookkeeping the position list alone would miss.
        #expect(run().stream == GoldenSquare.oracle.stream)
    }
}
