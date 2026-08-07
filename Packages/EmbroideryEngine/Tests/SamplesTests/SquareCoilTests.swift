import EmbroideryEngine
import Samples
import Testing

/// Story item 3 — sample 2. Sample-specific literals for the square coil.
@Suite("Square coil")
struct SquareCoilTests {
    private var measured: SampleRun {
        run(SampleLibrary[.squareCoil])
    }

    /// ADR-015: the leading `setThreadColor` is **silent** — it selects the first
    /// block's colour and arms nothing, because no stitch has been emitted yet.
    /// The mid-program one arms exactly one change, so `CO = changes + 1 = 2`.
    ///
    /// The DST header is read rather than inferred from `colorChangeCount`, since
    /// `CO == 2` is what the acceptance criterion actually states.
    @Test("one effective colour change, so the header reads CO 2")
    func headerColourCountIsTwo() {
        #expect(measured.stream.colorChangeCount == 1)
        let header = DSTHeader(stream: measured.stream, name: SampleLibrary[.squareCoil].program.name)
        #expect(coField(of: header) == 2)
    }

    /// The two colour blocks are balanced to within a couple of stitches (1489 /
    /// 1487). The split point is chosen for that: cumulative thread after `k`
    /// sides is `3k(k+1)/2`, so 31 of 44 sides is the halfway mark, not 22.
    ///
    /// A balanced split makes this assertion mean something — "a change exists
    /// somewhere" would pass against a change on the second stitch.
    @Test("the colour change lands halfway through the thread, not halfway through the sides")
    func colourChangeSplitsTheDesignEvenly() throws {
        let firstChange = measured.stream.stitches.firstIndex { $0.isColorChange }
        let changeIndex = try #require(firstChange, "no colour-change record in the stream")
        let total = measured.stream.count
        let ratio = Double(changeIndex) / Double(total)
        #expect(abs(ratio - 0.5) < 0.02, "colour change at \(changeIndex) of \(total) (\(ratio))")
    }

    /// `TripleStitchPattern` emits `point, previous, point` per segment, so record
    /// *i* and *i + 2* share a position while *i + 1* differs. That triplet is the
    /// structural signature the story asks for.
    @Test("the stream contains triple-stitch triplets")
    func containsTripleStitchTriplets() {
        let positions: [StagePoint] = measured.stitchPositions
        var triplets = 0
        var index = 0
        while index + 2 < positions.count {
            let isTriplet = positions[index] == positions[index + 2]
                && positions[index] != positions[index + 1]
            if isTriplet {
                triplets += 1
            }
            index += 1
        }
        #expect(triplets > 0, "no back-and-forth triplet found — is this really triple stitch?")
    }

    /// Four right turns per revolution and 44 sides: 44 × 90° = 3960° = 11 × 360°,
    /// so the closing heading is exactly 0 (mod-360 normalization is exact,
    /// ADR-014). Asserted with `==`, not a tolerance.
    @Test("the coil's heading closes exactly")
    func headingClosesExactly() throws {
        let lastMove = try #require(
            measured.events.reversed().first(where: {
                if case .needleMoved = $0 {
                    true
                } else {
                    false
                }
            })
        )
        guard case let .needleMoved(_, update) = lastMove else {
            Issue.record("expected a needleMoved event")
            return
        }
        #expect(update.heading == 0)
    }

    /// Every gap is at most the 6-point stitch length, far under ADR-020's ±121.
    @Test("nothing interpolates and nothing jumps")
    func noJumps() {
        #expect(measured.stream.stitches.allSatisfy { !$0.isJump })
    }
}
