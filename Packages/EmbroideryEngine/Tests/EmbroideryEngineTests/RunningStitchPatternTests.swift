import EmbroideryEngine
import Testing

@Suite("RunningStitchPattern")
struct RunningStitchPatternTests {
    private func update(_ pattern: inout RunningStitchPattern, to x: Double, _ y: Double) -> [StagePoint] {
        pattern.update(NeedleUpdate(position: StagePoint(x: x, y: y)))
    }

    @Test("No movement emits nothing — no anchor stitch at construction")
    func noMove() {
        var pattern = RunningStitchPattern(length: 10, start: StagePoint(x: 0, y: 0))
        #expect(update(&pattern, to: 0, 0).isEmpty, "port of Catroid testNoMoveOfRunningStitch")
    }

    @Test("Movement below the length threshold emits nothing")
    func belowThreshold() {
        var pattern = RunningStitchPattern(length: 10, start: StagePoint(x: 0, y: 0))
        #expect(update(&pattern, to: 3, 0).isEmpty)
    }

    @Test("Straight line: 10 units at length 2 stitches at 0,2,4,6,8,10 — anchor arrives lazily")
    func straightLine() {
        var pattern = RunningStitchPattern(length: 2, start: StagePoint(x: 0, y: 0))
        #expect(update(&pattern, to: 10, 0) == [
            StagePoint(x: 0, y: 0),
            StagePoint(x: 2, y: 0),
            StagePoint(x: 4, y: 0),
            StagePoint(x: 6, y: 0),
            StagePoint(x: 8, y: 0),
            StagePoint(x: 10, y: 0)
        ])
    }

    @Test("Diagonal move: raw anchor plus javaRounded interpolated stitch")
    func diagonalMove() {
        // Port of Catroid testSimpleMoveOfRunningStitch (times(2)), with
        // coordinates: distance √200 ≈ 14.1421, one whole length of 10,
        // clamped point (7.0711, 7.0711) rounds to (7, 7).
        var pattern = RunningStitchPattern(length: 10, start: StagePoint(x: 0, y: 0))
        #expect(update(&pattern, to: 10, 10) == [
            StagePoint(x: 0, y: 0),
            StagePoint(x: 7, y: 7)
        ])
    }

    @Test("setStartPosition re-anchors; a two-length move emits anchor and two rounded stitches")
    func reAnchoredMultiStitch() {
        // Port of Catroid testSetStartCoordinates (times(3)): anchor moved to
        // (20,20), update to (0,0) covers √800 ≈ 28.2843 → two lengths of 10,
        // clamped (5.8579, 5.8579); javaRound(12.9289) = 13, javaRound(5.8579) = 6.
        var pattern = RunningStitchPattern(length: 10, start: StagePoint(x: 0, y: 0))
        pattern.setStartPosition(StagePoint(x: 20, y: 20))
        #expect(update(&pattern, to: 0, 0) == [
            StagePoint(x: 20, y: 20),
            StagePoint(x: 13, y: 13),
            StagePoint(x: 6, y: 6)
        ])
    }

    @Test("Direction change mid-path: anchor advances, first flag stays consumed")
    func directionChange() {
        var pattern = RunningStitchPattern(length: 5, start: StagePoint(x: 0, y: 0))
        #expect(update(&pattern, to: 10, 0) == [
            StagePoint(x: 0, y: 0),
            StagePoint(x: 5, y: 0),
            StagePoint(x: 10, y: 0)
        ])
        #expect(update(&pattern, to: 10, 10) == [
            StagePoint(x: 10, y: 5),
            StagePoint(x: 10, y: 10)
        ], "second segment follows the new direction without re-emitting the anchor")
    }

    @Test("Sub-length moves accumulate until the threshold is crossed — exactly one stitch each crossing")
    func accumulation() {
        var pattern = RunningStitchPattern(length: 2, start: StagePoint(x: 0, y: 0))
        #expect(update(&pattern, to: 1, 0).isEmpty)
        #expect(update(&pattern, to: 1.5, 0).isEmpty)
        #expect(update(&pattern, to: 2, 0) == [
            StagePoint(x: 0, y: 0),
            StagePoint(x: 2, y: 0)
        ], "first crossing delivers the lazy anchor plus the threshold stitch")
        #expect(update(&pattern, to: 2.5, 0).isEmpty)
        #expect(update(&pattern, to: 3, 0).isEmpty)
        #expect(update(&pattern, to: 3.5, 0).isEmpty)
        #expect(update(&pattern, to: 4, 0) == [StagePoint(x: 4, y: 0)], "later crossings emit exactly one stitch")
    }

    @Test("Surplus past the last whole length is dropped from the anchor")
    func surplusDropped() {
        // Catroid advances the anchor to the clamped point (2,0), not the
        // needle position (3,0) — the leftover unit is re-measured from there.
        var pattern = RunningStitchPattern(length: 2, start: StagePoint(x: 0, y: 0))
        #expect(update(&pattern, to: 3, 0) == [
            StagePoint(x: 0, y: 0),
            StagePoint(x: 2, y: 0)
        ])
        #expect(update(&pattern, to: 3, 0).isEmpty, "1 remaining unit from the (2,0) anchor is below threshold")
        #expect(update(&pattern, to: 6, 0) == [
            StagePoint(x: 4, y: 0),
            StagePoint(x: 6, y: 0)
        ], "4 units from the (2,0) anchor yield two stitches")
    }

    @Test("Interpolated positions use javaRound: -2.5 rounds to -2, not -3")
    func javaRoundNegativeHalves() {
        // Midpoint of (0,0)→(-5,0) at length 2.5 lands on exactly -2.5;
        // Java Math.round → floor(x + 0.5) = -2. Swift .rounded() would give
        // -3 (the Catty divergence ADR-012 forbids porting).
        var pattern = RunningStitchPattern(length: 2.5, start: StagePoint(x: 0, y: 0))
        #expect(update(&pattern, to: -5, 0) == [
            StagePoint(x: 0, y: 0),
            StagePoint(x: -2, y: 0),
            StagePoint(x: -5, y: 0)
        ])
    }
}
