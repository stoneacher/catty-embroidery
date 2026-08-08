import EmbroideryEngine
import Samples
import Testing

/// Story item 7 — the cheap early canary for US-211.
///
/// `DSTHeader.appendField` **preconditions** on field width today, so an overflow
/// traps the whole test process rather than throwing (ADR-020's open item). This
/// suite is therefore an existence proof, not an error-handling test: every sample
/// must stay inside the field widths.
///
/// Once US-211 lands and `DSTFile.init`/`DSTHeader.init` become throwing
/// (ADR-025), these calls gain `try` and the assertions below stay exactly as
/// they are — they already assert the values, not the absence of a trap.
@Suite("Sample DST serialization")
struct SampleDSTTests {
    @Test("every sample serializes without tripping a header field width", arguments: SampleLibrary.all)
    func buildsADSTFile(_ sample: SampleProgram) throws {
        let measured = run(sample)
        let file = DSTFile(stream: measured.stream, name: sample.program.name)

        // 512-byte header + 3 bytes per record + the 3-byte end-of-file record.
        #expect(file.data.count == 512 + 3 * measured.stream.count + 3)

        let header = DSTHeader(stream: measured.stream, name: sample.program.name)
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
