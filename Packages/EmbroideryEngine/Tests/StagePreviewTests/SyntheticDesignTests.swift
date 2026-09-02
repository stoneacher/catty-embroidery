import EmbroideryEngine
import Interpreter
import Samples
import StagePreview
import Testing

/// US-309's measurement fixture, guarded.
///
/// **The fixture is this story's instrument, and an unchecked instrument measures
/// something other than what it claims.** Three of the guards below exist because the
/// planning pass built the synthetic wrong twice before it built it right:
///
/// - `runningStitch(length: 0.5)` yields **five** stitches, not fifty thousand. The brick
///   reads its length through `interpretInteger` (ADR-017), so a fractional length
///   silently collapses the design — and a collapsed design still runs, still animates and
///   still produces a frame-time capture, of nothing.
/// - A first serpentine ran to y ∈ [−625, 0], **outside ADR-007's ±250 stage**. That is not
///   cosmetic: `StageGeometry.fitTarget` is the hoop *union* the content, so an out-of-hoop
///   design makes the fitted transform depend on the bounds, every bounds growth changes
///   `BakeKey.transform`, and the run re-rasterises on every batch. The capture would have
///   measured re-baking rather than the settled frame it exists to measure.
/// - Stitch counts near a `floor(distance / length)` boundary move under trig rounding
///   (ADR-019). The parameters are chosen a half-length off every boundary, and the exact
///   count is *pinned* so that a drift names itself instead of quietly restating the
///   measurement's premise.
@Suite("US-309 synthetic design")
struct SyntheticDesignTests {
    // MARK: - The display-list half (built directly, no interpreter)

    @Test("the display list holds exactly the requested stitch count",
          arguments: [1_000, 5_000, 25_000, 50_000])
    func theDisplayListHoldsExactlyTheRequestedStitchCount(_ count: Int) {
        #expect(SyntheticDesign.displayList(count: count).count == count)
    }

    @Test("the display list holds exactly the requested number of colour runs",
          arguments: [1, 2, 100, 1_000])
    func theDisplayListHoldsExactlyTheRequestedColourRuns(_ runs: Int) {
        let list = SyntheticDesign.displayList(count: 50_000, colorRuns: runs)
        #expect(list.colorRuns.count == runs)
    }

    /// The runs must be a **gapless partition**, which `StitchDisplayList` guarantees for
    /// any input — so what this actually checks is that the fixture does not hand it a
    /// colour sequence that collapses adjacent runs into one and quietly halves the
    /// independent variable of `StitchDrawPlanScalingTests`.
    @Test("consecutive colour runs never share a colour")
    func consecutiveColourRunsNeverShareAColour() {
        let list = SyntheticDesign.displayList(count: 50_000, colorRuns: 1_000)
        let colors = list.colorRuns.map(\.color)
        #expect(!zip(colors, colors.dropFirst()).contains { $0 == $1 })
    }

    @Test("the display list stays inside ADR-007's stage")
    func theDisplayListStaysInsideTheStage() throws {
        let bounds = try #require(SyntheticDesign.displayList(count: 50_000).bounds)
        #expect(extreme(of: bounds) <= StageGeometry.halfExtentInPoints,
                "reaches \(extreme(of: bounds)) stage points")
    }

    // MARK: - The program half (the production path: interpreter → RunBatch → list)

    /// **Pinned as a literal as well as bounded**, the way the bundled samples are: a
    /// bound alone lets the count drift within it and takes the measurement's premise
    /// with it.
    @Test("the program stitches fifty thousand times")
    func theProgramStitchesFiftyThousandTimes() {
        let count = stitchEventCount(of: SyntheticDesign.program())
        #expect(count == SyntheticDesign.programStitchCount)
        #expect(count >= 50_000)
        // The package states the same number for itself. Two independent statements of one
        // fact, so a drift in either names itself rather than moving both sides at once.
        #expect(count == us309SyntheticStitchCount)
    }

    @Test("the program stays inside ADR-007's stage")
    func theProgramStaysInsideTheStage() throws {
        var subject = interpreter(SyntheticDesign.program())
        let stitches = tickBatches(&subject).flatMap { RunBatch.reducing($0).stitches }
        let bounds = try #require(StageBox.containing(stitches.map(\.position)))
        #expect(extreme(of: bounds) <= StageGeometry.halfExtentInPoints,
                "reaches \(extreme(of: bounds)) stage points")
    }

    /// AC3 and AC8 both want a **≥ 10 s** capture window. At ADR-018's one tick per
    /// displayed frame that is 600 ticks, so a design that reaches 50 000 stitches in
    /// twenty ticks would satisfy every count assertion above and still be unmeasurable.
    @Test("the program animates long enough to capture a ten-second window")
    func theProgramAnimatesLongEnoughToCapture() {
        var subject = interpreter(SyntheticDesign.program())
        #expect(tickBatches(&subject).count >= 600)
    }

    /// The design stitches in bands, and the count is pinned.
    ///
    /// **Not decoration.** Per-frame planning cost grows with the colour-run count
    /// (`StitchDrawPlanScalingTests`), so a single-run fixture would leave the one dependence
    /// ADR-009's claim actually has entirely unexercised at scale — while also screenshotting
    /// as a featureless black rectangle, which is what the first version of this design did.
    @Test("the program stitches in five colour bands")
    func theProgramStitchesInFiveColourBands() {
        var subject = interpreter(SyntheticDesign.program())
        var list = StitchDisplayList()
        for events in tickBatches(&subject) {
            list.append(contentsOf: RunBatch.reducing(events).stitches)
        }
        #expect(list.colorRuns.count == us309SyntheticColorRunCount)
        // Roughly equal bands, so no run is a sliver that makes the multi-run path vacuous.
        let smallest = list.colorRuns.map(\.range.count).min() ?? 0
        #expect(smallest >= list.count / (us309SyntheticColorRunCount * 2))
    }

    /// The two halves must describe the same design, or the story measures one thing and
    /// screenshots another.
    @Test("both halves of the fixture reach the same scale")
    func bothHalvesOfTheFixtureReachTheSameScale() {
        #expect(SyntheticDesign.programStitchCount >= 50_000)
        #expect(SyntheticDesign.displayList(count: 50_000).count == 50_000)
    }

    private func extreme(of bounds: StageBox) -> Double {
        max(abs(bounds.minX), abs(bounds.maxX), abs(bounds.minY), abs(bounds.maxY))
    }
}
