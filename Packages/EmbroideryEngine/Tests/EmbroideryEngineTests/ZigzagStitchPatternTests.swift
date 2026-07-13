import EmbroideryEngine
import Foundation
import Testing

@Suite("ZigzagStitchPattern")
struct ZigzagStitchPatternTests {
    private func update(
        _ pattern: inout ZigzagStitchPattern, to x: Double, _ y: Double, heading: Double = 0
    ) -> [StagePoint] {
        pattern.update(NeedleUpdate(position: StagePoint(x: x, y: y), heading: heading))
    }

    /// Approximate comparison per ADR-014: the pattern computes in `Double`
    /// where Catroid uses `float`, and the heading's `sin`/`cos` leave
    /// transcendental dust (`sin(180°)` is 1.22e-16, not 0), so US-107-style
    /// exact `==` cannot hold. 1e-9 sits far above that noise and far below
    /// the 0.5-stage-point resolution the stream's javaRound absorbs.
    private func expect(
        _ actual: [StagePoint],
        approximates expected: [StagePoint],
        tolerance: Double = 1e-9,
        _ comment: Comment? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        guard actual.count == expected.count else {
            Issue.record(
                "expected \(expected.count) points \(expected), got \(actual)\(comment.map { " — \($0)" } ?? "")",
                sourceLocation: sourceLocation
            )
            return
        }
        for (index, pair) in zip(actual, expected).enumerated() {
            #expect(
                abs(pair.0.x - pair.1.x) <= tolerance && abs(pair.0.y - pair.1.y) <= tolerance,
                "point \(index): \(pair.0) !≈ \(pair.1)\(comment.map { " — \($0)" } ?? "")",
                sourceLocation: sourceLocation
            )
        }
    }

    // MARK: - Catroid golden ports

    private struct GoldenRow: Sendable, CustomStringConvertible {
        let name: String
        let length: Double
        let width: Double
        let heading: Double
        let expected: [StagePoint]
        var description: String {
            name
        }
    }

    /// The five rows of Catroid `ZigZagParametrizedTest` verbatim: start
    /// (10,0), one update to (30,0), expected X/Y lists zipped into points.
    private static let goldenRows = [
        GoldenRow(name: "Test Points", length: 10, width: 5, heading: 90, expected: [
            StagePoint(x: 10, y: 2.5), StagePoint(x: 20, y: -2.5), StagePoint(x: 30, y: 2.5)
        ]),
        GoldenRow(name: "Test more Points", length: 5, width: 2, heading: 90, expected: [
            StagePoint(x: 10, y: 1), StagePoint(x: 15, y: -1), StagePoint(x: 20, y: 1),
            StagePoint(x: 25, y: -1), StagePoint(x: 30, y: 1)
        ]),
        GoldenRow(name: "Test different length", length: 20, width: 5, heading: 90, expected: [
            StagePoint(x: 10, y: 2.5), StagePoint(x: 30, y: -2.5)
        ]),
        GoldenRow(name: "Test different width", length: 10, width: 10, heading: 90, expected: [
            StagePoint(x: 10, y: 5), StagePoint(x: 20, y: -5), StagePoint(x: 30, y: 5)
        ]),
        GoldenRow(name: "Test degrees", length: 10, width: 10, heading: 270, expected: [
            StagePoint(x: 10, y: -5), StagePoint(x: 20, y: 5), StagePoint(x: 30, y: -5)
        ])
    ]

    @Test("Catroid ZigZagParametrizedTest rows: (10,0) → (30,0)", arguments: goldenRows)
    private func parametrizedGolden(row: GoldenRow) {
        // ADR-007 angle mapping: heading 90° = right (+x); the offset uses
        // sin/cos of (heading + 90°), so heading 90 puts the full ±width/2
        // on y, starting positive (direction begins at 1, cos(180°) = −1
        // flips the subtraction). The classic silent-flip bug would show up
        // here as an inverted first offset.
        var pattern = ZigzagStitchPattern(
            length: row.length, width: row.width, start: StagePoint(x: 10, y: 0)
        )
        expect(update(&pattern, to: 30, 0, heading: row.heading), approximates: row.expected)
    }

    @Test("No movement emits nothing (port of Catroid testNoMoveOfRunningStitch)")
    func noMove() {
        var pattern = ZigzagStitchPattern(length: 5, width: 10, start: StagePoint(x: 0, y: 0))
        #expect(update(&pattern, to: 0, 0).isEmpty)
    }

    @Test("Diagonal move at length 5 emits 3 points (port of testSimpleMoveOfRunningStitch)")
    func simpleMoveCount() {
        var pattern = ZigzagStitchPattern(length: 5, width: 10, start: StagePoint(x: 0, y: 0))
        #expect(update(&pattern, to: 10, 10).count == 3)
    }

    @Test("setStartPosition re-anchors (port of Catroid testSetStartCoordinates)")
    func reAnchor() {
        var pattern = ZigzagStitchPattern(length: 5, width: 10, start: StagePoint(x: 0, y: 0))
        pattern.setStartPosition(StagePoint(x: 10, y: 10))
        #expect(update(&pattern, to: 0, 0).count == 3)
    }

    // MARK: - Perpendicular geometry beyond the horizontal golden line

    @Test("Vertical line, heading 0 (up): offsets are purely horizontal ∓width/2")
    func verticalLine() {
        var pattern = ZigzagStitchPattern(length: 10, width: 5, start: StagePoint(x: 0, y: 0))
        expect(update(&pattern, to: 0, 20, heading: 0), approximates: [
            StagePoint(x: -2.5, y: 0), StagePoint(x: 2.5, y: 10), StagePoint(x: -2.5, y: 20)
        ], "heading 0 = up; sin(90°) = 1 puts the full offset on x, first offset negative")
    }

    @Test("Diagonal heading 45°: components ±(width/2)·√2/2; the final clamped point stays unrounded")
    func diagonalLine() {
        // Expected values from the math, not the implementation: the
        // perpendicular of 45° has components √2/2, and the √200 move clamps
        // to one whole length of 10 at 10/√2 = 7.071… per axis. The final
        // point sits at the raw clamp — only interior midpoints javaRound.
        let half = sqrt(2) / 2
        let clamp = 10 / sqrt(2)
        var pattern = ZigzagStitchPattern(length: 10, width: 2, start: StagePoint(x: 0, y: 0))
        expect(update(&pattern, to: 10, 10, heading: 45), approximates: [
            StagePoint(x: -half, y: half),
            StagePoint(x: clamp + half, y: clamp - half)
        ])
    }

    // MARK: - Heading semantics (AC 2 and 3)

    @Test("Offsets follow the heading, not the path delta (Catroid samples motion direction)")
    func headingNotPathDelta() {
        var pattern = ZigzagStitchPattern(length: 10, width: 4, start: StagePoint(x: 0, y: 0))
        expect(update(&pattern, to: 20, 0, heading: 90), approximates: [
            StagePoint(x: 0, y: 2), StagePoint(x: 10, y: -2), StagePoint(x: 20, y: 2)
        ])
        // The path turns 90° upward but the sprite still faces right (a
        // goto/glide moves without rotating): offsets stay vertical rather
        // than turning perpendicular to the new path segment.
        expect(update(&pattern, to: 20, 20, heading: 90), approximates: [
            StagePoint(x: 20, y: 8), StagePoint(x: 20, y: 22)
        ])
    }

    @Test("A heading change takes effect on the next update — sampled once per call")
    func headingChangeNextUpdate() {
        var pattern = ZigzagStitchPattern(length: 10, width: 4, start: StagePoint(x: 0, y: 0))
        expect(update(&pattern, to: 20, 0, heading: 90), approximates: [
            StagePoint(x: 0, y: 2), StagePoint(x: 10, y: -2), StagePoint(x: 20, y: 2)
        ])
        // The sprite turned to heading 0 before the second move: every point
        // of this update — including the corner-adjacent midpoint — uses the
        // new heading. Catroid never re-orients within a single update.
        expect(update(&pattern, to: 20, 20, heading: 0), approximates: [
            StagePoint(x: 22, y: 10), StagePoint(x: 18, y: 20)
        ])
    }

    @Test("Direction alternation persists across update calls — never reset")
    func directionPersists() {
        var pattern = ZigzagStitchPattern(length: 10, width: 6, start: StagePoint(x: 0, y: 0))
        expect(update(&pattern, to: 20, 0, heading: 90), approximates: [
            StagePoint(x: 0, y: 3), StagePoint(x: 10, y: -3), StagePoint(x: 20, y: 3)
        ], "three emitted points flip direction three times")
        expect(update(&pattern, to: 30, 0, heading: 90), approximates: [
            StagePoint(x: 30, y: -3)
        ], "carried direction −1 puts the next point below the line; a reset would emit +3")
    }

    // MARK: - Rounding and accumulation

    @Test("Interior midpoints javaRound before the offset: −2.5 → −2, offset applied unrounded after")
    func midpointJavaRound() {
        // The base midpoint of (0,0)→(−5,0) at length 2.5 lands on exactly
        // −2.5: javaRound gives −2 (Swift .rounded() would give −3 — the
        // Catty divergence ADR-012 forbids porting; Catty's zigzag uses
        // plain round() here). The 2.5 offset lands after rounding:
        // −2 + 2.5 = 0.5, where offset-before-rounding would emit 0.
        var pattern = ZigzagStitchPattern(length: 2.5, width: 5, start: StagePoint(x: 0, y: 0))
        expect(update(&pattern, to: -5, 0, heading: 0), approximates: [
            StagePoint(x: -2.5, y: 0), StagePoint(x: 0.5, y: 0), StagePoint(x: -7.5, y: 0)
        ])
    }

    @Test("Sub-length moves accumulate until the threshold is crossed; surplus clamps the anchor")
    func accumulation() {
        var pattern = ZigzagStitchPattern(length: 10, width: 4, start: StagePoint(x: 0, y: 0))
        #expect(update(&pattern, to: 6, 0, heading: 90).isEmpty)
        expect(update(&pattern, to: 12, 0, heading: 90), approximates: [
            StagePoint(x: 0, y: 2), StagePoint(x: 10, y: -2)
        ], "crossing at 12 units clamps to one whole length from the origin anchor")
    }

    // MARK: - Degenerate inputs (guarded — ADR-014 divergence) and well-defined widths (not guarded)

    @Test("Zero and negative lengths emit nothing instead of trapping")
    func degenerateLengths() {
        var zero = ZigzagStitchPattern(length: 0, width: 5, start: StagePoint(x: 0, y: 0))
        #expect(update(&zero, to: 5, 0, heading: 90).isEmpty)
        var negative = ZigzagStitchPattern(length: -2, width: 5, start: StagePoint(x: 0, y: 0))
        #expect(update(&negative, to: 5, 0, heading: 90).isEmpty)
    }

    @Test("Non-finite needle positions emit nothing and leave the pattern alive")
    func nonFinitePositions() {
        var pattern = ZigzagStitchPattern(length: 2, width: 2, start: StagePoint(x: 0, y: 0))
        #expect(update(&pattern, to: .infinity, 0, heading: 90).isEmpty)
        #expect(update(&pattern, to: Double.nan, 0, heading: 90).isEmpty)
        expect(update(&pattern, to: 4, 0, heading: 90), approximates: [
            StagePoint(x: 0, y: 1), StagePoint(x: 2, y: -1), StagePoint(x: 4, y: 1)
        ], "anchor, first flag, and direction all survive the rejected updates")
    }

    @Test("A non-finite heading emits nothing — NaN offsets would trap at unit conversion")
    func nonFiniteHeading() {
        var pattern = ZigzagStitchPattern(length: 2, width: 2, start: StagePoint(x: 0, y: 0))
        #expect(update(&pattern, to: 4, 0, heading: .nan).isEmpty)
        #expect(update(&pattern, to: 4, 0, heading: .infinity).isEmpty)
        expect(update(&pattern, to: 4, 0, heading: 90), approximates: [
            StagePoint(x: 0, y: 1), StagePoint(x: 2, y: -1), StagePoint(x: 4, y: 1)
        ], "the anchor was not advanced by the rejected updates")
    }

    @Test("A non-finite width emits nothing — NaN offsets would trap at unit conversion")
    func nonFiniteWidth() {
        var nan = ZigzagStitchPattern(length: 2, width: .nan, start: StagePoint(x: 0, y: 0))
        #expect(update(&nan, to: 4, 0, heading: 90).isEmpty)
        var infinite = ZigzagStitchPattern(length: 2, width: .infinity, start: StagePoint(x: 0, y: 0))
        #expect(update(&infinite, to: 4, 0, heading: 90).isEmpty)
    }

    @Test("Width 0 collapses points onto the path line — well-defined in Catroid, not guarded")
    func zeroWidth() {
        var pattern = ZigzagStitchPattern(length: 5, width: 0, start: StagePoint(x: 0, y: 0))
        expect(update(&pattern, to: 10, 0, heading: 90), approximates: [
            StagePoint(x: 0, y: 0), StagePoint(x: 5, y: 0), StagePoint(x: 10, y: 0)
        ])
    }

    @Test("Negative width phase-flips the zigzag — Catroid behavior, preserved")
    func negativeWidth() {
        var pattern = ZigzagStitchPattern(length: 10, width: -5, start: StagePoint(x: 10, y: 0))
        expect(update(&pattern, to: 30, 0, heading: 90), approximates: [
            StagePoint(x: 10, y: -2.5), StagePoint(x: 20, y: 2.5), StagePoint(x: 30, y: -2.5)
        ], "the golden 'Test Points' row with the offset phase inverted")
    }
}
