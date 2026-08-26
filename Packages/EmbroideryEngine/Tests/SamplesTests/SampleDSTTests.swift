import EmbroideryEngine
import Samples
import Testing

/// Story item 7 — the cheap early canary for US-211.
///
/// `DSTHeader.appendField` used to **precondition** on field width, so an
/// overflow trapped the whole test process rather than throwing (ADR-020's open
/// item). This suite is an existence proof, not an error-handling test: every
/// sample must stay inside the field widths.
///
/// US-211 landed and both initializers now throw (ADR-025). The prediction this
/// comment carried held exactly: the calls gained `try` and every assertion
/// below is unchanged, because they already asserted the values rather than the
/// absence of a trap. The error handling itself is
/// `DSTFieldWidthChokepointTests`'.
@Suite("Sample DST serialization")
struct SampleDSTTests {
    @Test("every sample serializes without tripping a header field width", arguments: SampleLibrary.all)
    func buildsADSTFile(_ sample: SampleProgram) throws {
        let measured = run(sample)
        let file = try DSTFile(stream: measured.stream, name: sample.program.name)

        // 512-byte header + 3 bytes per record + the 3-byte end-of-file record.
        #expect(file.data.count == 512 + 3 * measured.stream.count + 3)

        let header = try DSTHeader(stream: measured.stream, name: sample.program.name)
        let stitchCount = try #require(stField(of: header))
        #expect(stitchCount == measured.stream.count)
        #expect(stitchCount <= 999_999, "ST is 6 digits wide")
    }

    /// The extents are the field most likely to overflow first — 4 digits each,
    /// i.e. 9999 units, reachable at stage x = 6000 (ADR-020). ADR-007's stage
    /// caps a legal design at 1000 units, so this is slack; assert it anyway,
    /// because sample 1 sits 3.58 points from the stage bound and a future edit
    /// to it would land here.
    @Test("every sample's extents stay inside the 4-digit fields", arguments: SampleLibrary.all)
    func extentsFitTheirFields(_ sample: SampleProgram) throws {
        let measured = run(sample)
        let box = try #require(measured.stream.boundingBox)
        for extent in [box.max.x - box.min.x, box.max.y - box.min.y] {
            #expect(extent <= 9999, "extent \(extent) units overflows a 4-digit field")
        }
    }
}
