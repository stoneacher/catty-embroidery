import EmbroideryEngine
import Foundation
import Interpreter
import ProgramModel
import Testing

/// US-208 items 1–3: the "stitch a star" golden — the M2 exit criterion
/// demonstrated a second time on a second pattern type, with wrapping turn
/// arithmetic and a mid-program colour change the square never reached.
///
/// Pinned the same two independent ways as US-207: against hand-derived
/// embroidery-unit literals (`goldenStarRecords`, owing nothing to the
/// interpreter) and against a differential replay through the engine's own
/// pattern types (`GoldenStar.oracle`, which has no compiler, scheduler or loop
/// counter, so neither miscompiled `repeatLoop` could be mirrored into the
/// expectation).
@Suite("Golden program: star")
struct GoldenProgramStarTests {
    private let clock = InterpreterClock(tickDelta: 0.05)

    private func run() -> (events: [InterpreterEvent], stream: EmbroideryStream) {
        var interpreter = Interpreter(program: GoldenStar.program, clock: clock)
        let events = interpreter.run(maxTicks: 100)
        return (events, interpreter.assembledStream())
    }

    // MARK: - Item 1 — golden ordered stitch events

    @Test("the star's stitch events equal the engine oracle's points, exactly")
    func stitchEventsEqualTheEngineOracle() {
        // Exact, not `expectApproximates`, for US-207's reason: both sides call
        // the same libm in the same process with the same operands, so the
        // sin/cos dust matches bit for bit. That matters more here than for the
        // square — every zigzag offset is a trig product, so a tolerance would
        // erase most of the signal. If this ever goes red at the 1e-16 scale,
        // investigate the divergence — do NOT loosen the comparison.
        expectExactlyEqual(stitchPositions(run().events), GoldenStar.oracle.points)
    }

    @Test("every event matches the oracle's full payload, actor and layer included")
    func eventPayloadsEqualTheEngineOracle() {
        #expect(run().events == GoldenStar.oracle.events)
    }

    @Test("the event stream interleaves two colours, motion, stitches and the finalize marker in order")
    func eventSequenceIsOrdered() {
        let events = run().events

        #expect(eventTags(events) == goldenStarEventTags)
        #expect(events.count == 39)
        #expect(events.first == .colorArmed(actor: GoldenStar.actor, hex: GoldenStar.startHex))
        #expect(events.last == .finalizeRequested(name: GoldenStar.designName))
        // Both intents, in order, each emitted exactly once — the second loop's
        // colour brick is outside its body, so it does not repeat per iteration.
        #expect(colorArmedHexes(events) == [GoldenStar.startHex, GoldenStar.midHex])
    }

    @Test("the star walks 21 path points, five on the first side and four on each of the rest")
    func perSideStitchCountsMatchTheZigzagOracle() {
        // Geometry only, no engine: 20 stage units at length 5 is 4 whole
        // intervals per side. Side 1 carries one extra point — the lazily
        // emitted anchor (offset, unlike the running stitch's raw one).
        let events = run().events
        let path = stitchPositions(events).dropLast(5)
        #expect(path.count == 21)

        // Stitches per motion brick, the tack and the finalize marker dropped so
        // only the walk is counted: a move carries its side's points, a turn
        // carries none (its zero-distance update is rejected by the pattern's
        // `distance >= length` guard).
        var perMotion: [Int] = []
        for tag in eventTags(events).dropLast(6) {
            if tag == "move" {
                perMotion.append(0)
            } else if tag == "stitch", !perMotion.isEmpty {
                perMotion[perMotion.count - 1] += 1
            }
        }
        #expect(perMotion == [5, 0, 4, 0, 4, 0, 4, 0, 4, 0])
    }

    @Test("the heading closes exactly at 0° while the position closes only within tolerance")
    func headingClosesExactlyAndPositionApproximately() throws {
        // The contrast is the point of this test. 5 × 144° = 720° ≡ 0°, and
        // `VirtualNeedle.turnRight` reduces both operands mod 360 before adding
        // (ADR-014), so the heading returns to *exactly* the value it started at
        // — no tolerance needed, and `expectApproximates` here would hide a
        // normalization that drifted.
        let updates = run().events.compactMap {
            if case let .needleMoved(_, update) = $0 {
                update
            } else {
                nil
            }
        }
        #expect(updates.count == 10) // one per move and per turn
        let closing = try #require(updates.last) // the fifth turn, back to 0°
        #expect(closing.heading == 0)

        // The position cannot do the same: five sin/cos accumulations leave a
        // residue no rounding absorbs, so closure is an ADR-014 tolerance claim.
        expectApproximates([closing.position], [StagePoint(x: 0, y: 0)])
        // …and it really is a residue, not exact — the discriminating half.
        #expect(closing.position != StagePoint(x: 0, y: 0))
    }

