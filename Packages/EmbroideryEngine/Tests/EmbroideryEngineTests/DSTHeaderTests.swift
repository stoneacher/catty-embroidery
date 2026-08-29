@testable import EmbroideryEngine
import Foundation
import Testing

@Suite("DST header writer")
struct DSTHeaderTests {
    // MARK: - Golden tests (fixtures are the byte-level arbiter, ADR-012)

    /// Metadata matches the stitch.dst fixture: ST=8, CO=1, +X=500,
    /// −X/+Y/−Y=0, AX=500, AY=0 — the fixture's actual program since US-105:
    /// one 500-unit move, interpolated to 6 jumps + plain target.
    @Test("reproduces the stitch.dst fixture header byte-for-byte")
    func goldenStitchHeader() throws {
        let stream = Self.makeStream([(0, 0), (250, 0)])
        let header = try DSTHeader(stream: stream, name: "stitch")
        #expect(try header.bytes == (Self.fixtureHeaderBytes("stitch")))
    }

    /// Metadata matches the color_change.dst fixture: ST=22, CO=2, +X=500,
    /// +Y=500, AX=0, AY=500 — three interpolated 500-unit moves with a color
    /// change before the second (8 + 7 + 7 stitches since US-105), and the
    /// >15-char name must truncate to "EmbroideryStitc" as in the fixture.
    @Test("reproduces the color_change.dst fixture header byte-for-byte")
    func goldenColorChangeHeader() throws {
        let stream = Self.makeStream(
            [(0, 0), (250, 0), (0, 0), (0, 250)],
            colorChangeBefore: 2
        )
        let header = try DSTHeader(stream: stream, name: "EmbroideryStitchColorChange")
        #expect(try header.bytes == (Self.fixtureHeaderBytes("color_change")))
    }

    // MARK: - Field-level formatting

    @Test("numeric fields are NUL-padded, the label keeps space padding")
    func fieldPadding() throws {
        let header = try DSTHeader(stream: Self.makeStream([(0, 0)]), name: "abc")
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
        let header = try DSTHeader(stream: Self.makeStream([(0, 0)]), name: "abc").bytes
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

    /// Stage (10,5), (0,0), (60,50), (20,45) → embroidery (20,10), (0,0),
    /// (120,100), (40,90): extents and AX/AY are relative to the first
    /// stitch (ADR-012), which origin-start fixtures cannot exercise. Every
    /// move stays within ±121 units so ST stays uninterpolated.
    @Test("extents and AX/AY are relative to the first stitch")
    func nonOriginFirstStitch() throws {
        let stream = Self.makeStream([(10, 5), (0, 0), (60, 50), (20, 45)])
        let fields = try Self.fields(in: DSTHeader(stream: stream, name: "rel").bytes)
        #expect(fields["ST"] == Self.ascii("4", paddedTo: 6, with: 0x00))
        #expect(fields["+X"] == Self.ascii("100", paddedTo: 4, with: 0x00))
        #expect(fields["-X"] == Self.ascii("20", paddedTo: 4, with: 0x00))
        #expect(fields["+Y"] == Self.ascii("90", paddedTo: 4, with: 0x00))
        #expect(fields["-Y"] == Self.ascii("10", paddedTo: 4, with: 0x00))
        #expect(fields["AX"] == Self.ascii("20", paddedTo: 5, with: 0x00))
        #expect(fields["AY"] == Self.ascii("80", paddedTo: 5, with: 0x00))
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
    ///
    /// Rows five and six were added by US-308, which depends on this method staying a
    /// *mangling backstop* while `DesignName` becomes the *rejecting* layer in front of it
    /// (ADR-026). Each pins one thing that story reasons from, and neither was covered
    /// before:
    ///
    /// - `"a/b:c"` passes through **untouched**. The file name rejects `/`
    ///   (`DSTFileNameProblem.prohibitedCharacter`) and the label accepts it, and
    ///   that same character reaching two different verdicts is what "the file
    ///   name is sanitized independently of the header label" means concretely.
    /// - `"  pad  "` keeps its **leading** whitespace. That is why `DesignName`
    ///   trims on input rather than trusting the engine to: untrimmed input
    ///   reaches the machine verbatim. The *trailing* spaces are deliberately
    ///   not asserted — the field is space-padded to 15, so they are
    ///   indistinguishable from padding, which is itself the reason an
    ///   all-whitespace name is `.empty` rather than valid.
    /// The last two rows were added by US-308's **cross-vendor round 2**, which found the
    /// backstop passing ASCII *control* bytes straight through: `DSTFile(name: "A\nB")`
    /// emitted an `LA` value beginning `41 0A 42`, and `0x0A` — with `0x1A` — is this
    /// header's own field terminator, so a scanning reader ends the field early and
    /// misparses everything after it. `DesignName` refuses them at the app boundary, but
    /// `DSTFile.init(stream:name:)` is public and takes a `String`, which is precisely the
    /// caller the backstop exists for. No test had sent a control byte down the direct path.
    private static let rawNames = [
        "", "stitch", "EmbroideryStitchColorChange", "Nähen⭐", "a/b:c", "  pad  ",
        "A\nB", "a\u{0}b\u{1A}c"
    ]
    private static let sanitizedLabels = [
        "", "stitch", "EmbroideryStitc", "N_hen_", "a/b:c", "  pad",
        "A_B", "a_b_c"
    ]

    @Test("names are sanitized deterministically", arguments: zip(rawNames, sanitizedLabels))
    func nameSanitization(name: String, label: String) throws {
        let header = try DSTHeader(stream: Self.makeStream([(0, 0)]), name: name)
        let fields = try Self.fields(in: header.bytes)
        #expect(fields["LA"] == Self.ascii(label, paddedTo: 15, with: 0x20))
    }

    /// **The whole forbidden ASCII domain, not three samples of it.** A cross-vendor round
    /// pointed out that the rows above cover LF, NUL and SUB, so a regression selectively
    /// preserving TAB, CR, another C0 control or DEL would pass every one of them. This walks
    /// all 33 non-printable ASCII bytes and both ends of the printable range.
    ///
    /// It asserts on the emitted `LA` bytes rather than on `sanitized` directly, because that
    /// method is `private` — and asserting where the bytes actually land is the stronger
    /// claim anyway.
    @Test("every non-printable ASCII byte is replaced, and every printable one survives")
    func theWholeASCIIDomainIsClassified() throws {
        for value in 0x00 ... 0x7F {
            let character = Character(UnicodeScalar(UInt8(value)))
            let header = try DSTHeader(stream: Self.makeStream([(0, 0)]), name: "a\(character)b")
            let label = try #require(Self.fields(in: header.bytes)["LA"])

            let isPrintable = (0x20 ... 0x7E).contains(value)
            let expected = isPrintable ? "a\(character)b" : "a_b"
            #expect(
                label == Self.ascii(expected, paddedTo: 15, with: 0x20),
                "byte 0x\(String(value, radix: 16))"
            )
            // The point of the rule: no field terminator, and nothing a C string would cut.
            #expect(label.contains(0x0A) == false)
            #expect(label.contains(0x1A) == false)
            #expect(label.contains(0x00) == false)
        }
    }

    // MARK: - Length invariant

    @Test("header is exactly 512 bytes with space fill after the content")
    func lengthAndFillInvariant() throws {
        let streams = [
            EmbroideryStream(),
            Self.makeStream([(0, 0)]),
            Self.makeStream([(0, 0), (-120, -50), (30, 20)], colorChangeBefore: 2)
        ]
        for stream in streams {
            let bytes = try DSTHeader(stream: stream, name: "AnyName").bytes
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
