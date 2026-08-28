import EmbroideryEngine
import ProgramModel
import Samples
import StagePreview
import Testing

/// US-308 test item 4 — the export gate.
///
/// **The gate is `exportModel.count > 1` on the post-replay assembled stream**, not
/// `hasValidPattern` (which counts recorded *ops* the replay may reject) and not the
/// display-list count (op-derived, same defect). That closes the divergence ADR-020 left
/// "for whoever wires up export to decide", and it matches Catroid's
/// `validPatternExists()`, which counts points in the *built* streams.
///
/// **This suite does not re-prove the divergence.** `DisplayVersusExportModelTests`
/// already owns that — six mechanisms, one of them the ADR-020 rejection this gate turns
/// on — and re-asserting it here would duplicate a green test. What is new is the
/// *verdict*: that the gate reaches five distinguishable answers, and in particular that
/// "drew nothing" and "drew something unsewable" are not the same answer, because the app
/// says different things about them.
@Suite("Export eligibility")
struct ExportEligibilityTests {
    // MARK: - Not run

    /// `exportModel` is `nil` until a terminal update arrives, so a fresh state is not
    /// exportable for a reason distinct from any verdict about stitches.
    @Test("a state that has never run is not exportable")
    func neverRunIsNotExportable() {
        let state = PreviewRunState()
        #expect(state.exportModel == nil)
        #expect(state.exportEligibility == .notRun)
        #expect(state.isExportable == false)
    }

    /// **Mid-run is never exportable, at any frame.** `PreviewRunState.exportModel` is
    /// written only in the terminal branch of `apply(_:)`, so the share affordance is
    /// disabled for the whole duration of every run — a consequence US-308's criteria do
    /// not state and ADR-026 must, since it means "export the design you can see, right
    /// now" is not something M3 offers.
    ///
    /// Frame by frame rather than at one arbitrary moment, because the claim is about
    /// every frame; a single mid-run sample would pass against an implementation that
    /// published the model on, say, the second frame.
    @Test("no frame of a running run is exportable")
    func midRunIsNeverExportable() async {
        let pacing = GatedRunPacing()
        let driver = InterpreterDriver(pacing: pacing)
        let session = driver.start(interpreter(foreverProgram()))

        var state = PreviewRunState()
        state.begin()
        var iterator = session.updates.makeAsyncIterator()

        var framesObserved = 0
        for frame in 0 ..< 5 {
            // The first frame needs no credit: the driver produces one, *then* paces.
            if frame > 0 {
                await pacing.grant()
            }
            guard let update = await iterator.next() else { break }
            state.apply(update)
            framesObserved += 1

            #expect(state.exportModel == nil, "frame \(frame) published an export model")
            #expect(state.exportEligibility == .notRun)
        }

        session.stop()
        while await iterator.next() != nil {}

        // Guards the loop above against passing vacuously on zero frames, and guards the
        // premise that a running run has stitches to show while still refusing export.
        #expect(framesObserved == 5)
        #expect(state.display.isEmpty == false)
    }

    /// Discarding a run takes the verdict back to `.notRun` rather than leaving the
    /// previous design exportable — the design on screen is gone, so the file must be too.
    @Test("resetting after a finished run returns to not-run")
    func resetReturnsToNotRun() async {
        var state = PreviewRunState()
        await Self.drive(Self.threeStitchProgram(), into: &state)
        #expect(state.exportEligibility == .ready)

        state.reset()

        #expect(state.exportModel == nil)
        #expect(state.exportEligibility == .notRun)
    }

    // MARK: - Ran, but not enough

    /// A program that terminates having stitched nothing at all: no display list, no
    /// stream. Distinct from the divergence below, because there is nothing on screen to
    /// explain away.
    @Test("a run that stitched nothing is not exportable")
    func nothingStitchedIsNotExportable() async {
        var state = PreviewRunState()
        await Self.drive(singleObjectProgram([.setThreadColor(hex: "#ff0000")]), into: &state)

        #expect(state.exportModel?.stitches.isEmpty == true)
        #expect(state.display.isEmpty)
        #expect(state.exportEligibility == .nothingStitched)
        #expect(state.isExportable == false)
    }

    /// One stitch is a point, not a design — and Catty ships exactly this as a
    /// valid-looking 515-byte header-plus-EOF file. The 518-byte one-stitch file is the
    /// same mistake one record later.
    ///
    /// The count is asserted **first**: without it the verdict could be right by accident,
    /// against an implementation that returned this case for anything it could not
    /// classify.
    @Test("a single stitch is not exportable")
    func oneStitchIsNotExportable() async {
        var state = PreviewRunState()
        await Self.drive(singleObjectProgram([.stitch]), into: &state)

        #expect(state.exportModel?.count == 1)
        #expect(state.exportEligibility == .singleStitch)
        #expect(state.isExportable == false)
    }

