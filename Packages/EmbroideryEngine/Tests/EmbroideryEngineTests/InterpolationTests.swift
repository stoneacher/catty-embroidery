import EmbroideryEngine
import Foundation
import Testing

/// US-105: moves whose delta exceeds ±121 embroidery units on either axis
/// are split into jump stitches inside `EmbroideryStream.addStitch`. The
/// algorithm is pinned to Catroid `DSTStream.addInterpolatedPoints`
/// (ADR-012): duplicate of the previous point as jump, evenly spaced
/// intermediates as jumps (rounded in stage coordinates before the ×2 unit
/// conversion), target as jump, then target again as a plain stitch.
@Suite("Long-move interpolation and jumps")
struct InterpolationTests {
    /// Encodes a stream through the production US-106 file generator and
    /// returns its 3-byte records (header and end-of-file record stripped).
    /// Replaced the pre-US-106 hand-rolled record sequence so these tests
    /// exercise the real serialization path.
    private func records(for stream: EmbroideryStream) -> [[UInt8]] {
        let body = Array(DSTFile(stream: stream, name: "test").data.dropFirst(512).dropLast(3))
        return stride(from: 0, to: body.count, by: 3).map { Array(body[$0 ..< $0 + 3]) }
    }

    /// Clean-failure guard (US-105 journal lesson): checks encodability
    /// with direct position math, never touching the production encoder —
    /// an interpolation regression fails here as an expectation instead of
    /// tripping `DSTFile`'s precondition and killing the test process.
    @Test("Interpolated streams keep every consecutive delta encodable")
    func deltasStayEncodable() {
        var stream = EmbroideryStream()
        stream.addStitch(at: StagePoint(x: 0, y: 0))
        stream.addStitch(at: StagePoint(x: 250, y: 0))
        stream.addStitch(at: StagePoint(x: -123.4, y: 250.1))

        var previous: EmbroideryPoint?
        for stitch in stream.stitches {
            let dx = stitch.position.x - (previous ?? stitch.position).x
            let dy = stitch.position.y - (previous ?? stitch.position).y
            #expect(abs(dx) <= DSTStitchRecord.maxDelta, "unencodable dx \(dx)")
            #expect(abs(dy) <= DSTStitchRecord.maxDelta, "unencodable dy \(dy)")
            previous = stitch.position
        }
    }

