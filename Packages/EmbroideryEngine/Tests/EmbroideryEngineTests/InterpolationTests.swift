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
    /// Encodes a stream's stitches as DST records the way the US-106 file
    /// generator will: the first record moves nowhere, every later record
    /// is the delta between consecutive absolute positions. Requires every
    /// delta to be encodable — interpolation's core guarantee — instead of
    /// letting the encoder's precondition kill the test process.
    private func records(for stream: EmbroideryStream) throws -> [DSTStitchRecord] {
        var previous: EmbroideryPoint?
        return try stream.stitches.map { stitch in
            let dx = stitch.position.x - (previous ?? stitch.position).x
            let dy = stitch.position.y - (previous ?? stitch.position).y
            previous = stitch.position
            try #require(
                abs(dx) <= DSTStitchRecord.maxDelta && abs(dy) <= DSTStitchRecord.maxDelta,
                "stream emitted an unencodable delta (\(dx), \(dy))"
            )
            return DSTStitchRecord(
                dx: dx,
                dy: dy,
                isJump: stitch.isJump,
                isColorChange: stitch.isColorChange
            )
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
        #expect(try records(for: stream).flatMap(\.bytes) == Array(fixtureRecords))
    }

    @Test("Emitted deltas telescope to the exact converted target and stay encodable")
    func accumulatedRounding() throws {
        var stream = EmbroideryStream()
        stream.addStitch(at: StagePoint(x: 0, y: 0))
        stream.addStitch(at: StagePoint(x: 123.4, y: -250.1))

        let deltas = try records(for: stream).map {
            DSTRecordDecoder.decode($0.bytes)
        }
        let target = EmbroideryPoint(converting: StagePoint(x: 123.4, y: -250.1))
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
