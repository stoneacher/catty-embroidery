import EmbroideryEngine
import Foundation
import Testing

/// US-106 round-trip property: reading a written file through the
/// test-only `DSTFileReader` reproduces the stream's stitch count, header
/// extents, per-record flags, and positions (relative to the first stitch
/// — DST stores only relative moves).
@Suite("DST file round-trip")
struct DSTRoundTripTests {
    @Test("an interpolated stream survives a round trip")
    func interpolatedStream() throws {
        var stream = EmbroideryStream()
        stream.addStitch(at: StagePoint(x: 0, y: 0))
        stream.addStitch(at: StagePoint(x: 250, y: 0))

        let decoded = try DSTFileReader.read(DSTFile(stream: stream, name: "stitch").data)
        try Self.expectMatches(decoded, stream)
        #expect(decoded.headerValue("CO") == 1)
    }

    @Test("jumps, a color change, and a non-origin start survive a round trip")
    func flagsAndNonOriginStart() throws {
        var stream = EmbroideryStream()
        stream.addStitch(at: StagePoint(x: 10, y: 5))
        stream.addJump()
        stream.addStitch(at: StagePoint(x: 0, y: 0))
        stream.addColorChange()
        stream.addStitch(at: StagePoint(x: 30, y: 20), color: ThreadColor(red: 255, green: 0, blue: 0))
        stream.addStitch(at: StagePoint(x: -40, y: -35), color: ThreadColor(red: 255, green: 0, blue: 0))

        let decoded = try DSTFileReader.read(DSTFile(stream: stream, name: "flags").data)
        try Self.expectMatches(decoded, stream)
        #expect(decoded.headerValue("CO") == 2)
    }

    /// Asserts the decoded file against the stream: ST, record count,
    /// flags, positions, and the four extents plus AX/AY relative to the
    /// first stitch. The extent formulas mirror `DSTHeader`'s on purpose —
    /// this property checks writer/reader agreement; the US-104 fixture
    /// goldens are the independent anchor for the semantics.
    private static func expectMatches(_ decoded: DecodedDSTFile, _ stream: EmbroideryStream) throws {
        #expect(decoded.headerValue("ST") == stream.count)
        #expect(decoded.records.count == stream.count)
        #expect(decoded.records.map(\.isJump) == stream.stitches.map(\.isJump))
        #expect(decoded.records.map(\.isColorChange) == stream.stitches.map(\.isColorChange))

        let first = try #require(stream.firstStitchPosition)
        let relativePositions = stream.stitches.map {
            EmbroideryPoint(x: $0.position.x - first.x, y: $0.position.y - first.y)
        }
        #expect(decoded.positions == relativePositions)

        let box = try #require(stream.boundingBox)
        let last = try #require(stream.lastStitchPosition)
        #expect(decoded.headerValue("+X") == max(box.max.x - first.x, 0))
        #expect(decoded.headerValue("-X") == abs(min(box.min.x - first.x, 0)))
        #expect(decoded.headerValue("+Y") == max(box.max.y - first.y, 0))
        #expect(decoded.headerValue("-Y") == abs(min(box.min.y - first.y, 0)))
        #expect(decoded.headerValue("AX") == last.x - first.x)
        #expect(decoded.headerValue("AY") == last.y - first.y)
    }
}
