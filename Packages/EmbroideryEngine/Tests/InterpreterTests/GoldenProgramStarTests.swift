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
        #expect(events.first == .colorArmed(actor: GoldenStar.actor, hex: GoldenStar.firstHex))
        #expect(events.last == .finalizeRequested(name: GoldenStar.designName))
        // Both intents, in order, each emitted exactly once — the second loop's
        // colour brick is outside its body, so it does not repeat per iteration.
        #expect(colorArmedHexes(events) == [GoldenStar.firstHex, GoldenStar.secondHex])
    }

    @Test("the star walks 21 path points, five on the first side and four on each of the rest")
    func eachSideCarriesItsOwnStitchesAndEachTurnNone() {
        // 20 stage units at length 5 is 4 whole intervals per side. Side 1
        // carries one extra point — the lazily emitted anchor (offset, unlike
        // the running stitch's raw one).
        let events = run().events
        let path = stitchPositions(events).dropLast(5)
        #expect(path.count == 21)

        // Stitches per motion brick, the tack and the finalize marker dropped so
        // only the walk is counted: a move carries its side's points, a turn
        // carries none (its zero-distance update is rejected by the pattern's
        // `distance >= length` guard).
        var perMotion: [Int] = []
        for tag in eventTags(events).dropLast(6) where tag != "color" {
            if tag == "move" {
                perMotion.append(0)
            } else {
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

    /// A tripwire, not a golden. A pentagram's directions are irrational, so a
    /// side whose nominal length is a whole multiple of the stitch length sits
    /// exactly **on** the pattern's interval boundary, and the last bit of
    /// `hypot` decides how many stitches the side emits.
    ///
    /// Side 4 is that side. Its exact length is 19.999999999999998122…, i.e.
    /// 1.878e-15 below 20 — past the half-ulp boundary (1.776e-15) by 1e-16.
    /// Darwin's `hypot` is 0.53 ulp high and returns 20.0; the correctly rounded
    /// result is 19.999999999999996, which costs side 4 an interval, leaves the
    /// anchor 5 units behind and deforms sides 4 and 5. `hypot` is not required
    /// to be correctly rounded by C or IEEE-754 and implementations disagree
    /// here. `GoldenStarLiterals` depends on that rounding from side 4 onward —
    /// sides 1–3 and the tack are identical either way (Codex US-208) — so
    /// this test exists to name the cause legibly when the platform's libm
    /// changes, instead of leaving a dozen unexplained golden diffs
    /// (swift-code-reviewer US-208).
    ///
    /// The needle's own step-to-step distance is the quantity the pattern
    /// measures only because the anchor tracks the vertices exactly — which is
    /// what whole-multiple distances establish in the first place, and what
    /// `eachSideCarriesItsOwnStitchesAndEachTurnNone` confirms through the real
    /// `ZigzagStitchPattern`.
    @Test("the golden's structure rests on libm's rounding of one hypot, so pin that hypot")
    func theGoldenDependsOnLibmRoundingOfHypot() {
        func sideDistances(side: Double) -> [Double] {
            var needle = VirtualNeedle()
            var previous = needle.position
            return (0 ..< GoldenStar.sides).map { _ in
                needle.moveNSteps(side)
                let distance = hypot(needle.position.x - previous.x, needle.position.y - previous.y)
                previous = needle.position
                needle.turnRight(GoldenStar.turn)
                return distance
            }
        }
        #expect(sideDistances(side: GoldenStar.side) == Array(repeating: 20, count: GoldenStar.sides))

        // The same computation one side length away, to show the boundary is real
        // and not an artifact of this test: at side 30 the fourth side falls the
        // other way, and no choice of an integer side/length ratio escapes the
        // boundary — it is where the ratio puts it.
        #expect(sideDistances(side: 30) == [30, 30, 30, 29.999999999999996, 30])
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
        #expect(colors.prefix(goldenStarColorChangeIndex).allSatisfy { $0 == GoldenStar.firstColor })
        #expect(colors.dropFirst(goldenStarColorChangeIndex).allSatisfy { $0 == GoldenStar.secondColor })
        #expect(Set(colors) == [GoldenStar.firstColor, GoldenStar.secondColor])
    }

    @Test("one change means the DST header declares two colour blocks: CO = changes + 1")
    func headerDeclaresTwoColorBlocks() throws {
        // The AC's "at the header level", taken literally, without straying into
        // US-209's pattern→stream→bytes scope: only the CO field is read.
        let header = try DSTHeader(stream: run().stream, name: GoldenStar.designName)
        // At a fixed offset rather than by searching for "CO:", which would also
        // match a design name containing it: `appendField` writes `TAG:` + value
        // + padding + \n + 0x1A, so LA occupies 3 + 15 + 2 = 20 bytes and ST the
        // next 3 + 6 + 2 = 11, putting CO's tag at byte 31.
        let coField = 31
        #expect(Array(header.bytes[coField ..< coField + 3]) == Array("CO:".utf8))
        // The value, then the NUL padding to the 2-byte field.
        #expect(Array(header.bytes[coField + 3 ..< coField + 5]) == Array("2".utf8) + [0x00])
    }
}
