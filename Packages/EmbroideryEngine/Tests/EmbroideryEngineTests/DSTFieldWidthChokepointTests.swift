import EmbroideryEngine
import Foundation
import Testing

/// US-211 / ADR-025: the DST header's fixed-width fields are a *serialization*
/// boundary, not a programmer-error backstop. `DSTHeader.appendField` ends in a
/// `precondition`, so a design the Tajima header cannot describe kills the
/// process — and three fields are reachable from ordinary input: the 4-wide
/// extents (`+X`/`-X`/`+Y`/`-Y`, > 9999 units), the 2-wide `CO` (> 99 colour
/// blocks) and the 6-wide `ST` (> 999,999 stitches).
///
/// The reachability is asymmetric, which is what rules out bounding coordinates
/// as the fix: inside ADR-007's 500x500 stage the maximum per-direction extent
/// is 1000 units, five times under the limit, whereas `CO` and `ST` overflow
/// without ever leaving the stage. US-210 closed the *coordinate* chokepoint
/// with guarded no-ops (ADR-020); a header field cannot be a no-op, so this one
/// becomes an error a caller handles.
///
/// ADR-019 screening: every input here sits *deliberately on* a field-width
/// boundary — 9999/10000, 99/100, 999,999/1,000,001 — because that is the
/// subject of the story rather than an accident of it. ADR-019's screening
/// question is answered yes; its *deciding* question (how far the exact value
/// sits from the boundary, in ulps) does not apply, because the comparison is
/// `valueBytes.count <= width` over exact decimal digit counts, not a
/// floating-point threshold crossing. The one input carrying any floating-point
/// content is the extent recipe (stage 4999.5 -> 9999 units), where 4999.5 and
/// its x2 product are both exactly representable, so `javaRound` has no residue
/// to resolve. The golden byte tests stay green untouched, which is the evidence
/// that only the trapping side of each boundary moved.
@Suite("DST field-width chokepoint: header limits are errors, not traps (ADR-025)")
struct DSTFieldWidthChokepointTests {
    // MARK: - The traps, pinned from the side that fails today

    // These assert `.success` rather than `.failure` on purpose.
    // `#expect(processExitsWith: .failure)` **passes today** — a trap is a
    // failure exit — so it would characterise the bug rather than fail on it,
    // and it would have to be deleted at green. Asserting `.success` fails now
    // with `.success -> .signal(SIGTRAP -> 5)`, turns green with the fix, and
    // survives as the guard for "no input, however adversarial, traps".
    //
    // An exit-test body runs in a fresh process and must not capture the
    // enclosing context — the constraint `DSTStitchRecordTests` documents.

