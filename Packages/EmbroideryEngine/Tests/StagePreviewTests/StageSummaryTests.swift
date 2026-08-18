import EmbroideryEngine
import Samples
import StagePreview
import Testing

/// US-307 items 3 and 6: the four facts the stage's VoiceOver summary is built from.
///
/// **Item 3 asks for a sentence and this suite asserts numbers, deliberately.** The story's
/// example reads `"3194 stitches, 1 colour, 98.6 by 98.6 millimetres"`, which is not
/// assertable as written: `%lld` renders 3194 as "3,194" in `en_US`, so the literal never
/// appears, and `AppStringsTests` refuses on principle to assert English wording in a repo
/// shipping ~75 languages through Crowdin. So the numbers are pinned here, on the fast gate,
/// and the catalog's plural forms and argument substitution are pinned in `AppStringsTests`
/// the way every other parameterised entry already is.
@Suite("Stage summary")
struct StageSummaryTests {
    private static func run(_ id: SampleID) async -> PreviewRunState {
        let drained = await driveToCompletion(SampleLibrary[id].program)
        var run = PreviewRunState()
        run.begin()
        for update in drained.updates {
            run.apply(update)
        }
        return run
    }

    /// Item 3's numbers, for sample 1.
    ///
    /// 98.6 mm doubles as a check that ADR-007's stage really is a ~100 mm hoop, and the
    /// tolerance is the same 0.05 — half of one displayed decimal —
    /// `OctagonRosetteGoldenTests.designExtentInMillimetres` already uses against the closed
    /// form `2·(100(1+√2)+5)·2/10`.
    @Test("sample 1 summarises as 3194 stitches, 1 colour and 98.6 by 98.6 millimetres")
    func sampleOneSummarises() async {
        let run = await Self.run(.octagonRosette)

        let summary = run.summary
        #expect(summary.stitchCount == 3194)
        #expect(summary.colorCount == 1)
        #expect(abs(summary.widthInMillimetres - 98.6) < 0.05, "width \(summary.widthInMillimetres)")
        #expect(abs(summary.heightInMillimetres - 98.6) < 0.05, "height \(summary.heightInMillimetres)")
    }

    /// Sample 2, so the colour count is pinned at a value other than 1 and the size at
    /// something other than a square.
    @Test("sample 2 summarises as two colours and a 53.4 by 52.8 millimetre design")
    func sampleTwoSummarises() async {
        let run = await Self.run(.squareCoil)

        let summary = run.summary
        #expect(summary.stitchCount == 2976)
        #expect(summary.colorCount == 2)
        #expect(abs(summary.widthInMillimetres - 53.4) < 0.05, "width \(summary.widthInMillimetres)")
        #expect(abs(summary.heightInMillimetres - 52.8) < 0.05, "height \(summary.heightInMillimetres)")
    }

    /// **The discriminating fixture, and it has to be synthetic.**
    ///
    /// `colorCount` is distinct colours; `StitchDisplayList.ColorRun` is a *run* partition,
    /// so red → green → red is three runs and two colours, and DST's `CO` field would call it
    /// three blocks (changes + 1, ADR-012). Measured, **neither bundled sample can tell those
    /// three definitions apart** — the rosette is 1/1/1 and the coil 2/2/2 — so without this
    /// test a later reader could "fix" the count toward the header field and every other
    /// assertion in the repo would stay green.
    @Test("the colour count counts distinct colours, not runs and not colour blocks")
    func theColourCountCountsDistinctColours() {
        var list = StitchDisplayList()
        list.append(previewStitch(0, 0, PreviewColor.red))
        list.append(previewStitch(10, 0, PreviewColor.green))
        list.append(previewStitch(20, 0, PreviewColor.red))

        let summary = StageSummary(display: list, exportModel: nil)

        #expect(list.colorRuns.count == 3, "fixture premise: three runs")
        #expect(summary.colorCount == 2)
    }

    /// Item 6, first half: the export model is preferred when there is one.
    ///
    /// Made observable by handing over a display list and an export model that **disagree**,
    /// which no real run does — the only way to tell which source was read.
    @Test("the export model's bounding box is preferred when present")
    func theExportModelIsPreferred() {
        var list = StitchDisplayList()
        list.append(previewStitch(0, 0))
        list.append(previewStitch(100, 100))

        var stream = EmbroideryStream()
        stream.addStitch(at: StagePoint(x: 0, y: 0))
        stream.addStitch(at: StagePoint(x: 10, y: 10))

        let summary = StageSummary(display: list, exportModel: stream)

        // The stream spans 20 units = 2 mm; the display list spans 100 points = 20 mm.
        #expect(abs(summary.widthInMillimetres - 2) < 1e-9)
        #expect(abs(summary.heightInMillimetres - 2) < 1e-9)
        // The counts still come from the display list, which is the documented asymmetry.
        #expect(summary.stitchCount == 2)
    }

    /// Item 6, second half: before a run ends there is no export model, and the display
    /// bounds are the only source. ADR-007's other conversion — 0.2 mm per stage point.
    @Test("display bounds are used when there is no export model")
    func displayBoundsAreUsedWithoutAnExportModel() {
        var list = StitchDisplayList()
        list.append(previewStitch(-50, -25))
        list.append(previewStitch(50, 25))

        let summary = StageSummary(display: list, exportModel: nil)

        #expect(abs(summary.widthInMillimetres - 20) < 1e-9)
        #expect(abs(summary.heightInMillimetres - 10) < 1e-9)
    }

    /// Total for the inputs a run really produces at its edges: nothing stitched yet, and a
    /// stream with no records (which has no bounding box).
    @Test("an empty run summarises as zeros rather than trapping")
    func anEmptyRunSummarisesAsZeros() {
        #expect(StageSummary(display: StitchDisplayList(), exportModel: nil) == .empty)
        #expect(StageSummary(display: StitchDisplayList(), exportModel: EmbroideryStream()) == .empty)
    }

    /// A single stitch has zero extent, which is a legitimate design and not a degenerate
    /// input — `StageTransform.fitting` documents the same case. It must read as 0 mm rather
    /// than as a NaN a formatter would then speak.
    @Test("a one-stitch design has a finite zero size")
    func aOneStitchDesignHasZeroSize() {
        var list = StitchDisplayList()
        list.append(previewStitch(42, -17))

        let summary = StageSummary(display: list, exportModel: nil)

        #expect(summary.stitchCount == 1)
        #expect(summary.colorCount == 1)
        #expect(summary.widthInMillimetres == 0)
        #expect(summary.heightInMillimetres == 0)
    }

    /// ADR-021 divergence #5 lets a coordinate the stream *rejects* reach the display trace,
    /// and `changeXBy` accumulates to infinity from a legal program. `StitchDisplayList.bounds`
    /// already drops a non-finite edge per axis; this pins that the summary inherits that
    /// rather than speaking an infinity.
    @Test("a non-finite stitch position cannot produce a non-finite size")
    func aNonFiniteStitchCannotPoisonTheSize() {
        var list = StitchDisplayList()
        list.append(previewStitch(0, 0))
        list.append(previewStitch(.infinity, 40))

        let summary = StageSummary(display: list, exportModel: nil)

        #expect(summary.widthInMillimetres.isFinite)
        #expect(summary.heightInMillimetres.isFinite)
    }
}
