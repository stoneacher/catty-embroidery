import EmbroideryEngine
import Testing

@Suite("TripleStitchPattern")
struct TripleStitchPatternTests {
    private func update(_ pattern: inout TripleStitchPattern, to x: Double, _ y: Double) -> [StagePoint] {
        // Heading is irrelevant: the triple stitch follows the movement
        // vector like the simple running stitch (Catroid TripleRunningStitch
        // ignores rotation entirely).
        pattern.update(NeedleUpdate(position: StagePoint(x: x, y: y), heading: 0))
    }

    // MARK: - Catroid golden ports (TripleRunningStitchTest)

    // The reference tests only count addStitchCommand calls; the sequences
    // asserted here additionally pin the positions the counts imply:
    // 1 (first anchor, once ever) + 3 per segment (new, previous, new).
    // Exact `==` per ADR-014: the pattern is trig-free, every coordinate is
    // the raw anchor or a javaRound-ed value.

    @Test("No movement emits nothing (port of testNoMoveOfRunningStitch)")
    func noMove() {
        var pattern = TripleStitchPattern(length: 10, start: StagePoint(x: 0, y: 0))
        #expect(update(&pattern, to: 0, 0).isEmpty)
    }

    @Test("One segment emits anchor + forward-back-forward (port of testSimpleMoveOfRunningStitch, 4 commands)")
    func simpleMove() {
        var pattern = TripleStitchPattern(length: 10, start: StagePoint(x: 0, y: 0))
        // Distance √200 ≈ 14.14: one whole length, clamp at 7.07… → javaRound 7.
        #expect(update(&pattern, to: 10, 10) == [
            StagePoint(x: 0, y: 0),
            StagePoint(x: 7, y: 7), StagePoint(x: 0, y: 0), StagePoint(x: 7, y: 7)
        ])
    }

    @Test("setStartPosition re-anchors (port of testSetStartCoordinates, 7 commands)")
    func setStartPosition() {
        var pattern = TripleStitchPattern(length: 10, start: StagePoint(x: 0, y: 0))
        pattern.setStartPosition(StagePoint(x: 20, y: 20))
        // Distance √800 ≈ 28.28 → two segments toward (0,0), clamp (5.86…, 5.86…);
        // interpolants javaRound to (13,13) and (6,6). Segment 2 stitches back
        // to the ROUNDED (13,13) — Catroid advances previous to the rounded value.
        #expect(update(&pattern, to: 0, 0) == [
            StagePoint(x: 20, y: 20),
            StagePoint(x: 13, y: 13), StagePoint(x: 20, y: 20), StagePoint(x: 13, y: 13),
            StagePoint(x: 6, y: 6), StagePoint(x: 13, y: 13), StagePoint(x: 6, y: 6)
        ])
    }

    // MARK: - Rounding & chaining subtleties the reference counts can't see

    @Test("Segment 1 stitches back to the raw, un-rounded anchor")
    func rawAnchorAsPrevious() {
        var pattern = TripleStitchPattern(length: 10, start: StagePoint(x: 0, y: 0))
        pattern.setStartPosition(StagePoint(x: 0.4, y: 0))
        // Distance 10.6 → one segment, clamp x = 10.4 → javaRound 10. The
        // back-stitch (index 2) returns to 0.4 exactly — Catroid keeps
        // previousX = firstX un-rounded for the first segment.
        #expect(update(&pattern, to: 11, 0) == [
            StagePoint(x: 0.4, y: 0),
            StagePoint(x: 10, y: 0), StagePoint(x: 0.4, y: 0), StagePoint(x: 10, y: 0)
        ])
    }

    @Test("Interior points javaRound half-up and chain as rounded previous")
    func interiorJavaRound() {
        var pattern = TripleStitchPattern(length: 2.5, start: StagePoint(x: 0, y: 0))
        // Four segments to (10,0): interpolants 2.5, 5, 7.5, 10 →
        // javaRound half-up gives 3, 5, 8, 10.
        #expect(update(&pattern, to: 12, 0) == [
            StagePoint(x: 0, y: 0),
            StagePoint(x: 3, y: 0), StagePoint(x: 0, y: 0), StagePoint(x: 3, y: 0),
            StagePoint(x: 5, y: 0), StagePoint(x: 3, y: 0), StagePoint(x: 5, y: 0),
            StagePoint(x: 8, y: 0), StagePoint(x: 5, y: 0), StagePoint(x: 8, y: 0),
            StagePoint(x: 10, y: 0), StagePoint(x: 8, y: 0), StagePoint(x: 10, y: 0)
        ])
    }

    @Test("Sub-length moves accumulate; the anchor only advances by whole lengths")
    func accumulation() {
        var pattern = TripleStitchPattern(length: 10, start: StagePoint(x: 0, y: 0))
        #expect(update(&pattern, to: 6, 0).isEmpty)
        // Anchor stayed at the origin, so (12,0) is one whole length + surplus.
        #expect(update(&pattern, to: 12, 0) == [
            StagePoint(x: 0, y: 0),
            StagePoint(x: 10, y: 0), StagePoint(x: 0, y: 0), StagePoint(x: 10, y: 0)
        ])
    }

    // MARK: - Degenerate inputs (ADR-014 guard policy)

    @Test("Zero and negative lengths emit nothing instead of trapping")
    func degenerateLengths() {
        var zero = TripleStitchPattern(length: 0, start: StagePoint(x: 0, y: 0))
        #expect(update(&zero, to: 10, 0).isEmpty)

        var negative = TripleStitchPattern(length: -2, start: StagePoint(x: 0, y: 0))
        #expect(update(&negative, to: 10, 0).isEmpty)
    }

    @Test("Non-finite needle positions emit nothing and leave the pattern alive")
    func nonFinitePositions() {
        var pattern = TripleStitchPattern(length: 10, start: StagePoint(x: 0, y: 0))
        #expect(update(&pattern, to: .infinity, 0).isEmpty)
        #expect(update(&pattern, to: .nan, 0).isEmpty)
        // Anchor and first-flag survived the garbage updates.
        #expect(update(&pattern, to: 10, 0) == [
            StagePoint(x: 0, y: 0),
            StagePoint(x: 10, y: 0), StagePoint(x: 0, y: 0), StagePoint(x: 10, y: 0)
        ])
    }

    @Test("Astronomical stitch counts emit nothing instead of trapping the Int conversion")
    func astronomicalStitchCount() {
        var pattern = TripleStitchPattern(length: 1, start: StagePoint(x: 0, y: 0))
        #expect(update(&pattern, to: 1e19, 0).isEmpty)

        var subnormal = TripleStitchPattern(length: .leastNonzeroMagnitude, start: StagePoint(x: 0, y: 0))
        #expect(update(&subnormal, to: 1, 0).isEmpty)

        // State untouched by the rejected updates.
        #expect(update(&pattern, to: 2, 0) == [
            StagePoint(x: 0, y: 0),
            StagePoint(x: 1, y: 0), StagePoint(x: 0, y: 0), StagePoint(x: 1, y: 0),
            StagePoint(x: 2, y: 0), StagePoint(x: 1, y: 0), StagePoint(x: 2, y: 0)
        ])
    }

    // MARK: - Value semantics

    @Test("A copy does not alias the original's anchor or first-flag")
    func valueSemantics() {
        var original = TripleStitchPattern(length: 10, start: StagePoint(x: 0, y: 0))
        var copy = original
        #expect(update(&original, to: 10, 0) == [
            StagePoint(x: 0, y: 0),
            StagePoint(x: 10, y: 0), StagePoint(x: 0, y: 0), StagePoint(x: 10, y: 0)
        ])
        // The copy still has first == true and the original anchor.
        #expect(update(&copy, to: 10, 0) == [
            StagePoint(x: 0, y: 0),
            StagePoint(x: 10, y: 0), StagePoint(x: 0, y: 0), StagePoint(x: 10, y: 0)
        ])
    }
}