    @Test("Delta of exactly 121 units passes through uninterpolated")
    func boundaryPassthrough() {
        var stream = EmbroideryStream()
        stream.addStitch(at: StagePoint(x: 0, y: 0))
        stream.addStitch(at: StagePoint(x: 60.5, y: 0))

        #expect(stream.stitches.map(\.position) == [
            EmbroideryPoint(x: 0, y: 0),
            EmbroideryPoint(x: 121, y: 0)
        ])
        #expect(stream.stitches.allSatisfy { !$0.isJump })
    }

    @Test("Delta of 122 units splits in two: dup, midpoint, target as jumps, then plain target")
    func justOverBoundary() {
        var stream = EmbroideryStream()
        stream.addStitch(at: StagePoint(x: 0, y: 0))
        stream.addStitch(at: StagePoint(x: 61, y: 0))

        // splitCount = ceil(122/121) = 2; midpoint rounds in stage
        // coordinates first: round(30.5) = 31 → 62 units.
        #expect(stream.stitches.map(\.position) == [
            EmbroideryPoint(x: 0, y: 0),
            EmbroideryPoint(x: 0, y: 0),
            EmbroideryPoint(x: 62, y: 0),
            EmbroideryPoint(x: 122, y: 0),
            EmbroideryPoint(x: 122, y: 0)
        ])
        #expect(stream.stitches.map(\.isJump) == [false, true, true, true, false])
    }

    // MARK: - The encodable-delta backstop (US-210, ADR-020)

    // These four sit *deliberately on* the ±121 threshold rather than a safe
    // distance from it — ADR-019 asks a story comparing against a threshold to
    // say where its inputs sit, and here the exact boundary is the subject.
    // The decision above rounds the stage *difference*; `DSTFile` encodes the
    // difference of *individually rounded positions* (ADR-012). At half-unit
    // stage fractions the two disagree by one, and the three cases below are
    // the ones where the decision says 121 and the encoder produces 122 —
    // which used to reach `DSTStitchRecord`'s precondition and kill the
    // process. ADR-020 adds the encoded delta as a second trigger, so the move
    // splits instead. Catroid does not split here; it emits a corrupt record
    // (`CONVERSION_TABLE[122]` is the −1 entry), which ADR-012 classes as a
    // reference accident rather than semantics to port.

    @Test("A move the decision rounds to 121 but the encoder to 122 splits instead of trapping")
    func encodedDeltaBackstopAtAPositiveHalfUnit() {
        // The journal's minimal repro (Codex US-110 round 1, 2026-07-16):
        // round((60.75 − 0.125) × 2) = round(121.25) = 121 → the difference
        // says "no split", while round(0.25) = 0 and round(121.5) = 122 make
        // the encoded delta 122.
        var stream = EmbroideryStream()
        stream.addStitch(at: StagePoint(x: 0.125, y: 0))
        stream.addStitch(at: StagePoint(x: 60.75, y: 0))

        // splitCount = ceil(122/121) = 2; the intermediate rounds in stage
        // coordinates first: round(30.4375) = 30 → 60 units.
        #expect(stream.stitches.map(\.position) == [
            EmbroideryPoint(x: 0, y: 0),
            EmbroideryPoint(x: 0, y: 0),
            EmbroideryPoint(x: 60, y: 0),
            EmbroideryPoint(x: 122, y: 0),
            EmbroideryPoint(x: 122, y: 0)
        ])
        #expect(stream.stitches.map(\.isJump) == [false, true, true, true, false])
    }

    @Test("The backstop fires across zero, where the two roundings straddle the origin")
    func encodedDeltaBackstopAcrossZero() {
        // The original 2026-07-09 swift-code-reviewer repro. Neither endpoint
        // is a half-unit on its own: round(−0.6) = −1 and round(120.6) = 121
        // put the encoded delta at 122, while round(121.2) = 121 leaves the
        // difference one short.
        var stream = EmbroideryStream()
        stream.addStitch(at: StagePoint(x: -0.3, y: 0))
        stream.addStitch(at: StagePoint(x: 60.3, y: 0))

        #expect(stream.stitches.map(\.position) == [
            EmbroideryPoint(x: -1, y: 0),
            EmbroideryPoint(x: -1, y: 0),
            EmbroideryPoint(x: 60, y: 0), // intermediate: stage round(30.0) = 30
            EmbroideryPoint(x: 121, y: 0),
            EmbroideryPoint(x: 121, y: 0)
        ])
        #expect(stream.stitches.map(\.isJump) == [false, true, true, true, false])
    }

    @Test("The backstop fires in the negative direction too")
    func encodedDeltaBackstopInTheNegativeDirection() {
        // The mirror of `encodedDeltaBackstopAcrossZero`. `javaRound` is
        // asymmetric at negative halves, so mirroring a trapping case is not
        // automatic — 0 → ±60.75 traps in neither direction, and this pair is
        // the one that does.
        var stream = EmbroideryStream()
        stream.addStitch(at: StagePoint(x: 0.3, y: 0))
        stream.addStitch(at: StagePoint(x: -60.3, y: 0))

        #expect(stream.stitches.map(\.position) == [
            EmbroideryPoint(x: 1, y: 0),
            EmbroideryPoint(x: 1, y: 0),
            EmbroideryPoint(x: -60, y: 0), // intermediate: stage round(−30.0) = −30
            EmbroideryPoint(x: -121, y: 0),
            EmbroideryPoint(x: -121, y: 0)
        ])
        #expect(stream.stitches.map(\.isJump) == [false, true, true, true, false])
    }

    @Test("The mirror disagreement — decision 122, encoder 121 — keeps splitting as Catroid does")
    func differenceTriggerStillWinsWhereTheEncoderIsInRange() {
        // Green before ADR-020 as well as after: the regression guard for the
        // half of the disagreement where the reference is *not* broken.
        // round((61 − 0.25) × 2) = round(121.5) = 122 splits, while the encoded
        // delta 122 − 1 = 121 would be legal on its own. Deciding from the
        // encoded delta *alone* would stop splitting here and diverge from
        // Catroid at a point it handles correctly — which is why ADR-020 takes
        // the max of the two rather than replacing one with the other.
        var stream = EmbroideryStream()
        stream.addStitch(at: StagePoint(x: 0.25, y: 0))
        stream.addStitch(at: StagePoint(x: 61, y: 0))

        #expect(stream.stitches.map(\.position) == [
            EmbroideryPoint(x: 1, y: 0),
            EmbroideryPoint(x: 1, y: 0),
            EmbroideryPoint(x: 62, y: 0), // intermediate: stage round(30.625) = 31
            EmbroideryPoint(x: 122, y: 0),
            EmbroideryPoint(x: 122, y: 0)
        ])
        #expect(stream.stitches.map(\.isJump) == [false, true, true, true, false])
    }

    // MARK: - Catroid parity

    @Test("Diagonal split matches Catroid DSTStreamTest.testInterpolatedStitchPoints")
    func catroidDiagonalPort() {
        var stream = EmbroideryStream()
        stream.addStitch(at: StagePoint(x: 0, y: 0))
        stream.addStitch(at: StagePoint(x: 80, y: 80))

        // Stage (80,80) = 160 units per axis → splitCount 2, one
        // intermediate at stage (40,40) = units (80,80).
        #expect(stream.stitches.map(\.position) == [
            EmbroideryPoint(x: 0, y: 0),
            EmbroideryPoint(x: 0, y: 0),
            EmbroideryPoint(x: 80, y: 80),
            EmbroideryPoint(x: 160, y: 160),
            EmbroideryPoint(x: 160, y: 160)
        ])
        #expect(stream.stitches.map(\.isJump) == [false, true, true, true, false])
    }

    @Test("500-unit move reproduces the stitch.dst record bytes")
    func goldenAdjacentStructure() throws {
        var stream = EmbroideryStream()
        stream.addStitch(at: StagePoint(x: 0, y: 0))
        stream.addStitch(at: StagePoint(x: 250, y: 0))

        // splitCount = ceil(500/121) = 5 → dup + 4 intermediates + target
        // as jumps, then the plain target: ST grows by 7 to 8.
        #expect(stream.count == 8)
        #expect(stream.stitches.map(\.position.x) == [0, 0, 100, 200, 300, 400, 500, 500])
        #expect(stream.stitches.map(\.isJump) == [
            false, true, true, true, true, true, true, false
        ])

        let url = try #require(Bundle.module.url(
            forResource: "stitch",
            withExtension: "dst",
            subdirectory: "Resources/EmbroideryReference"
        ))
        let fixture = try Data(contentsOf: url)
        let fixtureRecords = fixture.dropFirst(512).dropLast(3)
        expectBytesEqual(records(for: stream).flatMap(\.self), fixtureRecords)
    }

    @Test("Emitted deltas telescope to the exact converted target and stay encodable")
    func accumulatedRounding() throws {
        var stream = EmbroideryStream()
        stream.addStitch(at: StagePoint(x: 0, y: 0))
        stream.addStitch(at: StagePoint(x: 123.4, y: -250.1))

        let deltas = records(for: stream).map(DSTRecordDecoder.decode)
        let target = try #require(EmbroideryPoint(converting: StagePoint(x: 123.4, y: -250.1)))
        #expect(deltas.reduce(0) { $0 + $1.dx } == target.x)
        #expect(deltas.reduce(0) { $0 + $1.dy } == target.y)
        #expect(stream.lastStitchPosition == target)
    }

    @Test("A user-armed jump flag survives interpolation onto the final stitch")
    func armedJumpFlagInteraction() {
        var stream = EmbroideryStream()
        stream.addStitch(at: StagePoint(x: 0, y: 0))
        stream.addJump()
        stream.addStitch(at: StagePoint(x: 100, y: 0))

        #expect(stream.stitches.map(\.isJump) == [false, true, true, true, true])
    }

    @Test("A user-armed color change lands only on the final stitch and counts once")
    func armedColorChangeFlagInteraction() {
        let red = ThreadColor(red: 255, green: 0, blue: 0)
        var stream = EmbroideryStream()
        stream.addStitch(at: StagePoint(x: 0, y: 0))
        stream.addColorChange()
        stream.addStitch(at: StagePoint(x: 100, y: 0), color: red)

        #expect(stream.colorChangeCount == 1)
        #expect(stream.stitches.map(\.isColorChange) == [false, false, false, false, true])
    }

    @Test("Dup and intermediates keep the previous color; target jump carries the new one")
    func interpolatedStitchColors() {
        let red = ThreadColor(red: 255, green: 0, blue: 0)
        var stream = EmbroideryStream()
        stream.addStitch(at: StagePoint(x: 0, y: 0))
        stream.addStitch(at: StagePoint(x: 100, y: 0), color: red)

        #expect(stream.stitches.map(\.color) == [.black, .black, .black, red, red])
    }
}