    @Test("an extent past four digits does not kill the process")
    func anOversizeExtentDoesNotKillTheProcess() async {
        await #expect(processExitsWith: .success) {
            var stream = EmbroideryStream()
            stream.addStitch(at: StagePoint(x: 0, y: 0))
            stream.addStitch(at: StagePoint(x: 6000, y: 0))
            _ = DSTHeader(stream: stream, name: "overflow")
        }
    }

    @Test("a colour-block count past two digits does not kill the process")
    func anOversizeColorBlockCountDoesNotKillTheProcess() async {
        // 99 changes make `CO` = 100 with no stitches at all, so `CO` is the
        // only field over its width — `ST` reads 0 and every extent reads 0.
        await #expect(processExitsWith: .success) {
            var stream = EmbroideryStream()
            for _ in 0 ..< 99 {
                stream.addColorChange()
            }
            _ = DSTHeader(stream: stream, name: "overflow")
        }
    }

    @Test("a stitch count past six digits does not kill the process")
    func anOversizeStitchCountDoesNotKillTheProcess() async {
        // Isolated to one violated field on purpose. The ADR-020 cap move
        // (0 -> 60,500,000 stage points) also overflows `ST`, at 2,500,003
        // stitches, but it overflows `+X` too — and since `ST` is emitted
        // first, such a test would pass on emission order rather than on the
        // `ST` check. Alternating 1 unit apart dodges dedup inside a 1-unit
        // extent. Recorded in ADR-025, not committed: the cap move costs 1.4 s
        // and 134 MB for a number this recipe establishes in 0.5 s.
        await #expect(processExitsWith: .success) {
            var stream = EmbroideryStream()
            for index in 0 ..< 1_000_001 {
                stream.addStitch(at: StagePoint(x: index.isMultiple(of: 2) ? 0 : 0.5, y: 0))
            }
            _ = DSTHeader(stream: stream, name: "overflow")
        }
    }

    // MARK: - Just inside every boundary, which must keep working untouched

    @Test("an extent of exactly 9999 units serializes")
    func anExtentOfExactly9999Serializes() throws {
        // Stage 4999.5 -> 9999 embroidery units, the largest value the 4-wide
        // field can express; 5000 (10000 units) is the first that cannot.
        var stream = EmbroideryStream()
        stream.addStitch(at: StagePoint(x: 0, y: 0))
        stream.addStitch(at: StagePoint(x: 4999.5, y: 0))

        let fields = try Self.fields(in: DSTHeader(stream: stream, name: "extent").bytes)
        #expect(fields["+X"] == "9999")
        #expect(fields["-X"] == "0")
        #expect(fields["ST"] == "143")
    }

    /// The negative extent boundary puts `AX`/`AY` on *their* boundary at the
    /// same time, which is what makes the story's "`AX` is not an independent
    /// case" claim checked rather than asserted. `last` is always inside
    /// `boundingBox`, so `-(-X) <= AX <= +X` and a 4-digit extent bounds `AX`
    /// at `"-9999"` — five bytes in a five-wide field, **zero margin**. The
    /// safety is exact, not slack: widening the extent fields, or letting an
    /// extent reach five digits, overflows `AX` first.
    @Test("the negative extent boundary fills the signed axis fields exactly")
    func theNegativeExtentBoundaryAlsoFillsTheSignedAxisFields() throws {
        var stream = EmbroideryStream()
        stream.addStitch(at: StagePoint(x: 0, y: 0))
        stream.addStitch(at: StagePoint(x: -4999.5, y: -4999.5))

        let fields = try Self.fields(in: DSTHeader(stream: stream, name: "axis").bytes)
        #expect(fields["-X"] == "9999")
        #expect(fields["-Y"] == "9999")
        #expect(fields["AX"] == "-9999")
        #expect(fields["AY"] == "-9999")
    }

    @Test("exactly 99 colour blocks serialize")
    func ninetyNineColorBlocksSerialize() throws {
        // `CO` is changes + 1, so 98 changes is the largest count the 2-wide
        // field can express.
        var stream = EmbroideryStream()
        for _ in 0 ..< 98 {
            stream.addStitch(at: StagePoint(x: 1, y: 1))
            stream.addColorChange()
            stream.addStitch(at: StagePoint(x: 2, y: 2))
        }

        let fields = try Self.fields(in: DSTHeader(stream: stream, name: "blocks").bytes)
        #expect(fields["CO"] == "99")
    }

    /// Header only, deliberately: the record loop is orthogonal to field widths
    /// and costs an extra 0.3 s and 17 MB. Even so this is the most expensive
    /// test in the engine suite (~0.5 s, ~50 MB against a suite that otherwise
    /// runs in 0.2 s). It is paid because it is the boundary this story is
    /// *about* — the same trade `CoordinateChokepointTests` declined for the
    /// interpolation cap, and declined there because that cap "is a chosen
    /// round number rather than a semantic edge like +-121". A field width is
    /// the semantic edge.
    @Test("a stitch count of exactly 999,999 serializes")
    func aStitchCountOfExactly999999Serializes() throws {
        var stream = EmbroideryStream()
        for index in 0 ..< 999_999 {
            stream.addStitch(at: StagePoint(x: index.isMultiple(of: 2) ? 0 : 0.5, y: 0))
        }

        let fields = try Self.fields(in: DSTHeader(stream: stream, name: "stitches").bytes)
        #expect(fields["ST"] == "999999")
        #expect(fields["+X"] == "1")
    }

    // MARK: - Helpers

    /// Splits the header's 124 content bytes into tag -> value, dropping the
    /// in-field padding and the `\n` + 0x1A terminator. Deliberately local: it
    /// reads values as text, where `DSTHeaderTests.fields(in:)` compares raw
    /// padded bytes because padding is its subject.
    private static func fields(in header: [UInt8]) throws -> [String: String] {
        try #require(header.count == 512)
        var result: [String: String] = [:]
        var index = 0
        while index < 124 {
            let tag = try #require(String(bytes: header[index ..< index + 2], encoding: .utf8))
            try #require(header[index + 2] == UInt8(ascii: ":"))
            var end = index + 3
            while end < 124, header[end] != 0x0A {
                end += 1
            }
            let value = header[(index + 3) ..< end].filter { $0 != 0x00 && $0 != 0x20 }
            result[tag] = try #require(String(bytes: value, encoding: .utf8))
            index = end + 2
        }
        return result
    }
}