    // MARK: - The divergence (ADR-020)

    /// **The case where the export gate and the render empty-state legitimately
    /// disagree**: every coordinate the program asked for is finite but unrepresentable,
    /// so `emitStitches` draws it and `addStitch` refuses it. Ops recorded and drawn,
    /// every one rejected at replay.
    ///
    /// Note the program has **no leading origin stitch** — the divergence suite's version
    /// does, which is why that one lands on `stream.count == 1` and this one on 0. Pure
    /// rejection is what this verdict is about.
    @Test("a design whose every coordinate is rejected is not exportable")
    func rejectedOnlyDesignIsNotExportable() async {
        var state = PreviewRunState()
        await Self.drive(
            singleObjectProgram([
                .placeAt(x: .number(1e300), y: .number(0)),
                .stitch,
                .placeAt(x: .number(2e300), y: .number(0)),
                .stitch
            ]),
            into: &state
        )

        #expect(state.display.count == 2, "the preview drew what the program asked for")
        #expect(state.exportModel?.stitches.isEmpty == true, "the machine never goes there")
        #expect(state.exportEligibility == .nothingEmbroiderable)
        #expect(state.isExportable == false)
    }

    /// **The two zero-stitch verdicts must not collapse into one.** They carry different
    /// messages — one design drew nothing, the other drew something no machine can sew —
    /// and an implementation that returned a single "empty" case would pass both tests
    /// above while making the app say the wrong thing about one of them.
    @Test("drawing nothing and drawing something unsewable are different verdicts")
    func theTwoEmptyVerdictsAreDistinct() async {
        var stitchedNothing = PreviewRunState()
        await Self.drive(
            singleObjectProgram([.setThreadColor(hex: "#ff0000")]), into: &stitchedNothing
        )

        var rejectedOnly = PreviewRunState()
        await Self.drive(
            singleObjectProgram([
                .placeAt(x: .number(1e300), y: .number(0)),
                .stitch
            ]),
            into: &rejectedOnly
        )

        // Same stream count, different verdicts — which is the whole point.
        #expect(stitchedNothing.exportModel?.count == rejectedOnly.exportModel?.count)
        #expect(stitchedNothing.exportEligibility != rejectedOnly.exportEligibility)
    }

    // MARK: - Ready

    /// Two stitches is the boundary the gate names, so it is asserted at the boundary
    /// rather than only far above it.
    @Test("two stitches are exportable")
    func twoStitchesAreExportable() async {
        var state = PreviewRunState()
        await Self.drive(
            singleObjectProgram([
                .placeAt(x: .number(0), y: .number(0)),
                .stitch,
                .placeAt(x: .number(5), y: .number(0)),
                .stitch
            ]),
            into: &state
        )

        #expect(state.exportModel?.count == 2)
        #expect(state.exportEligibility == .ready)
        #expect(state.isExportable)
    }

    /// **A real bundled design, and the test that stops every case above being satisfied
    /// by a constant.** Without a reachable `.ready`, an implementation that returned
    /// `.notRun` for everything passes the four refusal tests.
    ///
    /// The count is compared against `assembledStream(of:)` — derived without the driver —
    /// rather than against a literal, because the export model and the display list differ
    /// by ADR-021's six divergences, so a literal here would be pinning the wrong number.
    @Test("a bundled sample is exportable")
    func bundledSampleIsExportable() async throws {
        let sample = try #require(SampleLibrary.all.first)
        var state = PreviewRunState()
        await Self.drive(sample.program, into: &state)

        let model = try #require(state.exportModel)
        #expect(model == assembledStream(of: sample.program))
        #expect(model.count > 1)
        #expect(state.exportEligibility == .ready)
        #expect(state.isExportable)
    }

    // MARK: - Helpers

    /// Three stitches, used where the design's shape does not matter but its size does.
    private static func threeStitchProgram() -> Program {
        singleObjectProgram([
            .placeAt(x: .number(0), y: .number(0)),
            .stitch,
            .placeAt(x: .number(5), y: .number(0)),
            .stitch,
            .placeAt(x: .number(10), y: .number(0)),
            .stitch
        ])
    }

    /// Runs `program` to completion through the driver and folds every update into
    /// `state`, exactly as `RunViewModel` does — so the verdict is read off a state the
    /// app could actually be holding, rather than off a hand-assembled one.
    private static func drive(_ program: Program, into state: inout PreviewRunState) async {
        state.begin()
        let drained = await driveToCompletion(program)
        for update in drained.updates {
            state.apply(update)
        }
    }
}
