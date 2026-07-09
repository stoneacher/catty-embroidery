@testable import EmbroideryEngine
import Foundation
import Testing

@Suite("DST header writer")
struct DSTHeaderTests {
    // MARK: - Golden tests (fixtures are the byte-level arbiter, ADR-012)

    /// Metadata matches the stitch.dst fixture: ST=8, CO=1, +X=500,
    /// −X/+Y/−Y=0, AX=500, AY=0 — eight stitches zigzagging between stage
    /// x=0 and x=250 (embroidery x=500), name "stitch".
    @Test("reproduces the stitch.dst fixture header byte-for-byte")
    func goldenStitchHeader() throws {
        let stream = Self.makeStream([
            (0, 0), (250, 0), (0, 0), (250, 0),
            (0, 0), (250, 0), (0, 0), (250, 0)
        ])
        let header = DSTHeader(stream: stream, name: "stitch")
        #expect(try header.bytes == (Self.fixtureHeaderBytes("stitch")))
    }

    /// Metadata matches the color_change.dst fixture: ST=22, CO=2, +X=500,
    /// +Y=500, AX=0, AY=500 — and the >15-char name must truncate to
    /// "EmbroideryStitc" exactly as in the fixture.
    @Test("reproduces the color_change.dst fixture header byte-for-byte")
    func goldenColorChangeHeader() throws {
        var points: [(x: Double, y: Double)] = []
        for _ in 0 ..< 5 {
            points += [(0, 0), (250, 0)]
        }
        points.append((0, 0)) // 11 zigzag stitches in the first color block
        for step in 1 ... 10 {
            points.append((0, Double(step) * 25))
        }
        points.append((0, 250)) // 11 climbing stitches after the color change
        let stream = Self.makeStream(points, colorChangeBefore: 11)
        let header = DSTHeader(stream: stream, name: "EmbroideryStitchColorChange")
        #expect(try header.bytes == (Self.fixtureHeaderBytes("color_change")))
    }

    // MARK: - Field-level formatting

    @Test("numeric fields are NUL-padded, the label keeps space padding")
    func fieldPadding() throws {
        let header = DSTHeader(stream: Self.makeStream([(0, 0)]), name: "abc")
        let fields = try Self.fields(in: header.bytes)
        #expect(fields["LA"] == Self.ascii("abc", paddedTo: 15, with: 0x20))
        #expect(fields["ST"] == Self.ascii("1", paddedTo: 6, with: 0x00))
        #expect(fields["CO"] == Self.ascii("1", paddedTo: 2, with: 0x00))
        #expect(fields["PD"] == Self.ascii("*****", paddedTo: 5, with: 0x00))
    }

    /// Field widths are fixed, so every `\n` + 0x1A terminator sits at a
    /// known offset (LA ends at 18, ST at 29, … PD at 122).
    @Test("every field ends with newline + 0x1A at its fixed offset")
    func fieldTerminators() throws {
        let header = DSTHeader(stream: Self.makeStream([(0, 0)]), name: "abc").bytes
        try #require(header.count == 512)
        for offset in [18, 29, 36, 45, 54, 63, 72, 82, 92, 102, 112, 122] {
            #expect(header[offset] == 0x0A)
            #expect(header[offset + 1] == 0x1A)
        }
    }

    // MARK: - Field semantics (what the fixtures cannot cover)

    /// Stage (0,0), (−120,−50), (30,20) → embroidery (0,0), (−240,−100),
    /// (60,40): the −X/−Y extents must be magnitudes, never signed values
    /// (Catty's signed-extent bug, ADR-012 "do not port").
    @Test("negative extents are written as magnitudes")
    func negativeExtentMagnitudes() throws {
        let stream = Self.makeStream([(0, 0), (-120, -50), (30, 20)])
        let fields = try Self.fields(in: DSTHeader(stream: stream, name: "neg").bytes)
        #expect(fields["+X"] == Self.ascii("60", paddedTo: 4, with: 0x00))
        #expect(fields["-X"] == Self.ascii("240", paddedTo: 4, with: 0x00))
        #expect(fields["+Y"] == Self.ascii("40", paddedTo: 4, with: 0x00))
        #expect(fields["-Y"] == Self.ascii("100", paddedTo: 4, with: 0x00))
        #expect(fields["AX"] == Self.ascii("60", paddedTo: 5, with: 0x00))
        #expect(fields["AY"] == Self.ascii("40", paddedTo: 5, with: 0x00))
    }

