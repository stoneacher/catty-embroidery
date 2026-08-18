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

    /// The criterion's letter, on a real sample — and **what this number is and is not**.
    ///
    /// `revision` counts *observable* changes to the phase, not invocations of the summary
    /// builder. Codex round 3: adding a discarded `StageSummary(...)` to every `apply` would
    /// leave this at 2 and every assertion here green, while constructing 139 summaries. That
    /// gap is real and is not worth closing with instrumentation, because the thing the
    /// criterion protects is what VoiceOver *announces* — which is driven by the value
    /// changing, not by how often it was computed. `theSummaryIsIdenticalAcrossEveryBatch`
    /// below is the assertion that covers that, and the two are quoted together for a reason.
    @Test("the summary changes once per state transition, not once per batch")
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
    /// A terminal update that carries stitches of its own would be summarised one frame short
    /// if the state were entered before the append.
    ///
    /// **Synthetic, and it has to be.** The obvious version of this test drives a real sample
    /// and asserts the premise that its terminal batch carries stitches — measured, it carries
    /// **zero**: a program that finishes on its own does so on a step that emitted nothing, so
    /// the ordering is unobservable through either bundled sample and the test would have been
    /// vacuous while looking thorough. (Found by running it: the premise assertion was the one
    /// thing that failed in the green run.) The path is real all the same — ADR-027 records
    /// that a stop landing inside a frame rides that frame's stitches out on the terminal
    /// itself, which is `.stoppedByUser` and is what this fixture is.
    @Test("the terminal summary counts the terminal batch's own stitches")
    func theTerminalSummaryIncludesTheTerminalBatch() {
        var run = PreviewRunState()
        run.begin()
        run.apply(RunUpdate(batch: RunBatch(stitches: [previewStitch(0, 0)])))

        run.apply(
            RunUpdate(
                batch: RunBatch(stitches: [previewStitch(50, 0), previewStitch(50, 50)]),
                termination: RunTermination(reason: .stoppedByUser, exportModel: EmbroideryStream())
            )
        )

        #expect(run.display.count == 3, "premise: the terminal batch carried two stitches")
        #expect(run.summary.stitchCount == 3, "entering the state before the append gives 1")
    }

    /// The same claim for a run that ends on its own: the summary describes the whole design.
    ///
    /// Weaker than the ordering test above — this sample's terminal batch is empty, so it
    /// cannot distinguish the two orderings — but it is the one that pins the *number* a
    /// VoiceOver user actually hears for sample 1.
    @Test("a finished run's summary counts every stitch the run drew")
    func aFinishedRunCountsEveryStitch() async {
        let drained = await Self.drainedRosette()
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

    /// **A reset that resets nothing is not a transition.**
    ///
    /// Codex round 1: `reset()` on an already-idle run entered `.idle` from `.idle` and bumped
    /// the count anyway, so `summaryRevision == number of transitions` — the claim this
    /// story's headline criterion is asserted against — was literally false. Reachable in
    /// ordinary use: `AppModel.select(_:)` calls `runner.reset()` for the *first* selection,
    /// when the run has never started.
    @Test("resetting a run that never started is not counted as a transition")
    func resettingAFreshRunIsNotATransition() {
        var run = PreviewRunState()

        run.reset()
        run.reset()

        #expect(run.summaryRevision == 0)
        #expect(run.state == .idle)
        #expect(run.summary == .empty)
    }

    /// **Restarting mid-run is not a transition either, and working out why is the point.**
    ///
    /// This test was written expecting the opposite — that a second `begin()` must rebuild
    /// because it clears the display — and it failed, which is how a false claim in
    /// `RunPhase.enter`'s own comment was caught. A *running* summary carries no counts by
    /// design (criteria 5 and 6 are irreconcilable otherwise), so before and after the restart
    /// the state is `.running` and the summary is `.empty`: nothing a VoiceOver user could
    /// hear has changed, and the guard is right to say so. What did change — the display list
    /// — is asserted here so the restart is not mistaken for a no-op.
    @Test("restarting mid-run clears the design without counting as a transition")
    func restartingMidRunIsNotATransition() async {
        let drained = await Self.drainedRosette()
        var run = PreviewRunState()
        run.begin()
        for update in drained.updates where update.termination == nil {
            run.apply(update)
        }
        #expect(run.state == .running, "premise: still running")
        #expect(!run.display.isEmpty, "premise: the run drew something")
        let revisionBeforeRestart = run.summaryRevision

        run.begin()

        #expect(run.summaryRevision == revisionBeforeRestart)
        #expect(run.display.isEmpty, "the restart must still clear the design")
        #expect(run.summary == .empty)
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
