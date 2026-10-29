import EmbroideryEngine
import ProgramModel
import Samples
import Testing

/// US-316's overlap-density fixture as a sample: its floor-boundary margin, and the same
/// "DEBUG-only, never shipped" boundary `us309Synthetic` keeps.
@Suite("US-316 overlap-density fixture as a sample")
struct CompactSyntheticSampleTests {
    private static let sample = SampleProgram(id: .us316Compact, program: makeUS316CompactProgram())

    /// **The original's half-stitch argument does not carry over** (brief D2). With the
    /// anchor left where a row ended, the next row is measured diagonally, about
    /// √(400² + spacing²) away, close to the floor boundary at 400 lengths. So the margin is
    /// measured over every needle update rather than argued, and pinned.
    @Test("every needle update is far from a floor boundary")
    func farFromAnyFloorBoundary() {
        #expect(isScreenable(Self.sample.program))
        let screening = screen(Self.sample, patternLength: 2, pointsPerInterval: 1)
        #expect(screening.probes.count >= 250)
        #expect(screening.atRisk.isEmpty, "at risk: \(screening.atRisk.map(\.moveIndex))")
        #expect(
            screening.minimumUlpsFromBoundary >= 1e6,
            "closest approach \(screening.minimumUlpsFromBoundary) ulps"
        )
    }

    @Test("the fixture is not a shipping sample")
    func notShipped() {
        #expect(!SampleID.shipping.contains(.us316Compact))
        #expect(!SampleLibrary.all.map(\.id).contains(.us316Compact))
    }

    /// Fits the DST `LA` field's 15 ASCII characters (ADR-012), as `US309Synthetic` does.
    @Test("its resource name is a valid DST label")
    func resourceNameFitsTheLabel() {
        #expect(SampleID.us316Compact.resourceName == "US316Compact")
        #expect(SampleID.us316Compact.resourceName.allSatisfy { $0.isASCII })
        #expect(SampleID.us316Compact.resourceName.count <= 15)
    }

    @Test("its name and description resolve to real text")
    func stringsResolve() {
        let name = String(localized: Self.sample.displayName)
        let summary = String(localized: Self.sample.summary)
        #expect(name != Self.sample.nameKey)
        #expect(summary != Self.sample.descriptionKey)
    }
}
