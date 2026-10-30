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
        let engineCounts = emissionCountsPerMove(run(Self.sample))
        // The margin is evidence only if the mirror's anchor is the engine's, update for
        // update, through the diagonal row transitions (Codex slice review, finding 2).
        #expect(screening.predictedEmissions == engineCounts)
        // Every update screened exactly once: 250 rows that emit, and 750 that do not (250
        // spacing moves shorter than a stitch, and 500 turns, which update the needle without
        // moving it).
        let indices = (screening.probes + screening.subLengthProbes).map(\.moveIndex).sorted()
        #expect(indices == Array(0 ..< engineCounts.count))
        #expect(screening.probes.count == 250)
        #expect(engineCounts.count == 1_000)
        #expect(screening.subLengthProbes.count == 750)
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

    /// The program's name is what reaches the DST `LA` field since M5 (ADR-050: one name),
    /// so it must fit the field's 15 ASCII characters (ADR-012), or the export gate stays shut
    /// in the fixture's screenshots. `resourceName` is only the stable token, pinned beside it.
    @Test("its program name is a valid DST label")
    func programNameFitsTheLabel() {
        let name = Self.sample.program.name
        #expect(name == "US316 Compact")
        #expect(name.allSatisfy { $0.isASCII })
        #expect(name.count <= 15)
        #expect(SampleID.us316Compact.resourceName == "US316Compact")
    }

    @Test("its name and description resolve to real text")
    func stringsResolve() {
        let name = String(localized: Self.sample.displayName)
        let summary = String(localized: Self.sample.summary)
        #expect(name != Self.sample.nameKey)
        #expect(summary != Self.sample.descriptionKey)
    }
}