    /// Stage (50,25), (0,0), (150,100), (100,50) → embroidery (100,50),
    /// (0,0), (300,200), (200,100): extents and AX/AY are relative to the
    /// first stitch (ADR-012), which origin-start fixtures cannot exercise.
    @Test("extents and AX/AY are relative to the first stitch")
    func nonOriginFirstStitch() throws {
        let stream = Self.makeStream([(50, 25), (0, 0), (150, 100), (100, 50)])
        let fields = try Self.fields(in: DSTHeader(stream: stream, name: "rel").bytes)
        #expect(fields["ST"] == Self.ascii("4", paddedTo: 6, with: 0x00))
        #expect(fields["+X"] == Self.ascii("200", paddedTo: 4, with: 0x00))
        #expect(fields["-X"] == Self.ascii("100", paddedTo: 4, with: 0x00))
        #expect(fields["+Y"] == Self.ascii("150", paddedTo: 4, with: 0x00))
        #expect(fields["-Y"] == Self.ascii("50", paddedTo: 4, with: 0x00))
        #expect(fields["AX"] == Self.ascii("100", paddedTo: 5, with: 0x00))
        #expect(fields["AY"] == Self.ascii("50", paddedTo: 5, with: 0x00))
    }

    @Test("an empty stream produces a zeroed header with CO:1")
    func emptyStreamHeader() throws {
        let fields = try Self.fields(in: DSTHeader(stream: EmbroideryStream(), name: "empty").bytes)
        #expect(fields["ST"] == Self.ascii("0", paddedTo: 6, with: 0x00))
        #expect(fields["CO"] == Self.ascii("1", paddedTo: 2, with: 0x00))
        for tag in ["+X", "-X", "+Y", "-Y"] {
            #expect(fields[tag] == Self.ascii("0", paddedTo: 4, with: 0x00))
        }
        for tag in ["AX", "AY", "MX", "MY"] {
            #expect(fields[tag] == Self.ascii("0", paddedTo: 5, with: 0x00))
        }
    }

    // MARK: - Name sanitization

    /// Non-ASCII scalars become "_", then the result truncates to 15 chars;
    /// an empty name stays empty (all space padding).
    private static let rawNames = [
        "", "stitch", "EmbroideryStitchColorChange", "Nähen⭐"
    ]
    private static let sanitizedLabels = [
        "", "stitch", "EmbroideryStitc", "N_hen_"
    ]

    @Test("names are sanitized deterministically", arguments: zip(rawNames, sanitizedLabels))
    func nameSanitization(name: String, label: String) throws {
        let header = DSTHeader(stream: Self.makeStream([(0, 0)]), name: name)
        let fields = try Self.fields(in: header.bytes)
        #expect(fields["LA"] == Self.ascii(label, paddedTo: 15, with: 0x20))
    }

    // MARK: - Length invariant

    @Test("header is exactly 512 bytes with space fill after the content")
    func lengthAndFillInvariant() {
        let streams = [
            EmbroideryStream(),
            Self.makeStream([(0, 0)]),
            Self.makeStream([(0, 0), (-120, -50), (30, 20)], colorChangeBefore: 2)
        ]
        for stream in streams {
            let bytes = DSTHeader(stream: stream, name: "AnyName").bytes
            #expect(bytes.count == 512)
            #expect(bytes.dropFirst(124).allSatisfy { $0 == 0x20 })
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

    /// The first 512 bytes of a reference fixture.
    private static func fixtureHeaderBytes(_ name: String) throws -> [UInt8] {
        let url = try #require(Bundle.module.url(
            forResource: name,
            withExtension: "dst",
            subdirectory: "Resources/EmbroideryReference"
        ))
        return try Array(Data(contentsOf: url).prefix(512))
    }

    /// Splits the 124 content bytes into tag → raw value bytes (the value
    /// plus its in-field padding, excluding the `\n` + 0x1A terminator),
    /// requiring each field's two-byte terminator on the way.
    private static func fields(in header: [UInt8]) throws -> [String: [UInt8]] {
        try #require(header.count == 512)
        var result: [String: [UInt8]] = [:]
        var index = 0
        while index < 124 {
            let tag = try #require(String(bytes: header[index ..< index + 2], encoding: .utf8))
            try #require(header[index + 2] == UInt8(ascii: ":"))
            var end = index + 3
            while end < 124, header[end] != 0x0A {
                end += 1
            }
            try #require(header[end] == 0x0A)
            try #require(header[end + 1] == 0x1A)
            result[tag] = Array(header[index + 3 ..< end])
            index = end + 2
        }
        return result
    }

    /// ASCII bytes of `text` right-padded to `width` with `pad`.
    private static func ascii(_ text: String, paddedTo width: Int, with pad: UInt8) -> [UInt8] {
        Array(text.utf8) + Array(repeating: pad, count: width - text.utf8.count)
    }
}
