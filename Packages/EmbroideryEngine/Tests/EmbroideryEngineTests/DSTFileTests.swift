import EmbroideryEngine
import Foundation
import Testing

/// US-106: `DSTFile` serializes an `EmbroideryStream` into a complete
/// Tajima DST file — 512-byte header, one 3-byte record per stitch, and
/// the `00 00 F3` end-of-file record. The fixtures are the byte-level
/// arbiter (ADR-012); the color-change golden goes through the ADR-013
/// flag transposition.
@Suite("DST file generator")
struct DSTFileTests {
    // MARK: - Golden tests

    @Test("reproduces the stitch.dst fixture byte-for-byte")
    func goldenStitch() throws {
        let stream = Self.makeStream([(0, 0), (250, 0)])
        let file = DSTFile(stream: stream, name: "stitch")
        try expectBytesEqual(file.data, Self.fixtureData("stitch"))
    }

    /// ADR-013: Catroid flag placement wins (Catroweb: same program, same
    /// bytes as Android), so the expected bytes are the fixture with the
    /// color-change flag moved off Catty's placement — from the second
    /// move's duplicate jump (record 9) onto its final plain stitch
    /// (record 15). The `#require`s pin that the transposition still
    /// touches the fixture bytes it was derived from.
    @Test("reproduces color_change.dst through the ADR-013 flag transposition")
    func goldenColorChange() throws {
        let stream = Self.makeStream([(0, 0), (250, 0), (0, 0), (0, 250)], colorChangeBefore: 2)
        let file = DSTFile(stream: stream, name: "EmbroideryStitchColorChange")

        var expected = try Array(Self.fixtureData("color_change"))
        let dupFlagOffset = 512 + 8 * 3 + 2
        let plainFlagOffset = 512 + 14 * 3 + 2
        try #require(expected[dupFlagOffset] == 0xC3)
        try #require(expected[plainFlagOffset] == 0x03)
        expected[dupFlagOffset] = 0x83
        expected[plainFlagOffset] = 0xC3
        expectBytesEqual(file.data, expected)
    }

    // MARK: - Structure

    @Test("an empty stream produces header + end-of-file record only")
    func emptyStream() {
        let file = DSTFile(stream: EmbroideryStream(), name: "empty")
        #expect(file.data.count == 515)
        #expect(Array(file.data.suffix(3)) == [0x00, 0x00, 0xF3])
    }

    @Test("a single stitch emits one zero-delta plain record")
    func singleStitch() throws {
        let file = DSTFile(stream: Self.makeStream([(10, -20)]), name: "one")
        // #require, not #expect: indexing short data would crash the test
        // process and hide every other result (US-105 journal lesson).
        try #require(file.data.count == 518)
        #expect(Array(file.data[512 ..< 515]) == [0x00, 0x00, 0x03])
    }

    @Test("the end-of-file record appears exactly once, at the end")
    func terminatorOnlyAtEnd() throws {
        let stream = Self.makeStream([(0, 0), (250, 0), (0, 0), (0, 250)], colorChangeBefore: 2)
        let data = DSTFile(stream: stream, name: "term").data
        try #require(data.count >= 515)
        #expect(Array(data.suffix(3)) == [0x00, 0x00, 0xF3])
        let bytes = Array(data)
        for offset in stride(from: 512, to: bytes.count - 3, by: 3) {
            #expect(Array(bytes[offset ..< offset + 3]) != [0x00, 0x00, 0xF3])
        }
    }

    @Test("the first 512 bytes are the stream's DST header")
    func headerPrefix() {
        let stream = Self.makeStream([(0, 0), (30, 40)])
        let file = DSTFile(stream: stream, name: "head")
        expectBytesEqual(file.data.prefix(512), DSTHeader(stream: stream, name: "head").bytes)
    }

    // MARK: - write(to:)

    @Test("write(to:) persists exactly the in-memory data")
    func writeToURL() throws {
        let file = DSTFile(stream: Self.makeStream([(0, 0), (250, 0)]), name: "stitch")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("dst")
        defer { try? FileManager.default.removeItem(at: url) }

        try file.write(to: url)
        #expect(try Data(contentsOf: url) == file.data)
    }

    @Test("write(to:) throws when the destination directory does not exist")
    func writeToMissingDirectory() {
        let file = DSTFile(stream: Self.makeStream([(0, 0)]), name: "nowhere")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("missing.dst")
        #expect(throws: (any Error).self) {
            try file.write(to: url)
        }
    }

    // MARK: - Helpers

    /// Builds a stream from stage-space points, optionally signaling a
    /// color change before the stitch at `colorChangeBefore`.
    private static func makeStream(
        _ stagePoints: [(x: Double, y: Double)],
        colorChangeBefore: Int? = nil
    ) -> EmbroideryStream {
        var stream = EmbroideryStream()
        for (index, point) in stagePoints.enumerated() {
            if index == colorChangeBefore {
                stream.addColorChange()
            }
            stream.addStitch(at: StagePoint(x: point.x, y: point.y))
        }
        return stream
    }

    private static func fixtureData(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(
            forResource: name,
            withExtension: "dst",
            subdirectory: "Resources/EmbroideryReference"
        ))
        return try Data(contentsOf: url)
    }
}