    @Test("a star's side length can silently cost it an interval — these parameters do not")
    func starParametersAvoidTheIntervalCliff() {
        /// A characterization test, not a golden: it records the constraint that
        /// chose `GoldenStar.side`/`length`, so a later "rounder numbers" tidy-up
        /// fails loudly instead of silently deforming the design. A consequence
        /// of ADR-014's Double pattern arithmetic, not a new decision.
        ///
        /// The measurement that matters is the pattern's, not the needle's: it
        /// measures from its previous **clamped anchor**, so a short side does not
        /// just lose its own interval, it leaves the anchor behind and the deficit
        /// compounds. Walking the anchor chain is the whole point of this helper —
        /// needle-to-needle distances are all exactly `side` and would show nothing.
        func intervalsPerSide(side: Double, length: Double) -> [Double] {
            var needle = VirtualNeedle()
            var anchor = StagePoint(x: 0, y: 0)
            return (0 ..< GoldenStar.sides).map { _ in
                needle.moveNSteps(side)
                let dx = needle.position.x - anchor.x
                let dy = needle.position.y - anchor.y
                let distance = hypot(dx, dy)
                let remainder = distance.truncatingRemainder(dividingBy: length)
                let surplus = (distance - remainder) / distance
                anchor = StagePoint(x: anchor.x + surplus * dx, y: anchor.y + surplus * dy)
                needle.turnRight(GoldenStar.turn)
                return ((distance - remainder) / length).rounded(.down)
            }
        }
        // The chosen parameters: every side measures a whole number of intervals.
        #expect(intervalsPerSide(side: GoldenStar.side, length: GoldenStar.length) == [4, 4, 4, 4, 4])
        // Side 30 at the same length is the trap — an equally plausible choice
        // whose fourth move measures 29.999999999999996 from the anchor, so the
        // last two sides emit five interpolants where six were intended.
        #expect(intervalsPerSide(side: 30, length: GoldenStar.length) == [6, 6, 6, 5, 5])
    }

    // MARK: - Item 2 — golden assembled stream

    @Test("the assembled stream equals the hand-derived embroidery-unit golden")
    func assembledStreamEqualsTheHandDerivedGolden() throws {
        let stream = run().stream

        // Primary assertion: the independent, hand-derived golden.
        #expect(recordPositions(stream) == goldenStarRecords)
        #expect(stream.count == 26)
        #expect(stream.firstStitchPosition == EmbroideryPoint(x: -4, y: 0))
        #expect(stream.lastStitchPosition == EmbroideryPoint(x: 0, y: 0))
        let box = try #require(stream.boundingBox)
        #expect(box.min == EmbroideryPoint(x: -16, y: -6))
        #expect(box.max == EmbroideryPoint(x: 27, y: 40))
        // The widest gap is 12 units, far inside ±121, so nothing interpolates;
        // a single layer means no boundary jump either (ADR-012).
        #expect(stream.stitches.allSatisfy { !$0.isJump })
    }

    @Test("the assembled stream equals the differential engine replay")
    func assembledStreamEqualsTheEngineOracle() {
        #expect(run().stream == GoldenStar.oracle.stream)
    }

    // MARK: - Item 3 — ADR-015 colour semantics

    @Test("the leading colour is silent and the mid-program one arms exactly one change (ADR-015)")
    func midProgramColorArmsExactlyOneChange() {
        let stream = run().stream

        #expect(stream.colorChangeCount == 1)
        // Both colours were applied, and the change record is the *first* stitch
        // of the second loop — the armed change rides the next surviving stitch.
        let changeIndices = stream.stitches.indices.filter { stream.stitches[$0].isColorChange }
        #expect(changeIndices == [goldenStarColorChangeIndex])

        // Both colours were actually applied — the discriminating half, since a
        // manager that dropped the second set would keep every position intact.
        let colors = stream.stitches.map(\.color)
        #expect(colors.prefix(goldenStarColorChangeIndex).allSatisfy { $0 == GoldenStar.startColor })
        #expect(colors.dropFirst(goldenStarColorChangeIndex).allSatisfy { $0 == GoldenStar.midThreadColor })
        #expect(Set(colors) == [GoldenStar.startColor, GoldenStar.midThreadColor])
    }

    @Test("one change means the DST header declares two colour blocks: CO = changes + 1")
    func headerDeclaresTwoColorBlocks() throws {
        // The AC's "at the header level", taken literally, without straying into
        // US-209's pattern→stream→bytes scope: only the CO field is read.
        let header = DSTHeader(stream: run().stream, name: GoldenStar.designName)
        let tag = Array("CO:".utf8)
        let start = try #require(header.bytes.firstRange(of: tag)?.upperBound)
        // `appendField` writes the value then NUL-pads to the 2-byte field.
        #expect(Array(header.bytes[start ..< start + 2]) == Array("2".utf8) + [0x00])
    }
}
