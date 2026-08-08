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

    /// The colour change rides one exact record, and that record is derived, not
    /// eyeballed: 31 sides at 3 points per interval over `1 + 2 + … + 31 = 496`
    /// intervals, plus the one anchor point the pattern emits on its first update,
    /// puts the first amber stitch at index `3 × 496 + 1 = 1489`.
    ///
    /// **Pinned to the index, not to a ratio.** An earlier version allowed the
    /// flag anywhere within 2% of halfway — about 59 records — which is not an
    /// ADR-015 placement test at all: a bug delaying the armed change by thirty
    /// stitches would keep `CO == 2`, keep the split looking balanced, and still
    /// move where the machine stops (Codex round 1). ADR-015 says the change rides
    /// the actor's *next surviving stitch*; this asserts which one that is.
    @Test("the colour change rides the exact record ADR-015 puts it on")
    func colourChangeRidesTheExpectedRecord() throws {
        let firstChange = measured.stream.stitches.firstIndex { $0.isColorChange }
        let changeIndex = try #require(firstChange, "no colour-change record in the stream")
        let intervalsBeforeChange = (1 ... 31).reduce(0, +)
        #expect(changeIndex == 3 * intervalsBeforeChange + 1, "colour change at \(changeIndex)")

        // Exactly one record carries the flag, and it is the first amber stitch —
        // so the two blocks come out 1489 / 1487, near-balanced by construction.
        let flagged = measured.stream.stitches.count { $0.isColorChange }
        #expect(flagged == 1)
        #expect(measured.stream.count - changeIndex == 1487)
    }

    /// The record count and file size, pinned directly.
    ///
    /// `SampleDSTTests` only relates the byte count to `stream.count`, which stays
    /// true for *any* wrong stream — an implementation dropping the initial
    /// triple-stitch anchor would yield 2975 records and 9440 bytes while keeping
    /// the triplets, `CO 2`, no jumps, 137 ticks and the 132-record peak, and
    /// every other test in this suite would pass (Codex round 1).
    ///
    /// The derivation: `1 + 3 × (1 + 2 + … + 44) + 5` — one anchor, three points
    /// per interval over the 44 growing sides, and the five-point `sewUp` tack.
    @Test("2976 records and 9443 bytes, derived rather than observed")
    func recordAndByteCountsArePinned() {
        let intervals = (1 ... 44).reduce(0, +)
        #expect(measured.stream.count == 1 + 3 * intervals + 5)
        #expect(measured.stream.count == 2976)

        let file = DSTFile(stream: measured.stream, name: SampleLibrary[.squareCoil].program.name)
        #expect(file.data.count == 9443)
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
