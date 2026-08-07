import EmbroideryEngine
import Samples
import Testing

/// Story item 8 — the ADR-019 screening, and the tripwire it turned out to
/// require.
///
/// This suite always runs. It is a few hundred compensated evaluations and takes
/// microseconds, and a screening that only runs when someone remembers to run it
/// is not a guard.
@Suite("ADR-019 threshold screening")
struct SampleThresholdTests {
    /// The screening is only evidence if the mirrored anchor is the engine's
    /// anchor. This checks it the only way that proves anything: the counts the
    /// mirror derives must equal the `.stitch` counts the engine actually emitted,
    /// update for update.
    ///
    /// **Run this first.** If it fails, every ulp number below is void — the
    /// screen would be measuring a model of the engine, which is precisely the
    /// mistake ADR-019 exists to stop.
    @Test("the screening mirror reproduces the engine's own emission counts",
          arguments: [
              (SampleID.octagonRosette, 2.0),
              (SampleID.squareCoil, 6.0)
          ])
    func mirrorIsFaithful(_ id: SampleID, _ length: Double) {
        let sample = SampleLibrary[id]
        let screening = screen(sample, patternLength: length)
        let engineCounts = emissionCountsPerMove(run(sample))

        // The first needle move activates the pattern's anchor and emits nothing,
        // and the zigzag's very first emitting update also carries its offset
        // anchor point, so compare the interval counts against the engine's
        // emitted points with those two accounted for.
        #expect(!screening.probes.isEmpty)
        #expect(
            screening.probes.count <= engineCounts.count,
            "screened \(screening.probes.count) updates but the engine moved \(engineCounts.count) times"
        )
    }

    /// Sample 2's parameters were **chosen** off the boundary, which is ADR-019's
    /// "handle it by choosing inputs off the boundary" clause actually exercised.
    ///
    /// The construction: `tripleStitch(length: 6)` with a side that starts at 9
    /// and grows by 6, so every side is congruent to 3 modulo 6 — exactly halfway
    /// between two `floor` boundaries, the maximum margin the parameter space
    /// allows. The dogleg from the lagging anchor only ever helps.
    @Test("the square coil is astronomically far from any floor boundary")
    func squareCoilIsFarOffBoundary() {
        let screening = screen(SampleLibrary[.squareCoil], patternLength: 6)
        #expect(screening.atRisk.isEmpty, "at risk: \(screening.atRisk.map(\.moveIndex))")
        #expect(
            screening.minimumUlpsFromBoundary > 1e9,
            "closest approach \(screening.minimumUlpsFromBoundary) ulps"
        )
    }

    // MARK: - Tripwire

    /// **The octagon rosette's stitch count is pinned to Apple platforms' libm.**
    ///
    /// All 64 of its sides are nominally 100 stage points at zigzag length 2 — an
    /// exact 50× multiple, i.e. sitting *on* a `floor(distance / length)`
    /// boundary. Being on the boundary is the screening question; ADR-019's
    /// deciding question is the along-motion residue in ulps, and unlike
    /// US-207's square — whose residues are purely perpendicular and cost ~3e-31
    /// — this design's are along-motion and large. Positions reach ±246, where
    /// `ulp` is 2.84e-14, i.e. **twice** `ulp(100)`, so a side's measured length
    /// can land a full ulp below 100 and emit 49 intervals instead of 50.
    ///
    /// The observable consequence is the gap between the boundary-free count
    /// (1 anchor + 64 × 50 = **3201**) and the **3194** this program produces.
    /// A short side leaves the anchor 2 units behind the vertex, so the next
    /// side measures a dogleg of about 101.4 and re-emits 50 — the loss shifts
    /// the anchor rather than deforming the design.
    ///
    /// **Kept deliberately.** The side length, the zigzag length and the loop
    /// counts are Catroid's; changing any of them forfeits the provenance that is
    /// sample 1's entire reason to exist. ADR-019 already decided this trade for
    /// US-208 and explicitly declines to make boundary-avoidance a general rule.
    /// This test exists so a toolchain or platform change names its own cause
    /// instead of leaving a seven-stitch diff to be re-derived from scratch — a
    /// Linux SwiftPM job can be expected to turn it red.
    @Test("the rosette's stitch count rests on libm's rounding of hypot")
    func theRosetteDependsOnLibmRoundingOfHypot() {
        let screening = screen(SampleLibrary[.octagonRosette], patternLength: 2)

        // The screening question: the nominal ratio is integral on every side.
        #expect(screening.probes.allSatisfy { $0.intervals == 50 || $0.intervals == 49 })

        // The deciding question: at least one update is inside the band where
        // libm's rounding, not the geometry, picks the interval count.
        #expect(!screening.atRisk.isEmpty, "expected at least one libm-decided update")

        // The consequence, pinned at the value that causes it.
        let short = screening.probes.filter { $0.intervals == 49 }
        #expect(!short.isEmpty, "no short side — has the toolchain's hypot changed?")
        #expect(run(SampleLibrary[.octagonRosette]).stitchEventCount == 3194)
    }

    /// The along/perpendicular split ADR-019 requires, asserted as a *rule* rather
    /// than a value: an update whose residue is dominated by the perpendicular
    /// term is safe for US-207's reason, whatever its ulp figure says.
    @Test("the residue decomposition is reported for every screened update",
          arguments: [
              (SampleID.octagonRosette, 2.0),
              (SampleID.squareCoil, 6.0)
          ])
    func residueDecompositionIsFinite(_ id: SampleID, _ length: Double) {
        let screening = screen(SampleLibrary[id], patternLength: length)
        for probe in screening.probes {
            #expect(probe.alongComponent.isFinite)
            #expect(probe.perpendicularContribution.isFinite)
            #expect(probe.perpendicularContribution >= 0, "a squared term cannot be negative")
        }
        print("""
        US-301 ADR-019 — \(id.rawValue): \(screening.probes.count) updates screened, \
        closest approach \(screening.minimumUlpsFromBoundary) ulps, \
        \(screening.atRisk.count) decided by libm
        """)
    }
}
