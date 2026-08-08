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
              (SampleID.octagonRosette, 2.0, 1),
              (SampleID.squareCoil, 6.0, 3)
          ])
    func mirrorIsFaithful(_ id: SampleID, _ length: Double, _ pointsPerInterval: Int) {
        let sample = SampleLibrary[id]
        let screening = screen(sample, patternLength: length, pointsPerInterval: pointsPerInterval)
        let engineCounts = emissionCountsPerMove(run(sample))

        #expect(!screening.probes.isEmpty)

        // Element-by-element over every needle-move tick, zeros included. A
        // weaker form of this test — comparing totals, or counts, or asserting an
        // inequality — would pass against a mirror whose anchor drifted and whose
        // errors happened to cancel, which is exactly the failure mode that makes
        // a screen worthless. It has to be the whole sequence.
        #expect(screening.predictedEmissions == engineCounts, """
        mirror disagrees with the engine
          predicted \(screening.predictedEmissions.prefix(12))…
          engine    \(engineCounts.prefix(12))…
        """)
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
        let screening = screen(SampleLibrary[.squareCoil], patternLength: 6, pointsPerInterval: 3)
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
    /// (1 anchor + 64 × 50 = **3201**) and the **3194** this program produces,
    /// and it reconciles in three terms rather than one:
    ///
    ///     1 anchor + 54 × 50 + 10 × 49 + 3 × 1 = 3194
    ///
    /// Ten sides come up an interval short. Seven of those are decided by libm
    /// — their exact length sits within the band where `hypot`'s rounding, not
    /// the geometry, picks the count. The rest are the *geometric* consequence of
    /// the anchor those seven left behind: a short side leaves the anchor 2 units
    /// back, so the next side measures a dogleg and can fall ~1e-4 short, which is
    /// 1e10 ulps off the boundary and not a threshold case at all.
    ///
    /// **The split is not stable under rotation, and the total is.** Correcting
    /// the start heading from 0 to Catroid's 90 (Codex round 1) moved the shape
    /// from `55/9/2` to `54/10/3` while leaving the total at exactly 3194, the
    /// tick count at 139, the peak at 51 and the extents unchanged — the rosette
    /// has 8-fold symmetry, so a quarter turn maps it onto itself. Which
    /// *particular* sides fall short is threshold-sensitive; how many stitches
    /// come out is not. That is worth knowing before reading a future diff here.
    ///
    /// The `2 × 1` term is the surprise, and it is worth stating because nothing
    /// in ADR-019 predicts it: **a `turnRight` brick can emit a stitch.** A turn
    /// moves the needle zero distance, but it still produces a `.needleMoved`
    /// that reaches the pattern, and when a short side has left the anchor 2
    /// units behind — exactly the zigzag length — that zero-distance update
    /// measures 2.0 from the anchor and emits one catch-up point. So the design
    /// self-corrects: the anchor never drifts more than one interval behind, and
    /// the loss shifts the anchor rather than deforming the shape.
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
        let screening = screen(SampleLibrary[.octagonRosette], patternLength: 2, pointsPerInterval: 1)
        let histogram = Dictionary(grouping: screening.probes, by: \.intervals).mapValues(\.count)

        // The screening question — every side's nominal ratio is integral, so all
        // 64 are *on* a boundary. Pinned as the emission shape they produce.
        #expect(histogram[50] == 54, "full sides: \(histogram)")
        #expect(histogram[49] == 10, "short sides: \(histogram)")
        #expect(histogram[1] == 3, "turn catch-up updates: \(histogram)")

        // The deciding question — how many are inside the band where libm's
        // rounding, not the geometry, picks the count. Seven of the nine; the
        // other two are the lagging-anchor dogleg, 1e10 ulps clear.
        #expect(screening.atRisk.count == 7, "libm-decided: \(screening.atRisk.map(\.moveIndex))")

        // The consequence, pinned at the value that causes it.
        #expect(run(SampleLibrary[.octagonRosette]).stitchEventCount == 3194)
    }

    /// The along/perpendicular split ADR-019 requires, asserted as a *rule* rather
    /// than a value: an update whose residue is dominated by the perpendicular
    /// term is safe for US-207's reason, whatever its ulp figure says.
    @Test("the residue decomposition is reported for every screened update",
          arguments: [
              (SampleID.octagonRosette, 2.0, 1),
              (SampleID.squareCoil, 6.0, 3)
          ])
    func residueDecompositionIsFinite(_ id: SampleID, _ length: Double, _ pointsPerInterval: Int) {
        let screening = screen(SampleLibrary[id], patternLength: length, pointsPerInterval: pointsPerInterval)
        for probe in screening.probes {
            #expect(probe.alongComponent.isFinite)
            #expect(probe.perpendicularContribution.isFinite)

            // The two parts account for the whole residual. Nearly by construction
            // — the perpendicular term is *defined* as the remainder — so this
            // guards the definition rather than discovering anything, and exists
            // so that redefining either part independently breaks a test instead
            // of silently un-summing.
            //
            // Not exact equality, and the reason is the interesting part: the
            // remainder is a subtraction of a large along component from a ~1e-15
            // residual, so re-adding it cannot recover the original bits. The
            // tolerance is scaled to the larger operand, which is where the lost
            // bits come from.
            let recombined = probe.alongComponent + probe.perpendicularContribution
            let scale = max(probe.alongComponent.magnitude, probe.residual.magnitude)
            #expect(abs(recombined - probe.residual) <= 4 * scale.ulp,
                    "decomposition lost \(recombined - probe.residual) at move \(probe.moveIndex)")

            // No assertion that the along term dominates. A first version had one
            // and it was wrong on ADR-019's own terms: the rosette's *first* side
            // moves exactly along its heading, so its along component is 0.0 and
            // its entire 1.9e-31 residue is perpendicular. That is not a defect,
            // it is US-207's square — the case ADR-019 calls **safe**, because a
            // purely perpendicular residue enters the distance quadratically and
            // costs ~1e-31. Which term dominates is the *finding*, not a
            // precondition, so this suite reports the split and lets the at-risk
            // classification (asserted per sample below) carry the verdict.
            #expect(probe.alongComponent.magnitude < probe.distance)
        }
        let histogram = Dictionary(grouping: screening.probes, by: \.intervals)
            .mapValues(\.count)
            .sorted { $0.key < $1.key }
            .map { "\($0.key)x\($0.value)" }
            .joined(separator: " ")
        print("""
        US-301 ADR-019 — \(id.rawValue): \(screening.probes.count) updates screened, \
        closest approach \(screening.minimumUlpsFromBoundary) ulps, \
        \(screening.atRisk.count) decided by libm, intervals [\(histogram)]
        """)
    }
}
