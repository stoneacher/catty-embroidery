import EmbroideryEngine
import Samples
import Testing

/// Story item 2 — the sample-1 golden. Sample-specific, deliberately not
/// parameterised: these are literals about *this* design.
///
/// Every figure below was re-derived from a run rather than copied from the
/// story's planning measurement, as the story's own test plan instructs ("they
/// are a sanity target, not an oracle").
@Suite("Octagon rosette golden")
struct OctagonRosetteGoldenTests {
    private var measured: SampleRun {
        run(SampleLibrary[.octagonRosette])
    }

    /// 2 `setVariable` + 1 `zigZagStitch` + 8 outer iterations of
    /// (8 inner × [`moveNSteps`, `turnRight`] + 1 outer `turnRight`) = 139.
    /// Loop bookkeeping is zero-tick (ADR-018), so ticks are exactly the count of
    /// executed action bricks.
    @Test("139 ticks — one per executed action brick")
    func tickCount() {
        #expect(measured.ticks == 139)
    }

    /// **3194, not 3201.** The boundary-free count is 1 offset anchor + 64 sides ×
    /// 50 intervals = 3201; nine sides emit 49 because their measured length falls
    /// an ulp below 100. That is a structure-determining threshold crossing, and
    /// it is pinned and explained by
    /// `SampleThresholdTests.theRosetteDependsOnLibmRoundingOfHypot` — read that
    /// test before touching this number.
    @Test("3194 stitch events, seven short of the boundary-free 3201")
    func stitchEventCount() {
        #expect(measured.stitchEventCount == 3194)
    }

    /// Catroid's default project sets no thread colour, so neither do we
    /// (verbatim). One colour block ⇒ `CO == 1` (ADR-012: CO counts blocks, i.e.
    /// changes + 1).
    @Test("no colour is ever set, so the design is a single colour block")
    func singleColourBlock() {
        #expect(measured.stream.colorChangeCount == 0)
        #expect(measured.stream.stitches.allSatisfy { !$0.isColorChange })
    }

    /// The story's "98.6 × 98.6 mm" doubles as a check that ADR-007's stage really
    /// is a ~100 mm hoop. Derived, not a bare literal: the closed form is
    /// `2 × (100(1 + √2) + 5)` stage points — the octagon-fan vertex extent plus
    /// the zigzag half-width — at 2 units/point and 0.1 mm/unit.
    @Test("the design is a 98.6 mm square, i.e. an ADR-007 100 mm hoop")
    func designExtentInMillimetres() throws {
        let extent = try #require(extentInMillimetres(of: measured.stream))
        let closedForm = 2 * (100 * (1 + 2.0.squareRoot()) + 5) * 2 / 10
        #expect(abs(extent.width - closedForm) < 0.05, "width \(extent.width) mm vs \(closedForm) mm")
        #expect(abs(extent.height - closedForm) < 0.05, "height \(extent.height) mm vs \(closedForm) mm")
    }

    /// The ±250 stage criterion is met with **3.5 points (0.7 mm) to spare**.
    /// That margin is a consequence of transcribing Catroid verbatim, not a knob:
    /// the side length 100 and the zigzag width 10 are the reference's. Asserted
    /// at the measured value rather than at the limit, so a change announces
    /// itself here instead of as a near-miss in the generic budget test.
    ///
    /// 246.5 rather than the closed form's 246.4214 because the stream holds
    /// **integer machine units**: 246.4214 points × 2 units/point is 492.84,
    /// which `javaRound`s to 493 units = 246.5 points. The margin is quantized to
    /// half a stage point, and this test reads the quantized value because that
    /// is what the exported design actually contains.
    @Test("the rosette clears the stage bound by under a millimetre")
    func stageMarginIsThin() throws {
        let bounds = try #require(stageBounds(of: measured.stream))
        let extreme = bounds.extreme
        #expect(extreme == 246.5, "extreme \(extreme); margin to 250 is \(250 - extreme)")
    }

    /// Every consecutive gap is at most hypot(2, 10) ≈ 10.2 points = 20.4 units,
    /// far under ADR-020's ±121, so nothing interpolates and the record count is
    /// the emission count.
    @Test("nothing interpolates and nothing jumps")
    func noJumps() {
        #expect(measured.stream.stitches.allSatisfy { !$0.isJump })
        #expect(measured.stream.count == measured.stitchEventCount)
    }

    /// 512-byte header + 3 bytes per record + the 3-byte end-of-file record.
    @Test("the serialized file is 10 097 bytes")
    func dstByteLength() {
        let file = DSTFile(stream: measured.stream, name: SampleLibrary[.octagonRosette].program.name)
        #expect(file.data.count == 512 + 3 * 3194 + 3)
    }
}
