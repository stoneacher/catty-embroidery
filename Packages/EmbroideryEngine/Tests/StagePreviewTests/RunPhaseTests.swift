import EmbroideryEngine
import Samples
import StagePreview
import Testing

/// US-307 item 4 and its headline criterion: **the summary is rebuilt on run-state
/// transitions only, never per batch.** A VoiceOver value that changes sixty times a second
/// makes the screen unusable, and the criterion says explicitly that this is "asserted by
/// call count, not by inspection".
///
/// Two assertions carry it, and they are not redundant. The **count** is the criterion's
/// letter — 2 transitions against 139 batches for `octagonRosette`, two orders of magnitude
/// apart, so a per-batch fold fails loudly rather than marginally. The **equality across
/// every batch** is what actually protects VoiceOver, because the system re-announces on a
/// changed *value*, not on a write: a counter can be satisfied by an implementation that
/// rebuilds an identical value every frame, and that implementation would be silent anyway.
/// Neither alone is the property; both together are.
@Suite("Run phase")
struct RunPhaseTests {
    private static func drainedRosette() async -> DrainedRun {
        await driveToCompletion(SampleLibrary[.octagonRosette].program)
    }

    /// The criterion's letter, on a real sample.
    @Test("the summary is rebuilt once per state transition, not once per batch")
    func theSummaryIsRebuiltOncePerTransition() async {
        let drained = await Self.drainedRosette()
        var run = PreviewRunState()

        run.begin()
        for update in drained.updates {
            run.apply(update)
        }

        // idle → running (begin) and running → finished (the terminal update). Two.
        #expect(run.summaryRevision == 2)
        // The number this is worth comparing against, and the reason the claim is arithmetic
        // rather than a statement about code shape.
        #expect(run.revision == drained.updates.count)
        #expect(run.revision == 139)
        #expect(run.summaryRevision < run.revision / 10)
    }

    /// What actually keeps VoiceOver quiet: the value does not change mid-run, so there is
    /// nothing to re-announce even if something re-reads it.
    @Test("the summary value is identical across every batch of a run")
    func theSummaryIsIdenticalAcrossEveryBatch() async {
        let drained = await Self.drainedRosette()
        var run = PreviewRunState()
        run.begin()
        let whileRunning = run.summary
        var observed: [StageSummary] = []

        for update in drained.updates where update.termination == nil {
            run.apply(update)
            observed.append(run.summary)
        }

        #expect(observed.count > 100, "premise: this run has many non-terminal batches")
        #expect(observed.allSatisfy { $0 == whileRunning })
    }

    /// **The ordering bug this pins is invisible on screen and audible to a VoiceOver user.**
    /// The terminal update carries stitches of its own, so entering the terminal state before
    /// appending them would summarise a design one frame short. Asserted against the display
    /// list the same run ended with, not against a literal.
    @Test("the terminal summary counts the terminal batch's own stitches")
    func theTerminalSummaryIncludesTheTerminalBatch() async {
        let drained = await Self.drainedRosette()
        let terminal = drained.updates.last
        #expect(terminal?.termination != nil, "premise: the last update is the terminal one")
        #expect((terminal?.batch.stitches.count ?? 0) > 0, "premise: it carries stitches")

        var run = PreviewRunState()
        run.begin()
        for update in drained.updates {
            run.apply(update)
        }

        #expect(run.summary.stitchCount == run.display.count)
        #expect(run.summary.stitchCount == 3194)
    }

    /// A finished run's summary describes the finished design, so the size is the export
    /// model's — the source criterion 5 names, and the one only a terminal update supplies.
    @Test("a finished run summarises the size from the export model it was handed")
    func aFinishedRunSummarisesFromTheExportModel() async throws {
        let drained = await Self.drainedRosette()
        var run = PreviewRunState()
        run.begin()
        for update in drained.updates {
            run.apply(update)
        }

        let exported = try #require(run.exportModel)
        let box = try #require(exported.boundingBox)

        let width = Double(box.max.x - box.min.x) * StageGeometry.millimetresPerEmbroideryUnit
        #expect(abs(run.summary.widthInMillimetres - width) < 1e-9)
    }

    @Test("beginning a run clears the previous run's summary")
    func beginningClearsThePreviousSummary() async {
        let drained = await Self.drainedRosette()
        var run = PreviewRunState()
        run.begin()
        for update in drained.updates {
            run.apply(update)
        }
        #expect(run.summary.stitchCount == 3194, "premise: a finished run has a summary")

        run.begin()

        #expect(run.summary == .empty)
        #expect(run.state == .running)
        // The rebuild count keeps rising: it is a transition count, never live state.
        #expect(run.summaryRevision == 3)
    }

    @Test("resetting clears the summary and returns to idle")
    func resettingClearsTheSummary() async {
        let drained = await Self.drainedRosette()
        var run = PreviewRunState()
        run.begin()
        for update in drained.updates {
            run.apply(update)
        }

        run.reset()

        #expect(run.summary == .empty)
        #expect(run.state == .idle)
    }

    /// `apply` refuses updates outside a running run (ADR-027's guard against a discarded
    /// run's buffered frames). A refused update must not rebuild the summary either —
    /// otherwise a stale frame arriving after a reset would republish the discarded design's
    /// numbers to VoiceOver, which is the same hazard one layer up.
    @Test("an update refused because the run is not running does not touch the summary")
    func aRefusedUpdateDoesNotRebuildTheSummary() {
        var run = PreviewRunState()
        let before = run.summaryRevision

        run.apply(RunUpdate(batch: RunBatch(stitches: [previewStitch(1, 1)])))

        #expect(run.summaryRevision == before)
        #expect(run.summary == .empty)
    }

    /// A run that stops before its first stitch still gets a coherent terminal summary rather
    /// than the running one — reachable by pressing stop immediately, and by a program whose
    /// first bricks are `wait`.
    @Test("a run that produced nothing still summarises on finishing")
    func aRunThatProducedNothingStillSummarisesOnFinishing() {
        var run = PreviewRunState()
        run.begin()

        run.apply(
            RunUpdate(
                batch: RunBatch.empty,
                termination: RunTermination(reason: .stoppedByUser, exportModel: EmbroideryStream())
            )
        )

        #expect(run.state == .finished(.stoppedByUser))
        #expect(run.summaryRevision == 2)
        #expect(run.summary == .empty)
    }
}
